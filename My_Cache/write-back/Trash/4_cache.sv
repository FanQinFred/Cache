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

// `define  A_WIDTH         32                                                       // 32位的地址宽度
// `define  SET_ADDR_LEN    11                                                      // 2的SET_ADDR_LEN次方个组
// `define  WAY_CNT         4                                                      // 4个路
// `define  WORD_ADDR_LEN   2                                                     // 2位的字节偏移
// `define  LINE_ADDR_LEN   0                                                    // 0位的字偏移
// `define  TAG_ADDR_LEN    (32-WORD_ADDR_LEN-SET_ADDR_LEN-LINE_ADDR_LEN)       // 标记域的长度
// `define  MEM_ADDR_LEN    (`TAG_ADDR_LEN+SET_ADDR_LEN)                       // 访问SRAM的地址长度 此处为{30位，00}
// `define  SET_CNT         (1<<SET_ADDR_LEN)                                 // 组的数量

module d_cache#(parameter A_WIDTH = 32,parameter SET_ADDR_LEN = 11,parameter WORD_ADDR_LEN = 2,parameter LINE_ADDR_LEN = 0)(
        input  wire                   clk,clrn,
        // m_ready来源于AXI接口
        // assign m_ready <--- mem_ready = read_req && read_finish || write_req && write_finish;
        input  wire                   m_ready,    // 是否可以对sram进行读或写操作的 结束的 使能信号  0：不能；1：能
        input  wire [A_WIDTH-1:0]     p_a,        // 请求sram的地址     //data_sram_addr
        input  wire [31:0]            p_dout,     // data_sram_wdata   // 要写入sram的数据   // 来自于datapath
        // p_strobe来源于controller
        input  wire                   p_strobe,   // data_sram_en <-- memenM & ~(|excepttypeM);   // 数据sram的使能信号 
        input  wire [3:0]             p_wen,      // 字节使能信号
		input  wire [1:0]             p_size,     // 0: byte;  1: half word;  2: whole word
        input  wire                   p_rw,       // 0: read;  1: write
        input  wire [31:0]            m_dout,     // data_sram_write  // 来自于AXI

        output wire [A_WIDTH-1:0]     m_a,        // 操作SRAM的地址
        output wire [31:0]            m_din,      // 打算写入SRAM的数据
        output wire                   m_strobe,   // 向SRAM发送的操作请求使能
        output wire [3:0]             m_wen,
		output wire [1:0]             m_size,
        output wire                   m_rw,       // mem_write
        output wire [31:0]            p_din,      // data_sram_rdata   // 最终读得的数据
        output wire                   p_ready     // assign stallreq_from_mem = data_sram_en & ~d_ready;
    );
  
    wire                flag;

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
    wire                dram_wr_req;        //  request writing data to dram
    wire [31:0]         dram_wr_addr;       //  write data address
    wire [31:0]         dram_wr_data;       //  write data
    wire                dram_wr_val;        //  write a word valid

    // dram side(read)
    wire                dram_rd_req;        //  request reading data from dram
    wire [31:0]         dram_rd_addr;       //  read data address
    wire                dram_rd_val;        //  read a word valid

    wire [SET_ADDR_LEN-1:0]   index;
    wire [18:0]               tag;

    //sign in cache
    reg  [2:0]                state;                      // FSM
    wire                      cache_hit,dirty;            // dirty bit
    wire [18:0]               tagout;
    wire [31:0]               c_out;

    // 判断是否命中
    wire                      valid_tag_hit;

    // 命中的路数
    wire     [1:0]            hit_way;

    // state one-hot
    localparam          CPU_EXEC         =   3'b001;
    localparam          WR_DRAM          =   3'b010;
    localparam          RD_DRAM          =   3'b100;

    // for circle handle
    integer             i;

    // 标记
    wire     [18:0]                                      c_tags_way_0;  // [127:185]
    wire     [18:0]                                      c_tags_way_1;  // [184:166]
    wire     [18:0]                                      c_tags_way_2;  // [165:147]
    wire     [18:0]                                      c_tags_way_3;  // [146:127]
    // 数据 
    wire     [7:0]                                       c_data1_way_0;  // [127:120]
    wire     [7:0]                                       c_data1_way_1;  // [119:112]
    wire     [7:0]                                       c_data1_way_2;  // [111:104]
    wire     [7:0]                                       c_data1_way_3;  // [103:96]

    wire     [7:0]                                       c_data2_way_0;  // [95:88]
    wire     [7:0]                                       c_data2_way_1;  // [87:80]
    wire     [7:0]                                       c_data2_way_2;  // [79:72]
    wire     [7:0]                                       c_data2_way_3;  // [71:64]

    wire     [7:0]                                       c_data3_way_0;  // [63:56]
    wire     [7:0]                                       c_data3_way_1;  // [55:48]
    wire     [7:0]                                       c_data3_way_2;  // [47:40]
    wire     [7:0]                                       c_data3_way_3;  // [39:32]

    wire     [7:0]                                       c_data4_way_0;  // [31:24]
    wire     [7:0]                                       c_data4_way_1;  // [23:17]
    wire     [7:0]                                       c_data4_way_2;  // [15:8]
    wire     [7:0]                                       c_data4_way_3;  // [7:0]

    //年龄 
    wire     [3:0]                                       c_way_age_way_0;
    wire     [3:0]                                       c_way_age_way_1;
    wire     [3:0]                                       c_way_age_way_2;
    wire     [3:0]                                       c_way_age_way_3;

    wire [127:0] wr_mem_data;
    wire [127:0] rd_mem_data;

    wire         wr_bram;

    wire [127:0] r_data;
    wire [127:0] m_data;

    wire [127:0] m_data_1111sel;
    wire [127:0] m_data_1100sel;
    wire [127:0] m_data_0011sel;
    wire [127:0] m_data_1000sel;
    wire [127:0] m_data_0100sel;
    wire [127:0] m_data_0010sel;
    wire [127:0] m_data_0001sel;

    wire [15:0]  data_bram_wea_wire;

    //年龄 
    wire     [3:0]                                       dina_way_age_way_0;
    wire     [3:0]                                       dina_way_age_way_1;
    wire     [3:0]                                       dina_way_age_way_2;
    wire     [3:0]                                       dina_way_age_way_3;

    // cache_hit & memenM & memwriteM
    wire                                                 cmm_valid; 

    // 保存有效信息
    reg                                                  d_valid_way_0[0:(1<<SET_ADDR_LEN)-1];
    reg                                                  d_valid_way_1[0:(1<<SET_ADDR_LEN)-1];
    reg                                                  d_valid_way_2[0:(1<<SET_ADDR_LEN)-1];
    reg                                                  d_valid_way_3[0:(1<<SET_ADDR_LEN)-1];

    // 路是否全为脏
    wire                                                 dirty_all;

    // 保存脏信息
    reg                                                  d_dirty_way_0[0:(1<<SET_ADDR_LEN)-1];
    reg                                                  d_dirty_way_1[0:(1<<SET_ADDR_LEN)-1];
    reg                                                  d_dirty_way_2[0:(1<<SET_ADDR_LEN)-1];
    reg                                                  d_dirty_way_3[0:(1<<SET_ADDR_LEN)-1];

    reg [1:0]                                            rwc_way;
    reg [1:0]                                            mage_way;

    assign              memwriteM        =   p_rw;
    assign              sel              =   p_wen;
    assign              data_sram_size   =   p_size;
    assign              aluoutM          =   p_a;
    assign              writedata2M      =   p_dout;
    assign              memenM           =   p_strobe;
    assign              p_din            =   flag ? m_dout : readdataM;
    assign              p_ready          =   cache_ready;
    assign              flag             =   (aluoutM[31:16] == 16'hbfaf) ? 1'b1 : 1'b0;
    assign              rst              =   ~clrn;
    assign              data_data_ok     =   m_ready;
    assign              data_rdata       =   m_dout ;
    assign              m_a              =   flag ? {16'h1faf,aluoutM[15:0]} : data_addr;
    assign              m_din            =   flag ? p_dout : data_wdata;
    assign              m_strobe         =   flag ? p_strobe : data_req;
    assign              m_wen            =   flag ? p_wen : data_wen;
    assign              m_size           =   flag ? p_size: data_size;
    assign              m_rw             =   flag ? p_rw : data_wr;

    assign              cmm_valid        =   ~dram_rd_val & cache_hit & memenM & memwriteM;

    // TAG ENA
    wire   tags_way_0_wea;
    assign tags_way_0_wea = dram_rd_val==1 ? (rwc_way==0 ? 1 : 0) : (cmm_valid==1 ? (hit_way==0 ? 1 : 0) : 0);

    wire   tags_way_1_wea;
    assign tags_way_1_wea = dram_rd_val==1 ? (rwc_way==1 ? 1 : 0) : (cmm_valid==1 ? (hit_way==1 ? 1 : 0) : 0);

    wire   tags_way_2_wea;
    assign tags_way_2_wea = dram_rd_val==1 ? (rwc_way==2 ? 1 : 0) : (cmm_valid==1 ? (hit_way==2 ? 1 : 0) : 0);

    wire   tags_way_3_wea;
    assign tags_way_3_wea = dram_rd_val==1 ? (rwc_way==3 ? 1 : 0) : (cmm_valid==1 ? (hit_way==3 ? 1 : 0) : 0);
    
    // DATA
    assign m_data_1111sel = hit_way==0? {writedata2M[31:24],8'b0,8'b0,8'b0, writedata2M[23:16],8'b0,8'b0, 8'b0, writedata2M[15:8],8'b0,8'b0,8'b0, writedata2M[7:0],8'b0,8'b0,8'b0} :
                            hit_way==1? {8'b0,writedata2M[31:24],8'b0,8'b0, 8'b0,writedata2M[23:16],8'b0, 8'b0, 8'b0,writedata2M[15:8],8'b0,8'b0, 8'b0,writedata2M[7:0],8'b0,8'b0} :
                            hit_way==2? {8'b0,8'b0,writedata2M[31:24],8'b0, 8'b0,8'b0,writedata2M[23:16], 8'b0, 8'b0,8'b0,writedata2M[15:8],8'b0, 8'b0,8'b0,writedata2M[7:0],8'b0} :
                            hit_way==3? {8'b0,8'b0,8'b0,writedata2M[31:24], 8'b0,8'b0, 8'b0,writedata2M[23:16], 8'b0,8'b0,8'b0,writedata2M[15:8], 8'b0,8'b0,8'b0,writedata2M[7:0]} : 128'b0;

    assign m_data_1100sel = hit_way==0? {writedata2M[31:24],8'b0,8'b0,8'b0, writedata2M[23:16],8'b0,8'b0, 8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==1? {8'b0,writedata2M[31:24],8'b0,8'b0, 8'b0,writedata2M[23:16],8'b0, 8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==2? {8'b0,8'b0,writedata2M[31:24],8'b0, 8'b0,8'b0,writedata2M[23:16], 8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==3? {8'b0,8'b0,8'b0,writedata2M[31:24], 8'b0,8'b0, 8'b0,writedata2M[23:16], 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} : 128'b0;

    assign m_data_0011sel = hit_way==0? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0, 8'b0, writedata2M[15:8],8'b0,8'b0,8'b0, writedata2M[7:0],8'b0,8'b0,8'b0} :
                            hit_way==1? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0, 8'b0, 8'b0,writedata2M[15:8],8'b0,8'b0, 8'b0,writedata2M[7:0],8'b0,8'b0} :
                            hit_way==2? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0, 8'b0, 8'b0,8'b0,writedata2M[15:8],8'b0, 8'b0,8'b0,writedata2M[7:0],8'b0} :
                            hit_way==3? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0, 8'b0,8'b0, 8'b0,8'b0,8'b0,writedata2M[15:8], 8'b0,8'b0,8'b0,writedata2M[7:0]} : 128'b0;

    assign m_data_1000sel = hit_way==0? {writedata2M[31:24],8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0, 8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==1? {8'b0,writedata2M[31:24],8'b0,8'b0, 8'b0,8'b0,8'b0, 8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==2? {8'b0,8'b0,writedata2M[31:24],8'b0, 8'b0,8'b0,8'b0, 8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==3? {8'b0,8'b0,8'b0,writedata2M[31:24], 8'b0,8'b0, 8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} : 128'b0;

    assign m_data_0100sel = hit_way==0? {8'b0,8'b0,8'b0,8'b0, writedata2M[23:16],8'b0,8'b0, 8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==1? {8'b0,8'b0,8'b0,8'b0, 8'b0,writedata2M[23:16],8'b0, 8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==2? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,writedata2M[23:16], 8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==3? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0, 8'b0,writedata2M[23:16], 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} : 128'b0;

    assign m_data_0010sel = hit_way==0? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0, 8'b0, writedata2M[15:8],8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==1? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0, 8'b0, 8'b0,writedata2M[15:8],8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==2? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0, 8'b0, 8'b0,8'b0,writedata2M[15:8],8'b0, 8'b0,8'b0,8'b0,8'b0} :
                            hit_way==3? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0, 8'b0,8'b0, 8'b0,8'b0,8'b0,writedata2M[15:8], 8'b0,8'b0,8'b0,8'b0} : 128'b0;

    assign m_data_0001sel = hit_way==0? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0, 8'b0, 8'b0,8'b0,8'b0,8'b0, writedata2M[7:0],8'b0,8'b0,8'b0} :
                            hit_way==1? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0, 8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,writedata2M[7:0],8'b0,8'b0} :
                            hit_way==2? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0, 8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,writedata2M[7:0],8'b0} :
                            hit_way==3? {8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0, 8'b0,8'b0, 8'b0,8'b0,8'b0,8'b0, 8'b0,8'b0,8'b0,writedata2M[7:0]} : 128'b0;

    assign r_data         = rwc_way==0?{data_rdata[31:24],8'b0,8'b0,8'b0, data_rdata[23:16],8'b0,8'b0, 8'b0, data_rdata[15:8],8'b0,8'b0,8'b0, data_rdata[7:0],8'b0,8'b0,8'b0} :
                            rwc_way==1?{8'b0,data_rdata[31:24],8'b0,8'b0, 8'b0,data_rdata[23:16],8'b0, 8'b0, 8'b0,data_rdata[15:8],8'b0,8'b0, 8'b0,data_rdata[7:0],8'b0,8'b0} :
                            rwc_way==2?{8'b0,8'b0,data_rdata[31:24],8'b0, 8'b0,8'b0,data_rdata[23:16], 8'b0, 8'b0,8'b0,data_rdata[15:8],8'b0, 8'b0,8'b0,data_rdata[7:0],8'b0} :
                            rwc_way==3?{8'b0,8'b0,8'b0,data_rdata[31:24], 8'b0,8'b0, 8'b0,data_rdata[23:16], 8'b0,8'b0,8'b0,data_rdata[15:8], 8'b0,8'b0,8'b0,data_rdata[7:0]} : 128'b0;

    assign m_data         = sel==4'b1111 ? m_data_1111sel :
                            sel==4'b1100 ? m_data_1100sel :
                            sel==4'b0011 ? m_data_0011sel :
                            sel==4'b1000 ? m_data_1000sel :
                            sel==4'b0100 ? m_data_0100sel :
                            sel==4'b0010 ? m_data_0010sel :
                            sel==4'b0001 ? m_data_0001sel : 128'b0;

    assign wr_bram = dram_rd_val || cmm_valid;

    assign wr_mem_data = dram_rd_val==1 ? r_data : (cmm_valid==1 ? m_data : 0);

    reg  [15:0]  data_bram_wea_reg;
    assign       data_bram_wea_wire = data_bram_wea_reg;

    assign dina_way_age_way_0 = dram_rd_val==1 ? (rwc_way==0 ? 0 : (c_way_age_way_0 + 1)) : (cmm_valid==1 ? (hit_way==0 ? 0 : (c_way_age_way_0 + 1)) : 0);
    assign dina_way_age_way_1 = dram_rd_val==1 ? (rwc_way==1 ? 0 : (c_way_age_way_1 + 1)) : (cmm_valid==1 ? (hit_way==1 ? 0 : (c_way_age_way_1 + 1)) : 0);
    assign dina_way_age_way_2 = dram_rd_val==1 ? (rwc_way==2 ? 0 : (c_way_age_way_2 + 1)) : (cmm_valid==1 ? (hit_way==2 ? 0 : (c_way_age_way_2 + 1)) : 0);
    assign dina_way_age_way_3 = dram_rd_val==1 ? (rwc_way==3 ? 0 : (c_way_age_way_3 + 1)) : (cmm_valid==1 ? (hit_way==3 ? 0 : (c_way_age_way_3 + 1)) : 0);

    assign  index                     =    aluoutM[SET_ADDR_LEN+LINE_ADDR_LEN+1 : LINE_ADDR_LEN+WORD_ADDR_LEN];
    assign  tag                       =    aluoutM[A_WIDTH-1 : SET_ADDR_LEN+LINE_ADDR_LEN+2];

    assign  tagout                    =    (mage_way==0) ? c_tags_way_0 : (mage_way==1) ? c_tags_way_1 : 
                                           (mage_way==2) ? c_tags_way_2 : (mage_way==3) ? c_tags_way_3 : 19'b0;

    assign  c_out                     =    (valid_tag_hit && hit_way==0) ? {c_data1_way_0,c_data2_way_0,c_data3_way_0,c_data4_way_0} :
                                           (valid_tag_hit && hit_way==1) ? {c_data1_way_1,c_data2_way_1,c_data3_way_1,c_data4_way_1} :
                                           (valid_tag_hit && hit_way==2) ? {c_data1_way_2,c_data2_way_2,c_data3_way_2,c_data4_way_2} :
                                           (valid_tag_hit && hit_way==3) ? {c_data1_way_3,c_data2_way_3,c_data3_way_3,c_data4_way_3} : 0;

    //cache control
    assign  cache_hit                 =   valid_tag_hit & memenM & !flag;

    assign  dirty_all                 =   d_dirty_way_0[index] && d_dirty_way_1[index] && d_dirty_way_2[index] && d_dirty_way_3[index];

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
    assign dram_wr_data  = (mage_way==0) ? {c_data1_way_0,c_data2_way_0,c_data3_way_0,c_data4_way_0} : 
                           (mage_way==1) ? {c_data1_way_1,c_data2_way_1,c_data3_way_1,c_data4_way_1} : 
                           (mage_way==2) ? {c_data1_way_2,c_data2_way_2,c_data3_way_2,c_data4_way_2} :
                           (mage_way==3) ? {c_data1_way_3,c_data2_way_3,c_data3_way_3,c_data4_way_3} : 32'b0;

    assign valid_tag_hit = (d_valid_way_0[index]==1 && tag == c_tags_way_0)||
                           (d_valid_way_1[index]==1 && tag == c_tags_way_1)||
                           (d_valid_way_2[index]==1 && tag == c_tags_way_2)||
                           (d_valid_way_3[index]==1 && tag == c_tags_way_3);

    assign hit_way       = (d_valid_way_0[index]==1 && tag == c_tags_way_0) ? 0 :
                           (d_valid_way_1[index]==1 && tag == c_tags_way_1) ? 1 :
                           (d_valid_way_2[index]==1 && tag == c_tags_way_2) ? 2 :
                           (d_valid_way_3[index]==1 && tag == c_tags_way_3) ? 3 : 2'b0;

    // cpu/dram writes data_cache
    always@(posedge clk) begin
        //init cache memery
        if(rst) begin
            for(i=0;i<(1<<SET_ADDR_LEN);i=i+1) begin
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
            end
        end
        // SRAM的数据写入cache
        else if(dram_rd_val) begin   // dram write cache block
            d_valid_way_0[index]  <=  1'b1;
            d_dirty_way_0[index]  <=  1'b0;
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
            endcase
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
                CPU_EXEC:if( ~cache_hit & dirty_all & memenM & !flag)          // dirty block write back to dram
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

    wire [3:0] d_c_way_age_way_0;
    wire [3:0] d_c_way_age_way_1;
    wire [3:0] d_c_way_age_way_2;
    wire [3:0] d_c_way_age_way_3;

    assign d_c_way_age_way_0 = d_dirty_way_0[index]==1'b1 ? 0 : (c_way_age_way_0==4'b1111 ? c_way_age_way_0 : (c_way_age_way_0+1));  // 加一和0区分
    assign d_c_way_age_way_1 = d_dirty_way_1[index]==1'b1 ? 0 : (c_way_age_way_0==4'b1111 ? c_way_age_way_0 : (c_way_age_way_0+1));
    assign d_c_way_age_way_2 = d_dirty_way_2[index]==1'b1 ? 0 : (c_way_age_way_0==4'b1111 ? c_way_age_way_0 : (c_way_age_way_0+1));
    assign d_c_way_age_way_3 = d_dirty_way_3[index]==1'b1 ? 0 : (c_way_age_way_0==4'b1111 ? c_way_age_way_0 : (c_way_age_way_0+1));

    always@(*) begin
        if(rst) begin
            rwc_way<=0;
        end else
        if(dirty_all==1'b1) begin
            if(c_way_age_way_0 >= c_way_age_way_1 && c_way_age_way_0 >= c_way_age_way_2 && c_way_age_way_0 >= c_way_age_way_3) begin
                rwc_way<=0;
                mage_way<=0;
            end else
            if(c_way_age_way_1 >= c_way_age_way_0 && c_way_age_way_1 >= c_way_age_way_2 && c_way_age_way_1 >= c_way_age_way_3) begin
                rwc_way<=1;
                mage_way<=1;
            end else
            if(c_way_age_way_2 >= c_way_age_way_0 && c_way_age_way_2 >= c_way_age_way_1 && c_way_age_way_2 >= c_way_age_way_3) begin
                rwc_way<=2;
                mage_way<=2;
            end else begin
                rwc_way<=3;
                mage_way<=3;
            end
        end else begin
            if(d_c_way_age_way_0 >= d_c_way_age_way_1 && d_c_way_age_way_0 >= d_c_way_age_way_2 && d_c_way_age_way_0 >= d_c_way_age_way_3) begin
                rwc_way<=0;
            end else
            if(d_c_way_age_way_1 >= d_c_way_age_way_0 && d_c_way_age_way_1 >= d_c_way_age_way_2 && d_c_way_age_way_1 >= d_c_way_age_way_3) begin
                rwc_way<=1;
            end else
            if(d_c_way_age_way_2 >= d_c_way_age_way_0 && d_c_way_age_way_2 >= d_c_way_age_way_1 && d_c_way_age_way_2 >= d_c_way_age_way_3) begin
                rwc_way<=2;
            end else begin
                rwc_way<=3;
            end
        end
    end

    always@(*) begin
        if(rst) begin
            data_bram_wea_reg<=16'b0000_0000_0000_0000;
        end
        else if(dram_rd_val) begin
            case (rwc_way)
                2'b00: begin
                    data_bram_wea_reg<=16'b1000_1000_1000_1000;
                end
                2'b01: begin
                    data_bram_wea_reg<=16'b0100_0100_0100_0100;
                end
                2'b10: begin
                    data_bram_wea_reg<=16'b0010_0010_0010_0010;
                end
                2'b11: begin
                    data_bram_wea_reg<=16'b0001_0001_0001_0001;
                end
            endcase
        end
        else if(cmm_valid) begin
            case (sel)
                4'b1111: begin
                    case (hit_way)
                        2'b00: begin
                            data_bram_wea_reg<=16'b1000_1000_1000_1000;
                        end
                        2'b01: begin
                            data_bram_wea_reg<=16'b0100_0100_0100_0100;
                        end
                        2'b10: begin
                            data_bram_wea_reg<=16'b0010_0010_0010_0010;
                        end
                        2'b11: begin
                            data_bram_wea_reg<=16'b0001_0001_0001_0001;
                        end
                    endcase
                end
                4'b1100: begin
                    case (hit_way)
                        2'b00: begin
                            data_bram_wea_reg<=16'b1000_1000_0000_0000;
                        end
                        2'b01: begin
                            data_bram_wea_reg<=16'b0100_0100_0000_0000;
                        end
                        2'b10: begin
                            data_bram_wea_reg<=16'b0010_0010_0000_0000;
                        end
                        2'b11: begin
                            data_bram_wea_reg<=16'b0001_0001_0000_0000;
                        end
                    endcase
                end
                4'b0011: begin
                    case (hit_way)
                        2'b00: begin
                            data_bram_wea_reg<=16'b0000_0000_1000_1000;
                        end
                        2'b01: begin
                            data_bram_wea_reg<=16'b0000_0000_0100_0100;
                        end
                        2'b10: begin
                            data_bram_wea_reg<=16'b0000_0000_0010_0010;
                        end
                        2'b11: begin
                            data_bram_wea_reg<=16'b0000_0000_0001_0001;
                        end
                    endcase
                end
                4'b1000: begin
                    case (hit_way)
                        2'b00: begin
                            data_bram_wea_reg<=16'b1000_0000_0000_0000;
                        end
                        2'b01: begin
                            data_bram_wea_reg<=16'b0100_0000_0000_0000;
                        end
                        2'b10: begin
                            data_bram_wea_reg<=16'b0010_0000_0000_0000;
                        end
                        2'b11: begin
                            data_bram_wea_reg<=16'b0001_0000_0000_0000;
                        end
                    endcase
                end
                4'b0100: begin
                    case (hit_way)
                        2'b00: begin
                            data_bram_wea_reg<=16'b0000_1000_0000_0000;
                        end
                        2'b01: begin
                            data_bram_wea_reg<=16'b0000_0100_0000_0000;
                        end
                        2'b10: begin
                            data_bram_wea_reg<=16'b0000_0010_0000_0000;
                        end
                        2'b11: begin
                            data_bram_wea_reg<=16'b0000_0001_0000_0000;
                        end
                    endcase
                end
                4'b0010: begin
                    case (hit_way)
                        2'b00: begin
                            data_bram_wea_reg<=16'b0000_0000_1000_0000;
                        end
                        2'b01: begin
                            data_bram_wea_reg<=16'b0000_0000_0100_0000;
                        end
                        2'b10: begin
                            data_bram_wea_reg<=16'b0000_0000_0010_0000;
                        end
                        2'b11: begin
                            data_bram_wea_reg<=16'b0000_0000_0001_0000;
                        end
                    endcase
                end
                4'b0001: begin
                    case (hit_way)
                        2'b00: begin
                            data_bram_wea_reg<=16'b0000_0000_0000_1000;
                        end
                        2'b01: begin
                            data_bram_wea_reg<=16'b0000_0000_0000_0100;
                        end
                        2'b10: begin
                            data_bram_wea_reg<=16'b0000_0000_0000_0010;
                        end
                        2'b11: begin
                            data_bram_wea_reg<=16'b0000_0000_0000_0001;
                        end
                    endcase
                end
                default:;
            endcase
        end
    end

    tags_way_0 tags_way_0 (
        .clka(clk),
        .ena(wr_bram),
        .wea(tags_way_0_wea),
        .addra(index),
        .dina(tag),
        .clkb(~clk),
        .addrb(index),
        .doutb(c_tags_way_0)
    );

    tags_way_1 tags_way_1 (
        .clka(clk),
        .ena(wr_bram),
        .wea(tags_way_1_wea),
        .addra(index),
        .dina(tag),
        .clkb(~clk),
        .addrb(index),
        .doutb(c_tags_way_1)
    );

    tags_way_2 tags_way_2 (
        .clka(clk),
        .ena(wr_bram),
        .wea(tags_way_2_wea),
        .addra(index),
        .dina(tag),
        .clkb(~clk),
        .addrb(index),
        .doutb(c_tags_way_2)
    );

    tags_way_3 tags_way_3 (
        .clka(clk),
        .ena(wr_bram),
        .wea(tags_way_3_wea),
        .addra(index),
        .dina(tag),
        .clkb(~clk),
        .addrb(index),
        .doutb(c_tags_way_3)
    );

    way_age_way_0 way_age_way_0 (
        .clka(clk),
        .ena(wr_bram),
        .addra(index),
        .wea(wr_bram),
        .dina(dina_way_age_way_0),
        .clkb(~clk),
        .addrb(index),
        .doutb(c_way_age_way_0)
    );

    way_age_way_1 way_age_way_1 (
        .clka(clk),
        .ena(wr_bram),
        .addra(index),
        .wea(wr_bram),
        .dina(dina_way_age_way_1),
        .clkb(~clk),
        .addrb(index),
        .doutb(c_way_age_way_1)
    );

    way_age_way_2 way_age_way_2 (
        .clka(clk),
        .ena(wr_bram),
        .addra(index),
        .wea(wr_bram),
        .dina(dina_way_age_way_2),
        .clkb(~clk),
        .addrb(index),
        .doutb(c_way_age_way_2)
    );

    way_age_way_3 way_age_way_3 (
        .clka(clk),
        .ena(wr_bram),
        .addra(index),
        .wea(wr_bram),
        .dina(dina_way_age_way_3),
        .clkb(~clk),
        .addrb(index),
        .doutb(c_way_age_way_3)
    );

    data_cache_block_memory dcb_mem (
        .clka(clk),
        .ena(wr_bram),
        .wea(data_bram_wea_wire),      // input wire [15 : 0] wea
        .addra(index),
        .dina(wr_mem_data),    // input wire [127 : 0] dina
        .clkb(~clk),
        .addrb(index),
        .doutb({c_data1_way_0,c_data1_way_1,c_data1_way_2,c_data1_way_3,c_data2_way_0,c_data2_way_1,c_data2_way_2,c_data2_way_3,c_data3_way_0,c_data3_way_1,c_data3_way_2,c_data3_way_3,c_data4_way_0,c_data4_way_1,c_data4_way_2,c_data4_way_3})  // output wire [127 : 0] doutb
    );
endmodule