module queues_stimuli 
  import verification_hci_package::stimuli;
  import verification_hci_package::create_address_and_data_hwpe;
#(
  parameter int unsigned N_MASTER = 1,
  parameter int unsigned N_HWPE = 1,
  parameter int unsigned HWPE_WIDTH = 1,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADD_WIDTH = 32
) (
  hci_core_intf.target all_except_hwpe [0:N_MASTER-N_HWPE-1],
  hci_core_intf.target hwpe_intc       [0:N_HWPE-1],
  input logic          rst_n,
  input logic          clk
);  

  stimuli queue_all_except_hwpe[N_MASTER-N_HWPE][$];
  stimuli queue_hwpe[N_HWPE*HWPE_WIDTH][$];
  logic   rolls_over_check[N_HWPE];

// Add CORES + DMA + EXT transactions to input queues
  generate
    for(genvar ii=0;ii<N_MASTER-N_HWPE;ii++) begin :  queue_stimuli_all_except_hwpe
      initial begin
        stimuli     in_except_hwpe;
        wait(rst_n);
        while(1) begin
          @(negedge clk);
          if(all_except_hwpe[ii].req) begin
            in_except_hwpe.wen  =   all_except_hwpe[ii].wen;
            in_except_hwpe.data =   all_except_hwpe[ii].data;
            in_except_hwpe.add  =   all_except_hwpe[ii].add;
            queue_all_except_hwpe[ii].push_back(in_except_hwpe);
            while(1) begin
              if(all_except_hwpe[ii].gnt) begin
                break;
              end
              @(negedge clk);
            end
          end
        end
      end
    end
  endgenerate

// Add HWPE transactions to input queues
  generate
    for(genvar ii=0;ii<N_HWPE;ii++) begin :  queue_stimuli_hwpe
      initial begin
        stimuli     in_hwpe;
        wait(rst_n);
        while(1) begin
          @(negedge clk);
          if(hwpe_intc[ii].req) begin
            rolls_over_check[ii] = 0;
            for(int i=0;i<HWPE_WIDTH;i++) begin
              in_hwpe.wen  =   hwpe_intc[ii].wen;
              create_address_and_data_hwpe(hwpe_intc[ii].add,hwpe_intc[ii].data,i,in_hwpe.add,in_hwpe.data,rolls_over_check[ii],rolls_over_check[ii]);
              queue_hwpe[i+ii*HWPE_WIDTH].push_back(in_hwpe);
            end
            while(1) begin
              if(hwpe_intc[ii].gnt) begin
                break;
              end
              @(negedge clk);
            end
          end
        end
      end
    end
  endgenerate
endmodule