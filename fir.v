`timescale 1ns / 1ps
module fir
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    //axi write
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,

    //axi read
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
   
    //axi stream
    input   wire                     ss_tvalid,
    input   wire [(pDATA_WIDTH-1):0] ss_tdata,
    input   wire                     ss_tlast,
    output  wire                     ss_tready,

    input   wire                     sm_tready,
    output  wire                     sm_tvalid,
    output  wire [(pDATA_WIDTH-1):0] sm_tdata,
    output  wire                     sm_tlast,
   
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);

// write your code here!
// ------ axi write transaction ---------->

    //axi write
    // output  wire                     awready,
    // output  wire                     wready,
    // input   wire                     awvalid,
    // input   wire [(pADDR_WIDTH-1):0] awaddr,
    // input   wire                     wvalid,
    // input   wire [(pDATA_WIDTH-1):0] wdata,

reg awready_r;
reg wready_r;
reg aw_handshake_flag;
reg [3:0]coef_sent_cnt;
reg [3:0]tap_WE_r;
reg tap_EN_r;
reg [(pDATA_WIDTH-1):0]tap_Di_r;
reg [(pADDR_WIDTH-1):0]tap_A_r;
reg                    coef_en;
reg [2:0]           axi_read_en;

    //axi read
    // output  wire                     arready,
    // input   wire                     rready,
    // input   wire                     arvalid,
    // input   wire [(pADDR_WIDTH-1):0] araddr,
    // output  wire                     rvalid,
    // output  wire [(pDATA_WIDTH-1):0] rdata,
reg arready_r;
reg rvalid_r;
reg read_en;
reg [(pDATA_WIDTH-1):0]tap_Do_wire;

reg ss_tready_r;
reg [(pDATA_WIDTH-1):0]ss_tdata_r;

    // output  wire [3:0]               data_WE,
    // output  wire                     data_EN,
    // output  wire [(pDATA_WIDTH-1):0] data_Di,
    // output  wire [(pADDR_WIDTH-1):0] data_A,
    // input   wire [(pDATA_WIDTH-1):0] data_Do,

reg [3:0]               data_WE_r;
reg                     data_EN_r;
reg [(pDATA_WIDTH-1):0] data_Di_r;
reg [(pADDR_WIDTH-1):0] data_A_r;

reg [10:0]              rst_cnt;
reg [4:0]               zero_data_cnt;

reg                     fir_start_flag;      
reg                     fir_start_flag_r;
reg signed [pDATA_WIDTH-1:0] fir_mul_data;
reg signed [pDATA_WIDTH-1:0] fir_cal_data;
reg [4:0]               fir_mul_cal;

reg [(pADDR_WIDTH-1):0] fir_A_r;              
reg [4:0]               axi_read_cnt;    

reg [(pDATA_WIDTH-1):0] data_in_offset;
reg [(pADDR_WIDTH-1):0] data_A_in;



// sm
    // input   wire                     sm_tready,
    // output  wire                     sm_tvalid,
    // output  wire [(pDATA_WIDTH-1):0] sm_tdata,
    // output  wire                     sm_tlast,

reg sm_tvalid_r;
reg [(pDATA_WIDTH-1):0] sm_tdata_r;
reg sm_tlast_r;
reg [3:0]     fir_cal_cnt;
reg           axi_read_done;

reg [3:0]    data_in_cnt;
reg          fir_en;
reg          fir_flag;
reg [(pADDR_WIDTH-1):0]  fir_tap_addr;        

reg [3:0] rready_cnt;

assign sm_tvalid = sm_tvalid_r;
assign sm_tlast  = sm_tlast_r;
assign sm_tdata  = sm_tdata_r;

assign ss_tready = ss_tready_r;

assign arready = arready_r;
assign rvalid  = rvalid_r;
assign awready = awready_r;
assign wready  = wready_r;

assign tap_WE  = tap_WE_r;
assign tap_EN  = tap_EN_r;
assign tap_Di  = tap_Di_r;
assign tap_A   = tap_A_r;

assign data_EN = data_EN_r;
assign data_WE = data_WE_r;
assign data_Di = data_Di_r;
assign data_A  = (ss_tready) ? data_A_in : (fir_en) ? fir_A_r :data_A_r;

//---axi write---->
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                       awready_r <= 0;
    else if(coef_sent_cnt == 4'd11)        awready_r <= 0;
    else if(awvalid && awready)            awready_r <= 0;
    else if(awvalid )                      awready_r <= 1;                                      
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                       wready_r <= 0;  
    else if(coef_sent_cnt == 4'd11)        wready_r <= 0;
    else if(wvalid && wready)              wready_r <= 0;
    else if(wvalid)                        wready_r <= 1;
end
always@(posedge axis_clk  or negedge axis_rst_n)begin
     if (~axis_rst_n)                       coef_en <= 0;
     else if ((~wvalid) && (~wready))       coef_en <= 1'b1;
     else if (data_in_cnt == 12)            coef_en <= 0;
end
always@(posedge axis_clk  or negedge axis_rst_n)begin
     if (~axis_rst_n)                       coef_sent_cnt <= 0;
     else if (coef_en && wvalid && wready)  coef_sent_cnt <= coef_sent_cnt + 1'b1;
end
   
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                   tap_WE_r <= 0;
    else if (fir_en)                   tap_WE_r <= 0;
    else if ((wready==0) && wvalid)    tap_WE_r <= 4'b1111;
    else                               tap_WE_r <= 0;
end

always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                                    tap_EN_r <= 0;
    else if ((awready && awvalid)||(wready && wvalid))  tap_EN_r <= 1'b1;
    //else if (rready && rvalid)                          tap_EN_r <= 0;
    else if (ss_tready)                                 tap_EN_r <= 1'b1;
end

always@(posedge axis_clk or negedge axis_rst_n)begin
    if(!axis_rst_n)
        tap_Di_r <= 32'd0;
    else begin
        if ((wready==0) && wvalid && coef_en && (~axi_read_done))    tap_Di_r <= wdata;
    end
end

always@(*)begin
    if ((arvalid) && (coef_en))                 tap_A_r <= araddr - 32;
    else if ((awready && awvalid)&& (coef_en))  tap_A_r <= awaddr - 32;
    else if (fir_en)                            tap_A_r <= fir_tap_addr;

    //else if ((data_in_cnt <= 11)&&(fir_en))     tap_A_r <= data_A_r;

end
// always@(*)begin
//     if (((awready==0) && awvalid)&& (coef_en))              tap_A_r <= awaddr - 32;
//     else if ((arvalid == 0) && (arready==0) && (coef_en))   tap_A_r <= araddr - 32;
//     else if (fir_start_flag)                                tap_A_r <= fir_tap_addr;
// end

//----axi read---->
assign rdata = tap_Do_wire;
always@(*)begin
    if ((wdata == 1) && (rvalid) && (rready_cnt == 1)) tap_Do_wire <= 0;
    else if ((wdata == 1) && (rvalid) && (rready_cnt == 2)) tap_Do_wire <= 2;
    else if ((wdata == 1) && (rvalid) && (rready_cnt == 3)) tap_Do_wire <= 4;
    else if (rready && rvalid) tap_Do_wire <= tap_Do;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)              arready_r <= 0;
    else if (data_in_cnt == 12 )  arready_r <= 0;
    else if (arready && arvalid)  arready_r <= 0;
    else if (arvalid)             arready_r <= 1'b1;
end

always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                          rvalid_r <= 0;
    else if ((~rready) && (wdata == 1))       rvalid_r <= 1'b1;
    else if (axi_read_done)                   rvalid_r <= 0;
    else if (rready && rvalid)                rvalid_r <= 0;
    else if (rready && (axi_read_cnt>0))      rvalid_r <= 1'b1;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)              axi_read_cnt <= 0;
    else if (axi_read_cnt==12)   axi_read_cnt <= 12;
    else if (axi_read_cnt == 11)  axi_read_cnt <= 12;
    else if (arready && arvalid)    axi_read_cnt <= axi_read_cnt + 1;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)            axi_read_en <= 0;
    else if (rready && rvalid)  axi_read_en <= 1;
    else                        axi_read_en <= axi_read_en + 1;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                                 axi_read_done <= 0;
    else if (rready && rvalid && axi_read_cnt == 12)  axi_read_done <= 1;
end
// ----- axi stream input ------>
    // input   wire                     ss_tvalid,
    // input   wire [(pDATA_WIDTH-1):0] ss_tdata,
    // input   wire                     ss_tlast,
    // output  wire                     ss_tready,

    // output  wire [3:0]               data_WE,
    // output  wire                     data_EN,
    // output  wire [(pDATA_WIDTH-1):0] data_Di,
    // output  wire [(pADDR_WIDTH-1):0] data_A,
    // input   wire [(pDATA_WIDTH-1):0] data_Do,


always@(posedge axis_clk)begin
    if (zero_data_cnt <= 11)                        data_Di_r <= 0;
    else if ((fir_mul_cal == 11))                   data_Di_r <= ss_tdata;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                                    data_WE_r <= 0;
    else if (wready && wvalid && zero_data_cnt <= 11)   data_WE_r <= 4'b1111;
    else if ((fir_mul_cal == 11))                       data_WE_r <= 4'b1111;
    else if (fir_start_flag)                            data_WE_r <= 0;
    else                                                data_WE_r <= 0;
end

always@(posedge axis_clk)begin
    if (axis_rst_n)                    data_EN_r <= 1;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
   // if ((arvalid) && (coef_en))            data_A_r <= araddr - 32;
    if (~axis_rst_n)                                   data_A_r <= 0;
    else if (data_A == 40)                             data_A_r <= 0;
    else if (rst_cnt < 3)                              data_A_r <= 0;
    else if (wready && wvalid && zero_data_cnt <= 11)  data_A_r <= data_A + 4;
    else if (rready && rvalid && zero_data_cnt <= 11)  data_A_r <= data_A + 4;
    else if (ss_tready && data_in_cnt <= 10)           data_A_r <= 0;
    else if ((fir_en)&&(data_in_cnt <= 11))            data_A_r <= data_A + 4;
    else if (ss_tready )                               data_A_r <= data_A_r;
    else if (fir_en)                                   data_A_r <= data_A + 4;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                       fir_A_r <=  0;
    else if (ss_tready)                    fir_A_r <= data_A_in;
    else if (fir_en && (fir_A_r != 0))     fir_A_r <= fir_A_r - 4;
    else if (fir_en && (fir_A_r == 0))     fir_A_r <= 40;
end

always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                        rst_cnt <= 0;
    else if (axis_rst_n)                    rst_cnt <= rst_cnt + 1;
end

always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)              zero_data_cnt <= 0;
    else if (zero_data_cnt == 15) zero_data_cnt <= 15;
    else if (zero_data_cnt == 11) zero_data_cnt <= 15;
    else if (wready && wvalid)    zero_data_cnt <= zero_data_cnt + 1;
end

//------ FIR------->
always@(*)begin
    if ((fir_en) && (fir_mul_cal == 0))                fir_mul_data <= 0;
    else if (fir_en && (1 <= fir_mul_cal <= 11))       fir_mul_data <= ($signed(data_Do) * $signed(tap_Do)) ;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)            fir_mul_cal <= 0;
    else if (fir_mul_cal == 11)  fir_mul_cal <= 0;
    else if (rready && rvalid)  fir_mul_cal <= fir_mul_cal + 1;
    else if ((fir_en))              fir_mul_cal <= fir_mul_cal + 1;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                           fir_cal_data <= 0;
    else if  (rready && rvalid)                fir_cal_data <=  fir_cal_data + fir_mul_data ;
    else if (ss_tready)                        fir_cal_data <= 0;
    else if  ((fir_en)&&(1<=fir_mul_cal<=11))  fir_cal_data <=  fir_cal_data + fir_mul_data ;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                         sm_tvalid_r <= 0;
    else if ((fir_mul_cal == 11)&&(fir_en))  sm_tvalid_r <= 1;
    else                                     sm_tvalid_r <= 0;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                         sm_tdata_r <= 0;
    else if ((fir_mul_cal == 11)&&(fir_en))  sm_tdata_r <= fir_cal_data;                      
end


always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)                                    ss_tready_r <= 0;
    else if ((fir_mul_cal == 11))                       ss_tready_r <= 1;
    else                                                ss_tready_r <= 0;
end

always@(posedge axis_clk or negedge axis_rst_n)begin
    if (~axis_rst_n)               data_in_cnt <= 0;
    else if (data_in_cnt ==12)     data_in_cnt <= 12;      
    else if (data_in_cnt == 11 && ss_tready) data_in_cnt <= 12;
    else if (ss_tready)            data_in_cnt <= data_in_cnt + 1;
end

always@(posedge axis_clk or negedge axis_rst_n)begin
    if(~axis_rst_n)             fir_en <= 0;
    else if (fir_mul_cal == 11) fir_en <= 0;
    else if (ss_tready)         fir_en <= 1;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if(~axis_rst_n)             data_A_in <= 0;
    else if (ss_tready && (data_A_in == 40))   data_A_in <= 0;
    else if (ss_tready)         data_A_in <= data_A_in + 4;
end
always@(posedge axis_clk or negedge axis_rst_n)begin          
    if(~axis_rst_n)       fir_tap_addr <= 0;
    else if (ss_tready)   fir_tap_addr <= 0;
    else if (fir_en)      fir_tap_addr <= fir_tap_addr + 4;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if(~axis_rst_n)                    sm_tlast_r <= 0;
    else if ((rvalid)&&(wdata == 1))   sm_tlast_r <= 1;
end
always@(posedge axis_clk or negedge axis_rst_n)begin
    if(~axis_rst_n)                       rready_cnt <= 0;
    else if ((~rready) && (wdata == 1))   rready_cnt <= rready_cnt + 1;
end
endmodule