// ---------------------------------------------------------------------
// File name         : amiga_pll.v
// Module name       : Amiga_rPLL
// Description       : PLL wrapper to generate 28 MHz capture clock
//                     from the Amiga's 7M clock (~7.09 MHz PAL,
//                     ~7.16 MHz NTSC).
//
//                     Uses Gowin rPLL primitive with 4x multiplication.
//                     VCO runs at ~448 MHz, output divided by 16.
//
// NOTE: This PLL should be regenerated using the Gowin IP Core
//       Generator for your specific device. The parameters below
//       are for the GW2A-LV18PG256C8/I7 (Tang Primer 20K).
// ---------------------------------------------------------------------

module Amiga_rPLL (clkout, lock, clkin);

output clkout;
output lock;
input  clkin;

wire clkoutp_o;
wire clkoutd_o;
wire clkoutd3_o;
wire gw_gnd;

assign gw_gnd = 1'b0;

rPLL rpll_inst (
    .CLKOUT(clkout),
    .LOCK(lock),
    .CLKOUTP(clkoutp_o),
    .CLKOUTD(clkoutd_o),
    .CLKOUTD3(clkoutd3_o),
    .RESET(gw_gnd),
    .RESET_P(gw_gnd),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .FBDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .IDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .PSDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DUTYDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FDLY({gw_gnd,gw_gnd,gw_gnd,gw_gnd})
);

// PLL parameters for 7MHz -> 28MHz (4x multiplication)
// Fout = FCLKIN * (FBDIV_SEL+1) / (IDIV_SEL+1) = 7 * 4 / 1 = 28 MHz
// Fvco = Fout * ODIV_SEL = 28 * 32 = 896 MHz
// VCO range for GW2A-18C: 500-1250 MHz (896 MHz is valid)
// Valid ODIV_SEL values: 2,4,8,16,32,48,64,80,96,112,128
// Valid FBDIV_SEL range: 0-63
defparam rpll_inst.FCLKIN = "7";
defparam rpll_inst.DYN_IDIV_SEL = "false";
defparam rpll_inst.IDIV_SEL = 0;            // IDIV = 1
defparam rpll_inst.DYN_FBDIV_SEL = "false";
defparam rpll_inst.FBDIV_SEL = 3;           // FBDIV = 4
defparam rpll_inst.DYN_ODIV_SEL = "false";
defparam rpll_inst.ODIV_SEL = 32;           // Output divide by 32
defparam rpll_inst.PSDA_SEL = "0000";
defparam rpll_inst.DYN_DA_EN = "true";
defparam rpll_inst.DUTYDA_SEL = "1000";
defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL = "internal";
defparam rpll_inst.CLKOUT_BYPASS = "false";
defparam rpll_inst.CLKOUTP_BYPASS = "false";
defparam rpll_inst.CLKOUTD_BYPASS = "false";
defparam rpll_inst.DYN_SDIV_SEL = 2;
defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
defparam rpll_inst.DEVICE = "GW2A-18C";

endmodule
