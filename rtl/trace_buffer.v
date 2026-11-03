// trace_buffer.v -- 16-deep circular history buffer of retired instructions
// Stores the last 16 retired instructions' trace fields for debugger inspection.

`timescale 1ns/1ps

module trace_buffer #(
    parameter DEPTH = 16
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    // ---- Write Interface (snoops dsd8_cpu retire_* ports) ----
    input  wire        retire,
    input  wire [8:0]  retire_pc,
    input  wire [15:0] retire_ir,
    input  wire        retire_rf_we,
    input  wire [2:0]  retire_rf_addr,
    input  wire [7:0]  retire_rf_data,
    input  wire        retire_mem_we,
    input  wire [7:0]  retire_mem_addr,
    input  wire [7:0]  retire_mem_data,
    input  wire [3:0]  retire_flags,

    // ---- Inspection Read Interface ----
    input  wire [3:0]  read_slot,       // 0 = most recent, 1 = previous, ..., 15 = oldest
    output wire [8:0]  hist_pc,
    output wire [15:0] hist_ir,
    output wire        hist_rf_we,
    output wire [2:0]  hist_rf_addr,
    output wire [7:0]  hist_rf_data,
    output wire        hist_mem_we,
    output wire [7:0]  hist_mem_addr,
    output wire [7:0]  hist_mem_data,
    output wire [3:0]  hist_flags,
    output reg  [4:0]  valid_count      // 0 to DEPTH
);

    // Circular storage arrays
    reg [8:0]  buf_pc       [0:DEPTH-1];
    reg [15:0] buf_ir       [0:DEPTH-1];
    reg        buf_rf_we    [0:DEPTH-1];
    reg [2:0]  buf_rf_addr  [0:DEPTH-1];
    reg [7:0]  buf_rf_data  [0:DEPTH-1];
    reg        buf_mem_we   [0:DEPTH-1];
    reg [7:0]  buf_mem_addr [0:DEPTH-1];
    reg [7:0]  buf_mem_data [0:DEPTH-1];
    reg [3:0]  buf_flags    [0:DEPTH-1];

    reg [3:0]  wr_ptr;
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr      <= 4'h0;
            valid_count <= 5'd0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                buf_pc[i]       <= 9'h000;
                buf_ir[i]       <= 16'h0000;
                buf_rf_we[i]    <= 1'b0;
                buf_rf_addr[i]  <= 3'b000;
                buf_rf_data[i]  <= 8'h00;
                buf_mem_we[i]   <= 1'b0;
                buf_mem_addr[i] <= 8'h00;
                buf_mem_data[i] <= 8'h00;
                buf_flags[i]    <= 4'b0000;
            end
        end else if (clear) begin
            wr_ptr      <= 4'h0;
            valid_count <= 5'd0;
        end else if (retire) begin
            buf_pc[wr_ptr]       <= retire_pc;
            buf_ir[wr_ptr]       <= retire_ir;
            buf_rf_we[wr_ptr]    <= retire_rf_we;
            buf_rf_addr[wr_ptr]  <= retire_rf_addr;
            buf_rf_data[wr_ptr]  <= retire_rf_data;
            buf_mem_we[wr_ptr]   <= retire_mem_we;
            buf_mem_addr[wr_ptr] <= retire_mem_addr;
            buf_mem_data[wr_ptr] <= retire_mem_data;
            buf_flags[wr_ptr]    <= retire_flags;

            wr_ptr <= wr_ptr + 4'd1;
            if (valid_count < DEPTH) begin
                valid_count <= valid_count + 5'd1;
            end
        end
    end

    // Circular read index: slot 0 is the most recently written (wr_ptr - 1)
    wire [3:0] rd_idx = wr_ptr - 4'd1 - read_slot;

    assign hist_pc       = buf_pc[rd_idx];
    assign hist_ir       = buf_ir[rd_idx];
    assign hist_rf_we    = buf_rf_we[rd_idx];
    assign hist_rf_addr  = buf_rf_addr[rd_idx];
    assign hist_rf_data  = buf_rf_data[rd_idx];
    assign hist_mem_we   = buf_mem_we[rd_idx];
    assign hist_mem_addr = buf_mem_addr[rd_idx];
    assign hist_mem_data = buf_mem_data[rd_idx];
    assign hist_flags    = buf_flags[rd_idx];

endmodule

