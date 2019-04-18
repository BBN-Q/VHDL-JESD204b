-- wrap the VHDL-JESD module and transceiver PHY
-- * buffer syncn from the DAC
-- * instantiate VHDL-JESD  module
-- * synchronize reset
-- * buffer transceiver reference clock
-- * instantiate transceiver PHY wizard
-- * create transceiver reset pulse
--
-- Original author: Colm Ryan (colm@colmryan.org)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- for clock buffer primitives
Library UNISIM;
use UNISIM.vcomponents.all;

entity jesd_wrapper is
  port (
    rst    : in std_logic; -- asynchronous
    rst_gt : in std_logic; --asynchronous GT reset

    refclk_p : in std_logic; -- differential transceiver reference clock
    refclk_n : in std_logic;
    drpclk   : in std_logic; -- independent clock for transceiver configuration

    gt_reset_done : out std_logic; -- transceiver status pins
    qpll0_lock    : out std_logic;
    qpll1_lock    : out std_logic;

    clk_sys : out std_logic; -- provide clock to send data on

    syncn_p : in std_logic;  -- differential JESD sync from DAC
    syncn_n : in std_logic;
    syncn   : out std_logic; -- copy `clk_sys` clocked version out for status

    tx_tdata : in std_logic_vector(255 downto 0); -- data to send to the DAC (synchronous to `clk_sys`)
    tx_tready : out std_logic;

    tx_p : out std_logic_vector(7 downto 0); -- transcevier pins
    tx_n : out std_logic_vector(7 downto 0)
  );
end entity;

architecture arch of jesd_wrapper is

signal gt_tdata, gt_tdata_swapped : std_logic_vector(255 downto 0); -- data to transceivers
signal gt_charisk, gt_charisk_swapped : std_logic_vector(31 downto 0); -- K characters to transceivers

signal refclk : std_logic;
signal rst_sync, rst_gt_sync : std_logic;

-- GT wizard signals
signal txpmaresetdone : std_logic_vector(7 downto 0);
signal gtwiz_userclk_tx_reset : std_logic; -- hold user clock helper block in reset
signal gtwiz_userclk_tx_active : std_logic; -- user clock helper block up and ready
signal txctrl2 : std_logic_vector(63 downto 0) := (others => '0');

-- optional lane swapping example
--  DAC SerDes   TX Data Slice
--   6            0 (31:0)
--   7            1 (63:32)
--   4            2 (95:64)
--   5            3 (127:96)
--   3            4 (159:128)
--   1            5 (191:160)
--   0            6 (223:192)
--   2            7 (255:224)

-- map DAC serdes lanes to transceiver wizard lanes
constant LANE_MAPPING : integer_vector(0 to 7) := (6, 5, 7, 4, 2, 3, 0, 1);

begin

-------------------------------------- input buffers ----------------------------------------------

-- buffer syncn from DAC
syncn_IBUFDS_inst : IBUFDS
generic map ( DIFF_TERM => TRUE)
port map (
   O => syncn,
   I => syncn_p,
   IB => syncn_n
);

-------------------------------------------- JESD transmitter logic ------------------------------
-- synchronize reset onto system clock
rst_synchronizer_inst : entity work.synchronizer
generic map(RESET_VALUE => '1', NUM_FLIP_FLOPS => 3)
port map(rst => rst or not gtwiz_userclk_tx_active, clk => clk_sys, data_in => '0', data_out => rst_sync);

-- intantiate VHDL-JESD transmit module
jesd_inst : entity work.jesd204b_tx
  generic map (
    M => 2,
    L => 8,
    F => 1,
    K => 32,
    SCRAMBLING_ENABLED => TRUE
  )
  port map (
    clk => clk_sys,
    rst => rst_sync,

    syncn => syncn,
    sysref => '0',

    tx_tdata  => tx_tdata, -- data to send
    tx_tready => tx_tready,

    gt_tdata   => gt_tdata, -- data to transceivers
    gt_charisk => gt_charisk -- K characters to transceivers
  );

-- create reset pulse for transceivers
rst_gt_synchronizer_inst : entity work.synchronizer
generic map(RESET_VALUE => '1', NUM_FLIP_FLOPS => 5)
port map(rst => rst_gt, clk => drpclk, data_in => '0', data_out => rst_gt_sync);

-------------------------------------------- JESD transceivers  ------------------------------

-- buffer the reference clock
IBUFDS_GTE4_inst : IBUFDS_GTE4
generic map (
   REFCLK_EN_TX_PATH => '0',   -- Reserved. This attribute must always be set to 1'b0.
   REFCLK_HROW_CK_SEL => "00", -- 00: ODIV2 output == O; 01: ODIV2 = O/2
   REFCLK_ICNTL_RX => "00"     --  Reserved. Use the recommended value from the Wizard. -- wizard example uses  "00"
)
port map (
   O => refclk,
   ODIV2 => open,
   CEB => '0',     -- active low clock buffer enable
   I => refclk_p,
   IB => refclk_n
);

-- from example design hold tx userclk helper block in reset until we have a good clock
gtwiz_userclk_tx_reset <= not (and txpmaresetdone);

-- lane swapping
lane_mapping_loop : for lane_ct in 0 to 7 generate

  -- apply lane swapping to handle Wizard and FMC eval. board swaps
  gt_tdata_swapped((LANE_MAPPING(lane_ct)+1)*32-1 downto LANE_MAPPING(lane_ct)*32) <= gt_tdata((lane_ct+1)*32-1 downto lane_ct*32);
  gt_charisk_swapped((LANE_MAPPING(lane_ct)+1)*4-1 downto LANE_MAPPING(lane_ct)*4) <= gt_charisk((lane_ct+1)*4-1 downto lane_ct*4);

  -- K character control is through txctrl2
  -- since we are using a 32bit wide data path we only use the lower 4 bits of txcctrl2
  txctrl2((lane_ct+1)*8-5 downto lane_ct*8) <= gt_charisk_swapped((lane_ct+1)*4-1 downto lane_ct*4);
end generate;

jesd_gtwizard_inst : entity work.jesd_gtwizard_fmc0
 port map (
  gtwiz_userclk_tx_reset_in(0)          => gtwiz_userclk_tx_reset,
  gtwiz_userclk_tx_srcclk_out           => open,
  gtwiz_userclk_tx_usrclk_out           => open,
  gtwiz_userclk_tx_usrclk2_out(0)       => clk_sys,
  gtwiz_userclk_tx_active_out(0)        => gtwiz_userclk_tx_active,
  gtwiz_userclk_rx_reset_in(0)          => '0',
  gtwiz_userclk_rx_srcclk_out           => open,
  gtwiz_userclk_rx_usrclk_out           => open,
  gtwiz_userclk_rx_usrclk2_out          => open,
  gtwiz_userclk_rx_active_out           => open,
  gtwiz_reset_clk_freerun_in(0)         => drpclk,
  gtwiz_reset_all_in(0)                 => rst_gt_sync,
  gtwiz_reset_tx_pll_and_datapath_in(0) => '0',
  gtwiz_reset_tx_datapath_in(0)         => '0',
  gtwiz_reset_rx_pll_and_datapath_in(0) => '0',
  gtwiz_reset_rx_datapath_in(0)         => '0',
  gtwiz_reset_rx_cdr_stable_out         => open,
  gtwiz_reset_tx_done_out(0)            => gt_reset_done,
  gtwiz_reset_rx_done_out               => open,
  gtwiz_userdata_tx_in                  => gt_tdata_swapped,
  gtwiz_userdata_rx_out                 => open,
  gtrefclk00_in                        => (others => refclk),
  qpll0lock_out(0)                      => qpll0_lock,
  qpll0lock_out(1)                      => qpll1_lock,
  qpll0outclk_out                       => open,
  qpll0outrefclk_out                    => open,
  gthrxn_in                             => (others => '0'),
  gthrxp_in                             => (others => '0'),
  tx8b10ben_in                          => (others => '1'),
  txctrl0_in                            => (others => '0'), -- disparity control unused
  txctrl1_in                            => (others => '0'), -- disparity control unused
  txctrl2_in                            => txctrl2,
  txpolarity_in                         => x"0F", -- optional board pin inverions e.g. lanes 4-8 but this maps to 0-3 see LANE_MAPPING
  gthtxn_out                            => tx_n,
  gthtxp_out                            => tx_p,
  rxpmaresetdone_out                    => open,
  txpmaresetdone_out                    => txpmaresetdone
);

end architecture;
