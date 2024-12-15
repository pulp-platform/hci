// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

/*
 * tcdm_banks_wrap.sv
 * Davide Rossi <davide.rossi@unibo.it>
 * Antonio Pullini <pullinia@iis.ee.ethz.ch>
 * Igor Loi <igor.loi@unibo.it>
 * Francesco Conti <fconti@iis.ee.ethz.ch>
 */

module tcdm_banks_wrap #(
  parameter int unsigned BankSize  = 256,         //- -> OVERRIDE
  parameter int unsigned NbBanks   = 1,           // --> OVERRIDE
  parameter int unsigned DataWidth = 32,
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned BeWidth   = DataWidth/8,
  parameter int unsigned IdWidth   = 1
) (
  input logic        clk_i,
  input logic        rst_ni,
  input logic        test_mode_i,

  hci_core_intf.target tcdm_slave[0:NbBanks-1]
);
   

  for(genvar i=0; i<NbBanks; i++) begin : banks_gen

    // r_id is same as request id -> Don't know if this is needed, but OBI protocol requires it
    logic [IdWidth-1:0] resp_id_d, resp_id_q;
    assign resp_id_d = tcdm_slave[i].id;
    assign tcdm_slave[i].r_id = resp_id_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin : proc_resp_id
      if(~rst_ni) begin
        resp_id_q <= '0;
      end else begin
        resp_id_q <= resp_id_d;
      end
    end


    
      if (`RANDOM_GNT == 1) begin
        // random generation of gnt signal
        always_ff @(posedge clk_i or negedge rst_ni) begin : gnt_gen
          if(~rst_ni) begin
            tcdm_slave[i].gnt    <=  1'b1;
          end else begin
            tcdm_slave[i].gnt <= $urandom;
          end
        end
      end else begin 
        //gnt signal assigned to 1
        assign tcdm_slave[i].gnt    =  1'b1;
      end



    tc_sram #(
      .NumWords   (BankSize ), // Number of Words in data array
      .DataWidth  (DataWidth), // Data signal width
      .ByteWidth  (8        ), // Width of a data byte
      .NumPorts   (1        ), // Number of read and write ports
      .Latency    (1        ), // Latency when the read data is available
      .SimInit    ("ones"   ), // Simulation initialization
      .PrintSimCfg(0        )  // Print configuration
    ) i_bank (
      .clk_i  (clk_i                                    ), // Clock
      .rst_ni (rst_ni                                   ), // Asynchronous reset active low
      
      .req_i  (tcdm_slave[i].req                        ), // request
      .we_i   (~tcdm_slave[i].wen                       ), // write enable
      .addr_i (tcdm_slave[i].add[$clog2(BankSize)+2-1:2]), // request address
      .wdata_i(tcdm_slave[i].data                       ), // write data
      .be_i   (tcdm_slave[i].be                         ), // write byte enable
      
      .rdata_o(tcdm_slave[i].r_data                     )  // read data
    );

    //r_valid
    /*initial begin : r_valid_gen
      tcdm_slave[i].r_valid = 1'b0;
      wait (rst_ni);
      loop: forever begin
        @(posedge clk_i);
        if(tcdm_slave[i].req && tcdm_slave[i].gnt && tcdm_slave[i].wen) begin
          $display("TIMEEEEEEE %0t, bank %0d, in the next cycle it will be generatd the valid signal", $time, i);
          @(posedge clk_i);
          tcdm_slave[i].r_valid = 1'b1;
          @(posedge clk_i);
          tcdm_slave[i].r_valid = 1'b0;
        end
      end
    end*/
    always_ff @(posedge clk_i or negedge rst_ni) begin : rvalid_gen
      if(~rst_ni) begin
        tcdm_slave[i].r_valid    <=  1'b0;
      end else begin
        if(tcdm_slave[i].req && tcdm_slave[i].gnt && tcdm_slave[i].wen) begin
          tcdm_slave[i].r_valid <= 1'b1;
        end else begin
          tcdm_slave[i].r_valid <= 1'b0;

      end
    end
    end

    //r_ready
    assign tcdm_slave[i].r_ready = 1'b1;
  end

endmodule

