-- wrap the VHDL-JESD module and transceiver PHY
-- * buffer syncn from DAC
-- * instantiate VHDL-JESD module
-- * synchronize reset
-- * instantiate transceiver PHY
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
    rst_gt : in std_logic; -- asynchronous falling edge triggers transciever reset

    refclk_p : in std_logic; -- differential transceiver reference clock
    refclk_n : in std_logic;
    drpclk   : in std_logic; -- independent clock for transceiver configuration

    gt_reset_done : out std_logic; -- status pins from transceivers
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

signal gt_tdata : std_logic_vector(255 downto 0); -- data to transceivers
signal gt_charisk : std_logic_vector(31 downto 0); -- K characters to transceivers

signal rst_sync, rst_gt_sync, rst_gt_pulse : std_logic;

signal gt_reset_done_int : std_logic_vector(7 downto 0);

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
port map(rst => rst, clk => clk_sys, data_in => '0', data_out => rst_sync);

-- intantiate VHDL-JESD transmit module
jesd_inst : entity work.jesd204b_tx
  generic map (
    M => 4,
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
-- first synchronize to the drpclk
rst_gt_synchronizer_inst : entity work.synchronizer
generic map(RESET_VALUE => '1', NUM_FLIP_FLOPS => 3)
port map(rst => rst_gt, clk => drpclk, data_in => '0', data_out => rst_gt_sync);

-- create a pulse on the falling edge of rst_gt
transceiver_reset_pulse_pro : process(drpclk)
  variable delay_line : std_logic_vector(3 downto 0) := (others => '0');
  variable rst_gt_sync_d : std_logic;
begin
  if rising_edge(drpclk) then
    rst_gt_pulse <= delay_line(0);
    if rst_gt_sync = '0' and rst_gt_sync_d  = '1' then
      delay_line := (others => '1');
    else
      delay_line := '0' & delay_line(delay_line'high downto 1);
    end if;
    rst_gt_sync_d := rst_gt_sync;
  end if;
end process;


  -------------------------------------------- JESD transceivers  ------------------------------

-- report GT reset is done when all channels report done
gt_reset_done <= and gt_reset_done_int;

jesd_transceivers_inst : entity work.jesd_gtwizard
  port map(
    SOFT_RESET_TX_IN            => rst_gt_pulse,
    DONT_RESET_ON_DATA_ERROR_IN => '0',
    Q0_CLK0_GTREFCLK_PAD_N_IN   => refclk_n,
    Q0_CLK0_GTREFCLK_PAD_P_IN   => refclk_p,

    GT0_TX_FSM_RESET_DONE_OUT => gt_reset_done_int(0),
    GT0_RX_FSM_RESET_DONE_OUT => open,
    GT0_DATA_VALID_IN         => '0',
    GT1_TX_FSM_RESET_DONE_OUT => gt_reset_done_int(1),
    GT1_RX_FSM_RESET_DONE_OUT => open,
    GT1_DATA_VALID_IN         => '0',
    GT2_TX_FSM_RESET_DONE_OUT => gt_reset_done_int(2),
    GT2_RX_FSM_RESET_DONE_OUT => open,
    GT2_DATA_VALID_IN         => '0',
    GT3_TX_FSM_RESET_DONE_OUT => gt_reset_done_int(3),
    GT3_RX_FSM_RESET_DONE_OUT => open,
    GT3_DATA_VALID_IN         => '0',
    GT4_TX_FSM_RESET_DONE_OUT => gt_reset_done_int(4),
    GT4_RX_FSM_RESET_DONE_OUT => open,
    GT4_DATA_VALID_IN         => '0',
    GT5_TX_FSM_RESET_DONE_OUT => gt_reset_done_int(5),
    GT5_RX_FSM_RESET_DONE_OUT => open,
    GT5_DATA_VALID_IN         => '0',
    GT6_TX_FSM_RESET_DONE_OUT => gt_reset_done_int(6),
    GT6_RX_FSM_RESET_DONE_OUT => open,
    GT6_DATA_VALID_IN         => '0',
    GT7_TX_FSM_RESET_DONE_OUT => gt_reset_done_int(7),
    GT7_RX_FSM_RESET_DONE_OUT => open,
    GT7_DATA_VALID_IN         => '0',

    -- use GTO clock to  drive everything
    -- internal to wizard they are all the  same anyways - see "jesd_gtwizard_gt_usrclk_source.vhd"
    GT0_TXUSRCLK_OUT  => open,
    GT0_TXUSRCLK2_OUT => clk_sys,

    GT1_TXUSRCLK_OUT  => open,
    GT1_TXUSRCLK2_OUT => open,

    GT2_TXUSRCLK_OUT  => open,
    GT2_TXUSRCLK2_OUT => open,

    GT3_TXUSRCLK_OUT  => open,
    GT3_TXUSRCLK2_OUT => open,

    GT4_TXUSRCLK_OUT  => open,
    GT4_TXUSRCLK2_OUT => open,

    GT5_TXUSRCLK_OUT  => open,
    GT5_TXUSRCLK2_OUT => open,

    GT6_TXUSRCLK_OUT  => open,
    GT6_TXUSRCLK2_OUT => open,

    GT7_TXUSRCLK_OUT  => open,
    GT7_TXUSRCLK2_OUT => open,

    --_________________________________________________________________________
    --GT0  (X0Y0)
    --____________________________CHANNEL PORTS________________________________
    --------------------------------- CPLL Ports -------------------------------
    -- not using CPLL
    gt0_cpllfbclklost_out => open,
    gt0_cplllock_out => open,
    gt0_cpllreset_in => '0',
    ---------------------------- Channel - DRP Ports  --------------------------
    gt0_drpaddr_in => (others => '0'),
    gt0_drpdi_in => (others => '0'),
    gt0_drpdo_out => open,
    gt0_drpen_in => '0',
    gt0_drprdy_out => open,
    gt0_drpwe_in => '0',
    --------------------------- Digital Monitor Ports --------------------------
    gt0_dmonitorout_out => open,
    --------------------- RX Initialization and Reset Ports --------------------
    gt0_eyescanreset_in => '0',
    -------------------------- RX Margin Analysis Ports ------------------------
    gt0_eyescandataerror_out => open,
    gt0_eyescantrigger_in => '0',
    ------------------- Receive Ports - RX Buffer Bypass Ports -----------------
    gt0_rxbufreset_in => '0',
    gt0_rxbufstatus_out => open,
    --------------------- Receive Ports - RX Equalizer Ports -------------------
    gt0_rxmonitorout_out => open,
    gt0_rxmonitorsel_in => (others => '0'),
    ------------- Receive Ports - RX Initialization and Reset Ports ------------
    gt0_gtrxreset_in => '0',
    gt0_rxpcsreset_in => '0',
    --------------------- TX Initialization and Reset Ports --------------------
    gt0_gttxreset_in => '0',
    gt0_txuserrdy_in => '1',
    ------------------ Transmit Ports - TX Data Path interface -----------------
    gt0_txdata_in => gt_tdata((0+1)*32-1 downto 0*32),
    ---------------- Transmit Ports - TX Driver and OOB signaling --------------
    gt0_gtxtxn_out => tx_n(0),
    gt0_gtxtxp_out => tx_p(0),
    ----------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
    gt0_txoutclkfabric_out => open,
    gt0_txoutclkpcs_out => open,
    --------------------- Transmit Ports - TX Gearbox Ports --------------------
    gt0_txcharisk_in => gt_charisk((0+1)*4-1 downto 0*4),
    ------------- Transmit Ports - TX Initialization and Reset Ports -----------
    gt0_txresetdone_out => open,
    ----------------- Transmit Ports - TX Polarity Control Ports ---------------
    gt0_txpolarity_in => '0',

    --GT1  (X0Y1)
    --____________________________CHANNEL PORTS________________________________
    --------------------------------- CPLL Ports -------------------------------
    gt1_cpllfbclklost_out => open,
    gt1_cplllock_out => open,
    gt1_cpllreset_in => '0',
    ---------------------------- Channel - DRP Ports  --------------------------
    gt1_drpaddr_in => (others => '0'),
    gt1_drpdi_in => (others => '0'),
    gt1_drpdo_out => open,
    gt1_drpen_in => '0',
    gt1_drprdy_out => open,
    gt1_drpwe_in => '0',
    --------------------------- Digital Monitor Ports --------------------------
    gt1_dmonitorout_out => open,
    --------------------- RX Initialization and Reset Ports --------------------
    gt1_eyescanreset_in => '0',
    -------------------------- RX Margin Analysis Ports ------------------------
    gt1_eyescandataerror_out => open,
    gt1_eyescantrigger_in => '0',
    ------------------- Receive Ports - RX Buffer Bypass Ports -----------------
    gt1_rxbufreset_in => '0',
    gt1_rxbufstatus_out => open,
    --------------------- Receive Ports - RX Equalizer Ports -------------------
    gt1_rxmonitorout_out => open,
    gt1_rxmonitorsel_in => (others => '0'),
    ------------- Receive Ports - RX Initialization and Reset Ports ------------
    gt1_gtrxreset_in => '0',
    gt1_rxpcsreset_in => '0',
    --------------------- TX Initialization and Reset Ports --------------------
    gt1_gttxreset_in => '0',
    gt1_txuserrdy_in => '1',
    ------------------ Transmit Ports - TX Data Path interface -----------------
    gt1_txdata_in => gt_tdata((1+1)*32-1 downto 1*32),
    ---------------- Transmit Ports - TX Driver and OOB signaling --------------
    gt1_gtxtxn_out => tx_n(1),
    gt1_gtxtxp_out => tx_p(1),
    ----------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
    gt1_txoutclkfabric_out => open,
    gt1_txoutclkpcs_out => open,
    --------------------- Transmit Ports - TX Gearbox Ports --------------------
    gt1_txcharisk_in => gt_charisk((1+1)*4-1 downto 1*4),
    ------------- Transmit Ports - TX Initialization and Reset Ports -----------
    gt1_txresetdone_out => open,
    ----------------- Transmit Ports - TX Polarity Control Ports ---------------
    gt1_txpolarity_in => '0',

    --GT2  (X0Y2)
    --____________________________CHANNEL PORTS________________________________
    --------------------------------- CPLL Ports -------------------------------
    gt2_cpllfbclklost_out => open,
    gt2_cplllock_out => open,
    gt2_cpllreset_in => '0',
    ---------------------------- Channel - DRP Ports  --------------------------
    gt2_drpaddr_in => (others => '0'),
    gt2_drpdi_in => (others => '0'),
    gt2_drpdo_out => open,
    gt2_drpen_in => '0',
    gt2_drprdy_out => open,
    gt2_drpwe_in => '0',
    ------------------                        : in   std_logic;--------- Digital Monitor Ports --------------------------
    gt2_dmonitorout_out => open,
    --------------------- RX Initialization and Reset Ports --------------------
    gt2_eyescanreset_in => '0',
    -------------------------- RX Margin Analysis Ports ------------------------
    gt2_eyescandataerror_out => open,
    gt2_eyescantrigger_in => '0',
    ------------------- Receive Ports - RX Buffer Bypass Ports -----------------
    gt2_rxbufreset_in => '0',
    gt2_rxbufstatus_out => open,
    --------------------- Receive Ports - RX Equalizer Ports -------------------
    gt2_rxmonitorout_out => open,
    gt2_rxmonitorsel_in => (others => '0'),
    ------------- Receive Ports - RX Initialization and Reset Ports ------------
    gt2_gtrxreset_in => '0',
    gt2_rxpcsreset_in => '0',
    --------------------- TX Initialization and Reset Ports --------------------
    gt2_gttxreset_in => '0',
    gt2_txuserrdy_in => '1',
    ------------------ Transmit Ports - TX Data Path interface -----------------
    gt2_txdata_in => gt_tdata((2+1)*32-1 downto 2*32),
    ---------------- Transmit Ports - TX Driver and OOB signaling --------------
    gt2_gtxtxn_out => tx_n(2),
    gt2_gtxtxp_out => tx_p(2),
    ----------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
    gt2_txoutclkfabric_out => open,
    gt2_txoutclkpcs_out => open,
    --------------------- Transmit Ports - TX Gearbox Ports --------------------
    gt2_txcharisk_in => gt_charisk((2+1)*4-1 downto 2*4),
    ------------- Transmit Ports - TX Initialization and Reset Ports -----------
    gt2_txresetdone_out => open,
    ----------------- Transmit Ports - TX Polarity Control Ports ---------------
    gt2_txpolarity_in => '0',

    --GT3  (X0Y3)
    --____________________________CHANNEL PORTS________________________________
    --------------------------------- CPLL Ports -------------------------------
    gt3_cpllfbclklost_out => open,
    gt3_cplllock_out => open,
    gt3_cpllreset_in => '0',
    ---------------------------- Channel - DRP Ports  --------------------------
    gt3_drpaddr_in => (others => '0'),
    gt3_drpdi_in => (others => '0'),
    gt3_drpdo_out => open,
    gt3_drpen_in => '0',
    gt3_drprdy_out => open,
    gt3_drpwe_in => '0',
    --------------------------- Digital Monitor Ports --------------------------
    gt3_dmonitorout_out => open,
    --------------------- RX Initialization and Reset Ports --------------------
    gt3_eyescanreset_in => '0',
    -------------------------- RX Margin Analysis Ports ------------------------
    gt3_eyescandataerror_out => open,
    gt3_eyescantrigger_in => '0',
    ------------------- Receive Ports - RX Buffer Bypass Ports -----------------
    gt3_rxbufreset_in => '0',
    gt3_rxbufstatus_out => open,
    --------------------- Receive Ports - RX Equalizer Ports -------------------
    gt3_rxmonitorout_out => open,
    gt3_rxmonitorsel_in => (others => '0'),
    ------------- Receive Ports - RX Initialization and Reset Ports ------------
    gt3_gtrxreset_in => '0',
    gt3_rxpcsreset_in => '0',
    --------------------- TX Initialization and Reset Ports --------------------
    gt3_gttxreset_in => '0',
    gt3_txuserrdy_in => '1',
    ------------------ Transmit Ports - TX Data Path interface -----------------
    gt3_txdata_in => gt_tdata((3+1)*32-1 downto 3*32),
    ---------------- Transmit Ports - TX Driver and OOB signaling --------------
    gt3_gtxtxn_out => tx_n(3),
    gt3_gtxtxp_out => tx_p(3),
    ----------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
    gt3_txoutclkfabric_out => open,
    gt3_txoutclkpcs_out => open,
    --------------------- Transmit Ports - TX Gearbox Ports --------------------
    gt3_txcharisk_in => gt_charisk((3+1)*4-1 downto 3*4),
    ------------- Transmit Ports - TX Initialization and Reset Ports -----------
    gt3_txresetdone_out => open,
    ----------------- Transmit Ports - TX Polarity Control Ports ---------------
    gt3_txpolarity_in => '0',

    --GT4  (X0Y4)
    --____________________________CHANNEL PORTS________________________________
    --------------------------------- CPLL Ports -------------------------------
    gt4_cpllfbclklost_out => open,
    gt4_cplllock_out => open,
    gt4_cpllreset_in => '0',
    ---------------------------- Channel - DRP Ports  --------------------------
    gt4_drpaddr_in => (others => '0'),
    gt4_drpdi_in => (others => '0'),
    gt4_drpdo_out => open,
    gt4_drpen_in => '0',
    gt4_drprdy_out => open,
    gt4_drpwe_in => '0',
    --------------------------- Digital Monitor Ports --------------------------
    gt4_dmonitorout_out => open,
    --------------------- RX Initialization and Reset Ports --------------------
    gt4_eyescanreset_in => '0',
    -------------------------- RX Margin Analysis Ports ------------------------
    gt4_eyescandataerror_out => open,
    gt4_eyescantrigger_in => '0',
    ------------------- Receive Ports - RX Buffer Bypass Ports -----------------
    gt4_rxbufreset_in => '0',
    gt4_rxbufstatus_out => open,
    --------------------- Receive Ports - RX Equalizer Ports -------------------
    gt4_rxmonitorout_out => open,
    gt4_rxmonitorsel_in => (others => '0'),
    ------------- Receive Ports - RX Initialization and Reset Ports ------------
    gt4_gtrxreset_in => '0',
    gt4_rxpcsreset_in => '0',
    --------------------- TX Initialization and Reset Ports --------------------
    gt4_gttxreset_in => '0',
    gt4_txuserrdy_in => '1',
    ------------------ Transmit Ports - TX Data Path interface -----------------
    gt4_txdata_in => gt_tdata((4+1)*32-1 downto 4*32),
    ---------------- Transmit Ports - TX Driver and OOB signaling --------------
    gt4_gtxtxn_out => tx_n(4),
    gt4_gtxtxp_out => tx_p(4),
    ----------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
    gt4_txoutclkfabric_out => open,
    gt4_txoutclkpcs_out => open,
    --------------------- Transmit Ports - TX Gearbox Ports --------------------
    gt4_txcharisk_in => gt_charisk((4+1)*4-1 downto 4*4),
    ------------- Transmit Ports - TX Initialization and Reset Ports -----------
    gt4_txresetdone_out => open,
    ----------------- Transmit Ports - TX Polarity Control Ports ---------------
    gt4_txpolarity_in => '1',

    --GT5  (X0Y5)
    --____________________________CHANNEL PORTS________________________________
    --------------------------------- CPLL Ports -------------------------------
    gt5_cpllfbclklost_out => open,
    gt5_cplllock_out => open,
    gt5_cpllreset_in => '0',
    ---------------------------- Channel - DRP Ports  --------------------------
    gt5_drpaddr_in => (others => '0'),
    gt5_drpdi_in => (others => '0'),
    gt5_drpdo_out => open,
    gt5_drpen_in => '0',
    gt5_drprdy_out => open,
    gt5_drpwe_in => '0',
    --------------------------- Digital Monitor Ports --------------------------
    gt5_dmonitorout_out => open,
    --------------------- RX Initialization and Reset Ports --------------------
    gt5_eyescanreset_in => '0',
    -------------------------- RX Margin Analysis Ports ------------------------
    gt5_eyescandataerror_out => open,
    gt5_eyescantrigger_in => '0',
    ------------------- Receive Ports - RX Buffer Bypass Ports -----------------
    gt5_rxbufreset_in => '0',
    gt5_rxbufstatus_out => open,
    --------------------- Receive Ports - RX Equalizer Ports -------------------
    gt5_rxmonitorout_out => open,
    gt5_rxmonitorsel_in => (others => '0'),
    ------------- Receive Ports - RX Initialization and Reset Ports ------------
    gt5_gtrxreset_in => '0',
    gt5_rxpcsreset_in => '0',
    --------------------- TX Initialization and Reset Ports --------------------
    gt5_gttxreset_in => '0',
    gt5_txuserrdy_in => '1',
    ------------------ Transmit Ports - TX Data Path interface -----------------
    gt5_txdata_in => gt_tdata((5+1)*32-1 downto 5*32),
    ---------------- Transmit Ports - TX Driver and OOB signaling --------------
    gt5_gtxtxn_out => tx_n(5),
    gt5_gtxtxp_out => tx_p(5),
    ----------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
    gt5_txoutclkfabric_out => open,
    gt5_txoutclkpcs_out => open,
    --------------------- Transmit Ports - TX Gearbox Ports --------------------
    gt5_txcharisk_in => gt_charisk((5+1)*4-1 downto 5*4),
    ------------- Transmit Ports - TX Initialization and Reset Ports -----------
    gt5_txresetdone_out => open,
    ----------------- Transmit Ports - TX Polarity Control Ports ---------------
    gt5_txpolarity_in => '1',

    --GT6  (X0Y6)
    --____________________________CHANNEL PORTS________________________________
    --------------------------------- CPLL Ports -------------------------------
    gt6_cpllfbclklost_out => open,
    gt6_cplllock_out => open,
    gt6_cpllreset_in => '0',
    ---------------------------- Channel - DRP Ports  --------------------------
    gt6_drpaddr_in => (others => '0'),
    gt6_drpdi_in => (others => '0'),
    gt6_drpdo_out => open,
    gt6_drpen_in => '0',
    gt6_drprdy_out => open,
    gt6_drpwe_in => '0',
    --------------------------- Digital Monitor Ports --------------------------
    gt6_dmonitorout_out => open,
    --------------------- RX Initialization and Reset Ports --------------------
    gt6_eyescanreset_in => '0',
    -------------------------- RX Margin Analysis Ports ------------------------
    gt6_eyescandataerror_out => open,
    gt6_eyescantrigger_in => '0',
    ------------------- Receive Ports - RX Buffer Bypass Ports -----------------
    gt6_rxbufreset_in => '0',
    gt6_rxbufstatus_out => open,
    --------------------- Receive Ports - RX Equalizer Ports -------------------
    gt6_rxmonitorout_out => open,
    gt6_rxmonitorsel_in => (others => '0'),
    ------------- Receive Ports - RX Initialization and Reset Ports ------------
    gt6_gtrxreset_in => '0',
    gt6_rxpcsreset_in => '0',
    --------------------- TX Initialization and Reset Ports --------------------
    gt6_gttxreset_in => '0',
    gt6_txuserrdy_in => '1',
    ------------------ Transmit Ports - TX Data Path interface -----------------
    gt6_txdata_in => gt_tdata((6+1)*32-1 downto 6*32),
    ---------------- Transmit Ports - TX Driver and OOB signaling --------------
    gt6_gtxtxn_out => tx_n(6),
    gt6_gtxtxp_out => tx_p(6),
    ----------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
    gt6_txoutclkfabric_out => open,
    gt6_txoutclkpcs_out => open,
    --------------------- Transmit Ports - TX Gearbox Ports --------------------
    gt6_txcharisk_in => gt_charisk((6+1)*4-1 downto 6*4),
    ------------- Transmit Ports - TX Initialization and Reset Ports -----------
    gt6_txresetdone_out => open,
    ----------------- Transmit Ports - TX Polarity Control Ports ---------------
    gt6_txpolarity_in => '1',

    --GT7  (X0Y7)
    --____________________________CHANNEL PORTS________________________________
    --------------------------------- CPLL Ports -------------------------------
    gt7_cpllfbclklost_out => open,
    gt7_cplllock_out => open,
    gt7_cpllreset_in => '0',
    ---------------------------- Channel - DRP Ports  --------------------------
    gt7_drpaddr_in => (others => '0'),
    gt7_drpdi_in => (others => '0'),
    gt7_drpdo_out => open,
    gt7_drpen_in => '0',
    gt7_drprdy_out => open,
    gt7_drpwe_in => '0',
    --------------------------- Digital Monitor Ports --------------------------
    gt7_dmonitorout_out => open,
    --------------------- RX Initialization and Reset Ports --------------------
    gt7_eyescanreset_in => '0',
    -------------------------- RX Margin Analysis Ports ------------------------
    gt7_eyescandataerror_out => open,
    gt7_eyescantrigger_in => '0',
    ------------------- Receive Ports - RX Buffer Bypass Ports -----------------
    gt7_rxbufreset_in => '0',
    gt7_rxbufstatus_out => open,
    --------------------- Receive Ports - RX Equalizer Ports -------------------
    gt7_rxmonitorout_out => open,
    gt7_rxmonitorsel_in => (others => '0'),
    ------------- Receive Ports - RX Initialization and Reset Ports ------------
    gt7_gtrxreset_in => '0',
    gt7_rxpcsreset_in => '0',
    --------------------- TX Initialization and Reset Ports --------------------
    gt7_gttxreset_in => '0',
    gt7_txuserrdy_in => '1',
    ------------------ Transmit Ports - TX Data Path interface -----------------
    gt7_txdata_in => gt_tdata((7+1)*32-1 downto 7*32),
    ---------------- Transmit Ports - TX Driver and OOB signaling --------------
    gt7_gtxtxn_out => tx_n(7),
    gt7_gtxtxp_out => tx_p(7),
    ----------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
    gt7_txoutclkfabric_out => open,
    gt7_txoutclkpcs_out => open,
    --------------------- Transmit Ports - TX Gearbox Ports --------------------
    gt7_txcharisk_in => gt_charisk((7+1)*4-1 downto 7*4),
    ------------- Transmit Ports - TX Initialization and Reset Ports -----------
    gt7_txresetdone_out => open,
    ----------------- Transmit Ports - TX Polarity Control Ports ---------------
    gt7_txpolarity_in => '1',

    --____________________________COMMON PORTS________________________________
    GT0_QPLLLOCK_OUT => qpll0_lock,
    GT0_QPLLREFCLKLOST_OUT => open,
    GT0_QPLLOUTCLK_OUT => open,
    GT0_QPLLOUTREFCLK_OUT => open,
    --____________________________COMMON PORTS________________________________
    GT1_QPLLLOCK_OUT => qpll1_lock,
    GT1_QPLLREFCLKLOST_OUT => open,
    GT1_QPLLOUTCLK_OUT => open,
    GT1_QPLLOUTREFCLK_OUT => open,

    sysclk_in => drpclk
  );

end architecture;
