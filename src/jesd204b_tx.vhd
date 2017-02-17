-- Simple JESD204b transmitter
-- * subclass 0 only
-- * optional scrambler
-- * link parameters set through generics
-- Original author: Colm Ryan
-- Copyright 2017 Raytheon BBN Technologies

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.jesd204b_pkg.all;

entity jesd204b_tx is
	generic (
		M : natural := 1; -- number of converters
		L : natural := 4; -- number of physical lanes
		F : natural := 1; -- number of octets per frame -- only handle 1, 2, 4
		K : natural := 32 -- number of frames per multiframe
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

signal ila_multiframe_ct : natural range 0 to 3;
signal ila_last : boolean := false;
signal ila_data : octet_array(L*4-1 downto 0);

signal frame_ct : natural range 0 to K-1;

begin

fill_ila_data_gen : for lane_ct in 0 to L-1 generate
	ila_data_array(lane_ct) <= fill_ila_data(M, L, F, K, lane_ct, 16, 16, 0);
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

-- mux between the possible outputs
with state select gt_tdata <=
	(others => '0') when IDLE,
	flatten(cgs_data) when WAIT_FOR_CGS,
	flatten(ila_data) when ILA,
	tx_tdata when TRANSMITTING;

-- can take data when in TRANSMITTING state
tx_tready <= '1' when state = TRANSMITTING else '0';

-- process to count through the 4 ILA multiframes
ila_player : process(clk)
begin
	if rising_edge(clk) then
		if rst = '1' or state = WAIT_FOR_CGS then
			ila_multiframe_ct <= 0;
		else
			if (not ila_last) and (frame_ct = K-4/F) then
				ila_multiframe_ct <= ila_multiframe_ct + 1;
			end if;
		end if;
	end if;
end process;

ila_last <= (state = ILA)git  and (frame_ct = K - 4/F)  and (ila_multiframe_ct = 3);

ila_data_slicer : for lane_ct in 0 to L-1 generate
	ila_data_byte_slicer : for byte_ct in 0 to 3 generate
		ila_data(4*lane_ct + byte_ct) <= ila_data_array(lane_ct)(ila_multiframe_ct*K + frame_ct + byte_ct);
	end generate;
end generate;

-- count out multiframes
frame_counter : process(clk)
begin
	if rising_edge(clk) then
		if rst = '1' or state = WAIT_FOR_CGS then
			frame_ct <= 0;
		else
			if frame_ct = K - 4/F then
				frame_ct <= 0;
			else
				frame_ct <= frame_ct + 4/F; -- play 4 bytes at a time TODO: handle F other than 1,2,4
			end if;
		end if;
	end if;

end process;


end architecture;
