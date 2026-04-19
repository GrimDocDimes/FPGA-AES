## Nexys 4 DDR — Artix-7 XC7A100T-1CSG324C
## 100 MHz single-ended system clock (Pin E3)
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports sys_clk]
create_clock -add -name sys_clk_pin -period 10.000  -waveform {0.000 5.000} [get_ports sys_clk]
## USB-UART — BD exports as UART_rxd / UART_txd after make_bd_intf_pins_external
set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports UART_rxd]
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports UART_txd]
## Board configuration voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
