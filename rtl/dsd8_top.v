// dsd8_top.v -- system top level with lightweight built-in CPU debugger
// Spec: Section 5.1. Port list is FROZEN -- do not rename or resize.

`timescale 1ns/1ps

module dsd8_top #(parameter IMAGE = "program.hex") (
    input  wire       clk,
    input  wire       rst_n,       // synchronous, active low
    input  wire [7:0] switches,    // board slide switches  -> port 0x00
    input  wire [4:0] buttons,     // {btnU,btnD,btnL,btnR,btnC} -> port 0x01
    output wire [7:0] leds,        // board LEDs             <- port 0x02
    output wire [6:0] seg,         // seven-segment segments <- port 0x10
    output wire [3:0] an,          // seven-segment digit enables
    output wire       halted       // asserted after HLT retires
);


    /* verilator lint_off PINCONNECTEMPTY */
    dsd8_debug_system #(.IMAGE(IMAGE)) system (
        .clk(clk), .rst_n(rst_n), .switches(switches), .buttons(buttons),
        .leds(leds), .seg(seg), .an(an), .halted(halted),
        .periph_port(), .periph_wdata(), .periph_rdata(8'h00),
        .periph_rd(), .periph_wr(), .periph_ready(1'b1),
        .host_valid(1'b0), .host_request(13'b0), .host_response()
    );
    /* verilator lint_on PINCONNECTEMPTY */
endmodule
