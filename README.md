# Tang Primer 20K HDMI Video Output Project

## Overview

This is a **Verilog-based HDMI/DVI video generation project** for the Gowin Tang Primer 20K FPGA development board. The design generates configurable video test patterns and outputs them as HDMI-compatible signals at 1280×720 resolution (720p) at 60 Hz.

The project demonstrates core FPGA video generation concepts including:
- Video timing generation (horizontal and vertical sync signals)
- Color pattern generation and manipulation
- High-speed differential signaling (TMDS protocol)
- PLL-based clock multiplication for video serialization

## Project Structure

```
HDMI/
├── src/
│   ├── video_top.v          # Top-level module integrating all components
│   ├── testpattern.v        # Video pattern generator
│   ├── dvi_tx/
│   │   └── dvi_tx.v         # HDMI/DVI transmitter (encrypted Gowin IP core)
│   └── gowin_rpll/
│       └── TMDS_rPLL.v      # PLL for clock multiplication
├── impl/
│   └── pnr/                 # Place & Route results
├── dk_video.gprj            # Gowin IDE project file
├── dk_video.fs              # Gowin fileset (project configuration)
└── dk_video.gprj.user       # User-specific project settings
```

## Module Details

### 1. `video_top.v` - Top-Level Module

**Purpose:** Orchestrates all video generation components and manages the overall signal flow.

**Key Functionality:**
- **Clock Management:** Accepts 27 MHz input clock and generates required video clocks via PLL
- **LED Status Indicators:** 
  - LED[0-1]: Running status (blink pattern)
  - LED[2-3]: Reset status indication
- **Component Instantiation:** Brings together pattern generator, PLL, and DVI transmitter
- **Test Pattern Mode Switching:** Switches between 4 different patterns based on vertical sync counter

**Port Definitions:**
```verilog
input          I_clk            // 27 MHz input clock
input          I_rst_n          // Asynchronous reset (active low)
output [3:0]   O_led            // 4 LED outputs for status indication
output         O_tmds_clk_p     // HDMI clock positive differential
output         O_tmds_clk_n     // HDMI clock negative differential
output [2:0]   O_tmds_data_p    // HDMI data positive differential (R, G, B)
output [2:0]   O_tmds_data_n    // HDMI data negative differential (R, G, B)
```

**Key Logic:**
- LED blink counter cycles at 27 MHz for visual feedback
- Vertical sync counter (`cnt_vs`) increments on falling edge of VS signal, allowing mode selection
- PLL lock signal gates the reset to video components (safe state until PLL locks)

---

### 2. `testpattern.v` - Video Pattern Generator

**Purpose:** Generates video timing signals and configurable color patterns for a 1280×720@60Hz display.

**Key Functionality:**

#### Video Timing Generation
- **Horizontal Counter (`H_cnt`):** Counts pixels 0 to `I_h_total-1`
- **Vertical Counter (`V_cnt`):** Counts lines 0 to `I_v_total-1`
- **Signal Generation:**
  - **Data Enable (DE):** High during visible pixel area
  - **Horizontal Sync (HS):** Pulse at start of each line
  - **Vertical Sync (VS):** Pulse at start of each frame
  - Sync polarity selectable via `I_hs_pol` and `I_vs_pol` parameters

#### Delay Pipeline
- 5-stage delay chain on sync/DE signals to synchronize with color data pipeline
- Compensates for latency in pattern generation logic

#### Color Patterns (4 modes via `I_mode`)

**Mode 0: Color Bar Pattern**
- Generates 8 vertical color bars, each 1/8 of screen width
- Colors: WHITE → YELLOW → CYAN → GREEN → MAGENTA → RED → BLUE → BLACK
- Fixed color values (see color constants defined in module)
- Useful for testing display color accuracy

**Mode 1: Net Grid Pattern**
- Black background with red grid lines
- Grid spacing: 32 pixels (selected by bits [4:0] of position counter)
- Grid appears at horizontal and vertical boundaries of 32-pixel blocks
- Good for testing display geometry and alignment

**Mode 2: Gray Gradient**
- Horizontal gradient from black (left) to white (right)
- Each pixel's value equals its X-coordinate (0-255 mapped to 0-1280)
- Useful for testing grayscale linearity and response

**Mode 3: Single Color**
- Solid color throughout display
- Color specified by input pins: `I_single_r`, `I_single_g`, `I_single_b`
- Default in example: GREEN (R=0, G=255, B=0)

#### Input Parameters (All 12-bit)

Video timing parameters for 1280×720@60Hz:
```verilog
I_h_total  = 12'd1650    // Horizontal total pixels (incl. blanking)
I_h_sync   = 12'd40      // Horizontal sync pulse width
I_h_bporch = 12'd220     // Horizontal back porch
I_h_res    = 12'd1280    // Horizontal active pixels
I_v_total  = 12'd750     // Vertical total lines
I_v_sync   = 12'd5       // Vertical sync pulse height
I_v_bporch = 12'd20      // Vertical back porch
I_v_res    = 12'd720     // Vertical active lines
```

**Output Ports:**
```verilog
output       O_de        // Data enable (high during visible pixels)
output reg   O_hs        // Horizontal sync
output reg   O_vs        // Vertical sync
output [7:0] O_data_r    // Red channel (8-bit)
output [7:0] O_data_g    // Green channel (8-bit)
output [7:0] O_data_b    // Blue channel (8-bit)
```

---

### 3. `dvi_tx.v` - HDMI/DVI Transmitter

**Purpose:** Encodes RGB video data into TMDS format and outputs differential pairs for HDMI compatibility.

**Important Note:** This file is **encrypted** using Gowin's synthesis protection mechanism. It's a proprietary IP core generated by the Gowin IDE.

**Functionality (from documentation):**
- **Input:** Parallel RGB color data (8 bits each: R, G, B) + control signals (VS, HS, DE)
- **Output:** TMDS-encoded differential pairs:
  - 1 clock pair (CLK_P/CLK_N)
  - 3 data pairs (D0_P/D0_N, D1_P/D1_N, D2_P/D2_N) for R/G/B channels
- **TMDS Protocol:** Transitions-Minimized Differential Signaling
  - Reduces EMI by minimizing signal transitions
  - Industry-standard for HDMI/DVI

**Interface:**
```verilog
// Inputs
input        I_rst_n         // Asynchronous reset (active low)
input        I_serial_clk    // 5x pixel clock (~135 MHz for 720p)
input        I_rgb_clk       // Pixel clock (~74.25 MHz for 720p)
input        I_rgb_vs        // Vertical sync
input        I_rgb_hs        // Horizontal sync
input        I_rgb_de        // Data enable
input [7:0]  I_rgb_r         // Red channel
input [7:0]  I_rgb_g         // Green channel
input [7:0]  I_rgb_b         // Blue channel

// Outputs (differential pairs)
output       O_tmds_clk_p    // Clock positive
output       O_tmds_clk_n    // Clock negative
output [2:0] O_tmds_data_p   // Data positive (R, G, B)
output [2:0] O_tmds_data_n   // Data negative (R, G, B)
```

---

### 4. `TMDS_rPLL.v` - Phase-Locked Loop

**Purpose:** Generates the high-speed serial clock required for TMDS transmission by multiplying the input clock by 5.

**Timing Requirements:**
- **Input Clock:** 27 MHz (standard video reference clock)
- **Output Clock:** ~135 MHz (5× pixel clock for 1280×720@60Hz)
  - Pixel clock = 27 MHz ÷ 10 ÷ 3.65 ≈ 74.25 MHz
  - Serial clock = 74.25 MHz × 5 ≈ 135 MHz (theoretical, actual = 135 MHz from PLL)

**Outputs:**
```verilog
output clkout   // PLL output clock (~135 MHz)
output lock     // PLL lock indicator (high when stable)
```

**Integration:**
- Clock divider (`CLKDIV`) divides serial clock by 5 to get pixel clock
- Lock signal gates reset to ensure proper initialization

---

## Video Timing Analysis

### 1280×720@60Hz Display Format

| Parameter | Value | Notes |
|-----------|-------|-------|
| Active Pixels | 1280 | Visible horizontal resolution |
| Active Lines | 720 | Visible vertical resolution |
| Pixel Clock | 74.25 MHz | Standard 720p clock |
| Frame Rate | 60 Hz | Refresh rate |
| Total Pixels/Line | 1650 | Includes blanking intervals |
| Total Lines/Frame | 750 | Includes blanking intervals |
| Horizontal Sync | 40 pixels | Sync pulse width |
| H Back Porch | 220 pixels | From sync end to active start |
| Vertical Sync | 5 lines | Sync pulse height |
| V Back Porch | 20 lines | From sync end to active start |

### Timing Diagram
```
Horizontal Timeline:
|--HS(40)--|--HBP(220)--|--------Active(1280)--------|--HFP(110)--|
           ↑ DE goes HIGH here
           
Vertical Timeline:
|--VS(5)--|--VBP(20)--|--------Active(720)--------|--VFP(5)--|
          ↑ DE goes HIGH here
```

---

## Signal Flow

```
27 MHz Clock Input
        ↓
    [PLL] → 135 MHz Serial Clock
        ↓
    [CLKDIV÷5] → 74.25 MHz Pixel Clock
        ↓
    ┌─────────────────────┐
    │   TESTPATTERN       │
    │ (H/V timing + color)│
    └──────────┬──────────┘
               ↓
         (RGB + Sync)
               ↓
        [DVI_TX_TOP]
        TMDS Encoder
               ↓
    ┌─────────────────────┐
    │  HDMI Differential  │
    │   Output Pairs      │
    └─────────────────────┘
```

---

## Constraints & Resources

### FPGA Resource Usage
- Developed for **Gowin GW2A-LV18PG484C8/I7** (Tang Primer 20K)
- Primary usage: Logic LUTs, registers, PLL
- Implementation details in `impl/pnr/` directory

### Power Supply
- Typical HDMI output requires 3.3V or 1.8V LVCMOS differential drivers
- Gowin native differential output support

### Signal Integrity
- TMDS uses 100Ω differential impedance (HDMI standard)
- Minimize trace length mismatch between diff pairs
- Typical HDMI cable tolerance: up to 10 meters

---

## Usage & Configuration

### Running the Design
1. Open `dk_video.gprj` in Gowin EDA IDE
2. Configure IO pins to match Tang Primer 20K schematic:
   - HDMI clock pins (differential pair)
   - HDMI data pins (3× differential pairs for R/G/B)
   - LED pins
   - Reset and clock inputs
3. Run synthesis and place & route
4. Download to FPGA

### Changing Display Patterns
- Patterns rotate automatically every frame based on `cnt_vs` counter
- Modify `I_mode` input to `testpattern` in `video_top.v` for different test patterns
- Single color mode: Change `I_single_r`, `I_single_g`, `I_single_b` inputs

### Modifying Video Resolution
Replace timing parameters in `testpattern` instantiation for different formats:
- **800×600@60Hz:** Adjust H_total, H_sync, H_bporch, H_res, V_total, V_sync, V_bporch, V_res
- **1024×768@60Hz:** Similarly adjust timing values
- Update PLL configuration if pixel clock changes significantly

---

## Known Limitations & Notes

1. **DVI_TX Encryption:** The `dvi_tx.v` module is encrypted and cannot be modified. It's a pre-compiled Gowin IP core.

2. **Fixed Resolution:** Current configuration is hardcoded for 1280×720@60Hz. Runtime resolution switching would require dynamic parameter reconfiguration.

3. **8-bit Color Depth:** Design supports 8 bits per channel (24-bit RGB). Higher color depths would require architectural changes.

4. **No Scaler:** Input patterns are generated at 1280×720 resolution. No scaling is performed.

5. **Single Pattern Output:** Only one pattern is output at a time (selectable via mode bits).

---

## References

- **HDMI Specification:** HDMI 1.4+ (uses DVI 1.0 compatible TMDS encoding)
- **TMDS Encoding:** Transition Minimized Differential Signaling protocol
- **Gowin FPGA Documentation:** Available in Gowin EDA IDE
- **Tang Primer 20K Schematic:** Reference for IO pin assignments

---

## File Manifest

| File | Type | Purpose |
|------|------|---------|
| `video_top.v` | Verilog | Top-level integration module |
| `testpattern.v` | Verilog | Video timing & pattern generation |
| `dvi_tx/dvi_tx.v` | Encrypted Verilog/IP | HDMI transmitter core |
| `gowin_rpll/TMDS_rPLL.v` | Gowin Macro | PLL for clock multiplication |
| `dk_video.gprj` | Gowin IDE | Project configuration |
| `dk_video.fs` | Gowin Fileset | File dependencies & settings |
| `impl/pnr/` | Reports | Place & route results |

---

*Last Updated: 2026-01-05*
*FPGA Platform: Gowin Tang Primer 20K*
*Design Language: Verilog 2001*
