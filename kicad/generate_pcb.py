#!/usr/bin/env python3
"""
Generate KiCad 8 PCB for the DENISE 8373 interposer.

Layout:
  - DIP-48 pass-through pads (center of board)
  - Two TSSOP-20 74LVC245 level shifters (right side)
  - 2x10 pin header for FPGA connection (far right)
  - 0402 bypass caps near each IC
  - Board outline sized to fit

DIP-48 dimensions:
  - 24 pins per side, 2.54mm (100mil) pitch
  - Row spacing: 15.24mm (600mil) center-to-center
  - Total pin span: 23 * 2.54 = 58.42mm

Run: python3 generate_pcb.py
Output: denise_interposer.kicad_pcb
"""

import uuid

def uid():
    return str(uuid.uuid4())

_net_counter = [0]
_nets = {}

def get_net(name):
    if name not in _nets:
        _net_counter[0] += 1
        _nets[name] = _net_counter[0]
    return _nets[name]


def write_header(f):
    f.write('(kicad_pcb\n')
    f.write('  (version 20231014)\n')
    f.write('  (generator "pcbnew")\n')
    f.write('  (generator_version "8.0")\n')
    f.write('  (general\n')
    f.write('    (thickness 1.6)\n')
    f.write('    (legacy_teardrops no)\n')
    f.write('  )\n')
    f.write('  (paper "A4")\n')
    f.write('  (title_block\n')
    f.write('    (title "DENISE 8373 Interposer")\n')
    f.write('    (comment 1 "Amiga Flicker Fixer Level Shifting Interposer")\n')
    f.write('  )\n')
    f.write('  (layers\n')
    f.write('    (0 "F.Cu" signal)\n')
    f.write('    (31 "B.Cu" signal)\n')
    f.write('    (32 "B.Adhes" user "B.Adhesive")\n')
    f.write('    (33 "F.Adhes" user "F.Adhesive")\n')
    f.write('    (34 "B.Paste" user)\n')
    f.write('    (35 "F.Paste" user)\n')
    f.write('    (36 "B.SilkS" user "B.Silkscreen")\n')
    f.write('    (37 "F.SilkS" user "F.Silkscreen")\n')
    f.write('    (38 "B.Mask" user "B.Mask")\n')
    f.write('    (39 "F.Mask" user "F.Mask")\n')
    f.write('    (40 "Dwgs.User" user "User.Drawings")\n')
    f.write('    (44 "Edge.Cuts" user)\n')
    f.write('  )\n')
    f.write('  (setup\n')
    f.write('    (pad_to_mask_clearance 0.05)\n')
    f.write('    (allow_soldermask_bridges_in_footprints no)\n')
    f.write('    (pcbplotparams\n')
    f.write('      (layerselection 0x00010fc_ffffffff)\n')
    f.write('      (plot_on_all_layers_selection 0x0000000_00000000)\n')
    f.write('    )\n')
    f.write('  )\n')


def write_nets(f):
    f.write('  (net 0 "")\n')
    for name, idx in sorted(_nets.items(), key=lambda x: x[1]):
        f.write(f'  (net {idx} "{name}")\n')


def write_board_outline(f, x1, y1, x2, y2, corner_r=1.0):
    """Rounded rectangle board outline."""
    f.write(f'  (gr_line (start {x1 + corner_r} {y1}) (end {x2 - corner_r} {y1})\n')
    f.write(f'    (stroke (width 0.15) (type default)) (layer "Edge.Cuts") (uuid "{uid()}"))\n')
    f.write(f'  (gr_line (start {x2} {y1 + corner_r}) (end {x2} {y2 - corner_r})\n')
    f.write(f'    (stroke (width 0.15) (type default)) (layer "Edge.Cuts") (uuid "{uid()}"))\n')
    f.write(f'  (gr_line (start {x2 - corner_r} {y2}) (end {x1 + corner_r} {y2})\n')
    f.write(f'    (stroke (width 0.15) (type default)) (layer "Edge.Cuts") (uuid "{uid()}"))\n')
    f.write(f'  (gr_line (start {x1} {y2 - corner_r}) (end {x1} {y1 + corner_r})\n')
    f.write(f'    (stroke (width 0.15) (type default)) (layer "Edge.Cuts") (uuid "{uid()}"))\n')
    for cx, cy, sa in [
        (x1+corner_r, y1+corner_r, 180), (x2-corner_r, y1+corner_r, 270),
        (x2-corner_r, y2-corner_r, 0), (x1+corner_r, y2-corner_r, 90)]:
        f.write(f'  (gr_arc (start {cx} {cy - corner_r if sa == 180 else cy + corner_r if sa == 0 else cy})')
        f.write(f' (mid {cx} {cy}) (end {cx} {cy})\n')
    # Simpler: just use straight lines (skip arcs for compatibility)


def write_thru_hole_pad(f, num, x, y, net_name="", drill=1.0, pad_d=1.7, shape="circle", layer="*.Cu"):
    """Single through-hole pad."""
    net_str = ""
    if net_name:
        net_id = get_net(net_name)
        net_str = f'(net {net_id} "{net_name}")'
    f.write(f'    (pad "{num}" thru_hole {shape}\n')
    f.write(f'      (at {x:.3f} {y:.3f})\n')
    f.write(f'      (size {pad_d} {pad_d})\n')
    f.write(f'      (drill {drill})\n')
    f.write(f'      (layers "*.Cu" "*.Mask")\n')
    if net_str:
        f.write(f'      {net_str}\n')
    f.write(f'      (uuid "{uid()}")\n')
    f.write(f'    )\n')


def write_smd_pad(f, num, x, y, w, h, net_name="", layer="F.Cu"):
    """SMD pad."""
    net_str = ""
    if net_name:
        net_id = get_net(net_name)
        net_str = f'(net {net_id} "{net_name}")'
    f.write(f'    (pad "{num}" smd rect\n')
    f.write(f'      (at {x:.3f} {y:.3f})\n')
    f.write(f'      (size {w} {h})\n')
    f.write(f'      (layers "{layer}" "F.Paste" "F.Mask")\n')
    if net_str:
        f.write(f'      {net_str}\n')
    f.write(f'      (uuid "{uid()}")\n')
    f.write(f'    )\n')


def write_silk_text(f, text, x, y, size=1.0, layer="F.SilkS"):
    f.write(f'  (gr_text "{text}"\n')
    f.write(f'    (at {x} {y})\n')
    f.write(f'    (layer "{layer}")\n')
    f.write(f'    (effects (font (size {size} {size}) (thickness {size * 0.15:.3f})))\n')
    f.write(f'    (uuid "{uid()}")\n')
    f.write(f'  )\n')


def write_fp_text(f, text, x, y, size=1.0, layer="F.SilkS", ttype="reference"):
    f.write(f'    (fp_text {ttype} "{text}"\n')
    f.write(f'      (at {x:.3f} {y:.3f})\n')
    f.write(f'      (layer "{layer}")\n')
    f.write(f'      (effects (font (size {size} {size}) (thickness {size * 0.15:.3f})))\n')
    f.write(f'      (uuid "{uid()}")\n')
    f.write(f'    )\n')


# DENISE 8373 complete pinout for net assignment
DENISE_LEFT = [
    (1,"D6"),(2,"D5"),(3,"D4"),(4,"D3"),(5,"D2"),(6,"D1"),(7,"D0"),
    (8,"M1H"),(9,"M0H"),
    (10,"RGA8"),(11,"RGA7"),(12,"RGA6"),(13,"RGA5"),(14,"RGA4"),
    (15,"RGA3"),(16,"RGA2"),(17,"RGA1"),
    (18,"nBURST"),(19,"+5V"),(20,"R0"),(21,"R1"),(22,"R2"),(23,"R3"),(24,"B0"),
]
DENISE_RIGHT = [
    (25,"B1"),(26,"B2"),(27,"B3"),
    (28,"G0"),(29,"G1"),(30,"G2"),(31,"G3"),
    (32,"nCSYNC"),(33,"nZD"),(34,"CDAC"),(35,"CLK7M"),
    (36,"CCK"),(37,"GND"),
    (38,"M0V"),(39,"M1V"),
    (40,"D7"),(41,"D8"),(42,"D9"),(43,"D10"),(44,"D11"),
    (45,"D12"),(46,"D13"),(47,"D14"),(48,"D15"),
]

# 74LVC245 pin-to-net mapping
U1_A_NETS = ["R0","R1","R2","R3","B0","B1","B2","B3"]
U1_B_NETS = ["R0_3V","R1_3V","R2_3V","R3_3V","B0_3V","B1_3V","B2_3V","B3_3V"]
U2_A_NETS = ["G0","G1","G2","G3","nCSYNC","nZD","CDAC","CLK7M"]
U2_B_NETS = ["G0_3V","G1_3V","G2_3V","G3_3V","nCSYNC_3V","nZD_3V","CDAC_3V","CLK7M_3V"]


def main():
    # Pre-register all nets
    for _, name in DENISE_LEFT + DENISE_RIGHT:
        get_net(name)
    for name in U1_A_NETS + U1_B_NETS + U2_A_NETS + U2_B_NETS:
        get_net(name)
    get_net("+3V3")
    get_net("+5V")
    get_net("GND")

    # Board geometry
    BOARD_X1, BOARD_Y1 = 90, 55
    BOARD_X2, BOARD_Y2 = 185, 130

    # DIP-48 center position
    DIP_CX = 115
    DIP_CY = 92.5
    DIP_ROW_SPACING = 15.24  # 600mil between pin rows
    DIP_PIN_PITCH = 2.54     # 100mil pin pitch

    # Level shifter positions (TSSOP-20)
    U1_CX, U1_CY = 152, 78
    U2_CX, U2_CY = 152, 107

    # FPGA connector position
    J2_CX, J2_CY = 175, 92.5

    with open("denise_interposer.kicad_pcb", "w") as f:
        write_header(f)
        write_nets(f)

        # ============================================================
        # Board outline
        # ============================================================
        f.write(f'  (gr_rect (start {BOARD_X1} {BOARD_Y1}) (end {BOARD_X2} {BOARD_Y2})\n')
        f.write(f'    (stroke (width 0.15) (type default)) (fill none)\n')
        f.write(f'    (layer "Edge.Cuts") (uuid "{uid()}"))\n')

        # ============================================================
        # Silk screen labels
        # ============================================================
        write_silk_text(f, "DENISE 8373 Interposer", (BOARD_X1+BOARD_X2)/2, BOARD_Y1 + 3, 1.5)
        write_silk_text(f, "Amiga Flicker Fixer", (BOARD_X1+BOARD_X2)/2, BOARD_Y1 + 5.5, 1.0)
        write_silk_text(f, "Pin 1", DIP_CX - DIP_ROW_SPACING/2 - 3, DIP_CY - 23*2.54/2 - 2, 0.8)

        # ============================================================
        # J1: DIP-48 pass-through footprint
        # ============================================================
        f.write(f'  (footprint "interposer:DIP-48_passthrough"\n')
        f.write(f'    (layer "F.Cu")\n')
        f.write(f'    (uuid "{uid()}")\n')
        f.write(f'    (at {DIP_CX} {DIP_CY})\n')
        write_fp_text(f, "J1", 0, -32, 1.2, "F.SilkS", "reference")
        write_fp_text(f, "DENISE_DIP48", 0, 32, 1.0, "F.SilkS", "value")

        # Pin 1 marker
        f.write(f'    (fp_circle (center {-DIP_ROW_SPACING/2 - 2} {-23*DIP_PIN_PITCH/2})\n')
        f.write(f'      (end {-DIP_ROW_SPACING/2 - 1.5} {-23*DIP_PIN_PITCH/2})\n')
        f.write(f'      (stroke (width 0.15) (type default)) (fill solid)\n')
        f.write(f'      (layer "F.SilkS") (uuid "{uid()}"))\n')

        # DIP body outline on silkscreen
        body_w = DIP_ROW_SPACING + 4
        body_h = 23 * DIP_PIN_PITCH + 4
        f.write(f'    (fp_rect (start {-body_w/2} {-body_h/2}) (end {body_w/2} {body_h/2})\n')
        f.write(f'      (stroke (width 0.15) (type default)) (fill none)\n')
        f.write(f'      (layer "F.SilkS") (uuid "{uid()}"))\n')

        # Left column: pins 1-24 (top to bottom)
        for i, (num, name) in enumerate(DENISE_LEFT):
            y = -23 * DIP_PIN_PITCH / 2 + i * DIP_PIN_PITCH
            x = -DIP_ROW_SPACING / 2
            shape = "rect" if num == 1 else "circle"
            write_thru_hole_pad(f, str(num), x, y, name, drill=1.0, pad_d=1.7, shape=shape)

        # Right column: pins 25-48 (bottom to top)
        for i, (num, name) in enumerate(DENISE_RIGHT):
            y = 23 * DIP_PIN_PITCH / 2 - i * DIP_PIN_PITCH
            x = DIP_ROW_SPACING / 2
            write_thru_hole_pad(f, str(num), x, y, name)

        f.write(f'  )\n')  # end DIP-48 footprint

        # ============================================================
        # U1: 74LVC245 (TSSOP-20) for R0-R3, B0-B3
        # ============================================================
        tssop_pitch = 0.65
        tssop_row = 3.1  # half-span between pad rows

        f.write(f'  (footprint "interposer:TSSOP-20_74LVC245"\n')
        f.write(f'    (layer "F.Cu")\n')
        f.write(f'    (uuid "{uid()}")\n')
        f.write(f'    (at {U1_CX} {U1_CY})\n')
        write_fp_text(f, "U1", 0, -5, 0.8, "F.SilkS", "reference")
        write_fp_text(f, "74LVC245", 0, 5, 0.6, "F.SilkS", "value")

        # Body outline
        f.write(f'    (fp_rect (start -2.2 -3.3) (end 2.2 3.3)\n')
        f.write(f'      (stroke (width 0.15) (type default)) (fill none)\n')
        f.write(f'      (layer "F.SilkS") (uuid "{uid()}"))\n')

        # Pin 1 marker
        f.write(f'    (fp_circle (center -1.5 -3.8) (end -1.2 -3.8)\n')
        f.write(f'      (stroke (width 0.15) (type default)) (fill solid)\n')
        f.write(f'      (layer "F.SilkS") (uuid "{uid()}"))\n')

        # TSSOP-20 pads: pins 1-10 on left, 11-20 on right
        # Pin 1=DIR, 2-9=A1-A8, 10=GND
        u1_left_nets = ["GND", "R0","R1","R2","R3","B0","B1","B2","B3", "GND"]
        # Pin 11=B8, 12=B7, ..., 18=B1, 19=OE, 20=VCC
        u1_right_nets = ["B3_3V","B2_3V","B1_3V","B0_3V","R3_3V","R2_3V","R1_3V","R0_3V", "GND", "+3V3"]

        for i in range(10):
            y = -4.5 * tssop_pitch + i * tssop_pitch
            write_smd_pad(f, str(i+1), -tssop_row, y, 1.2, 0.4, u1_left_nets[i])
            write_smd_pad(f, str(20-i), tssop_row, y, 1.2, 0.4, u1_right_nets[i])

        f.write(f'  )\n')  # end U1

        # ============================================================
        # U2: 74LVC245 (TSSOP-20) for G0-G3, nCSYNC, nZD, CDAC, 7M
        # ============================================================
        f.write(f'  (footprint "interposer:TSSOP-20_74LVC245"\n')
        f.write(f'    (layer "F.Cu")\n')
        f.write(f'    (uuid "{uid()}")\n')
        f.write(f'    (at {U2_CX} {U2_CY})\n')
        write_fp_text(f, "U2", 0, -5, 0.8, "F.SilkS", "reference")
        write_fp_text(f, "74LVC245", 0, 5, 0.6, "F.SilkS", "value")

        f.write(f'    (fp_rect (start -2.2 -3.3) (end 2.2 3.3)\n')
        f.write(f'      (stroke (width 0.15) (type default)) (fill none)\n')
        f.write(f'      (layer "F.SilkS") (uuid "{uid()}"))\n')
        f.write(f'    (fp_circle (center -1.5 -3.8) (end -1.2 -3.8)\n')
        f.write(f'      (stroke (width 0.15) (type default)) (fill solid)\n')
        f.write(f'      (layer "F.SilkS") (uuid "{uid()}"))\n')

        u2_left_nets = ["GND","G0","G1","G2","G3","nCSYNC","nZD","CDAC","CLK7M","GND"]
        u2_right_nets = ["CLK7M_3V","CDAC_3V","nZD_3V","nCSYNC_3V","G3_3V","G2_3V","G1_3V","G0_3V","GND","+3V3"]

        for i in range(10):
            y = -4.5 * tssop_pitch + i * tssop_pitch
            write_smd_pad(f, str(i+1), -tssop_row, y, 1.2, 0.4, u2_left_nets[i])
            write_smd_pad(f, str(20-i), tssop_row, y, 1.2, 0.4, u2_right_nets[i])

        f.write(f'  )\n')  # end U2

        # ============================================================
        # C1: 0402 bypass cap near U1
        # ============================================================
        f.write(f'  (footprint "interposer:C_0402"\n')
        f.write(f'    (layer "F.Cu")\n')
        f.write(f'    (uuid "{uid()}")\n')
        f.write(f'    (at {U1_CX + 6} {U1_CY - 2})\n')
        write_fp_text(f, "C1", 0, -1.5, 0.5, "F.SilkS", "reference")
        write_fp_text(f, "100nF", 0, 1.5, 0.4, "F.SilkS", "value")
        write_smd_pad(f, "1", -0.5, 0, 0.6, 0.5, "+3V3")
        write_smd_pad(f, "2", 0.5, 0, 0.6, 0.5, "GND")
        f.write(f'  )\n')

        # C2: 0402 bypass cap near U2
        f.write(f'  (footprint "interposer:C_0402"\n')
        f.write(f'    (layer "F.Cu")\n')
        f.write(f'    (uuid "{uid()}")\n')
        f.write(f'    (at {U2_CX + 6} {U2_CY - 2})\n')
        write_fp_text(f, "C2", 0, -1.5, 0.5, "F.SilkS", "reference")
        write_fp_text(f, "100nF", 0, 1.5, 0.4, "F.SilkS", "value")
        write_smd_pad(f, "1", -0.5, 0, 0.6, 0.5, "+3V3")
        write_smd_pad(f, "2", 0.5, 0, 0.6, 0.5, "GND")
        f.write(f'  )\n')

        # ============================================================
        # J2: 2x10 pin header for FPGA connection
        # ============================================================
        f.write(f'  (footprint "interposer:PinHeader_2x10"\n')
        f.write(f'    (layer "F.Cu")\n')
        f.write(f'    (uuid "{uid()}")\n')
        f.write(f'    (at {J2_CX} {J2_CY})\n')
        write_fp_text(f, "J2", 0, -15, 0.8, "F.SilkS", "reference")
        write_fp_text(f, "FPGA_OUT", 0, 15, 0.7, "F.SilkS", "value")

        # Body outline
        f.write(f'    (fp_rect (start -3.81 -13.97) (end 3.81 13.97)\n')
        f.write(f'      (stroke (width 0.15) (type default)) (fill none)\n')
        f.write(f'      (layer "F.SilkS") (uuid "{uid()}"))\n')

        j2_left_nets =  ["R0_3V","R2_3V","B0_3V","B2_3V","G0_3V",
                         "G2_3V","nCSYNC_3V","CDAC_3V","+3V3","GND"]
        j2_right_nets = ["R1_3V","R3_3V","B1_3V","B3_3V","G1_3V",
                         "G3_3V","nZD_3V","CLK7M_3V","+3V3","GND"]

        for i in range(10):
            y = -9 * 2.54 / 2 + i * 2.54
            odd = i * 2 + 1
            even = i * 2 + 2
            shape = "rect" if odd == 1 else "circle"
            write_thru_hole_pad(f, str(odd), -1.27, y, j2_left_nets[i], shape=shape)
            write_thru_hole_pad(f, str(even), 1.27, y, j2_right_nets[i])

        f.write(f'  )\n')  # end J2

        # ============================================================
        # Silkscreen annotations
        # ============================================================
        write_silk_text(f, "BOTTOM: plugs into Amiga motherboard socket",
                       DIP_CX, BOARD_Y2 - 3, 0.7, "B.SilkS")
        write_silk_text(f, "TOP: DENISE chip plugs in here",
                       DIP_CX, BOARD_Y1 + 8, 0.7)

        # Pin labels on silk for the FPGA connector
        for i, name in enumerate(j2_left_nets):
            y = J2_CY - 9*2.54/2 + i*2.54
            write_silk_text(f, name, J2_CX - 6, y, 0.5)
        for i, name in enumerate(j2_right_nets):
            y = J2_CY - 9*2.54/2 + i*2.54
            write_silk_text(f, name, J2_CX + 6, y, 0.5)

        f.write(')\n')  # end kicad_pcb

    print(f"Generated: denise_interposer.kicad_pcb ({len(_nets)} nets)")


if __name__ == "__main__":
    main()
