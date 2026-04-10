# Amiga DENISE Flicker Fixer

An FPGA-based flicker fixer for the Commodore Amiga that reads digital RGB directly from the Super DENISE (8373 ECS) chip and outputs progressive 720p HDMI video.

**Target Platform:** Sipeed Tang Primer 20K (Gowin GW2A-LV18PG256C8/I7)

## Overview

The Amiga's native video output is 15 kHz interlaced (or non-interlaced), which most modern displays cannot accept. This flicker fixer captures the 12-bit digital RGB output from DENISE before it reaches the analog video DAC, stores fields in a DDR3 frame buffer, performs weave deinterlacing, scales the image to 720p, and outputs progressive HDMI.

Key features:
- Direct digital capture from DENISE pins (no analog conversion artifacts)
- Supports all ECS video modes: lores, hires, and superhires
- PAL and NTSC auto-detection
- Interlaced and non-interlaced mode support
- Weave deinterlacing (field merging) for flicker-free interlaced display
- Line doubling for non-interlaced modes
- Nearest-neighbor scaling to 1280x720
- 720p50 output for PAL, 720p60 for NTSC (matches source frame rate)
- Test pattern fallback when no Amiga input detected
- 128 MB DDR3 frame buffer (ping-pong per field parity)

## System Architecture

```
                        Amiga Motherboard
                        ┌──────────────┐
                        │   DENISE     │
                        │   (8373)     │
                        │              │
                        │  R[3:0] ─────┼──┐
                        │  G[3:0] ─────┼──┤
                        │  B[3:0] ─────┼──┤  12-bit digital RGB
                        │  /CSYNC ─────┼──┤  + sync/clock
                        │  /ZD    ─────┼──┤
                        │  7M     ─────┼──┤
                        │  CDAC   ─────┼──┘
                        └──────────────┘
                               │
                    ┌──────────┴──────────┐
                    │  Level Shifter      │
                    │  (74LVC245 x2)      │
                    │  5V TTL → 3.3V      │
                    └──────────┬──────────┘
                               │
┌──────────────────────────────┴──────────────────────────────┐
│                   Tang Primer 20K FPGA                       │
│                                                              │
│  ┌─────────────────┐    ┌──────────────┐    ┌────────────┐  │
│  │ denise_capture   │    │ frame_buffer │    │ output_gen │  │
│  │                  │    │    _ctrl     │    │            │  │
│  │ • 28MHz sampling │───▶│              │───▶│ • 720p     │  │
│  │ • Sync separator │    │ • DDR3      │    │   timing   │  │
│  │ • Mode detection │    │   arbiter   │    │ • Weave    │  │
│  │ • Field ID       │    │ • Ping-pong │    │   deintlc  │  │
│  │ • Pixel coords   │    │   buffers   │    │ • NN scale │  │
│  └─────────────────┘    │ • Line bufs  │    └─────┬──────┘  │
│                          └──────┬───────┘          │         │
│       ┌────────┐                │           ┌──────┴──────┐  │
│       │ Amiga  │         ┌──────┴──────┐    │  DVI_TX_Top │  │
│       │  PLL   │         │   DDR3      │    │  (Gowin IP) │  │
│       │7M→28M  │         │ Controller  │    │  TMDS enc.  │  │
│       └────────┘         │ (nand2mario │    └──────┬──────┘  │
│       ┌────────┐         │  or Gowin)  │           │         │
│       │ TMDS   │         └──────┬──────┘    ┌──────┴──────┐  │
│       │  PLL   │                │           │ HDMI Output │  │
│       │27→371M │         ┌──────┴──────┐    │ (TMDS diff) │  │
│       └────────┘         │  DDR3 SDRAM │    └─────────────┘  │
│                          │  128 MB     │                     │
│                          └─────────────┘                     │
└──────────────────────────────────────────────────────────────┘
```

### Clock Domains

| Domain | Frequency | Source | Purpose |
|--------|-----------|--------|---------|
| `I_clk` | 27 MHz | Board oscillator | System reference, DDR3 PLL input |
| `clk_28m` | ~28.38/28.64 MHz | Amiga_rPLL (4x 7M) | DENISE pixel capture |
| `clk_mem` | 100 MHz | DDR3 controller PLL | Memory access |
| `pix_clk` | 74.25 MHz | TMDS_rPLL / CLKDIV | HDMI pixel output |
| `serial_clk` | ~371.25 MHz | TMDS_rPLL | HDMI TMDS serialization |

All clock domain crossings use dual-flop synchronizers (for control signals) or async FIFOs (for data streams).

### Data Flow

```
DENISE pins (5V TTL)
    │
    ▼ (level shifted to 3.3V)
┌─────────────────────────────────────┐
│ denise_capture (28 MHz domain)      │
│ • Double-flop sync all inputs       │
│ • Sample RGB at 28 MHz              │
│ • Separate CSYNC → HSYNC + VSYNC   │
│ • Count lines → PAL/NTSC detect    │
│ • Track active area via /ZD         │
│ • Output: pixel + coords + field ID │
└──────────────┬──────────────────────┘
               ▼
        [Async FIFO 28→100 MHz]
               ▼
┌─────────────────────────────────────┐
│ frame_buffer_ctrl (100 MHz domain)  │
│ • Write pixels to DDR3 field buffer │
│ • Ping-pong buffers per parity      │
│ • Read source lines into line bufs  │
│ • Priority arbitration (read > wr)  │
└──────────────┬──────────────────────┘
               ▼
        [Line buffer BSRAM]
               ▼
┌─────────────────────────────────────┐
│ output_gen (74.25 MHz domain)       │
│ • 720p timing (50Hz or 60Hz)       │
│ • Fixed-point scale computation     │
│ • Weave deinterlace (field merge)   │
│ • 4-bit → 8-bit color expansion    │
│ • Line prefetch from frame buffer   │
└──────────────┬──────────────────────┘
               ▼
┌─────────────────────────────────────┐
│ DVI_TX_Top (Gowin encrypted IP)     │
│ • 8b/10b TMDS encoding             │
│ • OSER10 serialization              │
│ • Differential output drive         │
└──────────────┬──────────────────────┘
               ▼
         HDMI connector
```

## Module Descriptions

### `flicker_fixer_top.v` — Top Level
Instantiates all modules, manages clock generation (3 PLLs), reset sequencing, clock domain crossing for control signals, and multiplexes between Amiga video and test pattern fallback.

### `denise_capture.v` — DENISE Signal Capture
Samples DENISE's 12-bit RGB output at 28 MHz (4x the 7M clock). Includes:
- **Input synchronization**: Double-flop metastability guard on all DENISE inputs
- **Composite sync separator**: Measures /CSYNC pulse widths to distinguish normal HSYNC (~4.7 us, ~132 clocks) from equalization/serration pulses (~2.35 us, ~66 clocks) during vertical sync
- **PAL/NTSC detection**: Counts lines per field (>280 = PAL, <280 = NTSC)
- **Interlace detection**: Compares consecutive field line counts (alternating 262/263 or 312/313 = interlaced)
- **Field identification**: Long frame (extra line) = odd field, short frame = even field
- **Active area detection**: Uses /ZD (zero detect) as blanking indicator to measure active pixel width and height
- **Coordinate tracking**: Outputs pixel X/Y position within the active display area

### `frame_buffer_ctrl.v` — DDR3 Frame Buffer Arbiter
Manages DDR3 memory access for writing captured pixels and reading lines for output:
- **4 field buffers** in DDR3 (ping-pong per parity): ensures the output always reads from a completed field while capture writes to another
- **Write path**: Accepts pixels from the async FIFO, computes DDR3 addresses, issues single-word writes
- **Read path**: Prefetches entire source lines into on-chip BSRAM line buffers for zero-latency output access
- **Arbitration**: Read priority (output timing is deadline-driven) over writes

Memory map (16-bit word addresses):
```
Buffer 0 (even ping):  0x000000 + line*2048 + pixel
Buffer 1 (even pong):  0x100000 + line*2048 + pixel
Buffer 2 (odd  ping):  0x200000 + line*2048 + pixel
Buffer 3 (odd  pong):  0x300000 + line*2048 + pixel
```

Each pixel stored as 16 bits: `{4'b0, R[3:0], G[3:0], B[3:0]}`

### `output_gen.v` — HDMI Output with Deinterlacing and Scaling
Generates 720p video timing and produces scaled, deinterlaced output:
- **720p50** (1980x750, HFP=440) for PAL input
- **720p60** (1650x750, HFP=110) for NTSC input
- Both use the same 74.25 MHz pixel clock

**Weave deinterlacing**: For interlaced input, the output interleaves lines from the even and odd field buffers. Even output lines read from the even field, odd output lines from the odd field. This reconstructs the full progressive frame.

**Line doubling**: For non-interlaced input, each source line maps to two consecutive output lines.

**Nearest-neighbor scaling**: Fixed-point arithmetic maps each output pixel to source coordinates. Scale factors are recomputed at each frame start based on the detected active area dimensions.

**Line prefetch**: At the start of each output line (during horizontal blanking), the required source line is fetched from DDR3 into a line buffer. If the source line hasn't changed (repeated lines during upscaling), the fetch is skipped.

**Color expansion**: DENISE's 4-bit-per-channel color (4096 colors) is expanded to 8-bit-per-channel by bit replication: `{nibble, nibble}` maps 0x0→0x00, 0xF→0xFF.

### `async_fifo.v` — Dual-Clock FIFO
Standard gray-code pointer async FIFO for safe clock domain crossing between the 28 MHz capture domain and 100 MHz memory domain. Parameterized width and depth.

### `line_buffer.v` — Dual-Port Line Buffer
Simple dual-port RAM that infers Gowin BSRAM. Used for zero-latency line access during output pixel generation.

### `amiga_pll.v` — Amiga Clock PLL
Gowin rPLL wrapper that multiplies the 7M clock by 4 to produce the 28 MHz capture clock. VCO runs at ~448 MHz (within GW2A-18C specifications).

### `testpattern.v` — Test Pattern Generator (original)
Retained from the original HDMI demo project. Generates color bars at 720p60 as a fallback when no Amiga input is detected. Useful for verifying HDMI output works before connecting DENISE.

## DENISE (8373) Interface

### Signals to Capture

| Signal | DENISE Pin | Direction | Description |
|--------|-----------|-----------|-------------|
| R0-R3 | 20-23 | Output | Red channel (4-bit, R0=LSB) |
| B0-B3 | 24-27 | Output | Blue channel (4-bit, B0=LSB) |
| G0-G3 | 28-31 | Output | Green channel (4-bit, G0=LSB) |
| /CSYNC | 32 | Input* | Composite sync (active low) |
| /ZD | 33 | Output | Zero detect / blanking (active low) |
| CDAC | 34 | Input | Clock DAC, ~7 MHz, 90 deg from 7M (ECS only) |
| 7M | 35 | Input | 7.09/7.16 MHz pixel clock reference |

*Note: /CSYNC is an input TO DENISE (from Agnus via a buffer), but we tap the signal on the motherboard trace.

### Pin Ordering Warning

DENISE's physical pin order is R, **B**, G (not R, G, B). The blue channel (pins 24-27) sits between red and green. Verify your wiring matches the actual chip pinout.

### Pixel Clock Rates by Mode

| Mode | Pixel Rate | Pixels per 7M Cycle | Amiga Resolution |
|------|-----------|---------------------|------------------|
| Lores | ~7.09/7.16 MHz | 1 | 320 px wide |
| Hires | ~14.19/14.32 MHz | 2 | 640 px wide |
| Superhires | ~28.38/28.64 MHz | 4 | 1280 px wide |

The flicker fixer always samples at 28 MHz, capturing all modes correctly. In lores, each source pixel is sampled 4 times; in hires, 2 times; in superhires, 1 time. The scaler handles this transparently.

## Hardware Integration

### Level Shifting (Required)

DENISE outputs 5V TTL signals. The GW2A-18C FPGA is **not 5V tolerant** (3.3V LVCMOS I/O). You **must** use level shifters between DENISE and the FPGA.

Recommended:
- **74LVC245** (unidirectional, 8-bit): 2 chips covers all 16 signals
- **TXB0108** (bidirectional, 8-bit): works but unidirectional is preferred
- **Resistor divider** (1k + 2k): functional for prototyping, adds propagation delay

Wiring for 74LVC245:
```
DENISE pin ──── 74LVC245 A side (5V VCC on A side)
                74LVC245 B side (3.3V VCC on B side) ──── FPGA GPIO
                DIR = GND (A→B direction, DENISE to FPGA)
                /OE = GND (always enabled)
```

### Flying Wire Prototype

For initial prototyping:

1. Solder thin wires (30 AWG kynar/wire-wrap) to DENISE pins:
   - Pins 20-23 (R0-R3)
   - Pins 24-27 (B0-B3)
   - Pins 28-31 (G0-G3)
   - Pin 32 (/CSYNC — tap on motherboard trace)
   - Pin 33 (/ZD)
   - Pin 34 (CDAC)
   - Pin 35 (7M)
   - Pin 37 (GND)
   - Pin 19 (VCC, for level shifter 5V supply)

2. Route to a level shifter board (small perfboard with 2x 74LVC245)

3. Connect level shifter output to Tang Primer 20K GPIO header

4. Keep wires **short** (<10 cm) and **matched length** for clock and data signals to maintain timing integrity at 28 MHz

### Interposer Design (Production)

For a permanent installation, design a PCB interposer that:
- Sits between DENISE's 48-pin DIP socket and the motherboard
- Passes all 48 pins through unchanged
- Taps the 16 required signals via traces to a header/FFC connector
- Includes 74LVC245 level shifters on-board
- Routes to the FPGA via flat flex cable or pin header

The interposer only **passively observes** signals. It does not drive any DENISE bus pins. All tapped signals are outputs from DENISE (RGB, /ZD) or existing motherboard traces (/CSYNC, 7M, CDAC).

## Building

### Prerequisites

1. **Gowin EDA** (Education or Commercial edition) — [gowinsemi.com](https://www.gowinsemi.com/en/support/home/)
2. **DDR3 Controller** — one of:
   - [nand2mario/ddr3-tang-primer-20k](https://github.com/nand2mario/ddr3-tang-primer-20k) (recommended, open source, Apache 2.0)
   - Gowin DDR3 Memory Interface IP (IPUG281)

### Steps

1. Clone or download the DDR3 controller source

2. Open the Gowin IDE and create a project targeting **GW2A-LV18PG256C8/I7**

3. Add all source files:
   ```
   src/flicker_fixer_top.v    (set as top module)
   src/denise_capture.v
   src/frame_buffer_ctrl.v
   src/output_gen.v
   src/async_fifo.v
   src/line_buffer.v
   src/amiga_pll.v
   src/testpattern.v
   src/gowin_rpll/TMDS_rPLL.v
   src/dvi_tx/dvi_tx.v
   <DDR3 controller sources>
   ```

4. Add constraint files:
   ```
   src/flicker_fixer.cst      (pin assignments)
   src/flicker_fixer.sdc      (timing constraints)
   ```

5. **Regenerate PLLs** using the Gowin IP Core Generator if needed:
   - `TMDS_rPLL`: 27 MHz input, output for 720p HDMI (existing, no change needed)
   - `Amiga_rPLL`: ~7 MHz input, ~28 MHz output (4x). Verify VCO range.

6. **Uncomment the DDR3 controller instantiation** in `flicker_fixer_top.v` (search for `PLACEHOLDER`) and remove the temporary tie-off assignments below it.

7. Adjust DENISE GPIO pin assignments in `flicker_fixer.cst` to match your physical wiring.

8. Synthesize, Place & Route, program the FPGA.

### Testing Without Amiga Hardware

The design includes a test pattern fallback. When no Amiga 7M clock is detected (PLL doesn't lock), the output automatically shows color bars at 720p60. This verifies HDMI output works before connecting to DENISE.

LED indicators:

| LED | Meaning |
|-----|---------|
| LED0 | Heartbeat (~1 Hz blink) — FPGA is running |
| LED1 | Amiga input detected |
| LED2 | Amiga PLL locked (7M clock present) |
| LED3 | HDMI PLL locked |

## Supported Amiga Video Modes

| Mode | Resolution | Refresh | Output |
|------|-----------|---------|--------|
| NTSC Lores | 320x200 | 60 Hz | Line doubled, 720p60 |
| NTSC Lores Interlaced | 320x400 | 30 Hz (60 fields) | Weave deinterlaced, 720p60 |
| NTSC Hires | 640x200 | 60 Hz | Line doubled, 720p60 |
| NTSC Hires Interlaced | 640x400 | 30 Hz (60 fields) | Weave deinterlaced, 720p60 |
| PAL Lores | 320x256 | 50 Hz | Line doubled, 720p50 |
| PAL Lores Interlaced | 320x512 | 25 Hz (50 fields) | Weave deinterlaced, 720p50 |
| PAL Hires | 640x256 | 50 Hz | Line doubled, 720p50 |
| PAL Hires Interlaced | 640x512 | 25 Hz (50 fields) | Weave deinterlaced, 720p50 |
| Superhires | 1280x200/256 | 50/60 Hz | Line doubled, 720p |
| Superhires Interlaced | 1280x400/512 | 25/30 Hz | Weave deinterlaced, 720p |
| HAM6 | 320x200-512 | 50/60 Hz | Transparent (DENISE resolves HAM) |

All special modes (HAM, Extra-Halfbrite, dual playfield) are supported transparently because DENISE resolves them internally before driving the RGB pins.

## Design Details

### Memory Bandwidth Budget

| Path | Data Rate | Notes |
|------|----------|-------|
| Capture write | ~38 MB/s | 28 MHz x 16 bits x ~85% active |
| Output read | ~30 MB/s | ~800 lines x 1024 px x 2 bytes x 60 fps |
| DDR3 capacity | ~130 MB/s | 100 MHz x 16 bits x ~80% efficiency |
| **Headroom** | **~62 MB/s** | Comfortable margin |

### FPGA Resource Estimate

| Resource | Estimated | Available | Utilization |
|----------|----------|-----------|-------------|
| Logic LUTs | ~3,000 | 20,736 | ~15% |
| Registers | ~2,000 | 16,173 | ~12% |
| BSRAM | ~6 blocks | 46 | ~13% |
| rPLL | 3 | 4 | 75% |
| CLKDIV | 1 | 8 | 13% |
| OSER10 | 4 | — | — |

### Future Enhancements

- **Motion-adaptive deinterlacing**: Compare same-parity fields across frames; weave static regions, bob moving regions. Requires a third field buffer per parity (6 total).
- **Bilinear scaling**: Interpolate between source pixels for smoother upscaling.
- **Scanline emulation**: Optional darkened scanlines for CRT-like appearance.
- **OSD overlay**: On-screen display for mode info and settings.
- **Integer scaling option**: Exact 2x/3x with black borders for pixel-perfect output.
- **Audio passthrough**: Capture Amiga audio and embed in HDMI audio data island packets.

## Project Structure

```
HDMI/
├── src/
│   ├── flicker_fixer_top.v      # Top-level: clocks, CDC, mux
│   ├── denise_capture.v         # DENISE RGB + sync capture
│   ├── frame_buffer_ctrl.v      # DDR3 frame buffer arbiter
│   ├── output_gen.v             # 720p output, deinterlace, scale
│   ├── async_fifo.v             # Dual-clock FIFO (CDC)
│   ├── line_buffer.v            # Dual-port line buffer (BSRAM)
│   ├── amiga_pll.v              # 7M → 28M PLL wrapper
│   ├── testpattern.v            # Test pattern fallback (original)
│   ├── video_top.v              # Original HDMI demo top (reference)
│   ├── flicker_fixer.cst        # Pin constraints
│   ├── flicker_fixer.sdc        # Timing constraints
│   ├── dk_video.cst             # Original demo pin constraints
│   ├── dk_video.sdc             # Original demo timing constraints
│   ├── dvi_tx/
│   │   └── dvi_tx.v             # HDMI transmitter (Gowin encrypted IP)
│   └── gowin_rpll/
│       └── TMDS_rPLL.v          # TMDS clock PLL
└── impl/                        # Synthesis and P&R output
```

## References

- [Amiga Hardware Reference Manual](http://amigadev.elowar.com/read/ADCD_2.1/Hardware_Manual_guide/node0000.html) — Official Commodore documentation
- [DENISE chip specifications](https://www.amigawiki.org/lib/exe/fetch.php?media=de:parts:denise_specs.pdf) — Pin assignments and timing
- [c0pperdragon/Amiga-Digital-Video](https://github.com/c0pperdragon/Amiga-Digital-Video) — FPGA digital video for Amiga (reference design)
- [nand2mario/ddr3-tang-primer-20k](https://github.com/nand2mario/ddr3-tang-primer-20k) — DDR3 controller for this board
- [Sipeed Tang Primer 20K Wiki](https://wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html) — Board documentation
- [Gowin GW2A-18C Datasheet](https://www.gowinsemi.com/en/product/detail/38/) — FPGA specifications

## License

This project extends the original Gowin HDMI demo. DENISE flicker fixer additions are provided as-is for educational and hobbyist use. The Gowin DVI_TX IP core is proprietary and subject to Gowin's license terms.
