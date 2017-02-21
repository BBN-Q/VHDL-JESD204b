-- Simple JESD204b transmitter
-- * subclass 0 only
-- * optional scrambler
-- * link parameters set through generics
--
-- Original author: Colm Ryan
-- Copyright 2017 Raytheon BBN Technologies

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

use work.jesd204b_pkg.all;

entity jesd204b_tx is
	generic (
		M : natural := 1; -- number of converters
		L : natural := 4; -- number of physical lanes
		F : natural := 1; -- number of octets per frame -- only handle 1, 2, 4
		K : natural := 32; -- number of frames per multiframe
		SCRAMBLING_ENABLED : boolean := false
	);
	port (
		clk : in std_logic;
		rst : in std_logic; -- synchronous to clk

		syncn  : in std_logic;
		sysref : in std_logic;

		tx_tdata  : in std_logic_vector(L*32-1 downto 0); -- data to be sent L-1 downto 0 32 bits wide each
		tx_tready : out std_logic;

		gt_tdata : out std_logic_vector(L*32-1 downto 0); -- data for gigabit transceivers lanes L-1 downto 0 32 bits wide each
		gt_charisk : out std_logic_vector(L*4-1 downto 0) -- whether trasmitted byte is K character
	);
end entity;

architecture arch of jesd204b_tx is

constant cgs_data : octet_array(L*4-1 downto 0) := (others => control_chars.K);

signal syncn_sync : std_logic := '0';

type state_t is (IDLE, WAIT_FOR_CGS, ILA, TRANSMITTING);
signal state : state_t := WAIT_FOR_CGS;

type ila_data_array_t is array(L-1 downto 0) of octet_array(0 to 4*K*F-1);
-- should be able to do this as a constant with VHDL-2008
signal ila_data_array : ila_data_array_t := (others => (others => x"00"));

constant ila_charisk_array : std_logic_vector := fill_ila_charisk(F, K);

signal ila_multiframe_ct : natural range 0 to 3;
signal ila_last, ila_done, ila_done_d, ila_done_dd : boolean := false;
signal ila_data : octet_array(L*4-1 downto 0);
signal ila_charisk : std_logic_vector(L*4-1 downto 0);

signal cgs_ila_tdata, cgs_ila_tdata_d : std_logic_vector(L*32-1 downto 0);
signal cgs_ila_charisk, cgs_ila_charisk_d : std_logic_vector(L*4-1 downto 0);

signal frame_ct : natural range 0 to K-1;
signal end_of_multiframe : boolean := false;

-- scrambler state for each lane
type scramber_state_t is array(L-1 downto 0) of std_logic_vector(15 downto 0);
signal scrambler_state : scramber_state_t := (others => x"7f80");

-- keep track of octets for alignemnt character insertion without scrambling
signal prev_octet : octet_array(L-1 downto 0) := (others => x"00");
signal prev_octet_replaced : boolean_vector(L-1 downto 0) := (others => true);

signal data_octets : octet_array(L*4-1 downto 0) := (others => x"00");
signal data_scrambled : octet_array(L*4-1 downto 0) := (others => x"00");
signal data_alignment_inserted : octet_array(L*4-1 downto 0) := (others => x"00");
signal data_charisk : std_logic_vector(L*4-1 downto 0);

begin

fill_ila_data_gen : for lane_ct in 0 to L-1 generate
	ila_data_array(lane_ct) <= fill_ila_data(M, L, F, K, lane_ct, 16, 16, SCRAMBLING_ENABLED);
end generate;
-- synchronize syncn onto clk
syncn_synchronizer_inst : entity work.synchronizer
port map(rst => rst, clk => clk, data_in => syncn, data_out => syncn_sync);

-- main process to watch syncn and step through CGS, ILA, TRANSMITTING states
main : process(clk)
begin
	if rising_edge(clk) then
		if rst = '1' then
			state <= IDLE;
		elsif syncn_sync = '0' then
			state <= WAIT_FOR_CGS;
		else

			case( state ) is

				when IDLE =>
					state <= WAIT_FOR_CGS;

				when WAIT_FOR_CGS =>
					if syncn_sync = '1' then
						state <= ILA;
					end if;

				when ILA =>
					if ila_last then
						state <= TRANSMITTING;
					end if;

				when TRANSMITTING =>
					null;

			end case;

		end if;
	end if;

end process;

-- process to count through the 4 ILA multiframes
ila_player : process(clk)
begin
	if rising_edge(clk) then
		if rst = '1' or state = WAIT_FOR_CGS then
			ila_multiframe_ct <= 0;
			ila_last <= false;
			ila_done <= false;
			ila_done_d <= false;
			ila_done_dd <= false;
		else
			ila_done <= ila_last;
			ila_done_d <= ila_done;
			ila_done_dd <= ila_done_d;
			if (frame_ct = K - 8/F)  and (ila_multiframe_ct = 3) then
				ila_last <= true;
			end if;
			-- latch on ila_last
			if (not ila_last) and (frame_ct = K-4/F) and ila_multiframe_ct < 3 then
				ila_multiframe_ct <= ila_multiframe_ct + 1;
			end if;
		end if;
	end if;
end process;


ila_data_slicer : for lane_ct in 0 to L-1 generate
	-- we send 4 octets at a time
	ila_data_byte_slicer : for byte_ct in 0 to 3 generate
		ila_charisk(4*lane_ct+byte_ct) <= ila_charisk_array(ila_multiframe_ct*K + frame_ct + byte_ct);
		ila_data(4*lane_ct + byte_ct) <= ila_data_array(lane_ct)(ila_multiframe_ct*K + frame_ct + byte_ct);
	end generate;
end generate;

-- double register jesd cfg data to align with user data for scrambling and character replacement pipeline
cfg_data_delay_registers : process(clk)
begin
	if rising_edge(clk) then
		case( state ) is
			when IDLE | TRANSMITTING =>
				cgs_ila_tdata <= (others => '0');
				cgs_ila_charisk <= (others => '0');
			when WAIT_FOR_CGS =>
				cgs_ila_tdata <= flatten(cgs_data);
				cgs_ila_charisk <= (others => '1');
			when ILA =>
				cgs_ila_tdata <= flatten(ila_data);
				cgs_ila_charisk <= ila_charisk;
		end case;
		cgs_ila_tdata_d <= cgs_ila_tdata;
		cgs_ila_charisk_d <= cgs_ila_charisk;
	end if;
end process;

-- count out multiframes
-- assume for now that frames and muliframes are 4 byte aligned so that end_of_multiframe
-- implies last byte of 4 is end of multiframe
frame_counter : process(clk)
begin
	if rising_edge(clk) then
		if rst = '1' or state = WAIT_FOR_CGS then
			frame_ct <= 0;
			end_of_multiframe <= false;
		else
			if frame_ct = K - 4/F then
				frame_ct <= 0;
				end_of_multiframe <= true;
			else
				frame_ct <= frame_ct + 4/F; -- play 4 bytes at a time TODO: handle F other than 1,2,4
				end_of_multiframe <= false;
			end if;
		end if;
	end if;
end process;

data_in_to_octets : for lane_ct in 0 to L-1 generate
	byte_gen : for byte_ct in 4*lane_ct to 4*lane_ct+3 generate
		data_octets(byte_ct) <= tx_tdata(8*(byte_ct+1)-1 downto 8*byte_ct);
	end generate;
end generate;

-- TODO: scramble data
-- see section 5.2
-- scramble each frame from MSB to LSB
-- scrambling polynomial is 1 + x^14 + x^15
-- initial seed is (see section 5.2.5)
-- ""1" for the eight storage elements with the highest indices and "0" for the seven remaining ones."

scrambler_enabled_gen : if SCRAMBLING_ENABLED generate

	scrambler_per_lane_gen : for lane_ct in 0 to L-1 generate

		scrambler_pro : process(clk)
			variable tmp_state : std_logic_vector(15 downto 0);
			variable data_in, data_out : octet_array(3 downto 0);
			variable scrambled_bit : std_logic;
			variable l : line;
		begin
			if rising_edge(clk) then
				if rst = '1' or state = WAIT_FOR_CGS then
					scrambler_state(lane_ct) <= x"7f80";

				elsif tx_tready = '1' then
					tmp_state := scrambler_state(lane_ct);
					data_in := data_octets(4*(lane_ct+1)-1 downto 4*lane_ct);

					for frame_idx in 1 to 4/F loop
						write(l, "frame_idx = " & integer'image(frame_idx));
						writeline(output, l);
						for byte_idx in F-1 downto 0 loop
							write(l, "byte_idx = " & integer'image(byte_idx) & " data_byte = " & to_hstring(data_in((frame_idx-1)*F + byte_idx)));
							writeline(output, l);
							for bit_idx in 7 downto 0 loop
								tmp_state := tmp_state srl 1;
								write(l, "bit_idx = " & integer'image(bit_idx) &
								" current bit = " & std_logic'image(data_in((frame_idx-1)*F + byte_idx)(bit_idx)) &
								" tmp_state = " & to_hstring(tmp_state));
								writeline(output, l);
								tmp_state(15) := data_in((frame_idx-1)*F + byte_idx)(bit_idx) xor tmp_state(1) xor tmp_state(0);
								data_out((frame_idx-1)*F + byte_idx)(bit_idx) := tmp_state(15);
								write(l, "tmp_state = " & to_hstring(tmp_state) & "; data_out = ");
								for ct in 7 downto 0 loop
									write(l, std_logic'image(data_out((frame_idx-1)*F + byte_idx)(ct)));
								end loop;
								writeline(output, l);
							end loop;
						end loop;
					end loop;

					-- output register
					data_scrambled(4*(lane_ct+1)-1 downto 4*lane_ct) <= data_out;
					scrambler_state(lane_ct) <= tmp_state;

				end if;
			end if;
		end process;

	end generate;

end generate;

scrambler_disabled_gen : if not SCRAMBLING_ENABLED generate
	-- with scrambler just register to mainitain timing
	scrambler_pro : process(clk)
	begin
		if rising_edge(clk) then
			data_scrambled <= data_octets;
		end if;
	end process;

end generate;


-- process to insert frame alignment characters when possible
-- see section 5.3.3.4
character_replacement_gen : for lane_ct in 0 to L-1 generate

	-- without scrambling then we replace repeated octets at the end of frames
	-- it's annoying we can't but the if generate in the process because there is
	-- repeated code between the two
	character_replacement_without_scrambler : if not SCRAMBLING_ENABLED generate

		character_replacement_pro : process(clk)
			variable tmp_prev : octet;
			variable tmp_replaced : boolean := true;
			variable tmp_charisk : std_logic_vector(3 downto 0);
			variable data_in, data_out : octet_array(3 downto 0);
		begin

			if rising_edge(clk) then

				if rst = '1' then
					prev_octet_replaced(lane_ct) <= true;
				else
					-- copy over data as default
					data_in := data_scrambled(4*(lane_ct+1)-1 downto 4*lane_ct);
					data_out := data_in;

					tmp_prev := prev_octet(lane_ct);
					tmp_replaced := prev_octet_replaced(lane_ct);
					tmp_charisk := b"0000";

					-- check octets at end of frame
					for ct in 1 to 4/F loop
						if data_in(F*ct-1) = tmp_prev then
							if (ct = 4/F) and end_of_multiframe then
								data_out(F*ct-1) := control_chars.A;
								tmp_replaced := true;
							elsif not tmp_replaced then
								data_out(F*ct-1) := control_chars.F;
								tmp_replaced := true;
							else
								tmp_replaced := false;
							end if;
						else
							tmp_replaced := false;
						end if;
						if tmp_replaced then
							tmp_charisk(F*ct-1) := '1';
						end if;
						tmp_prev := data_in(F*ct-1);
					end loop;

				end if;

				-- output registers
				data_alignment_inserted(4*(lane_ct+1)-1 downto 4*lane_ct) <= data_out;
				data_charisk(4*(lane_ct+1)-1 downto 4*lane_ct) <= tmp_charisk;

				prev_octet(lane_ct) <= tmp_prev;
				prev_octet_replaced(lane_ct) <= tmp_replaced;

			end if;
		end process;
	end generate;

	-- with scrambling we replace certain characters at the end of a frame or multiframe
	character_replacement_with_scrambler : if SCRAMBLING_ENABLED generate
		character_replacement_pro : process(clk)
			variable tmp_charisk : std_logic_vector(3 downto 0);
			variable data_in : octet_array(3 downto 0);
		begin

			if rising_edge(clk) then
				data_in := data_scrambled(4*(lane_ct+1)-1 downto 4*lane_ct);
				tmp_charisk := b"0000";

				-- check octets at end of frame
				for ct in 1 to 4/F loop
					if end_of_multiframe and (data_in(F*ct-1) = x"7c") then
						tmp_charisk(F*ct-1) := '1';
					elsif data_in(F*ct-1) = x"fc" then
						tmp_charisk(F*ct-1) := '1';
					end if;
				end loop;

				-- output registers
				data_alignment_inserted(4*(lane_ct+1)-1 downto 4*lane_ct) <= data_in;
				data_charisk(4*(lane_ct+1)-1 downto 4*lane_ct) <= tmp_charisk;

			end if;
		end process;
	end generate;

end generate;


-- can take data when in TRANSMITTING state
tx_tready <= '1' when (state = TRANSMITTING) else '0';

-- mux between user data and CGS/ILA data
gt_tdata <= flatten(data_alignment_inserted) when ila_done_dd else cgs_ila_tdata_d;
gt_charisk <= data_charisk when ila_done_dd else cgs_ila_charisk_d;


end architecture;
