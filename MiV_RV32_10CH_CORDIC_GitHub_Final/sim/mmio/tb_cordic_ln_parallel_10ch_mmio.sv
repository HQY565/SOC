`timescale 1ns/1ps
module tb_cordic_ln_parallel_10ch_mmio;
    localparam logic [31:0] BASE = 32'h6001_0000;
    logic clk = 0, resetn = 0;
    always #5 clk = ~clk;
    logic bus_valid = 0, bus_write = 0, bus_resp_ready = 0;
    logic [31:0] bus_addr = 0, bus_wdata = 0;
    wire bus_ready, bus_resp_valid, bus_error, busy, done_sticky;
    wire [31:0] bus_rdata;
    integer golden [0:9];
    logic [31:0] rdata;
    logic err;
    cordic_ln_parallel_10ch_mmio dut (
      .clk(clk), .resetn(resetn), .bus_valid(bus_valid),
      .bus_write(bus_write), .bus_addr(bus_addr), .bus_wdata(bus_wdata),
      .bus_ready(bus_ready), .bus_resp_valid(bus_resp_valid),
      .bus_resp_ready(bus_resp_ready), .bus_rdata(bus_rdata),
      .bus_error(bus_error), .busy(busy), .done_sticky(done_sticky)
    );
    task automatic transact(input bit wr,input logic [31:0] addr,
        input logic [31:0] data,output logic [31:0] result,output logic e);
      begin
        @(negedge clk);
        while (bus_ready !== 1'b1) @(negedge clk);
        bus_valid=1; bus_write=wr; bus_addr=addr; bus_wdata=data;
        @(posedge clk); #1;
        if (bus_resp_valid !== 1'b1) $fatal(1,"Missing MMIO response");
        result=bus_rdata; e=bus_error;
        @(negedge clk); bus_valid=0; bus_resp_ready=1;
        @(posedge clk); #1; bus_resp_ready=0;
      end
    endtask
    task automatic w(input logic [31:0] addr,input logic [31:0] data);
      logic [31:0] v; logic e;
      begin transact(1,addr,data,v,e);if (e) $fatal(1,"Bad write at %h",addr);end
    endtask
    task automatic r(input logic [31:0] addr,output logic [31:0] v);
      logic e;begin transact(0,addr,0,v,e);if(e)$fatal(1,"Bad read at %h",addr);end
    endtask
    initial begin
      repeat(4) @(negedge clk); resetn=1;
      w(BASE+0,2048);w(BASE+4,2560);w(BASE+8,3072);w(BASE+12,3584);
      w(BASE+16,4096);w(BASE+20,4608);w(BASE+24,5120);
      w(BASE+28,5632);w(BASE+32,6144);w(BASE+36,8192);
      golden[0]=-2839;golden[1]=-1925;golden[2]=-1178;golden[3]=-547;
      golden[4]=0;golden[5]=482;golden[6]=914;golden[7]=1304;
      golden[8]=1661;golden[9]=2839;
      w(BASE+32'h80,1);
      begin: poll
        for(int i=0;i<80;i++) begin
          r(BASE+32'h84,rdata);
          if(rdata[0]) disable poll;
        end
        $fatal(1,"LN MMIO timeout");
      end
      r(BASE+32'h88,rdata);
      if(rdata!==0) $fatal(1,"Bad invalid bitmap");
      for(int ch=0;ch<10;ch++) begin
        integer got;
        r(BASE+32'h100+4*ch,rdata); got=$signed(rdata);
        if(got<golden[ch]-3||got>golden[ch]+3)
          $fatal(1,"LN CH%0d got %0d expected %0d",ch,got,golden[ch]);
      end
      $display("ALL 10CH FULL LN MMIO TESTS PASSED");
      $finish;
    end
    initial begin #10000;$fatal(1,"MMIO timeout");end
endmodule
