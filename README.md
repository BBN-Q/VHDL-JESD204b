# VHDL-JESD204b

JESD204b module written in VHDL. Verified against [Xilinx JESD204b IP
core](https://www.xilinx.com/products/intellectual-property/ef-di-jesd204.html#overview).

The module has had only limited testing and validation. We have got it working
with a KCU105 development board and the
[AD9164-FMC-EBZ](http://www.analog.com/en/design-center/evaluation-hardware-and-software/evaluation-boards-kits/EVAL-AD916X.html).

## Transmit module

### Implemented Features

1. parameters for number lanes (L), octets per frame (M), frames per multiframe
(F) specified through module generics.
2. ILA sequence
3. optional scrambler

### Not Yet Implemented

1. PRBS test patterns
2. Lane mapping

## Receive module

Not yet implemented.

## License

This code is licensed under the Apache v2 license.  See the LICENSE file for
more information.

## Funding

This software was funded in part by the Office of the Director of National
Intelligence (ODNI), Intelligence Advanced Research Projects Activity (IARPA),
through the Army Research Office contract No. W911NF-14-1-0124. All statements
of fact, opinion or conclusions contained herein are those of the authors and
should not be construed as representing the official views or policies of IARPA,
the ODNI, or the US Government.
