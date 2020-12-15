`default_nettype none
// openlane context
`ifdef BLACKBOX
    `include "blackbox.v"
    `define MPRJ_IO_PADS 38
`endif
// cocotb simulation context
`ifdef COCOTB_SIM
    `define MPRJ_IO_PADS 38
`endif
`ifdef FORMAL
    `define MPRJ_IO_PADS 38
`endif
// caravel context has access to defines.v so can read MPRJ_IO_PADS from there
module multi_project_harness #(
    // address_active: write to this memory address to select the project
    parameter address_active = 32'h30000000,
    parameter address_oeb0   = 32'h30000004,
    parameter address_oeb1   = 32'h30000008,
    // each project gets 0x100 bytes memory space
    parameter address_ws2812 = 32'h30000100,
    parameter address_7seg   = 32'h30000200,
    // h30000300 reserved for proj_3: spinet
    parameter address_freq   = 32'h30000400,
    parameter address_watch   = 32'h30000500,
    parameter num_projects   = 8
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

    // IOs - avoid using 0-7 as they are dual purpose and maybe connected to other things
    input  wire [`MPRJ_IO_PADS-1:0] io_in,
    output wire [`MPRJ_IO_PADS-1:0] io_out,
    output wire [`MPRJ_IO_PADS-1:0] io_oeb, // active low!

    // then we need all the separate projects ios here
    // proj 0
    output wire proj0_wb_update,
    output wire proj0_clk,
    output wire proj0_reset,
    output wire  [`MPRJ_IO_PADS-1:0] proj0_io_in,
    input wire [`MPRJ_IO_PADS-1:0] proj0_io_out,

    // proj 1
    output wire proj1_wb_update,
    output wire proj1_clk,
    output wire proj1_reset,
    output wire  [`MPRJ_IO_PADS-1:0] proj1_io_in,
    input wire [`MPRJ_IO_PADS-1:0] proj1_io_out,

    // proj 2
    output wire proj2_clk,
    output wire proj2_reset,
    output wire  [`MPRJ_IO_PADS-1:0] proj2_io_in,
    input wire [`MPRJ_IO_PADS-1:0] proj2_io_out,

    // proj 3
    output wire proj3_clk,
    output wire proj3_reset,
    output wire  [`MPRJ_IO_PADS-1:0] proj3_io_in,
    input wire [`MPRJ_IO_PADS-1:0] proj3_io_out,

    // proj 4
    output wire proj4_clk,
    output wire proj4_reset,
    input wire [31:0] proj4_cnt,
    input wire [31:0] proj4_cnt_cont,
    output wire proj4_wb_update,
    output wire  [`MPRJ_IO_PADS-1:0] proj4_io_in,
    input wire [`MPRJ_IO_PADS-1:0] proj4_io_out,

    // proj 5
    output wire proj5_wb_update,
    output wire proj5_clk,
    output wire proj5_reset,
    output wire  [`MPRJ_IO_PADS-1:0] proj5_io_in,
    input wire [`MPRJ_IO_PADS-1:0] proj5_io_out,

    // proj 6
    output wire proj6_clk,
    output wire  [`MPRJ_IO_PADS-1:0] proj6_io_in,
    input wire [`MPRJ_IO_PADS-1:0] proj6_io_out,
    
    // proj 7
    output wire proj7_reset,
    output wire  [`MPRJ_IO_PADS-1:0] proj7_io_in,
    input wire [`MPRJ_IO_PADS-1:0] proj7_io_out

    );

    // couple of aliases
    wire clk = wb_clk_i;
    wire reset = wb_rst_i;


    // make all the possible connecting wires
    //wire [`MPRJ_IO_PADS-1:0] project_io_in  [num_projects-1:0];
    //wire [`MPRJ_IO_PADS-1:0] project_io_out [num_projects-1:0];

    reg [7:0] active_project; // which design is active
    reg [`MPRJ_IO_PADS-1:0] reg_oeb;

    // mux project outputs
    assign io_out = active_project == 0 ? proj0_io_out:
                    active_project == 1 ? proj1_io_out:
                    active_project == 2 ? proj2_io_out:
                    active_project == 3 ? proj3_io_out:
                    active_project == 4 ? proj4_io_out:
                    active_project == 5 ? proj5_io_out:
                    active_project == 6 ? proj6_io_out:
                    active_project == 7 ? proj7_io_out:
                                        {`MPRJ_IO_PADS {1'b0}};

    // each project sets own oeb via wishbone
    assign io_oeb = reg_oeb;

    // inputs get set to 0 if not selected
    assign proj0_io_in = active_project == 0 ? io_in : {`MPRJ_IO_PADS {1'b0}};
    assign proj1_io_in = active_project == 1 ? io_in : {`MPRJ_IO_PADS {1'b0}};
    assign proj2_io_in = active_project == 2 ? io_in : {`MPRJ_IO_PADS {1'b0}};
    assign proj3_io_in = active_project == 3 ? io_in : {`MPRJ_IO_PADS {1'b0}};
    assign proj4_io_in = active_project == 4 ? io_in : {`MPRJ_IO_PADS {1'b0}};
    assign proj5_io_in = active_project == 5 ? io_in : {`MPRJ_IO_PADS {1'b0}};
    assign proj6_io_in = active_project == 6 ? io_in : {`MPRJ_IO_PADS {1'b0}};
    assign proj7_io_in = active_project == 7 ? io_in : {`MPRJ_IO_PADS {1'b0}};


    // instantiate all the modules

    // project 0
    assign proj0_wb_update = wb_valid & wb_wstrb & (wbs_adr_i == address_7seg);
    assign proj0_clk = clk;
    assign proj0_reset = reset | la_data_in[0];
    `ifndef NO_PROJ0
    `ifndef FORMAL
    //seven_segment_seconds proj_0 (.clk(clk), .reset(reset | la_data_in[0]), .led_out(project_io_out[0][14:8]), .compare_in(wbs_dat_i[23:0]), .update_compare(seven_seg_update));
    `endif
    `endif

    // project 1
    // ws2812 needs led_num, rgb, write connected to wb
    assign proj1_clk = clk;
    assign proj1_reset = reset | la_data_in[0];
    assign proj1_wb_update = wb_valid & wb_wstrb & (wbs_adr_i == address_ws2812);
    `ifndef NO_PROJ1
    `ifndef FORMAL
//    ws2812                proj_1 (.clk(clk), .reset(reset | la_data_in[0]), .led_num(wbs_dat_i[31:24]), .rgb_data(wbs_dat_i[23:0]), .write(ws2812_write), .data(project_io_out[1][8]));
    `endif
    `endif

    // project 2
    assign proj2_clk = clk;
    assign proj2_reset = !(reset | la_data_in[0]);
    `ifndef NO_PROJ2
    `ifndef FORMAL
//    vga_clock             proj_2 (.clk(clk), .reset_n(!(reset | la_data_in[0])), .adj_hrs(project_io_in[2][8]), .adj_min(project_io_in[2][9]), .adj_sec(project_io_in[2][10]), .hsync(project_io_out[2][11]), .vsync(project_io_out[2][12]), .rrggbb(project_io_out[2][18:13]));
    `endif
    `endif

    // project 3
    assign proj3_clk = clk;
    assign proj3_reset = reset | la_data_in[0];
    `ifndef NO_PROJ3
    `ifndef FORMAL
//	spinet5 proj_3 ( .clk(clk), .rst(reset | la_data_in[0]), .io_in(project_io_in[3]), .io_out(project_io_out[3]));
    `endif
    `endif


    // project 4
    wire [31:0] cnt;
    wire [31:0] cnt_cont;
    assign cnt = proj4_cnt;
    assign cnt_cont = proj4_cnt_cont;
    assign proj4_wb_update = (wb_valid & (&wb_wstrb) & ((wbs_adr_i >> 8) == (address_freq >> 8)));
    assign proj4_clk = clk;
    assign proj4_reset = reset | la_data_in[0];
    /*
    `ifndef NO_PROJ4
    `ifndef FORMAL
    asic_freq proj_4(
        .clk(clk),
        .rst(reset | la_data_in[0]),

        // register write interface (ignores < 32 bit writes):
        // 30000400:
        //   write UART clock divider (min. value = 4),
        // 30000404:
        //   write frequency counter update period [sys_clks]
        // 30000408
        //   set 7-segment display mode,
        //   0: show meas. freq., 1: show wishbone value
        // 3000040C
        //   set 7-segment display value:
        //   digit7 ... digit0  (4 bit each)
        // 30000410
        //   set 7-segment display value:
        //   digit8
        // 30000414
        //   set 7-segment decimal points:
        //   dec_point8 ... dec_point0  (1 bit each)
        // 30000418
        //   read periodically reset freq. counter value
        // 3000041C
        //   read continuous freq. counter value
        .addr(wbs_adr_i[5:2]),
        .value(wbs_dat_i),
        .strobe(wb_valid & (&wb_wstrb) & ((wbs_adr_i >> 8) == (address_freq >> 8))),

        // signal under test input
        .samplee(project_io_in[4][25]),

        // periodic counter output to wishbone
        .o(cnt),

        // continuous counter output to wishbone
        .oc(cnt_cont),

        // UART output to FTDI input
        .tx(project_io_out[4][6]),

        // 7 segment display outputs
        .col_drvs(project_io_out[4][16:8]),  // 9 x column drivers
        .seg_drvs(project_io_out[4][24:17])  // 8 x segment drivers
    );
    `endif
    `endif
    */

     // project 5
    `ifndef NO_PROJ5
    `ifndef FORMAL
    assign proj5_wb_update = wb_valid & wb_wstrb & (wbs_adr_i == address_watch);
    assign proj5_clk = clk;
    assign proj5_reset = rstn_watch;
    reg rstn_watch;
    always @(posedge clk) begin
        rstn_watch <= ~(reset | la_data_in[0]);
    end
/*
    watch_hhmm proj_5 (
        .sysclk_i     (clk),
        .smode_i      (project_io_in[5][36]),
        .sclk_i       (project_io_in[5][37]),
        .dvalid_i     (watch_write),
        .cfg_i        (wbs_dat_i[11:0]),
        .rstn_i       (rstn_watch),
        .segment_hxxx (project_io_out[5][14:8]),
        .segment_xhxx (project_io_out[5][21:15]),
        .segment_xxmx (project_io_out[5][28:22]),
        .segment_xxxm (project_io_out[5][35:29])
    );
    */
    `endif
    `endif


     // project 6
     assign proj6_clk = clk;
    `ifndef NO_PROJ6
    `ifndef FORMAL
    //challenge proj_6 (.uart(project_io_in[6][8]), .clk_10(clk), .led_green(project_io_out[6][9]), .led_red(project_io_out[6][10]));
    `endif
    `endif


    // project 7
    assign proj7_reset = reset | proj7_io_in[36];
    `ifndef NO_PROJ7
    `ifndef FORMAL
    /*
    MM2hdmi proj_7 (
    .clock(project_io_in[7][35]),
    .reset(reset | project_io_in[7][36]),
    .io_data(project_io_in[7][23:8]),
    .io_newData(project_io_in[7][24]),
    .io_red(project_io_out[7][32:25]),
    .io_hSync(project_io_out[7][33]),
    .io_vSync(project_io_out[7][34])
    );
    */
    `endif    
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
            reg_oeb <= 0;
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
                address_oeb0: begin
                    if(&wb_wstrb)
                        reg_oeb[31:0] <= wbs_dat_i[31:0];
                    wbs_ack <= 1;
                end
                address_oeb1: begin
                    if(&wb_wstrb)
                        reg_oeb[`MPRJ_IO_PADS-1:32] <= wbs_dat_i[`MPRJ_IO_PADS-1-32:0];
                    wbs_ack <= 1;
                end
                address_ws2812: begin
                    wbs_ack <= 1;
                end
                address_7seg: begin
                    wbs_ack <= 1;
                end
                address_watch: begin
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

                address_freq + 8'h18: begin
                    wbs_data_out <= cnt;
                    wbs_ack <= 1;
                end

                address_freq + 8'h1c: begin
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
                // if project is selected
                case(active_project)
                    0: begin
                        // ins and outs are connected
                        assert(io_out == proj0_io_out);
                        assert(io_in == proj0_io_in);
                    end
                endcase
                    // all other project's ins are set to 0
                   // assert(proj0_io_in == {`MPRJ_IO_PADS {1'b0}});
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
