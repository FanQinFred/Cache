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

`define  A_WIDTH         32                                                           // 32λ�ĵ�ַ���
`define  SET_ADDR_LEN    9                                                            // 2��SET_ADDR_LEN�η�����
`define  WAY_CNT         4                                                            // 4��·
`define  WORD_ADDR_LEN   2                                                            // 2λ���ֽ�ƫ��
`define  LINE_ADDR_LEN   0                                                            // 0λ����ƫ��

`define  TAG_ADDR_LEN    (32 - `WORD_ADDR_LEN - `SET_ADDR_LEN - `LINE_ADDR_LEN)       // �����ĳ���
`define  MEM_ADDR_LEN    (`TAG_ADDR_LEN + `SET_ADDR_LEN)                              // ����SRAM�ĵ�ַ���� �˴�Ϊ{30λ��00}
`define  SET_SIZE        (1 << `SET_ADDR_LEN)                                         // �������

module i_cache (
    input wire clk, rst,
    //mips core
    input          cpu_data_req       ,
    input          cpu_data_wr        ,
    input   [1 :0] cpu_data_size      ,
    input   [31:0] cpu_data_addr      ,
    input   [31:0] cpu_data_wdata     ,
    output  [31:0] cpu_data_rdata     ,
    output         cpu_data_addr_ok   ,
    output         cpu_data_data_ok   ,
    //axi interface
    output         cache_data_req     ,
    output         cache_data_wr      ,
    output  [1 :0] cache_data_size    ,
    output  [31:0] cache_data_addr    ,
    output  [31:0] cache_data_wdata   ,
    input   [31:0] cache_data_rdata   ,
    input          cache_data_addr_ok ,
    input          cache_data_data_ok
);

    //Cache����
    parameter  INDEX_WIDTH  = 10;
    parameter  OFFSET_WIDTH = 2;
    localparam TAG_WIDTH    = 32 - INDEX_WIDTH - OFFSET_WIDTH;
    localparam CACHE_DEEPTH = 1 << INDEX_WIDTH;

    //Cache�洢��Ԫ
    // ������Ч��Ϣ
    reg                                                 cache_valid_way_0           [CACHE_DEEPTH - 1 : 0];
    reg                                                 cache_valid_way_1           [CACHE_DEEPTH - 1 : 0];
    reg                                                 cache_valid_way_2           [CACHE_DEEPTH - 1 : 0];
    reg                                                 cache_valid_way_3           [CACHE_DEEPTH - 1 : 0];
    // ��������Ϣ
    reg                                                 cache_dirty_way_0           [CACHE_DEEPTH-1:0];
    reg                                                 cache_dirty_way_1           [CACHE_DEEPTH-1:0];
    reg                                                 cache_dirty_way_2           [CACHE_DEEPTH-1:0];
    reg                                                 cache_dirty_way_3           [CACHE_DEEPTH-1:0];
    // ������
    reg     [TAG_WIDTH-1:0]                             cache_tags_way_0            [CACHE_DEEPTH - 1 : 0];
    reg     [TAG_WIDTH-1:0]                             cache_tags_way_1            [CACHE_DEEPTH - 1 : 0];
    reg     [TAG_WIDTH-1:0]                             cache_tags_way_2            [CACHE_DEEPTH - 1 : 0];
    reg     [TAG_WIDTH-1:0]                             cache_tags_way_3            [CACHE_DEEPTH - 1 : 0];
    // ��������
    reg     [31 : 0]                                    cache_block_way_0           [CACHE_DEEPTH - 1 : 0];
    reg     [31 : 0]                                    cache_block_way_1           [CACHE_DEEPTH - 1 : 0];
    reg     [31 : 0]                                    cache_block_way_2           [CACHE_DEEPTH - 1 : 0];
    reg     [31 : 0]                                    cache_block_way_3           [CACHE_DEEPTH - 1 : 0];
    //��������
    reg     [3: 0]                                      way_age_way_0               [CACHE_DEEPTH - 1 : 0];
    reg     [3: 0]                                      way_age_way_1               [CACHE_DEEPTH - 1 : 0];
    reg     [3: 0]                                      way_age_way_2               [CACHE_DEEPTH - 1 : 0];
    reg     [3: 0]                                      way_age_way_3               [CACHE_DEEPTH - 1 : 0];
    //����ÿ����������·��
    reg     [1: 0]                                      way_hold_max_age            [CACHE_DEEPTH - 1 : 0];
    
    //FSM
    reg  [1:0]          state;                      // FSM
    // state
    localparam          CPU_EXEC         =   0;
    localparam          WR_DRAM          =   1;
    localparam          RD_DRAM          =   2;

    //���ʵ�ַ�ֽ�
    wire    [OFFSET_WIDTH-1:0]                          offset;
    wire    [INDEX_WIDTH-1:0]                           index;
    wire    [TAG_WIDTH-1:0]                             tag;

    assign  offset = cpu_data_addr[OFFSET_WIDTH - 1 : 0];
    assign  index  = cpu_data_addr[INDEX_WIDTH + OFFSET_WIDTH - 1 : OFFSET_WIDTH];  //11:2
    assign  tag    = cpu_data_addr[31 : INDEX_WIDTH + OFFSET_WIDTH];

    //����Cache line
    wire                                                c_valid;
    wire [TAG_WIDTH-1:0]                                c_tag;
    wire [31:0]                                         c_block;

    // �ж��Ƿ�����
    wire                      valid_tag_hit;
    // ���е�·��
    wire [1:0]                hit_way;

    assign valid_tag_hit = (cache_valid_way_0[index] && tag == cache_tags_way_0[index])||
                           (cache_valid_way_1[index] && tag == cache_tags_way_1[index])||
                           (cache_valid_way_2[index] && tag == cache_tags_way_2[index])||
                           (cache_valid_way_3[index] && tag == cache_tags_way_3[index]);
                           
    assign dirty         = hit && hit_way==0 ? cache_dirty_way_0[index] : 
                           hit && hit_way==1 ? cache_dirty_way_1[index] : 
                           hit && hit_way==2 ? cache_dirty_way_2[index] :
                           hit && hit_way==3 ? cache_dirty_way_3[index] : 0;
    
    assign hit_way       = (cache_valid_way_0[index] && tag == cache_tags_way_0[index]) ? 0:
                           (cache_valid_way_1[index] && tag == cache_tags_way_1[index]) ? 1:
                           (cache_valid_way_2[index] && tag == cache_tags_way_2[index]) ? 2:
                           (cache_valid_way_3[index] && tag == cache_tags_way_3[index]) ? 3:0;

    // ���cache��Ӧ��valid
    assign c_valid       = (cache_valid_way_0[index] && tag == cache_tags_way_0[index])||
                           (cache_valid_way_1[index] && tag == cache_tags_way_1[index])||
                           (cache_valid_way_2[index] && tag == cache_tags_way_2[index])||
                           (cache_valid_way_3[index] && tag == cache_tags_way_3[index]);

    assign c_tag         = (way_hold_max_age[index]==0) ? cache_tags_way_0[index] : (way_hold_max_age[index]==1) ? cache_tags_way_1[index] : 
                           (way_hold_max_age[index]==2) ? cache_tags_way_2[index] : (way_hold_max_age[index]==3) ? cache_tags_way_3[index] : 0;

    // ���cache��Ӧ��data
    assign c_block                      =  hit && hit_way==0 ? cache_block_way_0[index] :
                                           hit && hit_way==1 ? cache_block_way_1[index] :
                                           hit && hit_way==2 ? cache_block_way_2[index] :
                                           hit && hit_way==3 ? cache_block_way_3[index] : 0;

    //�ж��Ƿ�����
    wire hit;
    wire miss;
    assign hit   = c_valid;
    assign miss  = ~hit;

    //����д
    wire read;
    wire write;
    assign read  = ~write;
    assign write = cpu_data_wr;

    //���ڴ���ƿ�ʼ
    //����read_req, addr_rcv, read_finish���ڹ�����sram�źš�
    reg  addr_rcv;       //��ַ���ճɹ�(addr_ok)�󵽽���
    wire read_finish;    //���ݽ��ճɹ�(data_ok)�������������
    always @(posedge clk) begin
        addr_rcv <= rst ? 1'b0 :
                    //read & cache_data_req & cache_data_addr_ok ? 1'b1 :
                    dram_wr_req & cache_data_addr_ok ? 1'b1 :
                    read_finish ? 1'b0 : addr_rcv;
    end
    assign read_finish = read & cache_data_data_ok;
    //���ڴ���ƽ���

    //д�ڴ���ƿ�ʼ
    reg  waddr_rcv;      
    wire write_finish;   
    always @(posedge clk) begin
        waddr_rcv <= rst ? 1'b0 :
                     //write & cache_data_req & cache_data_addr_ok ? 1'b1 :
                     dram_wr_req & cache_data_addr_ok ? 1'b1 :
                     write_finish ? 1'b0 : waddr_rcv;
    end
    assign write_finish = write & cache_data_data_ok;
    //д�ڴ���ƽ���

    //output to mips core
    assign cpu_data_rdata   = hit ? c_block : cache_data_rdata;
    assign cpu_data_addr_ok = cpu_data_req & hit;//hit;//read & cpu_data_req & hit | cache_data_req & cache_data_addr_ok;
    assign cpu_data_data_ok = cpu_data_req & hit;//read & cpu_data_req & hit | cache_data_data_ok;
 
    wire [31:0] dram_wr_addr,dram_rd_addr;
    assign  dram_wr_addr              =   {c_tag,index,2'b00};
    assign  dram_rd_addr              =   cpu_data_addr;
    //output to axi interface
    assign cache_data_req   = (dram_rd_req ) | (dram_wr_req);//dram_rd_req & ~addr_rcv | dram_wr_req & ~waddr_rcv;
    assign cache_data_wr    = dram_wr_req ? 1 : 0;;
    assign cache_data_size  = 2'b10;        //    wire    dram_wr_req,dram_rd_req;
    assign cache_data_addr  = dram_wr_req ? dram_wr_addr : dram_rd_req ?  dram_rd_addr : 32'b0;//cpu_data_addr;
    assign cache_data_wdata = c_block;//cpu_data_wdata;

    // data_cache state machine
    // �����ڿ��ƶ���д�����ź�
    wire   dram_wr_val,dram_rd_val;
    assign dram_wr_val = dram_wr_req ? cache_data_data_ok : 0;
    assign dram_rd_val = dram_rd_req ? cache_data_data_ok : 0; 
    // dram write/read request
    // ͨ��state���ƶ���д�����ź�
    wire    dram_wr_req,dram_rd_req;
    assign  dram_wr_req = ( state == WR_DRAM );
    assign  dram_rd_req = ( state == RD_DRAM );
    always@(posedge clk) begin
        if(rst) begin
            state   <=  CPU_EXEC;
        end
        else begin
            case(state)
                CPU_EXEC:if( miss & dirty & cpu_data_req)          // dirty block write back to dram
                            state   <=  WR_DRAM;
                        else if( miss & cpu_data_req)              // request new block from dram
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

    //д��Cache
    //�����ַ�е�tag, index����ֹaddr�����ı�
    reg [TAG_WIDTH-1:0]   tag_save;
    reg [INDEX_WIDTH-1:0] index_save;
    //��cpu_data_req�ű���
    always @(posedge clk) begin
        tag_save   <= rst ? 0 :
                      cpu_data_req ? tag : tag_save;
        index_save <= rst ? 0 :
                      cpu_data_req ? index : index_save;
    end

    wire [31:0] write_cache_data;
    wire [3:0]  write_mask;

    integer             i;
    integer             max_age_way;
    always @(posedge clk) begin
        if(rst) begin
            for(i=0; i<CACHE_DEEPTH; i=i+1) begin   //�տ�ʼ��Cache��Ϊ��Ч
                // valid
                cache_valid_way_0[i] <= 0;
                cache_valid_way_1[i] <= 0;
                cache_valid_way_2[i] <= 0;
                cache_valid_way_3[i] <= 0;
                // dirty
                cache_dirty_way_0[i] <= 1'b0;
                cache_dirty_way_1[i] <= 1'b0;
                cache_dirty_way_2[i] <= 1'b0;
                cache_dirty_way_3[i] <= 1'b0;
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
        else begin
            if(dram_rd_val) begin //��ȱʧ���ô����ʱ
                case (way_hold_max_age[index_save])
                    2'd0: begin
                        cache_valid_way_0[index_save]  <=  1'b1;
                        cache_dirty_way_0[index_save]  <=  1'b0;
                        cache_tags_way_0 [index_save]  <=  tag_save;
                        cache_block_way_0[index_save]  <=  cache_data_rdata; //д��Cache line
                    end
                    2'd1: begin
                        cache_valid_way_1[index_save]  <=  1'b1;
                        cache_dirty_way_1[index_save]  <=  1'b0;
                        cache_tags_way_1 [index_save]  <=  tag_save;
                        cache_block_way_1[index_save]  <=  cache_data_rdata; //д��Cache line
                    end
                    2'd2: begin
                        cache_valid_way_2[index_save]  <=  1'b1;
                        cache_dirty_way_2[index_save]  <=  1'b0;
                        cache_tags_way_2 [index_save]  <=  tag_save;
                        cache_block_way_2[index_save]  <=  cache_data_rdata; //д��Cache line
                    end
                    2'd3: begin
                        cache_valid_way_3[index_save]  <=  1'b1;
                        cache_dirty_way_3[index_save]  <=  1'b0;
                        cache_tags_way_3 [index_save]  <=  tag_save;
                        cache_block_way_3[index_save]  <=  cache_data_rdata; //д��Cache line
                    end
                    default:;
                endcase
                
                // �ҵ���������way��
                if((0!=way_hold_max_age[index_save]?way_age_way_0[index_save]+1:0)>=(1!=way_hold_max_age[index_save]?way_age_way_1[index_save]+1:0)&&
                (0!=way_hold_max_age[index_save]?way_age_way_0[index_save]+1:0)>=(2!=way_hold_max_age[index_save]?way_age_way_2[index_save]+1:0)&&
                (0!=way_hold_max_age[index_save]?way_age_way_0[index_save]+1:0)>=(3!=way_hold_max_age[index_save]?way_age_way_3[index_save]+1:0)) begin
                    way_hold_max_age[index_save] <= 0;
                end else if((1!=way_hold_max_age[index_save]?way_age_way_1[index_save]+1:0)>=(0!=way_hold_max_age[index_save]?way_age_way_0[index_save]+1:0)&&
                            (1!=way_hold_max_age[index_save]?way_age_way_1[index_save]+1:0)>=(2!=way_hold_max_age[index_save]?way_age_way_2[index_save]+1:0)&&
                            (1!=way_hold_max_age[index_save]?way_age_way_1[index_save]+1:0)>=(3!=way_hold_max_age[index_save]?way_age_way_3[index_save]+1:0)) begin
                    way_hold_max_age[index_save] <= 1;
                end else if((2!=way_hold_max_age[index_save]?way_age_way_2[index_save]+1:0)>=(0!=way_hold_max_age[index_save]?way_age_way_0[index_save]+1:0)&&
                            (2!=way_hold_max_age[index_save]?way_age_way_2[index_save]+1:0)>=(1!=way_hold_max_age[index_save]?way_age_way_1[index_save]+1:0)&&
                            (2!=way_hold_max_age[index_save]?way_age_way_2[index_save]+1:0)>=(3!=way_hold_max_age[index_save]?way_age_way_3[index_save]+1:0)) begin
                    way_hold_max_age[index_save] <= 2;
                end else if((3!=way_hold_max_age[index_save]?way_age_way_3[index_save]+1:0)>=(0!=way_hold_max_age[index_save]?way_age_way_0[index_save]+1:0)&&
                            (3!=way_hold_max_age[index_save]?way_age_way_3[index_save]+1:0)>=(1!=way_hold_max_age[index_save]?way_age_way_1[index_save]+1:0)&&
                            (3!=way_hold_max_age[index_save]?way_age_way_3[index_save]+1:0)>=(2!=way_hold_max_age[index_save]?way_age_way_2[index_save]+1:0)) begin
                    way_hold_max_age[index_save] <= 3;
                end
                // ������way�����1
                way_age_way_0[index_save] <= way_hold_max_age[index_save]==0 ? 0 : way_age_way_0[index_save] + 1;
                way_age_way_1[index_save] <= way_hold_max_age[index_save]==1 ? 0 : way_age_way_1[index_save] + 1;
                way_age_way_2[index_save] <= way_hold_max_age[index_save]==2 ? 0 : way_age_way_2[index_save] + 1;
                way_age_way_3[index_save] <= way_hold_max_age[index_save]==3 ? 0 : way_age_way_3[index_save] + 1;

            end
            else if(write & hit) begin   //д����ʱ��ҪдCache
                //������λ
                case (hit_way)
                    0: begin
                        cache_dirty_way_0[index]  <=  1'b1;
                    end
                    1: begin
                        cache_dirty_way_1[index]  <=  1'b1;
                    end
                    2: begin
                        cache_dirty_way_2[index]  <=  1'b1;
                    end
                    3: begin
                        cache_dirty_way_3[index]  <=  1'b1;
                    end
                    default:;
                endcase
                //������д��cache
                case (hit_way)
                    0: begin
                        cache_block_way_0[index] <= write_cache_data;
                    end
                    1: begin
                        cache_block_way_1[index] <= write_cache_data;
                    end
                    2: begin
                        cache_block_way_2[index] <= write_cache_data;
                    end
                    3: begin
                        cache_block_way_3[index] <= write_cache_data;
                    end
                    default:;
                endcase
                // �ҵ���������way��
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
                // ������way�����1
                way_age_way_0[index] <= hit_way==0 ? 0 : way_age_way_0[index] + 1;
                way_age_way_1[index] <= hit_way==1 ? 0 : way_age_way_1[index] + 1;
                way_age_way_2[index] <= hit_way==2 ? 0 : way_age_way_2[index] + 1;
                way_age_way_3[index] <= hit_way==3 ? 0 : way_age_way_3[index] + 1;

            end
        end
    end

    //���ݵ�ַ����λ��size������д���루���sb��sh�Ȳ���д����һ���ֵ�ָ���4λ��Ӧ1���֣�4�ֽڣ���ÿ���ֵ�дʹ��
    assign write_mask = cpu_data_size==2'b00 ?
                            (cpu_data_addr[1] ? (cpu_data_addr[0] ? 4'b1000 : 4'b0100):  // 1���ֽ�
                                                (cpu_data_addr[0] ? 4'b0010 : 4'b0001)) :
                            (cpu_data_size==2'b01 ? (cpu_data_addr[1] ? 4'b1100 : 4'b0011) : 4'b1111);  //2���ֽ�   ��   ȫ��
                            //cpu_data_size!=2'b00��2'b01ʱ��write_maskΪ4'b1111

    //�����ʹ�ã�λΪ1�Ĵ�����Ҫ���µġ�
    //λ��չ��{8{1'b1}} -> 8'b11111111
    //new_data = old_data & ~mask | write_data & mask
    assign write_cache_data = c_block & ~{{8{write_mask[3]}}, {8{write_mask[2]}}, {8{write_mask[1]}}, {8{write_mask[0]}}} | 
                              cpu_data_wdata & {{8{write_mask[3]}}, {8{write_mask[2]}}, {8{write_mask[1]}}, {8{write_mask[0]}}};

endmodule