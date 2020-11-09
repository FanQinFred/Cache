`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/07/21 12:31:54
// Design Name: FanQin
// Module Name: d_cache
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`define  A_WIDTH         32                                        // 32位的地址宽度
`define  SET_ADDR_LEN    9                                         // 2的SET_ADDR_LEN次方个组
`define  WAY_CNT         4                                         // 4个路
`define  WORD_ADDR_LEN   2                                         // 2位的字节偏移
`define  LINE_ADDR_LEN   0                                         // 0位的字偏移

`define  TAG_ADDR_LEN    (32 - `WORD_ADDR_LEN - `SET_ADDR_LEN - `LINE_ADDR_LEN)       // 标记域的长度
`define  MEM_ADDR_LEN    (`TAG_ADDR_LEN + `SET_ADDR_LEN)             // 访问SRAM的地址长度 此处为{30位，00}
`define  SET_SIZE        (1 << `SET_ADDR_LEN)                        // 组的数量


module bridge_cache(
    input wire clk, rst,
    //mips core
    input         cpu_data_req     ,//p_strobe
    input         cpu_data_wr      ,//p_rw
    input  [1 :0] cpu_data_size    ,//p_size
    input  [31:0] cpu_data_addr    ,//p_a
    input  [31:0] cpu_data_wdata   ,//p_dout
    output [31:0] cpu_data_rdata   ,//p_din
    output        cpu_data_addr_ok ,//p_ready
    output        cpu_data_data_ok ,//p_ready

    //axi interface
    output         cache_data_req     ,//m_strobe
    output         cache_data_wr      ,//m_rw
    output  [1 :0] cache_data_size    ,//m_size
    output  [31:0] cache_data_addr    ,//m_a
    output  [31:0] cache_data_wdata   ,//m_din
    input   [31:0] cache_data_rdata   ,//m_dout
    input          cache_data_addr_ok ,//m_ready
    input          cache_data_data_ok //m_ready
);

    d_cache d_cache_(
        .clk(clk),.clrn(rst),
        // m_ready来源于AXI接口
        // assign m_ready <--- mem_ready = read_req && read_finish || write_req && write_finish;
        .m_ready(cache_data_addr_ok&cache_data_data_ok),    // 是否可以对sram进行读或写操作的 结束的 使能信号  0：不能；1：能
        .p_a(cpu_data_addr),        // 请求sram的地址     //data_sram_addr
        .p_dout(cpu_data_wdata),     // data_sram_wdata   // 要写入sram的数据   // 来自于datapath
        // p_strobe来源于controller
        .p_strobe(cpu_data_req),   // data_sram_en <-- memenM & ~(|excepttypeM);   // 数据sram的使能信号 
        .p_wen(4'b1111),      // 字节使能信号
		.p_size(cpu_data_size),     // 0: byte;  1: half word;  2: whole word
        .p_rw(cpu_data_wr),       // 0: read;  1: write
        .m_dout(cache_data_rdata),     // data_sram_write  // 来自于AXI

        .m_a(cache_data_addr),        // 操作SRAM的地址
        .m_din(cache_data_wdata),      // 打算写入SRAM的数据
        .m_strobe(cache_data_req),   // 向SRAM发送的操作请求使能
        .m_wen(4'b1111),
		.m_size(cache_data_size),
        .m_rw(cache_data_wr),       // mem_write
        .p_din(cpu_data_rdata),      // data_sram_rdata   // 最终读得的数据
        .p_ready(cpu_data_addr_ok&cpu_data_data_ok)     // assign stallreq_from_mem = data_sram_en & ~d_ready;
    );
endmodule

module d_cache(
        input  wire                   clk,clrn,
        // m_ready来源于AXI接口
        // assign m_ready <--- mem_ready = read_req && read_finish || write_req && write_finish;
        input  wire                   m_ready,    // 是否可以对sram进行读或写操作的 结束的 使能信号  0：不能；1：能
        input  wire [`A_WIDTH-1:0]    p_a,        // 请求sram的地址     //data_sram_addr
        input  wire [31:0]            p_dout,     // data_sram_wdata   // 要写入sram的数据   // 来自于datapath
        // p_strobe来源于controller
        input  wire                   p_strobe,   // data_sram_en <-- memenM & ~(|excepttypeM);   // 数据sram的使能信号 
        input  wire [3:0]             p_wen,      // 字节使能信号
		input  wire [1:0]             p_size,     // 0: byte;  1: half word;  2: whole word
        input  wire                   p_rw,       // 0: read;  1: write
        input  wire [31:0]            m_dout,     // data_sram_write  // 来自于AXI

        output wire [`A_WIDTH-1:0]    m_a,        // 操作SRAM的地址
        output wire [31:0]            m_din,      // 打算写入SRAM的数据
        output wire                   m_strobe,   // 向SRAM发送的操作请求使能
        output wire [3:0]             m_wen,
		output wire [1:0]             m_size,
        output wire                   m_rw,       // mem_write
        output wire [31:0]            p_din,      // data_sram_rdata   // 最终读得的数据
        output wire                   p_ready     // assign stallreq_from_mem = data_sram_en & ~d_ready;
    );
  
    wire flag;
    
    wire                memwriteM;          //p_rw
    wire [3:0]          sel;                //p_wen
    wire [1:0]          data_sram_size;     //P_size
    wire [31:0]         aluoutM;            //p_a
    wire [31:0]         writedata2M;        //p_dout
    wire                memenM;             //p_strobe
    wire [31:0]         readdataM;          //p_din
    wire                cache_ready;

    wire                rst;
    wire                data_req;
    wire                data_wr;
    wire [3:0]          data_wen;
    wire [1:0]          data_size;
    wire [31:0]         data_addr;
    wire [31:0]         data_wdata;
    wire [31:0]         data_rdata;
    wire                data_data_ok;

    //cache interface
    // dram side(write)
    wire                      dram_wr_req;        //  request writing data to dram
    wire        [31:0]        dram_wr_addr;       //  write data address
    wire        [31:0]        dram_wr_data;       //  write data
    wire                      dram_wr_val;        //  write a word valid

    // dram side(read)
    wire                      dram_rd_req;        //  request reading data from dram
    wire        [31:0]        dram_rd_addr;       //  read data address
    wire                      dram_rd_val;        //  read a word valid

    wire [`SET_ADDR_LEN-1:0]  index;
    wire [T_WIDTH-1:0]        tag;

    //sign in cache
    reg  [1:0]                state;                      // FSM
    wire                      cache_hit,dirty;            // dirty bit
    wire [T_WIDTH-1:0]        tagout;
    wire [31:0]               c_out;

    // 判断是否命中
    wire                      valid_tag_hit;

    // 命中的路数
    wire     [`WAY_CNT>>2:0 ] hit_way;


    // state
    localparam          CPU_EXEC         =   0;
    localparam          WR_DRAM          =   1;
    localparam          RD_DRAM          =   2;
    // tag width
    localparam          T_WIDTH          =   `A_WIDTH - `SET_ADDR_LEN - `LINE_ADDR_LEN - `WORD_ADDR_LEN;

    // for circle handle
    integer             i;
    integer             k;
    integer             j;
    integer             way;
    integer             max_age;
    integer             max_age_way;

    assign              memwriteM        =   p_rw;
    assign              sel              =   p_wen;
    assign              data_sram_size   =   p_size;
    assign              aluoutM          =   p_a;
    assign              writedata2M      =   p_dout;
    assign              memenM           =   p_strobe;
    assign              p_din            =   flag ? m_dout : readdataM;
    assign              p_ready          =   cache_ready;
    assign              flag             =   1'b0;//(aluoutM[31:16] == 16'hbfaf) ? 1'b1 : 1'b0;
    assign              rst              =   ~clrn;
    assign              data_data_ok     =   m_ready;
    assign              data_rdata       =   m_dout ;
    assign              m_a              =   flag ? {16'h1faf,aluoutM[15:0]} : data_addr;
    assign              m_din            =   flag ? p_dout : data_wdata;
    assign              m_strobe         =   flag ? p_strobe : data_req;
    assign              m_wen            =   flag ? p_wen : data_wen;
    assign              m_size           =   flag ? p_size: data_size;
    assign              m_rw             =   flag ? p_rw : data_wr;

    // 保存有效信息
    reg                                                 d_valid_way_0           [`SET_SIZE-1:0];
    reg                                                 d_valid_way_1           [`SET_SIZE-1:0];
    reg                                                 d_valid_way_2           [`SET_SIZE-1:0];
    reg                                                 d_valid_way_3           [`SET_SIZE-1:0];
    // 保存脏信息
    reg                                                 d_dirty_way_0           [`SET_SIZE-1:0];
    reg                                                 d_dirty_way_1           [`SET_SIZE-1:0];
    reg                                                 d_dirty_way_2           [`SET_SIZE-1:0];
    reg                                                 d_dirty_way_3           [`SET_SIZE-1:0];
    // 保存标记
    reg     [T_WIDTH-1:0]                               d_tags_way_0            [`SET_SIZE-1:0];
    reg     [T_WIDTH-1:0]                               d_tags_way_1            [`SET_SIZE-1:0];
    reg     [T_WIDTH-1:0]                               d_tags_way_2            [`SET_SIZE-1:0];
    reg     [T_WIDTH-1:0]                               d_tags_way_3            [`SET_SIZE-1:0];
    // 保存数据
    reg     [7 : 0]                                     d_data1_way_0           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data1_way_1           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data1_way_2           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data1_way_3           [`SET_SIZE-1:0];

    reg     [7 : 0]                                     d_data2_way_0           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data2_way_1           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data2_way_2           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data2_way_3           [`SET_SIZE-1:0];

    reg     [7 : 0]                                     d_data3_way_0           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data3_way_1           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data3_way_2           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data3_way_3           [`SET_SIZE-1:0];

    reg     [7 : 0]                                     d_data4_way_0           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data4_way_1           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data4_way_2           [`SET_SIZE-1:0];
    reg     [7 : 0]                                     d_data4_way_3           [`SET_SIZE-1:0];
    //保存年龄
    reg     [3: 0]                                      way_age_way_0           [`SET_SIZE-1:0];
    reg     [3: 0]                                      way_age_way_1           [`SET_SIZE-1:0];
    reg     [3: 0]                                      way_age_way_2           [`SET_SIZE-1:0];
    reg     [3: 0]                                      way_age_way_3           [`SET_SIZE-1:0];
    //保存每组最大年龄的路号
    reg     [1: 0]                                      way_hold_max_age        [`SET_SIZE-1:0];

    assign  index                     =   aluoutM [`SET_ADDR_LEN+`LINE_ADDR_LEN+1 : `LINE_ADDR_LEN+`WORD_ADDR_LEN];
    assign  tag                       =   aluoutM [`A_WIDTH-1 : `SET_ADDR_LEN+`LINE_ADDR_LEN+2];

    // 获得cache对应的tag
    assign  tagout                    =    valid_tag_hit && hit_way==0 ? d_tags_way_0[index] : 
                                           valid_tag_hit && hit_way==1 ? d_tags_way_1[index] : 
                                           valid_tag_hit && hit_way==2 ? d_tags_way_2[index] :
                                           valid_tag_hit && hit_way==3 ? d_tags_way_3[index] : 0;

    assign  c_out                     =    valid_tag_hit && hit_way==0 ? {d_data1_way_0[index],d_data2_way_0[index],d_data3_way_0[index],d_data4_way_0[index]} :
                                           valid_tag_hit && hit_way==1 ? {d_data1_way_1[index],d_data2_way_1[index],d_data3_way_1[index],d_data4_way_1[index]} :
                                           valid_tag_hit && hit_way==2 ? {d_data1_way_2[index],d_data2_way_2[index],d_data3_way_2[index],d_data4_way_2[index]} :
                                           valid_tag_hit && hit_way==3 ? {d_data1_way_3[index],d_data2_way_3[index],d_data3_way_3[index],d_data4_way_3[index]} : 0;

    //cache control
    assign  cache_hit                 =   valid_tag_hit & memenM & !flag;

    assign  dirty                     =   valid_tag_hit && hit_way==0 ? d_dirty_way_0[index] : 
                                          valid_tag_hit && hit_way==1 ? d_dirty_way_1[index] : 
                                          valid_tag_hit && hit_way==2 ? d_dirty_way_2[index] :
                                          valid_tag_hit && hit_way==3 ? d_dirty_way_3[index] : 0;

    assign  dram_wr_addr              =   {tagout,index,2'b00};
    assign  dram_rd_addr              =   aluoutM;

    assign cache_ready                =   (memenM & cache_hit & !flag) || (memenM && flag && m_ready);

    assign readdataM                  =   cache_hit ? c_out : data_rdata;

    assign data_req                   =   (dram_rd_req ) || (dram_wr_req);
    assign data_wr                    =   dram_wr_req ? 1 : 0;
    assign data_addr                  =   dram_wr_req ? dram_wr_addr : dram_rd_req ?  dram_rd_addr : 32'b0;
    assign data_wdata                 =   dram_wr_data;

    //assign dram_rd_data = data_rdata;
    assign dram_wr_val = dram_wr_req ? data_data_ok : 0;
    assign dram_rd_val = dram_rd_req ? data_data_ok : 0; 
 
    assign data_wen  = 4'b1111;
    assign data_size = 2'b10;

    // dram write/read request
    // 通过state控制读与写请求信号
    assign  dram_wr_req = ( state == WR_DRAM );
    assign  dram_rd_req = ( state == RD_DRAM );

    // data_cache writes dram
    assign dram_wr_data =c_out;

    assign valid_tag_hit = (d_valid_way_0[index] && tag == d_tags_way_0[index])||
                           (d_valid_way_1[index] && tag == d_tags_way_1[index])||
                           (d_valid_way_2[index] && tag == d_tags_way_2[index])||
                           (d_valid_way_3[index] && tag == d_tags_way_3[index]);
    
    assign hit_way = (d_valid_way_0[index] && tag == d_tags_way_0[index]) ? 0:
                     (d_valid_way_1[index] && tag == d_tags_way_1[index]) ? 1:
                     (d_valid_way_2[index] && tag == d_tags_way_2[index]) ? 2:
                     (d_valid_way_3[index] && tag == d_tags_way_3[index]) ? 3:0;

    // cpu/dram writes data_cache
    always@(posedge clk) begin
        //init cache memery
        if(rst) begin
            for(i=0;i<`SET_SIZE;i=i+1) begin
                // valid
                d_valid_way_0[i] <= 0;
                d_valid_way_1[i] <= 0;
                d_valid_way_2[i] <= 0;
                d_valid_way_3[i] <= 0;
                // dirty
                d_dirty_way_0[i] <= 1'b0;
                d_dirty_way_1[i] <= 1'b0;
                d_dirty_way_2[i] <= 1'b0;
                d_dirty_way_3[i] <= 1'b0;
                // way_age
                way_age_way_0[i] <= 1;
                way_age_way_1[i] <= 1;
                way_age_way_2[i] <= 1;
                way_age_way_3[i] <= 1;
                // way_hold_max_age
                way_hold_max_age[i] <= 1'b0;
            end
            // max_age_way
            max_age_way <= 0;
        end
        // SRAM的数据写入cache
        else if(dram_rd_val) begin   // dram write cache block
            
            case (way_hold_max_age[index])
                2'd0: begin
                    d_valid_way_0[index]  <=  1'b1;
                    d_dirty_way_0[index]  <=  1'b0;
                    d_tags_way_0 [index]  <=  tag;
                    d_data1_way_0[index]  <=  data_rdata[31:24];
                    d_data2_way_0[index]  <=  data_rdata[23:16];
                    d_data3_way_0[index]  <=  data_rdata[15:8];
                    d_data4_way_0[index]  <=  data_rdata[7:0];
                end
                2'd1: begin
                    d_valid_way_1[index]  <=  1'b1;
                    d_dirty_way_1[index]  <=  1'b0;
                    d_tags_way_1 [index]  <=  tag;
                    d_data1_way_1[index]  <=  data_rdata[31:24];
                    d_data2_way_1[index]  <=  data_rdata[23:16];
                    d_data3_way_1[index]  <=  data_rdata[15:8];
                    d_data4_way_1[index]  <=  data_rdata[7:0];
                end
                2'd2: begin
                    d_valid_way_2[index]  <=  1'b1;
                    d_dirty_way_2[index]  <=  1'b0;
                    d_tags_way_2 [index]  <=  tag;
                    d_data1_way_2[index]  <=  data_rdata[31:24];
                    d_data2_way_2[index]  <=  data_rdata[23:16];
                    d_data3_way_2[index]  <=  data_rdata[15:8];
                    d_data4_way_2[index]  <=  data_rdata[7:0];
                end
                2'd3: begin
                    d_valid_way_3[index]  <=  1'b1;
                    d_dirty_way_3[index]  <=  1'b0;
                    d_tags_way_3 [index]  <=  tag;
                    d_data1_way_3[index]  <=  data_rdata[31:24];
                    d_data2_way_3[index]  <=  data_rdata[23:16];
                    d_data3_way_3[index]  <=  data_rdata[15:8];
                    d_data4_way_3[index]  <=  data_rdata[7:0];
                end
                default:;
            endcase

            if((0!=way_hold_max_age[index]?way_age_way_0[index]+1:0)>=(1!=way_hold_max_age[index]?way_age_way_1[index]+1:0)&&
               (0!=way_hold_max_age[index]?way_age_way_0[index]+1:0)>=(2!=way_hold_max_age[index]?way_age_way_2[index]+1:0)&&
               (0!=way_hold_max_age[index]?way_age_way_0[index]+1:0)>=(3!=way_hold_max_age[index]?way_age_way_3[index]+1:0)) begin
                way_hold_max_age[index] <= 0;
            end else if((1!=way_hold_max_age[index]?way_age_way_1[index]+1:0)>=(0!=way_hold_max_age[index]?way_age_way_0[index]+1:0)&&
                        (1!=way_hold_max_age[index]?way_age_way_1[index]+1:0)>=(2!=way_hold_max_age[index]?way_age_way_2[index]+1:0)&&
                        (1!=way_hold_max_age[index]?way_age_way_1[index]+1:0)>=(3!=way_hold_max_age[index]?way_age_way_3[index]+1:0)) begin
                way_hold_max_age[index] <= 1;
            end else if((2!=way_hold_max_age[index]?way_age_way_2[index]+1:0)>=(0!=way_hold_max_age[index]?way_age_way_0[index]+1:0)&&
                        (2!=way_hold_max_age[index]?way_age_way_2[index]+1:0)>=(1!=way_hold_max_age[index]?way_age_way_1[index]+1:0)&&
                        (2!=way_hold_max_age[index]?way_age_way_2[index]+1:0)>=(3!=way_hold_max_age[index]?way_age_way_3[index]+1:0)) begin
                way_hold_max_age[index] <= 2;
            end else if((3!=way_hold_max_age[index]?way_age_way_3[index]+1:0)>=(0!=way_hold_max_age[index]?way_age_way_0[index]+1:0)&&
                        (3!=way_hold_max_age[index]?way_age_way_3[index]+1:0)>=(1!=way_hold_max_age[index]?way_age_way_1[index]+1:0)&&
                        (3!=way_hold_max_age[index]?way_age_way_3[index]+1:0)>=(2!=way_hold_max_age[index]?way_age_way_2[index]+1:0)) begin
                way_hold_max_age[index] <= 3;
            end

            way_age_way_0[index] <= way_hold_max_age[index]==0 ? 0 : way_age_way_0[index] + 1;
            way_age_way_1[index] <= way_hold_max_age[index]==1 ? 0 : way_age_way_1[index] + 1;
            way_age_way_2[index] <= way_hold_max_age[index]==2 ? 0 : way_age_way_2[index] + 1;
            way_age_way_3[index] <= way_hold_max_age[index]==3 ? 0 : way_age_way_3[index] + 1;
        end
        // 数据不脏，写进cache
        else if( cache_hit & memenM & memwriteM ) begin

            case (hit_way)
                0: begin
                    d_dirty_way_0[index]  <=  1'b1;
                end
                1: begin
                    d_dirty_way_1[index]  <=  1'b1;
                end
                2: begin
                    d_dirty_way_2[index]  <=  1'b1;
                end
                3: begin
                    d_dirty_way_3[index]  <=  1'b1;
                end
                default:;
            endcase

            case (sel)
                4'b1111:begin//sw
                    case (hit_way)
                        0: begin
                            d_data1_way_0[index] <= writedata2M[31:24];
                            d_data2_way_0[index] <= writedata2M[23:16];
                            d_data3_way_0[index] <= writedata2M[15:8];
                            d_data4_way_0[index] <= writedata2M[7:0];
                        end
                        1: begin
                            d_data1_way_1[index] <= writedata2M[31:24];
                            d_data2_way_1[index] <= writedata2M[23:16];
                            d_data3_way_1[index] <= writedata2M[15:8];
                            d_data4_way_1[index] <= writedata2M[7:0];
                        end
                        2: begin
                            d_data1_way_2[index] <= writedata2M[31:24];
                            d_data2_way_2[index] <= writedata2M[23:16];
                            d_data3_way_2[index] <= writedata2M[15:8];
                            d_data4_way_2[index] <= writedata2M[7:0];
                        end
                        3: begin
                            d_data1_way_3[index] <= writedata2M[31:24];
                            d_data2_way_3[index] <= writedata2M[23:16];
                            d_data3_way_3[index] <= writedata2M[15:8];
                            d_data4_way_3[index] <= writedata2M[7:0];
                        end
                        default:;
                    endcase
                end
                4'b1100:begin//sh
                    case (hit_way)
                        0: begin
                            d_data1_way_0[index] <= writedata2M[31:24];
                            d_data2_way_0[index] <= writedata2M[23:16];
                        end
                        1: begin
                            d_data1_way_1[index] <= writedata2M[31:24];
                            d_data2_way_1[index] <= writedata2M[23:16];
                        end
                        2: begin
                            d_data1_way_2[index] <= writedata2M[31:24];
                            d_data2_way_2[index] <= writedata2M[23:16];
                        end
                        3: begin
                            d_data1_way_3[index] <= writedata2M[31:24];
                            d_data2_way_3[index] <= writedata2M[23:16];
                        end
                        default:;
                    endcase
                end
                4'b0011:begin//sh
                    case (hit_way)
                        0: begin
                            d_data3_way_0[index] <= writedata2M[15:8];
                            d_data4_way_0[index] <= writedata2M[7:0];
                        end
                        1: begin
                            d_data3_way_1[index] <= writedata2M[15:8];
                            d_data4_way_1[index] <= writedata2M[7:0];
                        end
                        2: begin
                            d_data3_way_2[index] <= writedata2M[15:8];
                            d_data4_way_2[index] <= writedata2M[7:0];
                        end
                        3: begin
                            d_data3_way_3[index] <= writedata2M[15:8];
                            d_data4_way_3[index] <= writedata2M[7:0];
                        end
                        default:;
                    endcase
                end
                4'b1000:begin//sb 1000
                    case (hit_way)
                        0: begin
                            d_data1_way_0[index] <= writedata2M[31:24];
                        end
                        1: begin
                            d_data1_way_1[index] <= writedata2M[31:24];
                        end
                        2: begin
                            d_data1_way_2[index] <= writedata2M[31:24];
                        end
                        3: begin
                            d_data1_way_3[index] <= writedata2M[31:24];
                        end
                        default:;
                    endcase
                end
                4'b0100:begin//sb 0100
                    case (hit_way)
                        0: begin
                            d_data2_way_0[index] <= writedata2M[23:16];
                        end
                        1: begin
                            d_data2_way_1[index] <= writedata2M[23:16];
                        end
                        2: begin
                            d_data2_way_2[index] <= writedata2M[23:16];
                        end
                        3: begin
                            d_data2_way_3[index] <= writedata2M[23:16];
                        end
                        default:;
                    endcase
                end
                4'b0010:begin//sb 0010
                    case (hit_way)
                        0: begin
                            d_data3_way_0[index] <= writedata2M[15:8];
                        end
                        1: begin
                            d_data3_way_1[index] <= writedata2M[15:8];
                        end
                        2: begin
                            d_data3_way_2[index] <= writedata2M[15:8];
                        end
                        3: begin
                            d_data3_way_3[index] <= writedata2M[15:8];
                        end
                        default:;
                    endcase
                end
                4'b0001:begin//sb 0001
                    case (hit_way)
                        0: begin
                            d_data4_way_0[index] <= writedata2M[7:0];
                        end
                        1: begin
                            d_data4_way_1[index] <= writedata2M[7:0];
                        end
                        2: begin
                            d_data4_way_2[index] <= writedata2M[7:0];
                        end
                        3: begin
                            d_data4_way_3[index] <= writedata2M[7:0];
                        end
                        default:;
                    endcase
                end
                default: ;
            endcase

            if((0!=hit_way?way_age_way_0[index]+1:0)>=(1!=hit_way?way_age_way_1[index]+1:0)&&
               (0!=hit_way?way_age_way_0[index]+1:0)>=(2!=hit_way?way_age_way_2[index]+1:0)&&
               (0!=hit_way?way_age_way_0[index]+1:0)>=(3!=hit_way?way_age_way_3[index]+1:0)) begin
                way_hold_max_age[index] <= 0;
            end else if((1!=hit_way?way_age_way_1[index]+1:0)>=(0!=hit_way?way_age_way_0[index]+1:0)&&
                        (1!=hit_way?way_age_way_1[index]+1:0)>=(2!=hit_way?way_age_way_2[index]+1:0)&&
                        (1!=hit_way?way_age_way_1[index]+1:0)>=(3!=hit_way?way_age_way_3[index]+1:0)) begin
                way_hold_max_age[index] <= 1;
            end else if((2!=hit_way?way_age_way_2[index]+1:0)>=(0!=hit_way?way_age_way_0[index]+1:0)&&
                        (2!=hit_way?way_age_way_2[index]+1:0)>=(1!=hit_way?way_age_way_1[index]+1:0)&&
                        (2!=hit_way?way_age_way_2[index]+1:0)>=(3!=hit_way?way_age_way_3[index]+1:0)) begin
                way_hold_max_age[index] <= 2;
            end else if((3!=hit_way?way_age_way_3[index]+1:0)>=(0!=hit_way?way_age_way_0[index]+1:0)&&
                        (3!=hit_way?way_age_way_3[index]+1:0)>=(1!=hit_way?way_age_way_1[index]+1:0)&&
                        (3!=hit_way?way_age_way_3[index]+1:0)>=(2!=hit_way?way_age_way_2[index]+1:0)) begin
                way_hold_max_age[index] <= 3;
            end

            way_age_way_0[index] <= hit_way==0 ? 0 : way_age_way_0[index] + 1;
            way_age_way_1[index] <= hit_way==1 ? 0 : way_age_way_1[index] + 1;
            way_age_way_2[index] <= hit_way==2 ? 0 : way_age_way_2[index] + 1;
            way_age_way_3[index] <= hit_way==3 ? 0 : way_age_way_3[index] + 1;
        end
    end

    // data_cache state machine
    // 仅用于控制读与写请求信号
    always@(posedge clk) begin
        if(rst) begin
            state   <=  CPU_EXEC;
        end
        else begin
            case(state)
                CPU_EXEC:if( ~cache_hit & dirty & memenM & !flag)          // dirty block write back to dram
                            state   <=  WR_DRAM;
                        else if( ~cache_hit & memenM & !flag)              // request new block from dram
                            state   <=  RD_DRAM;
                        else
                            state   <=  CPU_EXEC;
                WR_DRAM:if(dram_wr_val & dram_wr_req)
                            state   <=  RD_DRAM;
                        else
                            state   <=  WR_DRAM;
                RD_DRAM:if(dram_rd_val & dram_rd_req)
                            state   <=  CPU_EXEC;   
                        else
                            state   <=  RD_DRAM;
                default:    state   <=  CPU_EXEC;   
            endcase
        end
    end

endmodule