# DSD-8 hardware debugger

Use `dsd8_jtag_top` as the FPGA top and set its `IMAGE` parameter to the
assembled program image. The original `dsd8_top` still supports button
debugging. Serial debug takes control on `pause` and hands it back on
`release`. The application retains the LEDs and display during serial debug.

## Board integration

Assign `tck`, `tms`, and `tdi` as inputs and `tdo` as an output. Connect
the adapter ground and select voltage-compatible GPIO and clock-capable pins
appropriate to your board. These are user logic pins. Access through a
board's FPGA configuration JTAG header would require a vendor-specific
bridge. Set clock constraints for both `clk` and `tck`.

The forwarded `periph_*` bus is for UART, timer, SLOW_ECHO, or other
external devices. For the LED demo, tie `periph_ready` to 1 and
`periph_rdata` to 0. The supplied peripheral models are for simulation.
The core samples reset on the system clock. The TAP resets when board
reset asserts, even with TCK stopped. Keep TMS high for at least eight
TCK cycles after reset before trying to scan. A TMS-only TAP reset selects
BYPASS and leaves the CPU's debugger state intact.

The TAP uses the 16-state scan controller, a 4-bit instruction register,
and LSB-first scans. Instruction `0xF` selects 1-bit BYPASS, the reset
default. Instruction `0x2` selects the private 64-bit debug data register.
The interface implements internal debugging and does not implement
boundary scan or a GDB target. The request and response cross the clock
boundary through one-entry toggle mailboxes with synchronized control
signals and held payloads. Constrain and check the bundled-data paths
and synchronizers with your FPGA tool when integrating this top.

## Run the demo with OpenOCD

Use your adapter configuration, select JTAG transport, and declare the TAP
before running `init`:

```tcl
jtag newtap dsd8 debug -irlen 4 -ircapture 0x1 -irmask 0x3
```

Load the multiplication image. To let the probe attach before instruction
zero executes, keep switch 7 high during board reset. Then run:

```tcl
source tools/dsd8_openocd.tcl
dsd8 pause
dsd8 break 10
dsd8 run
dsd8 status
dsd8 inspect 3
dsd8 step
dsd8 trace 0
```

When the status shows a breakpoint at PC 10 (`0x00A`), `inspect 3`
returns `0x5B` in the low byte. After `step`, the LEDs show `0x5B`
and the newest trace records the `OUT`. Use `dsd8 run` to execute
the following `HLT`. Reset the board to start a halted program again.

| Command | Code | Argument / result |
| --- | --- | --- |
| `pause` | `1` | Attach and request a pause at the next safe instruction boundary |
| `run` | `2` | Resume, stepping over the current breakpoint if stopped on it |
| `step` | `3` | Execute one instruction from a debug pause |
| `break` | `4` | Set one 9-bit breakpoint address |
| `status` | `5` | Bits 24:22 state, 21:18 flags, 17:9 PC, 8:4 trace count, then attached, halted, breakpoint-hit, paused in bits 3:0 |
| `inspect` | `6` | Select 0–7 for R0–R7, 8 for PC low byte, 9 for PC bit 8, 10–11 for instruction low/high bytes, 12 for flags, or 15 for debug state |
| `trace` | `7` | Read a retirement entry. Slot 0 is newest and slot 15 is oldest. |
| `release` | `8` | Clear the serial breakpoint and return control to the board |
| `clear` | `9` | Disable the serial breakpoint |

For a raw transaction, scan the command in bits 3:0 and the argument in
bits 12:4. Poll by scanning zeros until response bit 63 is set. Bit 62 is
the error flag. Poll until the response arrives before sending a new command.
A successful run-control response acknowledges the request. Use `status`
to check when execution has actually paused. Read registers and trace while
paused. A slow I/O request that has already started completes before a
pause takes effect.

The 58-bit trace entry packs PC (57:49), instruction (48:33), register write
enable (32), register address (31:29), register data (28:21), memory write
enable (20), memory address (19:12), memory data (11:4), and ZNCV (3:0).
