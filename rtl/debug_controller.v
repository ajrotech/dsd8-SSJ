// debug_controller.v -- lightweight built-in CPU debugger controller
// Supports disabled, running, paused, single-step, and PC breakpoint states.
// Gates dsd8_cpu.io_ready non-intrusively and provides shadow register inspection.

`timescale 1ns/1ps

module debug_controller (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Control & Command Inputs ----
    input  wire        debug_en,        // 1 = Debugger active, 0 = Normal execution
    input  wire        cmd_step,        // 1-cycle synchronized pulse to step 1 instruction
    input  wire        cmd_resume,      // 1-cycle synchronized pulse to resume running
    input  wire        cmd_pause,       // 1-cycle synchronized pulse to pause running
    input  wire        bp_en,           // 1 = Breakpoint enabled
    input  wire [8:0]  bp_pc,           // Target breakpoint PC

    // ---- Snooped CPU Ports (dsd8_cpu outputs) ----
    input  wire [8:0]  imem_addr,       // Current PC being fetched (checked for BP)
    input  wire [15:0] imem_data,       // Current IR being fetched
    input  wire        cpu_halted,      // CPU halted output
    input  wire        retire,          // CPU retire strobe
    input  wire [8:0]  retire_pc,
    input  wire [15:0] retire_ir,
    input  wire        retire_rf_we,
    input  wire [2:0]  retire_rf_addr,
    input  wire [7:0]  retire_rf_data,
    input  wire [3:0]  retire_flags,

    // ---- CPU Stall Control (gates io_ready) ----
    input  wire        bus_io_ready,    // Normal io_ready from io_bus
    output wire        cpu_io_ready,    // Gated io_ready delivered to dsd8_cpu

    // ---- Status Indicators ----
    output wire [2:0]  debug_state,     // Current FSM state
    output wire        dbg_paused,      // 1 when CPU is currently paused
    output reg         dbg_bp_hit,      // 1 when paused due to breakpoint match

    // ---- Architectural State Inspection ----
    input  wire [3:0]  inspect_sel,     // 0..7: R0..R7, 8: PC[7:0], 9: PC[8], 10: IR[7:0], 11: IR[15:8], 12: Flags
    output reg  [7:0]  inspect_data     // 8-bit inspected value
);

    // State definitions
    localparam STATE_DISABLED = 3'b000;
    localparam STATE_PAUSED   = 3'b001;
    localparam STATE_STEP     = 3'b010;
    localparam STATE_RUNNING  = 3'b011;
    localparam STATE_BP_HIT   = 3'b100;

    reg [2:0] state;
    reg       step_resume; // 1 = stepping over breakpoint before returning to running

    assign debug_state = state;
    assign dbg_paused  = (state == STATE_PAUSED) || (state == STATE_BP_HIT);

    // ---- io_ready Gating ----
    // When debug_en is 0, bus_io_ready passes through with zero modification.
    // When debug_en is 1, CPU is allowed to advance only in RUNNING and STEP states.
    assign cpu_io_ready = (!debug_en) ? bus_io_ready :
                          ((state == STATE_RUNNING || state == STATE_STEP) ? bus_io_ready : 1'b0);

    // ---- FSM State Transitions ----
    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= STATE_DISABLED;
            dbg_bp_hit  <= 1'b0;
            step_resume <= 1'b0;
        end else if (!debug_en) begin
            state       <= STATE_DISABLED;
            dbg_bp_hit  <= 1'b0;
            step_resume <= 1'b0;
        end else begin
            case (state)
                STATE_DISABLED: begin
                    // debug_en asserted: enter paused state
                    state      <= STATE_PAUSED;
                    dbg_bp_hit <= 1'b0;
                end

                STATE_PAUSED: begin
                    dbg_bp_hit <= 1'b0;
                    if (cmd_step) begin
                        state <= STATE_STEP;
                    end else if (cmd_resume) begin
                        state <= STATE_RUNNING;
                    end
                end

                STATE_STEP: begin
                    if (retire || cpu_halted) begin
                        if (step_resume) begin
                            step_resume <= 1'b0;
                            state       <= STATE_RUNNING;
                        end else begin
                            state <= STATE_PAUSED;
                        end
                    end
                end

                STATE_RUNNING: begin
                    if (cmd_pause || cpu_halted) begin
                        state <= STATE_PAUSED;
                    end else if (bp_en && (imem_addr == bp_pc)) begin
                        state      <= STATE_BP_HIT;
                        dbg_bp_hit <= 1'b1;
                    end
                end

                STATE_BP_HIT: begin
                    if (!bp_en) begin
                        state      <= STATE_PAUSED;
                        dbg_bp_hit <= 1'b0;
                    end else if (cmd_step) begin
                        dbg_bp_hit <= 1'b0;
                        state      <= STATE_STEP;
                    end else if (cmd_resume) begin
                        dbg_bp_hit  <= 1'b0;
                        step_resume <= 1'b1; // Step past breakpoint, then continue running
                        state       <= STATE_STEP;
                    end
                end

                default: state <= STATE_DISABLED;
            endcase
        end
    end

    // ---- Shadow Register File for Non-Intrusive Inspection ----
    reg [7:0] shadow_rf [0:7];
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                shadow_rf[i] <= 8'h00;
            end
        end else if (retire && retire_rf_we) begin
            shadow_rf[retire_rf_addr] <= retire_rf_data;
        end
    end

    // ---- Architectural State Inspection Mux ----
    always @(*) begin
        case (inspect_sel)
            4'h0, 4'h1, 4'h2, 4'h3,
            4'h4, 4'h5, 4'h6, 4'h7: inspect_data = shadow_rf[inspect_sel[2:0]];
            4'h8: inspect_data = imem_addr[7:0];
            4'h9: inspect_data = {7'b0000000, imem_addr[8]};
            4'hA: inspect_data = imem_data[7:0];
            4'hB: inspect_data = imem_data[15:8];
            4'hC: inspect_data = {4'b0000, retire_flags};
            4'hD: inspect_data = retire_pc[7:0];
            4'hE: inspect_data = retire_ir[7:0];
            4'hF: inspect_data = {5'b00000, state};
            default: inspect_data = 8'h00;
        endcase
    end

endmodule

