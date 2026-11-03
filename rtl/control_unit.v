// control_unit.v -- the FSM that sequences every instruction
// Owner: member C -- this is YOUR module; you are individually examined
// on it at the oral defence, and it is the heart of your microarchitecture
// choice (Section 4.3).
// Spec: Section 6. Port list is FROZEN.
//
// This is deliberately the least finished file in this repository: the
// control unit is the one part of the design the spec leaves entirely
// up to you (single-cycle, multi-cycle, or pipelined -- Section 4.3),
// and it is what the recommended state machine and control-signal
// table in Section 6 describe. Copying a working FSM from anywhere
// would defeat the point of the assignment and of the oral defence.
//
// What every implementation must guarantee, regardless of style
// (Section 8.2, R22): instructions retire in program order, and
// `retire` pulses exactly once per retired instruction -- never zero,
// never twice.

module control_unit (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] opcode,
    input  wire [2:0] cond,
    input  wire [3:0] flags,      // {Z,N,C,V}
    input  wire       io_ready,
    output reg        pc_en,
    output reg        pc_load,
    output reg        rf_we,
    output reg        mem_we,
    output reg        io_rd,
    output reg        io_wr,
    output reg        flags_we,
    output reg  [1:0] wb_sel,     // 0=ALU 1=DMEM 2=imm8 3=io_rdata
    output reg        halted,
    output reg        retire
);

    wire z = flags[3];
    wire n = flags[2];
    wire c = flags[1];
    wire v = flags[0];

    reg branch_taken;
    always @(*) begin
        case (cond)
            3'b000: branch_taken = (z == 1'b1); // BEQ
            3'b001: branch_taken = (z == 1'b0); // BNE
            3'b010: branch_taken = (c == 1'b1); // BCS
            3'b011: branch_taken = (c == 1'b0); // BCC
            3'b100: branch_taken = (n == 1'b1); // BMI
            3'b101: branch_taken = (n == 1'b0); // BPL
            3'b110: branch_taken = (v == 1'b1); // BVS
            3'b111: branch_taken = (v == 1'b0); // BVC
            default: branch_taken = 1'b0;
        endcase
    end

    reg halted_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            halted_r <= 1'b0;
        end else if (opcode == 4'hF && !halted_r && io_ready) begin
            halted_r <= 1'b1;
        end
    end

    always @(*) begin
        halted   = halted_r;
        pc_en    = 1'b0;
        pc_load  = 1'b0;
        rf_we    = 1'b0;
        mem_we   = 1'b0;
        io_rd    = 1'b0;
        io_wr    = 1'b0;
        flags_we = 1'b0;
        wb_sel   = 2'b00;
        retire   = 1'b0;

        if (rst_n && !halted_r) begin
            case (opcode)
                4'h0: begin // NOP
                    pc_en  = io_ready;
                    retire = io_ready;
                end
                4'h1: begin // LDI
                    pc_en  = io_ready;
                    rf_we  = io_ready;
                    wb_sel = 2'b10;
                    retire = io_ready;
                end
                4'h2: begin // LD
                    pc_en  = io_ready;
                    rf_we  = io_ready;
                    wb_sel = 2'b01;
                    retire = io_ready;
                end
                4'h3: begin // ST
                    pc_en  = io_ready;
                    mem_we = io_ready;
                    retire = io_ready;
                end
                4'h4, 4'h5, 4'h6, 4'h7, 4'h8, 4'h9, 4'hA: begin // ADD, SUB, AND, OR, XOR, SHL, SHR
                    pc_en    = io_ready;
                    rf_we    = io_ready;
                    flags_we = io_ready;
                    wb_sel   = 2'b00;
                    retire   = io_ready;
                end
                4'hB: begin // CMP
                    pc_en    = io_ready;
                    flags_we = io_ready;
                    retire   = io_ready;
                end
                4'hC: begin // JMP
                    pc_en   = io_ready;
                    pc_load = 1'b1;
                    retire  = io_ready;
                end
                4'hD: begin // Bcc
                    pc_en   = io_ready;
                    pc_load = branch_taken;
                    retire  = io_ready;
                end
                4'hE: begin // IN / OUT (cond[0]: 0=IN, 1=OUT)
                    if (cond[0] == 1'b0) begin // IN
                        io_rd  = 1'b1;
                        pc_en  = io_ready;
                        rf_we  = io_ready;
                        wb_sel = 2'b11;
                        retire = io_ready;
                    end else begin // OUT
                        io_wr  = 1'b1;
                        pc_en  = io_ready;
                        retire = io_ready;
                    end
                end
                4'hF: begin // HLT
                    pc_en  = 1'b0;
                    retire = io_ready;
                end
                default: begin
                    pc_en  = 1'b0;
                    retire = 1'b0;
                end
            endcase
        end
    end

endmodule
