## Nexys 4 DDR — AES JTAG-to-AXI design
## 100 MHz single-ended system clock (Pin E3)
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports sys_clk]
create_clock -add -name sys_clk_pin -period 10.000  -waveform {0.000 5.000} [get_ports sys_clk]
## Board configuration voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
