`timescale 1ns/1ps

module tb_jtag;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b1;
    reg [7:0] switches = 8'h80; // Board mode holds the CPU until the host attaches.
    reg tck = 1'b0, tms = 1'b1, tdi = 1'b0;
    wire tdo;
    wire [7:0] leds;
    wire halted;
    wire [7:0] port, wdata;
    wire rd, wr;

    reg allow_ready = 1'b0;
    reg [7:0] echo;
    integer echo_writes;
    wire ready = allow_ready && (rd || wr);

    always @(posedge clk) begin
        if (!rst_n) begin
            echo <= 8'h00;
            echo_writes <= 0;
        end else if (wr && ready) begin
            echo <= wdata;
            echo_writes <= echo_writes + 1;
        end
    end

    dsd8_jtag_top #(.IMAGE("tb/fixtures/jtag_demo.hex")) dut (
        .clk(clk), .rst_n(rst_n), .switches(switches), .buttons(5'b0),
        .leds(leds), .seg(), .an(), .halted(halted),
        .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo),
        .periph_port(port), .periph_wdata(wdata), .periph_rdata(echo),
        .periph_rd(rd), .periph_wr(wr), .periph_ready(ready)
    );

    task tick(input mode, input data, output sampled);
        begin
            tms = mode;
            tdi = data;
            #7;
            sampled = tdo;
            tck = 1'b1;
            #7;
            tck = 1'b0;
            #1;
        end
    endtask

    reg ignored;
    task tap_reset;
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1) tick(1, 0, ignored);
            tick(0, 0, ignored); // Idle
        end
    endtask

    task select_debug;
        integer i;
        reg [3:0] selected, captured;
        begin
            selected = 4'h2;
            tick(1, 0, ignored); // Select DR
            tick(1, 0, ignored); // Select IR
            tick(0, 0, ignored); // Capture IR
            tick(0, 0, ignored); // Shift IR
            for (i = 0; i < 4; i = i + 1) tick(i == 3, selected[i], captured[i]);
            if (captured[1:0] !== 2'b01) fail("IR capture signature");
            tick(1, 0, ignored); // Update IR
            tick(0, 0, ignored); // Idle
        end
    endtask

    task scan_frame(input [63:0] outgoing, output [63:0] incoming);
        integer i;
        begin
            tick(1, 0, ignored); // Select DR
            tick(0, 0, ignored); // Capture DR
            tick(0, 0, ignored); // Shift DR
            for (i = 0; i < 64; i = i + 1) tick(i == 63, outgoing[i], incoming[i]);
            tick(1, 0, ignored); // Update DR
            tick(0, 0, ignored); // Idle
        end
    endtask

    task transact(input [3:0] cmd, input [8:0] argument, output [63:0] response);
        integer attempts;
        begin
            scan_frame({51'b0, argument, cmd}, response);
            scan_frame(64'b0, response);
            for (attempts = 0; response[63] !== 1'b1 && attempts < 5; attempts = attempts + 1)
                scan_frame(64'b0, response);
            if (response[63] !== 1'b1) fail("mailbox response timed out");
        end
    endtask

    task fail(input [511:0] reason);
        begin
            $display("TESTBENCH: FAIL (%0s)", reason);
            $finish;
        end
    endtask

    reg [63:0] value;
    task command(input [3:0] cmd, input [8:0] argument);
        begin
            transact(cmd, argument, value);
            if (value[62] !== 1'b0) fail("command rejected");
        end
    endtask

    task expect_status(input [8:0] pc, input [3:0] flags);
        begin
            command(5, 0);
            if (value[17:9] !== pc || value[3:0] !== flags)
                fail("unexpected debug status/PC");
        end
    endtask

    reg bypass_first, bypass_second;
    initial begin
        #1 rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        tap_reset();
        tick(1, 0, ignored);
        tick(0, 0, ignored);
        tick(0, 0, ignored);
        tick(0, 1, bypass_first);
        tick(1, 0, bypass_second);
        tick(1, 0, ignored);
        tick(0, 0, ignored);
        if ({bypass_first, bypass_second} !== 2'b01) fail("default BYPASS");
        select_debug();

        command(1, 0); // Attach and pause at address zero.
        expect_status(0, 4'b1001);
        transact(7, 0, value);
        if (value[62] !== 1'b1) fail("empty trace was accepted");

        command(4, 3);
        command(2, 0);
        expect_status(3, 4'b1011);
        if (leds !== 8'h00) fail("breakpoint allowed an LED write");
        command(6, 1);
        if (value[7:0] !== 8'hA5) fail("register inspection");
        command(7, 0);
        if (value[57:49] !== 9'd2 || value[48:33] !== 16'h3200 ||
            value[20] !== 1'b1 || value[11:4] !== 8'hA5)
            fail("retirement trace for ST");

        command(3, 0);
        expect_status(4, 4'b1001);
        if (leds !== 8'hA5) fail("single-step did not write LEDs");

        command(9, 0);
        command(2, 0);
        if (wr !== 1'b1 || port !== 8'h40 || echo_writes != 0)
            fail("OUT did not wait for peripheral");
        command(1, 0);
        expect_status(4, 4'b1000);
        if (wr !== 1'b1) fail("pause canceled a pending write");
        allow_ready = 1'b1;
        repeat (2) @(negedge clk);
        allow_ready = 1'b0;
        expect_status(5, 4'b1001);
        if (echo_writes != 1 || rd !== 1'b0) fail("write committed twice or next read leaked");

        command(3, 0);
        expect_status(5, 4'b1000);
        if (rd !== 1'b1) fail("step did not start delayed IN");
        allow_ready = 1'b1;
        repeat (2) @(negedge clk);
        allow_ready = 1'b0;
        expect_status(6, 4'b1001);
        command(6, 2);
        if (value[7:0] !== 8'hA5) fail("delayed IN writeback");

        command(3, 0);
        expect_status(6, 4'b1101);
        if (halted !== 1'b1) fail("HLT did not latch");
        command(7, 0);
        if (value[57:49] !== 9'd6 || value[48:33] !== 16'hF000)
            fail("HLT missing from trace");

        command(8, 0);
        @(negedge clk);
        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        tap_reset();
        select_debug();
        command(1, 0);
        command(3, 0);
        command(6, 6);
        if (value[7:0] !== 8'h00) fail("data RAM was stale after CPU reset");

        $display("TESTBENCH: PASS");
        $finish;
    end

    initial begin
        #100000;
        fail("simulation timeout");
    end
endmodule
