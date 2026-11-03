// dsd8_top.v -- system top level with lightweight built-in CPU debugger
// Spec: Section 5.1. Port list is FROZEN -- do not rename or resize.

`timescale 1ns/1ps

module dsd8_top (
    input  wire       clk,
    input  wire       rst_n,       // synchronous, active low
    input  wire [7:0] switches,    // board slide switches  -> port 0x00
    input  wire [4:0] buttons,     // {btnU,btnD,btnL,btnR,btnC} -> port 0x01
    output wire [7:0] leds,        // board LEDs             <- port 0x02
    output wire [6:0] seg,         // seven-segment segments <- port 0x10
    output wire [3:0] an,          // seven-segment digit enables
    output wire       halted       // asserted after HLT retires
);

    // ---- 2-FF Button Synchronizer & Positive-Edge Pulse Generator ----
    // buttons mapping: buttons[4]=btnU, buttons[3]=btnD, buttons[2]=btnL, buttons[1]=btnR, buttons[0]=btnC
    reg [4:0] btn_sync0, btn_sync1, btn_prev;
    wire [4:0] btn_pulse;

    always @(posedge clk) begin
        if (!rst_n) begin
            btn_sync0 <= 5'h00;
            btn_sync1 <= 5'h00;
            btn_prev   <= 5'h00;
        end else begin
            btn_sync0 <= buttons;
            btn_sync1 <= btn_sync0;
            btn_prev   <= btn_sync1;
        end
    end

    assign btn_pulse = btn_sync1 & ~btn_prev;

    wire cmd_resume     = btn_pulse[4]; // btnU: Resume execution
    wire cmd_pause      = btn_pulse[3]; // btnD: Pause execution
    wire trace_slot_dec = btn_pulse[2]; // btnL: Previous history trace slot
    wire trace_slot_inc = btn_pulse[1]; // btnR: Next history trace slot
    wire cmd_step       = btn_pulse[0]; // btnC: Single-step one instruction

    // ---- Switch Controls ----
    wire       debug_en    = switches[7];
    wire       bp_en       = switches[6];
    wire [8:0] bp_pc       = {3'b000, switches[5:0]};
    wire [3:0] inspect_sel = switches[3:0];

    // ---- Trace Slot Navigation ----
    reg [3:0] trace_read_slot;
    always @(posedge clk) begin
        if (!rst_n) begin
            trace_read_slot <= 4'h0;
        end else if (trace_slot_inc) begin
            trace_read_slot <= trace_read_slot + 4'h1;
        end else if (trace_slot_dec) begin
            trace_read_slot <= trace_read_slot - 4'h1;
        end
    end

    // ---- Fetch interface between dsd8_cpu and instr_memory ----
    wire [8:0]  imem_addr;
    wire [15:0] imem_data;

    // ---- I/O bus signals ----
    wire [7:0]  io_port;
    wire [7:0]  io_wdata;
    wire [7:0]  io_rdata;
    wire        io_rd;
    wire        io_wr;
    wire        bus_io_ready;
    wire        cpu_io_ready;

    // ---- CPU status & trace signals ----
    wire        cpu_halted;
    wire        cpu_retire;
    wire [8:0]  retire_pc;
    wire [15:0] retire_ir;
    wire        retire_rf_we;
    wire [2:0]  retire_rf_addr;
    wire [7:0]  retire_rf_data;
    wire        retire_mem_we;
    wire [7:0]  retire_mem_addr;
    wire [7:0]  retire_mem_data;
    wire [3:0]  retire_flags;

    // ---- Board peripherals from io_bus ----
    wire [7:0]  bus_leds;
    wire [7:0]  seg_value;
    wire [7:0]  seg_enable;

    // ---- Debugger signals ----
    wire [2:0]  debug_state;
    wire        dbg_paused;
    wire        dbg_bp_hit;
    wire [7:0]  inspect_data;

    // ---- Trace buffer inspection signals ----
    wire [8:0]  hist_pc;
    wire [15:0] hist_ir;
    wire        hist_rf_we;
    wire [2:0]  hist_rf_addr;
    wire [7:0]  hist_rf_data;
    wire        hist_mem_we;
    wire [7:0]  hist_mem_addr;
    wire [7:0]  hist_mem_data;
    wire [3:0]  hist_flags;
    wire [4:0]  trace_valid_count;

    assign halted = cpu_halted;

    // ---- Instruction Memory ----
    instr_memory u_imem (
        .clk  (clk),
        .addr (imem_addr),
        .data (imem_data)
    );

    // ---- CPU Core (Frozen port list preserved exactly) ----
    dsd8_cpu u_cpu (
        .clk             (clk),
        .rst_n           (rst_n),
        .imem_addr       (imem_addr),
        .imem_data       (imem_data),
        .io_port         (io_port),
        .io_wdata        (io_wdata),
        .io_rdata        (io_rdata),
        .io_rd           (io_rd),
        .io_wr           (io_wr),
        .io_ready        (cpu_io_ready),
        .halted          (cpu_halted),
        .retire          (cpu_retire),
        .retire_pc       (retire_pc),
        .retire_ir       (retire_ir),
        .retire_rf_we    (retire_rf_we),
        .retire_rf_addr  (retire_rf_addr),
        .retire_rf_data  (retire_rf_data),
        .retire_mem_we   (retire_mem_we),
        .retire_mem_addr (retire_mem_addr),
        .retire_mem_data (retire_mem_data),
        .retire_flags    (retire_flags)
    );

    // ---- I/O Bus ----
    io_bus u_io_bus (
        .clk           (clk),
        .rst_n         (rst_n),
        .io_port       (io_port),
        .io_wdata      (io_wdata),
        .io_rdata      (io_rdata),
        .io_rd         (io_rd),
        .io_wr         (io_wr),
        .io_ready      (bus_io_ready),
        .switches      (switches),
        .buttons       (buttons),
        .leds          (bus_leds),
        .seg_value     (seg_value),
        .seg_enable    (seg_enable),
        .periph_port   (),
        .periph_wdata  (),
        .periph_rdata  (8'h00),
        .periph_rd     (),
        .periph_wr     (),
        .periph_ready  (1'b1)
    );

    // ---- Debug Controller ----
    debug_controller u_debug_ctrl (
        .clk             (clk),
        .rst_n           (rst_n),
        .debug_en        (debug_en),
        .cmd_step        (cmd_step),
        .cmd_resume      (cmd_resume),
        .cmd_pause       (cmd_pause),
        .bp_en           (bp_en),
        .bp_pc           (bp_pc),
        .imem_addr       (imem_addr),
        .imem_data       (imem_data),
        .cpu_halted      (cpu_halted),
        .retire          (cpu_retire),
        .retire_pc       (retire_pc),
        .retire_ir       (retire_ir),
        .retire_rf_we    (retire_rf_we),
        .retire_rf_addr  (retire_rf_addr),
        .retire_rf_data  (retire_rf_data),
        .retire_flags    (retire_flags),
        .bus_io_ready    (bus_io_ready),
        .cpu_io_ready    (cpu_io_ready),
        .debug_state     (debug_state),
        .dbg_paused      (dbg_paused),
        .dbg_bp_hit      (dbg_bp_hit),
        .inspect_sel     (inspect_sel),
        .inspect_data    (inspect_data)
    );

    // ---- Trace Buffer (16-deep circular history) ----
    trace_buffer #(.DEPTH(16)) u_trace_buffer (
        .clk             (clk),
        .rst_n           (rst_n),
        .clear           (!debug_en),
        .retire          (cpu_retire),
        .retire_pc       (retire_pc),
        .retire_ir       (retire_ir),
        .retire_rf_we    (retire_rf_we),
        .retire_rf_addr  (retire_rf_addr),
        .retire_rf_data  (retire_rf_data),
        .retire_mem_we   (retire_mem_we),
        .retire_mem_addr (retire_mem_addr),
        .retire_mem_data (retire_mem_data),
        .retire_flags    (retire_flags),
        .read_slot       (trace_read_slot),
        .hist_pc         (hist_pc),
        .hist_ir         (hist_ir),
        .hist_rf_we      (hist_rf_we),
        .hist_rf_addr    (hist_rf_addr),
        .hist_rf_data    (hist_rf_data),
        .hist_mem_we     (hist_mem_we),
        .hist_mem_addr   (hist_mem_addr),
        .hist_mem_data   (hist_mem_data),
        .hist_flags      (hist_flags),
        .valid_count     (trace_valid_count)
    );

    // ---- LED Multiplexing ----
    // Normal mode: bus LEDs (port 0x02)
    // Debug mode: [7] paused, [6] bp_hit, [5] halted, [4] bp_en, [3:0] retire_flags {Z,N,C,V}
    assign leds = (!debug_en) ? bus_leds :
                  {dbg_paused, dbg_bp_hit, cpu_halted, bp_en, retire_flags};

    // ---- Seven-Segment Display Multiplexing ----
    wire [7:0] active_seg_val = (!debug_en) ? seg_value : inspect_data;
    wire [7:0] active_seg_en  = (!debug_en) ? seg_enable : 8'h03; // digits 0 and 1 active in debug

    reg [17:0] refresh_counter;
    always @(posedge clk) begin
        if (!rst_n) refresh_counter <= 18'h0;
        else        refresh_counter <= refresh_counter + 18'h1;
    end

    wire [1:0] active_digit = refresh_counter[17:16];
    reg [3:0]  digit_val;
    reg        digit_en;

    always @(*) begin
        case (active_digit)
            2'b00: begin
                digit_val = active_seg_val[3:0];
                digit_en  = active_seg_en[0];
            end
            2'b01: begin
                digit_val = active_seg_val[7:4];
                digit_en  = active_seg_en[1];
            end
            2'b10: begin
                digit_val = 4'h0;
                digit_en  = active_seg_en[2];
            end
            2'b11: begin
                digit_val = 4'h0;
                digit_en  = active_seg_en[3];
            end
        endcase
    end

    function [6:0] hex2seg(input [3:0] d);
        case (d)
            4'h0: hex2seg = 7'b1000000;
            4'h1: hex2seg = 7'b1111001;
            4'h2: hex2seg = 7'b0100100;
            4'h3: hex2seg = 7'b0110000;
            4'h4: hex2seg = 7'b0011001;
            4'h5: hex2seg = 7'b0010010;
            4'h6: hex2seg = 7'b0000010;
            4'h7: hex2seg = 7'b1111000;
            4'h8: hex2seg = 7'b0000000;
            4'h9: hex2seg = 7'b0010000;
            4'hA: hex2seg = 7'b0001000;
            4'hB: hex2seg = 7'b0000011;
            4'hC: hex2seg = 7'b1000110;
            4'hD: hex2seg = 7'b0100001;
            4'hE: hex2seg = 7'b0000110;
            4'hF: hex2seg = 7'b0001110;
        endcase
    endfunction

    assign seg = digit_en ? hex2seg(digit_val) : 7'b1111111;

    reg [3:0] an_out;
    always @(*) begin
        if (!rst_n) begin
            an_out = 4'b1111;
        end else begin
            case (active_digit)
                2'b00: an_out = digit_en ? 4'b1110 : 4'b1111;
                2'b01: an_out = digit_en ? 4'b1101 : 4'b1111;
                2'b10: an_out = digit_en ? 4'b1011 : 4'b1111;
                2'b11: an_out = digit_en ? 4'b0111 : 4'b1111;
            endcase
        end
    end

    assign an = an_out;

endmodule
