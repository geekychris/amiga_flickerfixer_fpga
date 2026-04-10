#!/usr/bin/env python3
"""
Generate KiCad 8 schematic for the DENISE 8373 interposer.

Shows the full 48-pin DIP pass-through with all DENISE pin names,
two 74LVC245 level shifters, and FPGA output connector.

Run: python3 generate_schematic.py
Output: denise_interposer.kicad_sch
"""

import uuid

def uid():
    return str(uuid.uuid4())

# Complete DENISE 8373 pinout (48-pin DIP)
# Left side: pins 1-24 (top to bottom)
# Right side: pins 25-48 (bottom to top, DIP convention)
DENISE_LEFT_PINS = [
    (1,  "D6"),    (2,  "D5"),    (3,  "D4"),    (4,  "D3"),
    (5,  "D2"),    (6,  "D1"),    (7,  "D0"),    (8,  "M1H"),
    (9,  "M0H"),   (10, "RGA8"),  (11, "RGA7"),  (12, "RGA6"),
    (13, "RGA5"),  (14, "RGA4"),  (15, "RGA3"),  (16, "RGA2"),
    (17, "RGA1"),  (18, "~{BURST}"), (19, "VCC"), (20, "R0"),
    (21, "R1"),    (22, "R2"),    (23, "R3"),    (24, "B0"),
]
DENISE_RIGHT_PINS = [
    # Right side goes bottom-to-top in DIP, but in schematic
    # we list top-to-bottom: pin 48 at top, pin 25 at bottom
    (48, "D15"),   (47, "D14"),   (46, "D13"),   (45, "D12"),
    (44, "D11"),   (43, "D10"),   (42, "D9"),    (41, "D8"),
    (40, "D7"),    (39, "M1V"),   (38, "M0V"),   (37, "GND"),
    (36, "CCK"),   (35, "7M"),    (34, "CDAC"),  (33, "~{ZD}"),
    (32, "~{CSYNC}"), (31, "G3"), (30, "G2"),    (29, "G1"),
    (28, "G0"),    (27, "B3"),    (26, "B2"),    (25, "B1"),
]

# Signals tapped for the flicker fixer (and which 74LVC245 channel)
# U1: R0-R3 (pins 20-23), B0-B3 (pins 24-27)
# U2: G0-G3 (pins 28-31), nCSYNC (32), nZD (33), CDAC (34), 7M (35)
U1_SIGNALS = ["R0", "R1", "R2", "R3", "B0", "B1", "B2", "B3"]
U2_SIGNALS = ["G0", "G1", "G2", "G3", "nCSYNC", "nZD", "CDAC", "CLK7M"]

# Map from DENISE pin names to tap net names
TAP_MAP = {
    "R0": "R0", "R1": "R1", "R2": "R2", "R3": "R3",
    "B0": "B0", "B1": "B1", "B2": "B2", "B3": "B3",
    "G0": "G0", "G1": "G1", "G2": "G2", "G3": "G3",
    "~{CSYNC}": "nCSYNC", "~{ZD}": "nZD", "CDAC": "CDAC", "7M": "CLK7M",
}


def write_denise_dip48_libsym(f):
    """Full 48-pin DIP symbol for DENISE 8373."""
    f.write('    (symbol "interposer:DENISE_8373"\n')
    f.write('      (exclude_from_sim no) (in_bom yes) (on_board yes)\n')
    # Graphics
    f.write('      (symbol "DENISE_8373_0_1"\n')
    f.write('        (rectangle (start -12.7 30.48) (end 12.7 -30.48)\n')
    f.write('          (stroke (width 0.254) (type default))\n')
    f.write('          (fill (type background))\n')
    f.write('        )\n')
    f.write('        (text "DENISE" (at 0 0 0)\n')
    f.write('          (effects (font (size 2.54 2.54)))\n')
    f.write('        )\n')
    f.write('        (text "8373" (at 0 -3.0 0)\n')
    f.write('          (effects (font (size 1.5 1.5)))\n')
    f.write('        )\n')
    f.write('      )\n')
    f.write('      (symbol "DENISE_8373_1_1"\n')
    # Left side pins (1-24), top to bottom
    for i, (num, name) in enumerate(DENISE_LEFT_PINS):
        y = 29.21 - i * 2.54
        ptype = "power_in" if name in ("VCC", "GND") else "bidirectional"
        f.write(f'        (pin {ptype} line (at -15.24 {y:.2f} 0) (length 2.54)\n')
        f.write(f'          (name "{name}" (effects (font (size 1.0 1.0))))\n')
        f.write(f'          (number "{num}" (effects (font (size 1.0 1.0))))\n')
        f.write(f'        )\n')
    # Right side pins (48 at top down to 25 at bottom)
    for i, (num, name) in enumerate(DENISE_RIGHT_PINS):
        y = 29.21 - i * 2.54
        ptype = "power_in" if name in ("VCC", "GND") else "bidirectional"
        f.write(f'        (pin {ptype} line (at 15.24 {y:.2f} 180) (length 2.54)\n')
        f.write(f'          (name "{name}" (effects (font (size 1.0 1.0))))\n')
        f.write(f'          (number "{num}" (effects (font (size 1.0 1.0))))\n')
        f.write(f'        )\n')
    f.write('      )\n')
    f.write('    )\n')


def write_74lvc245_libsym(f):
    """74LVC245 level shifter symbol."""
    f.write('    (symbol "interposer:74LVC245"\n')
    f.write('      (exclude_from_sim no) (in_bom yes) (on_board yes)\n')
    f.write('      (symbol "74LVC245_0_1"\n')
    f.write('        (rectangle (start -7.62 12.7) (end 7.62 -12.7)\n')
    f.write('          (stroke (width 0.254) (type default))\n')
    f.write('          (fill (type background))\n')
    f.write('        )\n')
    f.write('      )\n')
    f.write('      (symbol "74LVC245_1_1"\n')
    left_pins = [
        ("1", "DIR",  "input",  10.16),
        ("2", "A1",   "bidirectional",  7.62),
        ("3", "A2",   "bidirectional",  5.08),
        ("4", "A3",   "bidirectional",  2.54),
        ("5", "A4",   "bidirectional",  0),
        ("6", "A5",   "bidirectional", -2.54),
        ("7", "A6",   "bidirectional", -5.08),
        ("8", "A7",   "bidirectional", -7.62),
        ("9", "A8",   "bidirectional", -10.16),
    ]
    for num, name, ptype, y in left_pins:
        f.write(f'        (pin {ptype} line (at -10.16 {y} 0) (length 2.54)\n')
        f.write(f'          (name "{name}" (effects (font (size 1.27 1.27))))\n')
        f.write(f'          (number "{num}" (effects (font (size 1.27 1.27))))\n')
        f.write(f'        )\n')
    right_pins = [
        ("19", "~{{OE}}", "input",  10.16),
        ("18", "B1",  "bidirectional",  7.62),
        ("17", "B2",  "bidirectional",  5.08),
        ("16", "B3",  "bidirectional",  2.54),
        ("15", "B4",  "bidirectional",  0),
        ("14", "B5",  "bidirectional", -2.54),
        ("13", "B6",  "bidirectional", -5.08),
        ("12", "B7",  "bidirectional", -7.62),
        ("11", "B8",  "bidirectional", -10.16),
    ]
    for num, name, ptype, y in right_pins:
        f.write(f'        (pin {ptype} line (at 10.16 {y} 180) (length 2.54)\n')
        f.write(f'          (name "{name}" (effects (font (size 1.27 1.27))))\n')
        f.write(f'          (number "{num}" (effects (font (size 1.27 1.27))))\n')
        f.write(f'        )\n')
    f.write('        (pin power_in line (at 0 15.24 270) (length 2.54)\n')
    f.write('          (name "VCC" (effects (font (size 1.27 1.27))))\n')
    f.write('          (number "20" (effects (font (size 1.27 1.27))))\n')
    f.write('        )\n')
    f.write('        (pin power_in line (at 0 -15.24 90) (length 2.54)\n')
    f.write('          (name "GND" (effects (font (size 1.27 1.27))))\n')
    f.write('          (number "10" (effects (font (size 1.27 1.27))))\n')
    f.write('        )\n')
    f.write('      )\n')
    f.write('    )\n')


def write_conn_02x10_libsym(f):
    """2x10 connector for FPGA output."""
    f.write('    (symbol "interposer:Conn_02x10"\n')
    f.write('      (exclude_from_sim no) (in_bom yes) (on_board yes)\n')
    f.write('      (symbol "Conn_02x10_0_1"\n')
    f.write('        (rectangle (start -2.54 13.97) (end 2.54 -13.97)\n')
    f.write('          (stroke (width 0.254) (type default))\n')
    f.write('          (fill (type background))\n')
    f.write('        )\n')
    f.write('      )\n')
    f.write('      (symbol "Conn_02x10_1_1"\n')
    for i in range(10):
        y = 12.7 - i * 2.54
        odd = i * 2 + 1
        even = i * 2 + 2
        f.write(f'        (pin passive line (at -5.08 {y:.2f} 0) (length 2.54)\n')
        f.write(f'          (name "Pin_{odd}" (effects (font (size 1.27 1.27))))\n')
        f.write(f'          (number "{odd}" (effects (font (size 1.27 1.27))))\n')
        f.write(f'        )\n')
        f.write(f'        (pin passive line (at 5.08 {y:.2f} 180) (length 2.54)\n')
        f.write(f'          (name "Pin_{even}" (effects (font (size 1.27 1.27))))\n')
        f.write(f'          (number "{even}" (effects (font (size 1.27 1.27))))\n')
        f.write(f'        )\n')
    f.write('      )\n')
    f.write('    )\n')


def write_cap_libsym(f):
    """Capacitor symbol."""
    f.write('    (symbol "interposer:C"\n')
    f.write('      (exclude_from_sim no) (in_bom yes) (on_board yes)\n')
    f.write('      (symbol "C_0_1"\n')
    f.write('        (polyline (pts (xy -1.27 0.508) (xy 1.27 0.508))\n')
    f.write('          (stroke (width 0.3) (type default)) (fill (type none)))\n')
    f.write('        (polyline (pts (xy -1.27 -0.508) (xy 1.27 -0.508))\n')
    f.write('          (stroke (width 0.3) (type default)) (fill (type none)))\n')
    f.write('      )\n')
    f.write('      (symbol "C_1_1"\n')
    f.write('        (pin passive line (at 0 2.54 270) (length 2.032)\n')
    f.write('          (name "~" (effects (font (size 1.27 1.27))))\n')
    f.write('          (number "1" (effects (font (size 1.27 1.27))))\n')
    f.write('        )\n')
    f.write('        (pin passive line (at 0 -2.54 90) (length 2.032)\n')
    f.write('          (name "~" (effects (font (size 1.27 1.27))))\n')
    f.write('          (number "2" (effects (font (size 1.27 1.27))))\n')
    f.write('        )\n')
    f.write('      )\n')
    f.write('    )\n')


def write_power_libsym(f, name):
    """Power symbol (+3V3, +5V, GND)."""
    f.write(f'    (symbol "power:{name}"\n')
    f.write('      (power)\n')
    f.write('      (exclude_from_sim no) (in_bom no) (on_board yes)\n')
    f.write(f'      (symbol "{name}_0_1"\n')
    if name == "GND":
        f.write('        (polyline (pts (xy -1.27 0) (xy 1.27 0) (xy 0 -1.27) (xy -1.27 0))\n')
        f.write('          (stroke (width 0) (type default)) (fill (type outline)))\n')
    else:
        f.write('        (polyline (pts (xy 0 0) (xy 0 1.27))\n')
        f.write('          (stroke (width 0) (type default)) (fill (type none)))\n')
        f.write('        (polyline (pts (xy -0.762 1.27) (xy 0.762 1.27))\n')
        f.write('          (stroke (width 0.254) (type default)) (fill (type none)))\n')
    f.write('      )\n')
    f.write(f'      (symbol "{name}_1_1"\n')
    f.write(f'        (pin power_in line (at 0 0 90) (length 0)\n')
    f.write(f'          (name "{name}" (effects (font (size 1.27 1.27))))\n')
    f.write(f'          (number "1" (effects (font (size 1.27 1.27))))\n')
    f.write(f'        )\n')
    f.write('      )\n')
    f.write('    )\n')


def write_symbol_instance(f, lib_id, ref, value, x, y, angle, pin_count, footprint=""):
    """Place a component instance."""
    u = uid()
    f.write(f'  (symbol (lib_id "{lib_id}") (at {x} {y} {angle})\n')
    f.write(f'    (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no)\n')
    f.write(f'    (uuid "{u}")\n')
    ref_y = y - 33 if pin_count > 20 else y - 17.78
    f.write(f'    (property "Reference" "{ref}" (at {x} {ref_y:.2f} 0)\n')
    f.write(f'      (effects (font (size 1.27 1.27))))\n')
    f.write(f'    (property "Value" "{value}" (at {x} {ref_y + 2:.2f} 0)\n')
    f.write(f'      (effects (font (size 1.27 1.27))))\n')
    if footprint:
        f.write(f'    (property "Footprint" "{footprint}" (at {x} {y} 0)\n')
        f.write(f'      (effects (font (size 1.27 1.27)) hide))\n')
    for p in range(1, pin_count + 1):
        f.write(f'    (pin "{p}" (uuid "{uid()}"))\n')
    f.write(f'  )\n')


_pwr_counter = [0]
def write_power_instance(f, name, x, y, angle=0):
    """Place a power symbol."""
    _pwr_counter[0] += 1
    f.write(f'  (symbol (lib_id "power:{name}") (at {x} {y} {angle})\n')
    f.write(f'    (unit 1) (exclude_from_sim no) (in_bom no) (on_board yes) (dnp no)\n')
    f.write(f'    (uuid "{uid()}")\n')
    f.write(f'    (property "Reference" "#{name}_{_pwr_counter[0]:02d}" (at {x + 2.54} {y} 0)\n')
    f.write(f'      (effects (font (size 1.27 1.27)) hide))\n')
    vy = y - 1.5 if name != "GND" else y + 1.5
    f.write(f'    (property "Value" "{name}" (at {x} {vy:.2f} 0)\n')
    f.write(f'      (effects (font (size 1.0 1.0))))\n')
    f.write(f'    (pin "1" (uuid "{uid()}"))\n')
    f.write(f'  )\n')


def write_label(f, name, x, y, angle=0):
    """Place a net label."""
    f.write(f'  (label "{name}" (at {x} {y} {angle})\n')
    f.write(f'    (effects (font (size 1.27 1.27)))\n')
    f.write(f'    (uuid "{uid()}")\n')
    f.write(f'  )\n')


def write_wire(f, x1, y1, x2, y2):
    """Draw a wire segment."""
    f.write(f'  (wire (pts (xy {x1} {y1}) (xy {x2} {y2}))\n')
    f.write(f'    (stroke (width 0) (type default))\n')
    f.write(f'    (uuid "{uid()}")\n')
    f.write(f'  )\n')


def write_text(f, text, x, y, size=2.0):
    """Place a text annotation."""
    f.write(f'  (text "{text}" (at {x} {y} 0)\n')
    f.write(f'    (effects (font (size {size} {size})))\n')
    f.write(f'    (uuid "{uid()}")\n')
    f.write(f'  )\n')


def main():
    # Component positions
    DENISE_X, DENISE_Y = 68.58, 76.2    # DENISE DIP-48 (large symbol)
    U1_X, U1_Y = 152.4, 50.8            # 74LVC245 #1 (R+B channels)
    U2_X, U2_Y = 152.4, 101.6           # 74LVC245 #2 (G+sync+clk)
    J2_X, J2_Y = 228.6, 76.2            # FPGA output connector

    with open("denise_interposer.kicad_sch", "w") as f:
        # === Header ===
        f.write('(kicad_sch\n')
        f.write('  (version 20231120)\n')
        f.write('  (generator "eeschema")\n')
        f.write('  (generator_version "8.0")\n')
        f.write(f'  (uuid "{uid()}")\n')
        f.write('  (paper "A3")\n')
        f.write('  (title_block\n')
        f.write('    (title "DENISE 8373 Interposer - Amiga Flicker Fixer")\n')
        f.write('    (comment 1 "5V TTL to 3.3V LVCMOS level shifting")\n')
        f.write('    (comment 2 "48-pin DIP pass-through with 16 signal taps")\n')
        f.write('  )\n\n')

        # === Library symbols ===
        f.write('  (lib_symbols\n')
        write_denise_dip48_libsym(f)
        write_74lvc245_libsym(f)
        write_conn_02x10_libsym(f)
        write_cap_libsym(f)
        write_power_libsym(f, "+3V3")
        write_power_libsym(f, "+5V")
        write_power_libsym(f, "GND")
        f.write('  )\n\n')

        # === Design notes ===
        write_text(f, "DENISE 8373 Interposer", 25.4, 17.78, 3.0)
        write_text(f, "All 48 DIP pins pass through. Tapped signals (bold) route to level shifters.", 25.4, 22.86, 1.5)
        write_text(f, "74LVC245: VCC=3.3V, 5V-tolerant inputs. DIR=GND (A to B), OE=GND (enabled).", 25.4, 25.86, 1.5)

        # === Place DENISE DIP-48 ===
        write_symbol_instance(f, "interposer:DENISE_8373", "J1", "DENISE_8373_DIP48",
                            DENISE_X, DENISE_Y, 0, 48,
                            "Package_DIP:DIP-48_W15.24mm")

        # === Place 74LVC245 U1 and U2 ===
        write_symbol_instance(f, "interposer:74LVC245", "U1", "74LVC245",
                            U1_X, U1_Y, 0, 20, "Package_SO:TSSOP-20_4.4x6.5mm_P0.65mm")
        write_symbol_instance(f, "interposer:74LVC245", "U2", "74LVC245",
                            U2_X, U2_Y, 0, 20, "Package_SO:TSSOP-20_4.4x6.5mm_P0.65mm")

        # === Place FPGA connector J2 ===
        write_symbol_instance(f, "interposer:Conn_02x10", "J2", "FPGA_OUT",
                            J2_X, J2_Y, 0, 20,
                            "Connector_PinHeader_2.54mm:PinHeader_2x10_P2.54mm_Vertical")

        # === Place bypass caps ===
        write_symbol_instance(f, "interposer:C", "C1", "100nF",
                            U1_X + 15.24, U1_Y - 7.62, 0, 2,
                            "Capacitor_SMD:C_0402_1005Metric")
        write_symbol_instance(f, "interposer:C", "C2", "100nF",
                            U2_X + 15.24, U2_Y - 7.62, 0, 2,
                            "Capacitor_SMD:C_0402_1005Metric")

        # ============================================================
        # Compute pin connection points
        # ============================================================

        # DENISE left pins: x = DENISE_X - 15.24
        # DENISE right pins: x = DENISE_X + 15.24
        den_lx = DENISE_X - 15.24
        den_rx = DENISE_X + 15.24

        # DENISE pin y positions (24 pins per side, 2.54mm spacing)
        def denise_pin_y(row_index):
            return DENISE_Y - (29.21 - row_index * 2.54)

        # 74LVC245 pin positions
        def u_pin_left(ux, uy, local_y):
            return (ux - 10.16, uy - local_y)
        def u_pin_right(ux, uy, local_y):
            return (ux + 10.16, uy - local_y)

        lvc_local_ys = {
            "DIR": 10.16, "A1": 7.62, "A2": 5.08, "A3": 2.54, "A4": 0,
            "A5": -2.54, "A6": -5.08, "A7": -7.62, "A8": -10.16,
            "OE": 10.16, "B1": 7.62, "B2": 5.08, "B3": 2.54, "B4": 0,
            "B5": -2.54, "B6": -5.08, "B7": -7.62, "B8": -10.16,
        }

        # J2 pin positions
        j2_lx = J2_X - 5.08
        j2_rx = J2_X + 5.08
        def j2_pin_y(row):
            return J2_Y - (12.7 - row * 2.54)

        # ============================================================
        # Labels on DENISE tapped pins
        # ============================================================
        # Place labels on the tapped DENISE pins (left side taps)
        for i, (num, name) in enumerate(DENISE_LEFT_PINS):
            y = denise_pin_y(i)
            if name in TAP_MAP:
                write_label(f, TAP_MAP[name], den_lx, y, 180)

        # Right side taps
        for i, (num, name) in enumerate(DENISE_RIGHT_PINS):
            y = denise_pin_y(i)
            if name in TAP_MAP:
                write_label(f, TAP_MAP[name], den_rx, y, 0)

        # DENISE VCC (pin 19) - power label
        vcc_idx = next(i for i, (n, _) in enumerate(DENISE_LEFT_PINS) if n == 19)
        write_power_instance(f, "+5V", den_lx - 2.54, denise_pin_y(vcc_idx), 90)
        write_wire(f, den_lx, denise_pin_y(vcc_idx), den_lx - 2.54, denise_pin_y(vcc_idx))

        # DENISE GND (pin 37) - power label
        gnd_idx = next(i for i, (n, _) in enumerate(DENISE_RIGHT_PINS) if n == 37)
        write_power_instance(f, "GND", den_rx + 2.54, denise_pin_y(gnd_idx), 270)
        write_wire(f, den_rx, denise_pin_y(gnd_idx), den_rx + 2.54, denise_pin_y(gnd_idx))

        # ============================================================
        # Labels on U1 (74LVC245 #1: R0-R3, B0-B3)
        # ============================================================
        for i, sig in enumerate(U1_SIGNALS):
            ax, ay = u_pin_left(U1_X, U1_Y, lvc_local_ys[f"A{i+1}"])
            write_label(f, sig, ax, ay, 180)
            bx, by = u_pin_right(U1_X, U1_Y, lvc_local_ys[f"B{i+1}"])
            write_label(f, sig + "_3V", bx, by, 0)

        # U1 DIR → GND
        dx, dy = u_pin_left(U1_X, U1_Y, lvc_local_ys["DIR"])
        write_wire(f, dx, dy, dx - 5.08, dy)
        write_power_instance(f, "GND", dx - 5.08, dy, 90)

        # U1 ~{OE} → GND
        ox, oy = u_pin_right(U1_X, U1_Y, lvc_local_ys["OE"])
        write_wire(f, ox, oy, ox + 5.08, oy)
        write_power_instance(f, "GND", ox + 5.08, oy, 270)

        # U1 VCC → +3V3
        write_power_instance(f, "+3V3", U1_X, U1_Y - 15.24)
        # U1 GND
        write_power_instance(f, "GND", U1_X, U1_Y + 15.24)

        # ============================================================
        # Labels on U2 (74LVC245 #2: G0-G3, nCSYNC, nZD, CDAC, 7M)
        # ============================================================
        for i, sig in enumerate(U2_SIGNALS):
            ax, ay = u_pin_left(U2_X, U2_Y, lvc_local_ys[f"A{i+1}"])
            write_label(f, sig, ax, ay, 180)
            bx, by = u_pin_right(U2_X, U2_Y, lvc_local_ys[f"B{i+1}"])
            write_label(f, sig + "_3V", bx, by, 0)

        # U2 DIR → GND
        dx, dy = u_pin_left(U2_X, U2_Y, lvc_local_ys["DIR"])
        write_wire(f, dx, dy, dx - 5.08, dy)
        write_power_instance(f, "GND", dx - 5.08, dy, 90)

        # U2 ~{OE} → GND
        ox, oy = u_pin_right(U2_X, U2_Y, lvc_local_ys["OE"])
        write_wire(f, ox, oy, ox + 5.08, oy)
        write_power_instance(f, "GND", ox + 5.08, oy, 270)

        # U2 VCC → +3V3
        write_power_instance(f, "+3V3", U2_X, U2_Y - 15.24)
        # U2 GND
        write_power_instance(f, "GND", U2_X, U2_Y + 15.24)

        # ============================================================
        # Bypass caps C1, C2 → +3V3 / GND
        # ============================================================
        c1x, c1y = U1_X + 15.24, U1_Y - 7.62
        write_power_instance(f, "+3V3", c1x, c1y - 2.54)
        write_power_instance(f, "GND", c1x, c1y + 2.54)

        c2x, c2y = U2_X + 15.24, U2_Y - 7.62
        write_power_instance(f, "+3V3", c2x, c2y - 2.54)
        write_power_instance(f, "GND", c2x, c2y + 2.54)

        # ============================================================
        # FPGA output connector J2 labels
        # ============================================================
        # Pin assignment: odd=left column, even=right column
        j2_left_nets =  ["R0_3V", "R2_3V", "B0_3V", "B2_3V",
                         "G0_3V", "G2_3V", "nCSYNC_3V", "CDAC_3V",
                         "+3V3", "GND"]
        j2_right_nets = ["R1_3V", "R3_3V", "B1_3V", "B3_3V",
                         "G1_3V", "G3_3V", "nZD_3V", "CLK7M_3V",
                         "+3V3", "GND"]

        for i, sig in enumerate(j2_left_nets):
            y = j2_pin_y(i)
            if sig == "+3V3":
                write_power_instance(f, "+3V3", j2_lx, y, 90)
            elif sig == "GND":
                write_power_instance(f, "GND", j2_lx, y, 90)
            else:
                write_label(f, sig, j2_lx, y, 180)

        for i, sig in enumerate(j2_right_nets):
            y = j2_pin_y(i)
            if sig == "+3V3":
                write_power_instance(f, "+3V3", j2_rx, y, 270)
            elif sig == "GND":
                write_power_instance(f, "GND", j2_rx, y, 270)
            else:
                write_label(f, sig, j2_rx, y, 0)

        # ============================================================
        # DENISE pin reference table as text
        # ============================================================
        tx, ty = 25.4, 140.0
        write_text(f, "DENISE 8373 (ECS Super DENISE) - 48-pin DIP", tx, ty, 2.0)
        notes = [
            "Tapped signals: R0-R3(20-23), B0-B3(24-27), G0-G3(28-31)",
            "                nCSYNC(32), nZD(33), CDAC(34), 7M(35)",
            "Pass-through:   D0-D15, RGA1-8, M0H/V, M1H/V, CCK, BURST",
            "Power:          VCC=pin19(+5V), GND=pin37",
        ]
        for i, note in enumerate(notes):
            write_text(f, note, tx, ty + 4 + i * 3.5, 1.27)

        # === Footer ===
        f.write('\n  (sheet_instances\n')
        f.write(f'    (path "/" (page "1"))\n')
        f.write('  )\n')
        f.write(')\n')

    print("Generated: denise_interposer.kicad_sch")


if __name__ == "__main__":
    main()
