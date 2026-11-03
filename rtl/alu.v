// alu.v -- arithmetic, logic, shifts, and the four flag outputs
// Owner: member B -- this is YOUR module; you are individually examined
// on it at the oral defence, and it is the one Section 8.5 (R24-R25)
// requires a constrained-random self-checking testbench for.
// Spec: Section 5.7 and Section 2.3. Purely combinational. Port list
// is FROZEN. `op` is the instruction opcode directly (R15) -- no
// separate ALU-control encoding needed.
//
// This file intentionally does NOT implement the truth table for you
// -- Section 2.3 already gives you the exact carry, overflow and flag
// definitions; writing the RTL from that table (and then proving it
// correct with your own random test) is the actual exercise. See
// tools/dsd8sim.py if you want a second, independent statement of the
// same semantics in Python to cross-check your own reading of the spec
// against -- but write this module yourself.

module alu (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [3:0] op,     // instruction opcode: 0x4 ADD .. 0xB CMP
    output wire [7:0] result,
    output wire       flag_z,
    output wire       flag_n,
    output wire       flag_c,
    output wire       flag_v
);

    reg [7:0] alu_out;
    reg       c_out;
    reg       v_out;

    wire [8:0] add9 = {1'b0, a} + {1'b0, b};
    wire [8:0] sub9 = {1'b0, a} + {1'b0, ~b} + 9'h001;

    always @(*) begin
        case (op)
            4'h4: begin // ADD
                alu_out = add9[7:0];
                c_out   = add9[8];
                v_out   = (a[7] == b[7]) && (add9[7] != a[7]);
            end
            4'h5: begin // SUB
                alu_out = sub9[7:0];
                c_out   = sub9[8]; // C=1 means NO borrow (a >= b)
                v_out   = (a[7] != b[7]) && (sub9[7] != a[7]);
            end
            4'h6: begin // AND
                alu_out = a & b;
                c_out   = 1'b0;
                v_out   = 1'b0;
            end
            4'h7: begin // OR
                alu_out = a | b;
                c_out   = 1'b0;
                v_out   = 1'b0;
            end
            4'h8: begin // XOR
                alu_out = a ^ b;
                c_out   = 1'b0;
                v_out   = 1'b0;
            end
            4'h9: begin // SHL
                alu_out = {a[6:0], 1'b0};
                c_out   = a[7];
                v_out   = 1'b0;
            end
            4'hA: begin // SHR
                alu_out = {1'b0, a[7:1]};
                c_out   = a[0];
                v_out   = 1'b0;
            end
            4'hB: begin // CMP
                alu_out = sub9[7:0];
                c_out   = sub9[8];
                v_out   = (a[7] != b[7]) && (sub9[7] != a[7]);
            end
            default: begin
                alu_out = 8'h00;
                c_out   = 1'b0;
                v_out   = 1'b0;
            end
        endcase
    end

    assign result = alu_out;
    assign flag_z = (alu_out == 8'h00);
    assign flag_n = alu_out[7];
    assign flag_c = c_out;
    assign flag_v = v_out;

endmodule
