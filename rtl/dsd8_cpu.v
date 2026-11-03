// dsd8_cpu.v -- the processor core: fetch, decode, execute, writeback
// Owner: shared (whole team integrates this together)
// Spec: Section 5.2. Port list is FROZEN -- tb_dsd8.v binds to these
// exact names to extract the execution trace (Section 8.3). Renaming
// any of them means the harness will not compile against your design.
//
// retire_* are not debug decoration -- they are how your processor is
// graded (Section 8.2). Get them right early.

module dsd8_cpu (
    input  wire        clk,
    input  wire        rst_n,

    // ---- instruction fetch interface ----
    output wire [8:0]  imem_addr,   // program counter
    input  wire [15:0] imem_data,   // instruction word, valid combinationally

    // ---- I/O bus (Section 7) ----
    output wire [7:0]  io_port,     // port number from IR[7:0]
    output wire [7:0]  io_wdata,    // data for OUT
    input  wire [7:0]  io_rdata,    // data for IN
    output wire        io_rd,       // asserted for one access during IN
    output wire        io_wr,       // asserted for one access during OUT
    input  wire        io_ready,    // peripheral ready; low stalls the CPU

    // ---- status and trace ----
    output wire        halted,
    output wire        retire,          // one pulse per retired instruction
    output wire [8:0]  retire_pc,       // PC of the instruction just retired
    output wire [15:0] retire_ir,       // its instruction word
    output wire        retire_rf_we,    // did it write a register?
    output wire [2:0]  retire_rf_addr,
    output wire [7:0]  retire_rf_data,
    output wire        retire_mem_we,   // did it write data memory?
    output wire [7:0]  retire_mem_addr,
    output wire [7:0]  retire_mem_data,
    output wire [3:0]  retire_flags     // {Z,N,C,V} after the instruction
);

    // ---- Internal Wires ----
    wire [8:0]  pc_curr;
    wire [3:0]  opcode;
    wire [2:0]  dec_rd;
    wire [2:0]  dec_rs1;
    wire [2:0]  dec_rs2;
    wire [7:0]  dec_imm8;
    wire [8:0]  dec_addr9;
    wire [2:0]  dec_cond;
    wire [7:0]  dec_port;
    wire        dec_io_dir;

    wire        pc_en;
    wire        pc_load;
    wire        rf_we;
    wire        mem_we;
    wire        flags_we;
    wire [1:0]  wb_sel;

    wire [7:0]  rf_rd1;
    wire [7:0]  rf_rd2;
    reg  [7:0]  rf_wdata;

    wire [7:0]  alu_result;
    wire        flag_z;
    wire        flag_n;
    wire        flag_c;
    wire        flag_v;
    wire [3:0]  alu_flags = {flag_z, flag_n, flag_c, flag_v};

    wire [3:0]  arch_flags;
    wire [7:0]  dmem_rdata;

    // ---- Program Counter ----
    prog_counter u_pc (
        .clk         (clk),
        .rst_n       (rst_n),
        .pc_en       (pc_en),
        .pc_load     (pc_load),
        .branch_addr (dec_addr9),
        .pc          (pc_curr)
    );

    assign imem_addr = pc_curr;

    // ---- Instruction Decoder ----
    instr_decoder u_dec (
        .instr  (imem_data),
        .opcode (opcode),
        .rd     (dec_rd),
        .rs1    (dec_rs1),
        .rs2    (dec_rs2),
        .imm8   (dec_imm8),
        .addr9  (dec_addr9),
        .cond   (dec_cond),
        .port   (dec_port),
        .io_dir (dec_io_dir)
    );

    // ---- Control Unit ----
    control_unit u_cu (
        .clk      (clk),
        .rst_n    (rst_n),
        .opcode   (opcode),
        .cond     ((opcode == 4'hE) ? {2'b00, dec_io_dir} : dec_cond),
        .flags    (arch_flags),
        .io_ready (io_ready),
        .pc_en    (pc_en),
        .pc_load  (pc_load),
        .rf_we    (rf_we),
        .mem_we   (mem_we),
        .io_rd    (io_rd),
        .io_wr    (io_wr),
        .flags_we (flags_we),
        .wb_sel   (wb_sel),
        .halted   (halted),
        .retire   (retire)
    );

    // ---- Register File ----
    // For ST [rs1], rs2 and OUT port, rs: data register is in instr[11:9] (dec_rd)
    wire [2:0] rf_ra2 = (opcode == 4'h3 || (opcode == 4'hE && dec_io_dir)) ? dec_rd : dec_rs2;

    register_file u_rf (
        .clk   (clk),
        .rst_n (rst_n),
        .ra1   (dec_rs1),
        .ra2   (rf_ra2),
        .rd1   (rf_rd1),
        .rd2   (rf_rd2),
        .we    (rf_we),
        .wa    (dec_rd),
        .wd    (rf_wdata)
    );

    // Writeback Mux
    always @(*) begin
        case (wb_sel)
            2'b00:   rf_wdata = alu_result;
            2'b01:   rf_wdata = dmem_rdata;
            2'b10:   rf_wdata = dec_imm8;
            2'b11:   rf_wdata = io_rdata;
        endcase
    end

    // ---- ALU ----
    alu u_alu (
        .a      (rf_rd1),
        .b      (rf_rd2),
        .op     (opcode),
        .result (alu_result),
        .flag_z (flag_z),
        .flag_n (flag_n),
        .flag_c (flag_c),
        .flag_v (flag_v)
    );

    // ---- Architectural Flags Register ----
    flags_reg u_flags (
        .clk      (clk),
        .rst_n    (rst_n),
        .flags_we (flags_we),
        .flags_in (alu_flags),
        .flags_out(arch_flags)
    );

    // ---- Data Memory ----
    data_memory u_dmem (
        .clk   (clk),
        .addr  (rf_rd1),
        .we    (mem_we),
        .wdata (rf_rd2),
        .rdata (dmem_rdata)
    );

    // ---- I/O Interface Outputs ----
    assign io_port  = dec_port;
    assign io_wdata = rf_rd2;

    // ---- Retire / Trace Outputs ----
    assign retire_pc       = pc_curr;
    assign retire_ir       = imem_data;
    assign retire_rf_we    = rf_we;
    assign retire_rf_addr  = rf_we ? dec_rd : 3'b000;
    assign retire_rf_data  = rf_we ? rf_wdata : 8'h00;
    assign retire_mem_we   = mem_we;
    assign retire_mem_addr = mem_we ? rf_rd1 : 8'h00;
    assign retire_mem_data = mem_we ? rf_rd2 : 8'h00;
    assign retire_flags    = flags_we ? alu_flags : arch_flags;

endmodule
