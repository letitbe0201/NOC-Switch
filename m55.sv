// This is a memory model for the perm_blk
//

module m55(input clk, input rst, input reg [2:0] rx,input reg [2:0] ry, output reg [63:0] rd,
    input reg [2:0] wx,input reg [2:0] wy, input reg wr, input reg [63:0] wd);
    
    reg [4:0][4:0][63:0] mdata;
    
    always @(*) begin
        rd<=#1 mdata[ry][rx];
        //$monitor("rd changed now rd is in y=%d, x=%d, rd is %h, mdata is %h @%t", ry, rx, rd, mdata[ry][rx], $time);
    end
    always @(posedge(clk) or posedge(rst)) begin
        if(rst) begin
            mdata <= 64'hdeaddeaddeaddead;
        end else begin
            if(wr) begin
                mdata[wy][wx]<=#1 wd;
                //$monitor("Im writing wd in y=%d, x=%d, wd is %h @%t", wy, wx, wd, $time);
            end
        end
    end
endmodule : m55
