module queues_rdata #(
    parameter int unsigned N_MASTER = 1,
    parameter int unsigned N_HWPE = 1,
    parameter int unsigned N_BANKS = 8,
    parameter int unsigned HWPE_WIDTH = 1,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned ADD_WIDTH = 32
) (
    hci_core_intf.target           all_except_hwpe [0:N_MASTER-N_HWPE-1],
    hci_core_intf.target           hwpe_intc       [0:N_HWPE-1],
    hci_core_intf.target           intc_mem_wiring [0:N_BANKS-1],
    input logic                    EMPTY_queue_out_read[0:N_BANKS-1],
    input logic                    rst_n,
    input logic                    clk
);  

  logic                                           flag_read_master[N_MASTER-N_HWPE];
  logic                                           flag_read_hwpe[N_HWPE];
  logic                                           flag_read[N_BANKS];

  logic [DATA_WIDTH-1:0]                          log_rdata[N_MASTER-N_HWPE][$];
  logic [HWPE_WIDTH*DATA_WIDTH-1:0]               hwpe_rdata[N_HWPE][$];
  logic [DATA_WIDTH-1:0]                          mems_rdata[N_BANKS][$];

  generate 
    //LOG branch
    for(genvar ii=0;ii<N_MASTER-N_HWPE;ii++) begin : queue_rdata_log_branch
      always_ff @(posedge clk or negedge rst_n)
      begin
        if (~rst_n)
          flag_read_master[ii] <= 0;
        else if (all_except_hwpe[ii].req && all_except_hwpe[ii].wen && all_except_hwpe[ii].gnt)
          flag_read_master[ii] <= 1'b1;
        else
          flag_read_master[ii] <= 0;
      end

      initial begin: add_queue_read_master 
        int index_hwpe, index_master;
        wait (rst_n);
        while(1) begin
          @(posedge clk);
          if(all_except_hwpe[ii].r_valid && flag_read_master[ii]) begin
            log_rdata[ii].push_back(all_except_hwpe[ii].r_data);
          end
        end
      end
    end
  endgenerate

  //HWPE branch
  generate
    for(genvar ii=0;ii<N_HWPE;ii++) begin : queue_rdata_hwpe_branch
      always_ff @(posedge clk or negedge rst_n)
      begin
        if (~rst_n)
          flag_read_hwpe[ii] <= 0;
        else if (hwpe_intc[ii].req && hwpe_intc[ii].wen && hwpe_intc[ii].gnt)
          flag_read_hwpe[ii] <= 1'b1;
        else
          flag_read_hwpe[ii] <= 0;
      end
      initial begin: add_queue_read_hwpe_master
      int index_hwpe, index_master;
        wait (rst_n);
        while(1) begin
          @(posedge clk);
          if(hwpe_intc[ii].r_valid && flag_read_hwpe[ii]) begin
            hwpe_rdata[ii].push_back(hwpe_intc[ii].r_data);
          end
        end
      end
    end
  endgenerate


  // Read transactions: Add r_data to a queue (TCDM side)
  generate
    for(genvar ii=0;ii<N_BANKS;ii++) begin: flag
      always_ff @(posedge clk or negedge rst_n)
      begin
        if (~rst_n)
          flag_read[ii] <= 0;
        else if (intc_mem_wiring[ii].req && intc_mem_wiring[ii].gnt && intc_mem_wiring[ii].wen)
          flag_read[ii] <= 1'b1;
        else
          flag_read[ii] <= 0;
      end
    end
  endgenerate 

  generate 
    for(genvar ii=0;ii<N_BANKS;ii++) begin: queue_read_tcdm 
      initial begin
        int index_hwpe, index_master;
        wait (rst_n);
        while(1) begin
          @(posedge clk);
          if(intc_mem_wiring[ii].r_valid && flag_read[ii]) begin
            mems_rdata[ii].push_back(intc_mem_wiring[ii].r_data);
            wait(EMPTY_queue_out_read[ii]);
          end
        end
      end
    end
  endgenerate
  endmodule