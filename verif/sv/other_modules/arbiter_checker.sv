module arbiter_checker 
import hci_package::hci_interconnect_ctrl_t;
import verification_hci_package::calculate_bank_index;
import verification_hci_package::create_address_and_data_hwpe;
#(
    parameter int unsigned ARBITER_MODE = 0,
    parameter int unsigned N_MASTER = 1,
    parameter int unsigned N_HWPE = 1,
    parameter int unsigned N_BANKS = 8,
    parameter int unsigned HWPE_WIDTH = 1,
    parameter int unsigned BIT_BANK_INDEX = 3,
    parameter int unsigned CLK_PERIOD = 50

) (
    output logic [N_BANKS-1:0]     HIDE_HWPE,
    output logic [N_BANKS-1:0]     HIDE_LOG,
    input  hci_interconnect_ctrl_t ctrl_i,
    input                          clk,
    input                          rst_n
);  

    logic [N_BANKS-1:0]                        LOG_REQ;
    logic [N_BANKS-1:0]                        HWPE_REQ;
    logic [N_BANKS-1:0][N_MASTER-N_HWPE-1:0]   LOG_REQ_EACH_MASTER = '{default: '0};
    logic [N_BANKS-1:0][N_HWPE-1:0]            HWPE_REQ_EACH_MASTER = '{default: '0};

    generate
      // Compute the requests for each bank
      for(genvar ii=0;ii<N_MASTER-N_HWPE;ii++) begin: req_per_bank_per_log_master
        logic [BIT_BANK_INDEX-1:0] bank_index_log;
        int unsigned bank_index_log_int;
        initial begin
                  $display("CHECK ARBITER!");
          wait(rst_n);
          while(1) begin
            wait(all_except_hwpe[ii].req)
              calculate_bank_index(all_except_hwpe[ii].add,bank_index_log);
              bank_index_log_int = int'(bank_index_log);
              LOG_REQ_EACH_MASTER[bank_index_log_int][ii] = 1'b1;
              #(CLK_PERIOD/100)
              while(1) begin
                @(posedge clk);
                if(all_except_hwpe[ii].gnt) begin
                  #(CLK_PERIOD/100)
                  LOG_REQ_EACH_MASTER[bank_index_log_int][ii] = 1'b0;
                  break;
                end
              end
          end
        end
      end

      for(genvar ii=0;ii<N_BANKS;ii++) begin
        assign LOG_REQ[ii] = |LOG_REQ_EACH_MASTER[ii];
      end

      for(genvar ii=0;ii<N_HWPE;ii++) begin: req_per_bank_per_hwpe_master
        logic [BIT_BANK_INDEX-1:0] bank_index_hwpe;
        int unsigned bank_index_hwpe_int;
        initial begin
          wait(rst_n);
          while(1) begin
            wait(hwpe_intc[ii].req);
              calculate_bank_index(hwpe_intc[ii].add,bank_index_hwpe);
              bank_index_hwpe_int = int'(bank_index_hwpe);
              for(int i=0;i<HWPE_WIDTH;i++) begin
                if(bank_index_hwpe_int + i >= N_BANKS) begin
                  HWPE_REQ_EACH_MASTER[bank_index_hwpe_int + i - N_BANKS][ii] = 1'b1; //rolls over
                end else begin 
                  HWPE_REQ_EACH_MASTER[bank_index_hwpe_int + i][ii] = 1'b1;
                end
              end
              #(CLK_PERIOD/100);
              while(1) begin
                @(posedge clk);
                if(hwpe_intc[ii].gnt) begin
                  #(CLK_PERIOD/100);
                  for(int i=0;i<HWPE_WIDTH;i++) begin
                    if(bank_index_hwpe_int + i >= N_BANKS) begin
                      HWPE_REQ_EACH_MASTER[bank_index_hwpe_int + i - N_BANKS][ii] = 1'b0; //rolls over
                    end else begin 
                      HWPE_REQ_EACH_MASTER[bank_index_hwpe_int + i][ii] = 1'b0;
                    end
                  end
                  break;
                end
              end
          end
        end
      end
      for(genvar ii=0;ii<N_BANKS;ii++) begin
        assign HWPE_REQ[ii] = |HWPE_REQ_EACH_MASTER[ii];
      end
    endgenerate

    logic [N_BANKS-1:0] CONFLICTS = '0;
    logic prior;

    generate 
    if(ARBITER_MODE == 1) begin
      // Check conflicts and the number of stalls
      initial begin : check_conflicts
        int stall;
        stall = 0;
        prior = ctrl_i.invert_prio;
        wait(rst_n);
        while(1) begin
          @(negedge clk);
          for(int i=0;i<N_BANKS;i++) begin
            CONFLICTS[i] = LOG_REQ[i] && HWPE_REQ[i];
          end
          stall = stall*|CONFLICTS + |CONFLICTS;
          if(prior == ctrl_i.invert_prio) begin
            if(stall == ctrl_i.low_prio_max_stall+1) begin
              prior = !prior;
              stall = 0;
            end
          end else begin
            prior = !prior;
            //stall = 0;
          end
        end
      end
    end
    if(ARBITER_MODE == 0) begin
      initial begin : check_conflicts
        int stall;
        stall = 0;
        prior = ctrl_i.invert_prio;
        wait(rst_n);
        while(1) begin
          @(negedge clk);
          for(int i=0;i<N_BANKS;i++) begin
            CONFLICTS[i] = LOG_REQ[i] && HWPE_REQ[i];
          end
          stall = stall*(|LOG_REQ && |HWPE_REQ) + (|LOG_REQ && |HWPE_REQ); // we improperly consider a stall when there is at least 1 req in both the high and low priority channel
          if(prior == ctrl_i.invert_prio) begin
            if(stall == ctrl_i.low_prio_max_stall+1) begin
              prior = !prior;
              stall = 0;
            end
          end else begin
            prior = !prior;
          end
        end
      end
    end

    //Hide low priority branch in case of conflicts
      always_comb begin : HIDE
        for(int i=0;i<N_BANKS;i++) begin
          if(!prior) begin
            HIDE_HWPE[i] = CONFLICTS[i];
            HIDE_LOG[i] = 0;
          end else begin
            HIDE_HWPE[i] = 0;
            HIDE_LOG[i] = CONFLICTS[i];
          end
        end
      end
    endgenerate

endmodule