// FPGA integration top. Connect user GPIO or a board-specific TAP bridge
// to the four scan pins, and attach peripherals to the forwarded I/O bus.
`timescale 1ns/1ps

module dsd8_jtag_top #(parameter IMAGE = "program.hex") (
    input  wire       clk,
    // The course core samples reset on clk. The TAP also needs to reset
    // while the external TCK is stopped.
    /* verilator lint_off SYNCASYNCNET */
    input  wire       rst_n,
    /* verilator lint_on SYNCASYNCNET */
    input  wire [7:0] switches,
    input  wire [4:0] buttons,
    output wire [7:0] leds,
    output wire [6:0] seg,
    output wire [3:0] an,
    output wire       halted,
    input  wire       tck,
    input  wire       tms,
    input  wire       tdi,
    output wire       tdo,
    output wire [7:0] periph_port,
    output wire [7:0] periph_wdata,
    input  wire [7:0] periph_rdata,
    output wire       periph_rd,
    output wire       periph_wr,
    input  wire       periph_ready
);
    wire host_valid;
    wire [12:0] host_request;
    wire [62:0] host_response;

    dsd8_jtag_tap tap (
        .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo),
        .clk(clk), .rst_n(rst_n), .host_valid(host_valid),
        .host_request(host_request), .host_response(host_response)
    );

    dsd8_debug_system #(.IMAGE(IMAGE)) system (
        .clk(clk), .rst_n(rst_n), .switches(switches), .buttons(buttons),
        .leds(leds), .seg(seg), .an(an), .halted(halted),
        .periph_port(periph_port), .periph_wdata(periph_wdata),
        .periph_rdata(periph_rdata), .periph_rd(periph_rd), .periph_wr(periph_wr),
        .periph_ready(periph_ready), .host_valid(host_valid),
        .host_request(host_request), .host_response(host_response)
    );
endmodule
