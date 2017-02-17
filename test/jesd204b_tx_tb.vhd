library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity jesd204b_tx_tb is
end;

architecture bench of jesd204b_tx_tb is


	signal gt0_txdata             : std_logic_vector(31 downto 0) := (others => '0');
	signal gt0_txcharisk          : std_logic_vector(3 downto 0) := (others => '0');
	signal gt1_txdata             : std_logic_vector(31 downto 0) := (others => '0');
	signal gt1_txcharisk          : std_logic_vector(3 downto 0) := (others => '0');
	signal gt2_txdata             : std_logic_vector(31 downto 0) := (others => '0');
	signal gt2_txcharisk          : std_logic_vector(3 downto 0) := (others => '0');
	signal gt3_txdata             : std_logic_vector(31 downto 0) := (others => '0');
	signal gt3_txcharisk          : std_logic_vector(3 downto 0) := (others => '0');
	signal tx_reset_done          : std_logic := '0';
	signal gt_prbssel_out         : std_logic_vector(3 downto 0) := (others => '0');
	signal tx_reset_gt            : std_logic := '0';
	signal tx_core_clk            : std_logic := '0';
	signal s_axi_aclk             : std_logic := '0';
	signal s_axi_aresetn          : std_logic := '0';
	signal s_axi_awaddr           : std_logic_vector(11 downto 0) := (others => '0');
	signal s_axi_awvalid          : std_logic := '0';
	signal s_axi_awready          : std_logic := '0';
	signal s_axi_wdata            : std_logic_vector(31 downto 0) := (others => '0');
	signal s_axi_wstrb            : std_logic_vector(3 downto 0) := (others => '0');
	signal s_axi_wvalid           : std_logic := '0';
	signal s_axi_wready           : std_logic := '0';
	signal s_axi_bresp            : std_logic_vector(1 downto 0) := (others => '0');
	signal s_axi_bvalid           : std_logic := '0';
	signal s_axi_bready           : std_logic := '1';
	signal s_axi_araddr           : std_logic_vector(11 downto 0) := (others => '0');
	signal s_axi_arvalid          : std_logic := '0';
	signal s_axi_arready          : std_logic := '0';
	signal s_axi_rdata            : std_logic_vector(31 downto 0) := (others => '0');
	signal s_axi_rresp            : std_logic_vector(1 downto 0) := (others => '0');
	signal s_axi_rvalid           : std_logic := '0';
	signal s_axi_rready           : std_logic := '0';
	signal tx_reset               : std_logic := '0';
	signal tx_sysref              : std_logic := '0';
	signal tx_start_of_frame      : std_logic_vector(3 downto 0) := (others => '0');
	signal tx_start_of_multiframe : std_logic_vector(3 downto 0) := (others => '0');
	signal tx_aresetn             : std_logic := '0';
	signal tx_tdata               : std_logic_vector(127 downto 0) := (others => '0');
	signal tx_tready              : std_logic := '0';

	signal tx_sync_xilinx, tx_sync_bbn : std_logic := '0';

	signal rst_bbn : std_logic := '1';
	signal tx_tready_bbn : std_logic := '0';
	signal gt_tdata : std_logic_vector(127 downto 0);
	type gt_tdata_array_t is array(3 downto 0) of std_logic_vector(31 downto 0);
	signal gt_tdata_array : gt_tdata_array_t;
	signal gt_charisk : std_logic_vector(15 downto 0);
	type gt_charisk_array_t is array(3 downto 0) of std_logic_vector(3 downto 0);
	signal gt_charisk_array : gt_charisk_array_t;

  constant axi_clock_period : time := 10 ns;
	constant core_clock_period : time := 5.5333 ns;
  signal stop_the_clocks : boolean;

begin

uut_xilinx: entity work.jesd204_xilinx
	port map (
		gt0_txdata             => gt0_txdata,
		gt0_txcharisk          => gt0_txcharisk,
		gt1_txdata             => gt1_txdata,
		gt1_txcharisk          => gt1_txcharisk,
		gt2_txdata             => gt2_txdata,
		gt2_txcharisk          => gt2_txcharisk,
		gt3_txdata             => gt3_txdata,
		gt3_txcharisk          => gt3_txcharisk,
		tx_reset_done          => tx_reset_done,
		gt_prbssel_out         => gt_prbssel_out,
		tx_reset_gt            => tx_reset_gt,
		tx_core_clk            => tx_core_clk,
		s_axi_aclk             => s_axi_aclk,
		s_axi_aresetn          => s_axi_aresetn,
		s_axi_awaddr           => s_axi_awaddr,
		s_axi_awvalid          => s_axi_awvalid,
		s_axi_awready          => s_axi_awready,
		s_axi_wdata            => s_axi_wdata,
		s_axi_wstrb            => s_axi_wstrb,
		s_axi_wvalid           => s_axi_wvalid,
		s_axi_wready           => s_axi_wready,
		s_axi_bresp            => s_axi_bresp,
		s_axi_bvalid           => s_axi_bvalid,
		s_axi_bready           => s_axi_bready,
		s_axi_araddr           => s_axi_araddr,
		s_axi_arvalid          => s_axi_arvalid,
		s_axi_arready          => s_axi_arready,
		s_axi_rdata            => s_axi_rdata,
		s_axi_rresp            => s_axi_rresp,
		s_axi_rvalid           => s_axi_rvalid,
		s_axi_rready           => s_axi_rready,
		tx_reset               => tx_reset,
		tx_sysref              => tx_sysref,
		tx_start_of_frame      => tx_start_of_frame,
		tx_start_of_multiframe => tx_start_of_multiframe,
		tx_aresetn             => tx_aresetn,
		tx_tdata               => tx_tdata,
		tx_tready              => tx_tready,
		tx_sync                => tx_sync_xilinx
	);

uut_bbn : entity work.jesd204b_tx
	generic map (
		M => 2,
		L => 4,
		F => 1,
		K => 32
	)
	port map (
		clk => tx_core_clk,
		rst => rst_bbn,

		syncn => tx_sync_bbn,
		sysref => tx_sysref,

		tx_tdata => tx_tdata,
		tx_tready => tx_tready_bbn,

		gt_tdata => gt_tdata,
		gt_charisk => gt_charisk
	);

split_gt_data : for ct in 0 to 3 generate
	gt_tdata_array(ct) <= gt_tdata(32*(ct+1)-1 downto 32*ct);
	gt_charisk_array(ct) <= gt_charisk(4*(ct+1)-1 downto 4*ct);
end generate;


s_axi_aclk <= not s_axi_aclk after axi_clock_period / 2 when not stop_the_clocks;
tx_core_clk <= not tx_core_clk after core_clock_period /2 when not stop_the_clocks;
tx_sysref <= not tx_sysref after 2 * core_clock_period when not stop_the_clocks;

stimulus: process

-- helper procedure to write to Xilinx JESD AXI configuration register
procedure write_xilinx_cfg_reg(
	addr : std_logic_vector(11 downto 0);
	val : std_logic_vector(31 downto 0)) is
begin
	wait until rising_edge(s_axi_aclk);
	s_axi_awaddr <= addr;
	s_axi_awvalid <= '1';
	wait until rising_edge(s_axi_aclk) and s_axi_awready = '1';
	s_axi_awvalid <= '0';
	s_axi_wdata <= val;
	s_axi_wstrb <= b"1111";
	s_axi_wvalid <= '1';
	wait until rising_edge(s_axi_aclk) and s_axi_wready = '1';
	s_axi_wvalid <= '0';
	wait until rising_edge(s_axi_aclk) and s_axi_bvalid = '1';
end procedure write_xilinx_cfg_reg;

-- helper procedure to read a Xilinx JESD AXI configuration registers
procedure read_xilinx_cfg_reg(addr : std_logic_vector(11 downto 0)) is
	variable l : line;
begin
	wait until rising_edge(s_axi_aclk);
	s_axi_araddr <= addr;
	s_axi_arvalid <= '1';
	wait until rising_edge(s_axi_aclk) and s_axi_arready = '1';
	s_axi_arvalid <= '0';
	s_axi_rready <= '1';
	wait until rising_edge(s_axi_aclk) and s_axi_rvalid = '1';
	s_axi_rready <= '0';
	write(l, "Xilinx JESD cfg reg at addr " & to_hstring(addr) & " is " & to_hstring(s_axi_rdata) );
	writeline(output, l);
end procedure read_xilinx_cfg_reg;

begin

tx_reset <= '1';
rst_bbn <= '1';
wait for 400 ns;

s_axi_aresetn <= '1';
wait for 100 ns;

-- check Xilinx core version
read_xilinx_cfg_reg(x"000");
-- check subclass mode
read_xilinx_cfg_reg(x"02c");

-- write Xilinx core configuration registers
write_xilinx_cfg_reg(x"00C", x"0000_0000"); -- scrambling
write_xilinx_cfg_reg(x"020", x"0000_0000"); -- F-1
write_xilinx_cfg_reg(x"024", x"0000_001f"); -- K-1
write_xilinx_cfg_reg(x"02C", x"0000_0000"); --subclass 0

--ILA config data for each lane
for ct in 0 to 3 loop
	write_xilinx_cfg_reg(std_logic_vector(to_unsigned(16#80C# + ct*64, 12)), x"00000bad"); -- BID - DID
	write_xilinx_cfg_reg(std_logic_vector(to_unsigned(16#810# + ct*64, 12)), x"000f0f01"); -- N' - N - M
	write_xilinx_cfg_reg(std_logic_vector(to_unsigned(16#814# + ct*64, 12)), x"00000000"); -- S-1
end loop;

-- check subclass mode
read_xilinx_cfg_reg(x"02c");


wait for 100 ns;
tx_reset <= '1';
tx_reset_done <='0';
wait for 400 ns;
tx_reset <= '0';
rst_bbn <= '0';
wait for 400 ns;
tx_reset_done <= '1';

wait until rising_edge(tx_core_clk) and  tx_aresetn = '1';
wait for 100ns;

-- write a AXI reset
write_xilinx_cfg_reg(x"004", x"0000_0001");
tx_reset_done <= '0';
wait for 400 ns;
tx_reset_done <= '1';

for ct in 0 to 2 loop
	read_xilinx_cfg_reg(x"004");
	wait for 100 ns;
end loop;


tx_sync_xilinx <= '1';
wait for 110 ns; -- Xilinx seems to take longer to respond to syncn
tx_sync_bbn <= '1';

wait for 1 us;
wait until rising_edge(tx_core_clk);
tx_tdata <= x"abcdef01abcdef02abcdef03abcdef04";
wait for 100 ns;
wait until rising_edge(tx_core_clk);
tx_tdata <= (others => '0');


wait;
stop_the_clocks <= true;
wait;
end process;


end;
