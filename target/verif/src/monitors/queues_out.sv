/**
 * Queues Output Monitor
 *
 * Monitors transactions at TCDM bank interfaces and stores them
 * in queues for verification by the checker.
 *
 * Copyright (C) 2019-2020 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

module queues_out
  import tb_hci_pkg::out_intc_to_mem_t;
#(
  parameter int unsigned N_MASTER = 1,
  parameter int unsigned N_HWPE = 1,
  parameter int unsigned N_BANKS = 8,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned AddrMemWidth = 32
) (
  hci_core_intf.target all_except_hwpe [0:N_MASTER-N_HWPE-1],
  hci_core_intf.target hwpe_intc       [0:N_HWPE-1],
  hci_core_intf.target intc_mem_wiring [0:N_BANKS-1],
  input logic          rst_n,
  input logic          clk
);

  // Use queues so we can push_back and query size dynamically
  out_intc_to_mem_t queue_out_write [N_BANKS][$];
  out_intc_to_mem_t queue_out_read  [N_BANKS][$];

  // Add transactions received by each BANK to different output queues
  generate
    for (genvar ii = 0; ii < N_BANKS; ii++) begin : gen_queue_out_intc
      initial begin
        out_intc_to_mem_t out_intc_write;
        out_intc_to_mem_t out_intc_read;
        wait (rst_n);
        while (1) begin
          @(posedge clk);
          if (intc_mem_wiring[ii].req && intc_mem_wiring[ii].gnt) begin
            if (!intc_mem_wiring[ii].wen) begin
              // Write transaction
              out_intc_write.data = intc_mem_wiring[ii].data;
              out_intc_write.add  = intc_mem_wiring[ii].add;
              queue_out_write[ii].push_back(out_intc_write);
              wait (queue_out_write[ii].size() == 0);
            end else begin
              // Read transaction
              out_intc_read.data = intc_mem_wiring[ii].data;
              out_intc_read.add  = intc_mem_wiring[ii].add;
              queue_out_read[ii].push_back(out_intc_read);
              wait (queue_out_read[ii].size() == 0);
            end
          end
        end
      end
    end
  endgenerate

endmodule