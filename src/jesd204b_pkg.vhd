library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package jesd204b_pkg is

	-- JESD control characters
	-- section 3.2 and Figure 35 of of JEDEC Standard No. 204B
	subtype octet is std_logic_vector(7 downto 0);
	type control_chars_t is
		record
			R : octet; -- K28.0 - ILA start of multiframe
			A : octet; -- K28.3 - ILA end of multiframe
			Q : octet; -- K28.4 - start of configuration data
			K : octet; -- K28.5 - CGS comma
			F : octet; -- K28.7 - character, frame sync
		end record;
	constant control_chars : control_chars_t := (
		R => x"1c",
		A => x"7c",
		Q => x"9c",
		K => x"bc",
		F => x"fc"
	);

	-- convenience helper to go from byte array to std_logic_vector
	type octet_array is array(natural range <>) of octet;
	function flatten(b_array : octet_array) return std_logic_vector;

	-- helper function to fill our ILA data ROM
	-- should be able to index this by multiframe but Vivado's VHDL-2008 support is terrible
	-- and "The "Vhdl 2008 Unconstrained Array Type as Subtype in Array Type Definition" is not supported yet for simulation"
	function fill_ila_data(M : natural; L : natural; F : natural; K : natural;
	                       lane_num : natural; converter_resolution : natural;
	                       bits_per_sample : natural; scrambling_enabled : boolean;
	                       HD: natural)
	                       return octet_array;


	function fill_ila_charisk(F : natural; K : natural) return std_logic_vector;

end jesd204b_pkg;


package body jesd204b_pkg is

	-- convenience helper to go from byte array to std_logic_vector
	function flatten(b_array : octet_array) return std_logic_vector is
		variable flattened : std_logic_vector(8*b_array'length-1 downto 0);
	begin
		for ct in 0 to b_array'length-1 loop
			flattened(8*(ct+1)-1 downto 8*ct) := b_array(ct);
		end loop;
		return flattened;
	end flatten;

	-- helper function to fill our ILA data ROM
	-- returns a flattened byte array of 4 multiframes
	-- see section 8.2 in particular Figure 50 of the JEDEC Standard No. 204B
	function fill_ila_data(M : natural; L : natural; F : natural; K : natural;
	                       lane_num : natural; converter_resolution : natural;
	                       bits_per_sample : natural; scrambling_enabled : boolean;
	                       HD : natural)
	                       return octet_array is
		variable ila_data : octet_array(0 to 4*K*F-1) := (others => x"00");
		variable checksum : unsigned(7 downto 0) := (others => '0');

		-- see Table 20 and Table 21 of JEDEC Standard No. 204B
		type configuration_data is record
			octet     : natural range 0 to 13;
			offset    : natural range 0 to 7;
			bit_width : natural range 1 to 8;
			value     : natural range 0 to 255;
		end record;

		type configuration_data_vector_t is array(0 to 21) of configuration_data;
		variable configuration_data_vector : configuration_data_vector_t := (
			(octet => 1,  offset => 4, bit_width => 4, value => 0), -- ADJCNT Number of adjustment resolution steps to adjust DAC LMFC. Applies to Subclass 2 operation only.
			(octet => 2,  offset => 6, bit_width => 1, value => 0), -- ADJDIR Direction to adjust DAC LMFC 0 – Advance 1 – Delay Applies to Subclass 2 operation only
			(octet => 1,  offset => 0, bit_width => 4, value => 0), -- BID Bank ID – Extension to DID -- x"b" or 11 for fun
			(octet => 10, offset => 0, bit_width => 5, value => 0), -- CF - No. of control words per frame clock period per link
			(octet => 7,  offset => 6, bit_width => 2, value => 0), -- CS No. of control bits per sample
			(octet => 0,  offset => 0, bit_width => 8, value => 0), -- DID Device (= link) identification no.  -- x"ad" or 173  for fun
			(octet => 4,  offset => 0, bit_width => 8, value => F-1), -- F-1 No. of octets per frame
			(octet => 10, offset => 7, bit_width => 1, value => HD), -- HD High Density format
			(octet => 9,  offset => 5, bit_width => 3, value => 1), -- JESDV JESD204 version 000 – JESD204A 001 – JESD204B
			(octet => 5,  offset => 0, bit_width => 5, value => K-1), -- K-1 No. of frames per multiframe
			(octet => 3,  offset => 0, bit_width => 5, value => L-1), -- L-1 No. of lanes per converter device (link)
			(octet => 2,  offset => 0, bit_width => 5, value => lane_num), -- LID Lane identification no. (within link)
			(octet => 6,  offset => 0, bit_width => 8, value => M-1), -- M-1 No. of converters per device
			(octet => 7,  offset => 0, bit_width => 5, value => converter_resolution-1), -- N Converter resolution - 1
			(octet => 8,  offset => 0, bit_width => 5, value => bits_per_sample-1), --N’ Total no. of bits per sample - 1
			(octet => 2,  offset => 5, bit_width => 1, value => 0), -- PHADJ Phase adjustment request to DAC Subclass 2 only.
			(octet => 9,  offset => 0, bit_width => 8, value => L*F/M/(bits_per_sample/8)-1), -- S No. of samples per converter per frame cycle - 1
			(octet => 3,  offset => 7, bit_width => 8, value => 0), -- SCR Scrambling enabled
			(octet => 8,  offset => 5, bit_width => 3, value => 0), -- SUBCLASSV Device Subclass Version
			(octet => 11, offset => 0, bit_width => 8, value => 0), -- RES1 Reserved field 1
			(octet => 12, offset => 0, bit_width => 8, value => 0), -- RES2 Reserved field 2
			(octet => 13, offset => 0, bit_width => 8, value => 0) -- CHKSUM Checksum Σ(all above fields)mod 256
		);
		variable cfg_data : configuration_data;
	begin
		-- fill in scrambling field
		if scrambling_enabled then
			configuration_data_vector(17).value := 1;
		end if;

		-- fill in data ramp
		for ct in 0 to ila_data'length-1 loop
			ila_data(ct) := std_logic_vector(to_unsigned(ct, 8));
		end loop;
		-- fill in start with /28.0/ (/R/) and end with /28.3/ (/A/) of each multiframe
		for ct in 0 to 3 loop
			ila_data(K*F*ct) := control_chars.R;
			ila_data(K*F*(ct+1)-1) := control_chars.A;
		end loop;

		-- 2nd octet of 2nd multiframe /28.4/ (/Q/)
		ila_data(K*F+1) := control_chars.Q;
		-- link configuration data starts after this
		-- zero them out First
		for ct in 0 to 13 loop
			ila_data(K*F+2+ct) := x"00";
		end loop;
		-- calculate checksum as we loop through and set bit values
		checksum := (others => '0');
		for ct in 0 to configuration_data_vector'length-1 loop
			cfg_data := configuration_data_vector(ct);
			checksum := checksum + to_unsigned(cfg_data.value, cfg_data.bit_width);
			if ct = configuration_data_vector'length-1 then
				cfg_data.value := to_integer(checksum);
			end if;
			ila_data(K*F+2+cfg_data.octet) := ila_data(K*F+2+cfg_data.octet) or
			                                  std_logic_vector(shift_left(resize(to_unsigned(cfg_data.value, cfg_data.bit_width), 8), cfg_data.offset));
		end loop;

		return ila_data;
	end fill_ila_data;


	function fill_ila_charisk(F : natural; K : natural) return std_logic_vector is
		variable ila_charisk : std_logic_vector(0 to 4*K*F-1) := (others => '0');
	begin
		-- each muliframe starts and ends with control character
		for ct in 0 to 3 loop
			ila_charisk(K*F*ct) := '1';
			ila_charisk(K*F*(ct+1)-1) := '1';
		end loop;

		-- 2nd octet of 2nd multiframe indicates configuration data with control character
		ila_charisk(K*F+1) := '1';

		return ila_charisk;
	end fill_ila_charisk;


end jesd204b_pkg;
