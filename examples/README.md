The VHDL-JESD core needs to be wired up to the transceivers. This folder contains two examples using
either Xilinx's [7 Series FPGA Transceivers Wizard][1] or [UltraScale FPGAs Transceivers Wizard][2]
from Vivado 2017.2. There are some additional bits-and-bobs of logic to buffer and synchronize
`syncn`, buffer the transceiver reference clock and generate appropriate reset pulses.


[1]: https://www.xilinx.com/products/intellectual-property/7-series_fpga_transceivers_wizard.html
[2]: https://www.xilinx.com/products/intellectual-property/ultrascale_transceivers_wizard.html
