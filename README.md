# DSD-8 Processor

DSD-8 is a Verilog implementation of an 8-bit processor with eight registers,
four status flags, separate instruction and data memories, and a port-mapped
I/O bus. The 512-word instruction ROM accepts 16-bit machine code from the
supplied assembler. The CPU includes a debugger for pause, run, instruction
stepping, one address breakpoint, register inspection, and a 16-instruction
retirement trace.

## Run the verification suite

Install Python 3, GNU Make, Icarus Verilog, and Verilator, then run:

```sh
make all
```

- `make lint` checks both top-level RTL variants.
- `make test` checks the ALU, debugger and trace buffer, and the complete
  JTAG debug path using a separate TCK clock.
- `make conformance` runs each public assembly program on the Verilog
  CPU and the Python reference simulator. It reports the first differing
  retirement line and stores traces in `build/conformance/<program>/`.

Only the public multiplication and population-count programs are checked in.
The course's T01–T40 suite is distributed separately.

## Run the multiplication demo

```sh
python3 tools/dsd8asm.py tests/conformance/sample01_multiply.asm -o program.hex
make conformance
```

The program calculates `13 × 7`, writes `0x5B` to the LEDs, and halts.
For the JTAG demo, use the same image and follow the
[debugger guide](doc/jtag_debugger.md) to stop at the LED write and step it.

| Path | Purpose |
| --- | --- |
| `rtl/dsd8_cpu.v` | CPU datapath, control wiring, and retirement interface |
| `rtl/dsd8_top.v` | Original board interface and button-controlled debugger |
| `rtl/dsd8_jtag_top.v` | System top with the four-wire TAP and peripheral connector |
| `tb/`, `sim/` | Unit tests, conformance harness, and reference peripheral models |
| `tools/` | Assembler, Python reference simulator, and OpenOCD debug commands |

See [CONTRIBUTING.md](CONTRIBUTING.md) for the course's review and milestone workflow.
