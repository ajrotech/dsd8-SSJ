// Four-wire TAP with BYPASS and a private DSD-8 command data register.
`timescale 1ns/1ps

module dsd8_jtag_tap (
    input  wire        tck,
    input  wire        tms,
    input  wire        tdi,
    output reg         tdo,
    input  wire        clk,
    input  wire        rst_n,
    output wire        host_valid,
    output reg  [12:0] host_request,
    input  wire [62:0] host_response
);
    localparam [3:0] TEST_RESET = 4'd0, IDLE = 4'd1,
        SELECT_DR = 4'd2, CAPTURE_DR = 4'd3, SHIFT_DR = 4'd4,
        EXIT1_DR = 4'd5, PAUSE_DR = 4'd6, EXIT2_DR = 4'd7, UPDATE_DR = 4'd8,
        SELECT_IR = 4'd9, CAPTURE_IR = 4'd10, SHIFT_IR = 4'd11,
        EXIT1_IR = 4'd12, PAUSE_IR = 4'd13, EXIT2_IR = 4'd14, UPDATE_IR = 4'd15;

    localparam [3:0] IR_DEBUG = 4'h2, IR_BYPASS = 4'hF;

    (* ASYNC_REG = "TRUE" *) reg [1:0] tap_reset_sync;
    always @(posedge tck or negedge rst_n) begin
        if (!rst_n) tap_reset_sync <= 2'b00;
        else tap_reset_sync <= {tap_reset_sync[0], 1'b1};
    end
    wire tap_rst_n = tap_reset_sync[1];

    reg [3:0] state, next_state;
    reg [3:0] ir, ir_shift;
    reg [63:0] dr_shift;
    reg [6:0] dr_bits;
    reg bypass_shift;

    // Toggle mailbox. Payloads are held stable until acknowledgment has
    // crossed back through two flops. Each receiving side captures its payload
    // only after the synchronized toggle arrives.
    reg request_toggle, ack_toggle;
    (* ASYNC_REG = "TRUE" *) reg [1:0] request_sync, ack_sync;
    reg [12:0] request_mailbox;
    reg [62:0] response_mailbox;
    reg host_active;
    wire busy = request_toggle != ack_sync[1];
    assign host_valid = host_active;

    always @(posedge clk) begin
        if (!rst_n) begin
            request_sync <= 2'b0;
            ack_toggle <= 1'b0;
            host_request <= 13'b0;
            host_active <= 1'b0;
            response_mailbox <= 63'b0;
        end else begin
            request_sync <= {request_sync[0], request_toggle};
            if (host_active) begin
                response_mailbox <= host_response;
                ack_toggle <= request_sync[1];
                host_active <= 1'b0;
            end else if (request_sync[1] != ack_toggle) begin
                host_request <= request_mailbox;
                host_active <= 1'b1;
            end
        end
    end

    always @(*) begin
        case (state)
            TEST_RESET: next_state = tms ? TEST_RESET : IDLE;
            IDLE:       next_state = tms ? SELECT_DR : IDLE;
            SELECT_DR:  next_state = tms ? SELECT_IR : CAPTURE_DR;
            CAPTURE_DR: next_state = tms ? EXIT1_DR : SHIFT_DR;
            SHIFT_DR:   next_state = tms ? EXIT1_DR : SHIFT_DR;
            EXIT1_DR:   next_state = tms ? UPDATE_DR : PAUSE_DR;
            PAUSE_DR:   next_state = tms ? EXIT2_DR : PAUSE_DR;
            EXIT2_DR:   next_state = tms ? UPDATE_DR : SHIFT_DR;
            UPDATE_DR:  next_state = tms ? SELECT_DR : IDLE;
            SELECT_IR:  next_state = tms ? TEST_RESET : CAPTURE_IR;
            CAPTURE_IR: next_state = tms ? EXIT1_IR : SHIFT_IR;
            SHIFT_IR:   next_state = tms ? EXIT1_IR : SHIFT_IR;
            EXIT1_IR:   next_state = tms ? UPDATE_IR : PAUSE_IR;
            PAUSE_IR:   next_state = tms ? EXIT2_IR : PAUSE_IR;
            EXIT2_IR:   next_state = tms ? UPDATE_IR : SHIFT_IR;
            UPDATE_IR:  next_state = tms ? SELECT_DR : IDLE;
            default:    next_state = TEST_RESET;
        endcase
    end

    always @(posedge tck or negedge tap_rst_n) begin
        if (!tap_rst_n) begin
            state <= TEST_RESET;
            ack_sync <= 2'b0;
            ir_shift <= 4'b0;
            bypass_shift <= 1'b0;
            dr_shift <= 64'b0;
            dr_bits <= 7'b0;
        end else begin
            state <= next_state;
            ack_sync <= {ack_sync[0], ack_toggle};
            case (state)
                CAPTURE_IR: ir_shift <= 4'b0001;
                SHIFT_IR: ir_shift <= {tdi, ir_shift[3:1]};
                CAPTURE_DR: begin
                    bypass_shift <= 1'b0;
                    dr_shift <= busy ? 64'b0 : {1'b1, response_mailbox};
                    dr_bits <= 7'b0;
                end
                SHIFT_DR: begin
                    if (ir == IR_DEBUG) begin
                        dr_shift <= {tdi, dr_shift[63:1]};
                        if (dr_bits < 7'd64) dr_bits <= dr_bits + 7'd1;
                    end else begin
                        bypass_shift <= tdi;
                    end
                end
                default: begin end
            endcase
        end
    end

    always @(negedge tck or negedge tap_rst_n) begin
        if (!tap_rst_n) begin
            ir <= IR_BYPASS;
            tdo <= 1'b0;
            request_toggle <= 1'b0;
            request_mailbox <= 13'b0;
        end else begin
            if (state == TEST_RESET) ir <= IR_BYPASS;
            else if (state == UPDATE_IR) ir <= ir_shift;

            if (state == SHIFT_IR) tdo <= ir_shift[0];
            else if (state == SHIFT_DR) tdo <= (ir == IR_DEBUG) ? dr_shift[0] : bypass_shift;
            else tdo <= 1'b0;

            // A zero command polls the response without changing the mailbox.
            if (state == UPDATE_DR && ir == IR_DEBUG && !busy &&
                dr_bits == 7'd64 && dr_shift[3:0] != 4'b0) begin
                request_mailbox <= dr_shift[12:0];
                request_toggle <= ~request_toggle;
            end
        end
    end
endmodule
