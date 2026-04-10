//Copyright (C)2014-2019 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Description: Amiga DENISE Flicker Fixer timing constraints

// Board oscillator - 27 MHz
create_clock -name I_clk -period 37.04 [get_ports {I_clk}] -add

// Amiga 7M clock input (~7.09 MHz PAL / ~7.16 MHz NTSC)
// Use worst-case (fastest) period: 1/7.16MHz = 139.66 ns
create_clock -name I_denise_7m -period 139.66 [get_ports {I_denise_7m}] -add

// Clock domain crossings - declare async clock groups
set_clock_groups -asynchronous -group {I_clk} -group {I_denise_7m}
