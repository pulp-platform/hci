module queues_out 
    import verification_hci_package::out_intc_to_mem;
#(
    parameter int unsigned N_MASTER = 1,
    parameter int unsigned N_HWPE = 1,
    parameter int unsigned N_BANKS = 8,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned AddrMemWidth = 32
) (
    hci_core_intf.target           all_except_hwpe [0:N_MASTER-N_HWPE-1],
    hci_core_intf.target           hwpe_intc       [0:N_HWPE-1],
    hci_core_intf.target           intc_mem_wiring [0:N_BANKS-1],
    input logic                    rst_n,
    input logic                    clk
);  

  out_intc_to_mem                                 queue_out_write[N_BANKS][$];
  out_intc_to_mem                                 queue_out_read[N_BANKS][$];

  // Add transactions received by each BANK to different output queues
  generate
    for(genvar ii=0;ii<N_BANKS;ii++) begin: queue_out_intc_write
      initial begin
        out_intc_to_mem         out_intc_write;
        out_intc_to_mem         out_intc_read;
        wait (rst_n);
        while (1) begin
          @(posedge clk);
          if(intc_mem_wiring[ii].req && intc_mem_wiring[ii].gnt) begin
            if(!intc_mem_wiring[ii].wen) begin
              out_intc_write.data =   intc_mem_wiring[ii].data;
              out_intc_write.add  =   intc_mem_wiring[ii].add;
              queue_out_write[ii].push_back(out_intc_write);
              wait(queue_out_write[ii].size() == 0);
            end else begin
              out_intc_read.data =  intc_mem_wiring[ii].data;
              out_intc_read.add = intc_mem_wiring[ii].add;
              queue_out_read[ii].push_back(out_intc_read);
              wait(queue_out_read[ii].size() == 0);
              end
            end
          end
        end
      end
  endgenerate
endmodule