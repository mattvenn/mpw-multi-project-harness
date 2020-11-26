`default_nettype none
//`include "defines.v"
`define MPRJ_IO_PADS 38
module multi_project_harness #(
    // address_active: write to this memory address to select the project
    parameter address_active = 32'h30000000,
    // each project gets 0x100 bytes memory space
    parameter address_ws2812 = 32'h30000100,
    parameter address_7seg   = 32'h30000200,
    // h30000300 reserved for proj_3: spinet
    parameter address_freq   = 32'h30000400,
    parameter num_projects   = 5
) (
    inout wire vdda1,   // User area 1 3.3V supply
    inout wire vdda2,   // User area 2 3.3V supply
    inout wire vssa1,   // User area 1 analog ground
    inout wire vssa2,   // User area 2 analog ground
    inout wire vccd1,   // User area 1 1.8V supply
    inout wire vccd2,   // User area 2 1.8v supply
    inout wire vssd1,   // User area 1 digital ground
    inout wire vssd2,   // User area 2 digital ground

    // Wishbone Slave ports (WB MI A)
    input wire wb_clk_i,             // clock
    input wire wb_rst_i,             // reset
    input wire wbs_stb_i,            // strobe - wb_valid data
    input wire wbs_cyc_i,            // cycle - high when during a request
    input wire wbs_we_i,             // write enable
    input wire [3:0] wbs_sel_i,      // which byte to read/write
    input wire [31:0] wbs_dat_i,     // data in
    input wire [31:0] wbs_adr_i,     // address
    output wire wbs_ack_o,           // ack
    output wire [31:0] wbs_dat_o,    // data out

    // Logic Analyzer Signals
    input  wire [127:0] la_data_in,
    output wire [127:0] la_data_out,
    input  wire [127:0] la_oen,

    // IOs
    input  wire [`MPRJ_IO_PADS-1:0] io_in,
    output wire [`MPRJ_IO_PADS-1:0] io_out,
    output wire [`MPRJ_IO_PADS-1:0] io_oeb
    );

    // couple of aliases
    wire clk = wb_clk_i;
    wire reset = wb_rst_i;

    `ifdef COCOTB_SIM
        initial begin
            $dumpfile ("harness.vcd");
            $dumpvars (0, multi_project_harness);
            #1;
        end
    `endif

    // make all the possible connecting wires
    wire [`MPRJ_IO_PADS-1:0] project_io_in  [num_projects-1:0];
    wire [`MPRJ_IO_PADS-1:0] project_io_out [num_projects-1:0];

    reg [7:0] active_project; // which design is active

    // mux project outputs
    assign io_out = active_project == 0 ? project_io_out[0] :
                    active_project == 1 ? project_io_out[1] :
                    active_project == 2 ? project_io_out[2] :
                    active_project == 3 ? project_io_out[3] :
                    active_project == 4 ? project_io_out[4] :
                                          `MPRJ_IO_PADS'b0;

    // each project sets own oeb
    assign io_oeb = active_project == 0 ? `MPRJ_IO_PADS'b1 : // all on
                    active_project == 1 ? `MPRJ_IO_PADS'b1 :
                    active_project == 2 ? `MPRJ_IO_PADS'b1 :
                    active_project == 3 ? `MPRJ_IO_PADS'b1 :
                    active_project == 4 ? `MPRJ_IO_PADS'b1 :
                                          `MPRJ_IO_PADS'b0;

    // inputs get set to 0 if not selected
    assign project_io_in[0] = active_project == 0 ? io_in : `MPRJ_IO_PADS'b0;
    assign project_io_in[1] = active_project == 1 ? io_in : `MPRJ_IO_PADS'b0;
    assign project_io_in[2] = active_project == 2 ? io_in : `MPRJ_IO_PADS'b0;
    assign project_io_in[3] = active_project == 3 ? io_in : `MPRJ_IO_PADS'b0;
    assign project_io_in[4] = active_project == 4 ? io_in : `MPRJ_IO_PADS'b0;


    // instantiate all the modules

    // project 0
    `ifndef FORMAL
    seven_segment_seconds proj_0 (.clk(clk), .reset(reset | la_data_in[0]), .led_out(project_io_out[0][8:2]), .compare_in(wbs_dat_i[23:0]), .update_compare(seven_seg_update));
    `endif

    // project 1
    // ws2812 needs led_num, rgb, write connected to wb
    wire ws2812_write = wb_valid & wb_wstrb & (wbs_adr_i == address_ws2812);
    wire seven_seg_update = wb_valid & wb_wstrb & (wbs_adr_i == address_7seg);
    `ifndef FORMAL
    ws2812                proj_1 (.clk(clk), .reset(reset | la_data_in[0]), .led_num(wbs_dat_i[31:24]), .rgb_data(wbs_dat_i[23:0]), .write(ws2812_write), .data(project_io_out[1][2]));
    `endif

    // project 2
    `ifndef FORMAL
    vga_clock             proj_2 (.clk(clk), .reset_n(!(reset | la_data_in[0])), .adj_hrs(project_io_in[2][2]), .adj_min(project_io_in[2][3]), .adj_sec(project_io_in[2][4]), .hsync(project_io_out[2][5]), .vsync(project_io_out[2][6]), .rrggbb(project_io_out[2][12:7]));
    `endif

    // project 3
    `ifndef FORMAL
	spinet6 proj_3 (
		.clk(clk),
		.rst(reset | la_data_in[0]),
		.io_in(project_io_in[3]),
		.io_out(project_io_out[3]));
    `endif

    // project 4
    wire [31:0] cnt;
    wire [31:0] cnt_cont;
    `ifndef FORMAL
    asic_freq proj_4(
        .clk(clk),
        .rst(reset | la_data_in[0]),

        // register write interface (ignores < 32 bit writes):
        // 30000300:
        //   write UART clock divider (min. value = 4),
        //   read periodically reset freq. counter value
        // 30000304:
        //   write frequency counter update period [sys_clks]
        //   read continuous freq. counter value
        // 30000308
        //   set 7-segment display mode,
        //   0: show meas. freq., 1: show wishbone value
        // 3000030C
        //   set 7-segment display value:
        //   digit7 ... digit0  (4 bit each)
        // 30000310
        //   set 7-segment display value:
        //   digit8
        // 30000314
        //   set 7-segment decimal points:
        //   dec_point8 ... dec_point0  (1 bit each)
        .addr(wbs_adr_i[5:2]),
        .value(wbs_dat_i),
        .strobe(wb_valid & (&wb_wstrb) & ((wbs_adr_i >> 8) == (address_freq >> 8))),

        // signal under test
        .samplee(project_io_in[4][18]),

        // periodic counter output to wishbone
        .o(cnt),

        // continuous counter output to wishbone
        .oc(cnt_cont),

        // UART output to pin
        .tx(project_io_out[4][0]),

        // 7 segment display outputs
        .col_drvs(project_io_out[4][9:1]),  // 9 x column drivers
        .seg_drvs(project_io_out[4][17:10])  // 8 x segment drivers
    );
    `endif

    // wishbone MUX signals
    wire wb_valid;
    wire [3:0] wb_wstrb;
    reg [31:0] wbs_data_out;
    reg wbs_ack;
    assign wbs_ack_o = wbs_ack;
    assign wbs_dat_o = wbs_data_out;
    assign wb_valid = wbs_cyc_i && wbs_stb_i;
    assign wb_wstrb = wbs_sel_i & {4{wbs_we_i}};

    always @(posedge clk) begin
        // reset
        if(reset) begin
            active_project <= 0;
            wbs_data_out <= 0;
            wbs_ack <= 0;
        end else
        // writes
        if(wb_valid & (wb_wstrb > 0)) begin
            case(wbs_adr_i)
                address_active: begin
                    if (wb_wstrb[0])
                        active_project[7:0] <= wbs_dat_i[7:0];
                    wbs_ack <= 1;
                end
                address_ws2812: begin
                    wbs_ack <= 1;
                end
                address_7seg: begin
                    wbs_ack <= 1;
                end
            endcase

            // asic_freq has a range of 6 registers
            if((wbs_adr_i >= address_freq) && (wbs_adr_i < address_freq + 6 * 4))
                wbs_ack <= 1;
        end else
        // reads - allow to see which is currently selected
        if(wb_valid & wb_wstrb == 4'b0) begin
            case(wbs_adr_i)
                address_active: begin
                    wbs_data_out[7:0] <= active_project[7:0];
                    wbs_ack <= 1;
                end

                address_freq: begin
                    wbs_data_out <= cnt;
                    wbs_ack <= 1;
                end

                address_freq + 4: begin
                    wbs_data_out <= cnt_cont;
                    wbs_ack <= 1;
                end
            endcase
        end else begin
            wbs_ack <= 0;
            wbs_data_out <= 32'b0;
        end
    end

    `ifdef FORMAL
        integer i;
        always @(*) begin
            if(active_project > 0 && active_project < num_projects)
                assert(io_oeb == `MPRJ_IO_PADS'b1);

            for(i = 0; i < num_projects; i ++) begin
                // if project is selected
                if(active_project == i) begin
                    // ins and outs are connected
                    assert(io_out == project_io_out[i]);
                    assert(io_in == project_io_in[i]);
                end else
                    // all other project's ins are set to 0
                    assert(project_io_in[i] == `MPRJ_IO_PADS'b0);
            end
        end

        // basic wishbone compliance
        reg f_past_valid = 0;

        always @(posedge clk) begin
            f_past_valid <= 1;
            assume(reset == !f_past_valid);

        end

        // assume controller keeps cyc & strobe high until ack, data, wstrb and data stay stable
        always @(posedge clk) begin
            if(reset)
                assume(!wbs_cyc_i);
            if(f_past_valid && $past(wb_valid)) begin
                // keep address & data stable
                assume($stable(wb_wstrb));
                assume($stable(wbs_adr_i));
                assume($stable(wbs_dat_i));

                // wait for ack
                if(!wbs_ack)
                    assume(wb_valid);
            end
        end

        // assert ack happens when writing to a known address
        always @(posedge clk) begin
            if(f_past_valid && $past(wb_valid) && !$past(reset))
                // reads & writes to project select address
                if($past(wbs_adr_i == address_active))
                    assert(wbs_ack);
        end

    `endif


endmodule
`default_nettype wire
