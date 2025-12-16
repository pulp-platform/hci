/**
 * Queues Stimuli Monitor
 *
 * Monitors HCI interfaces and stores incoming transactions in queues
 * for later verification by the checker.
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

module queues_stimuli
  import tb_hci_pkg::stimuli_t;
  import tb_hci_pkg::create_address_and_data_hwpe;
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

  // Use SystemVerilog queues (dynamic) so we can call .push_back()/.size()
  stimuli_t queue_all_except_hwpe [N_MASTER-N_HWPE][$];
  stimuli_t queue_hwpe [N_HWPE*HWPE_WIDTH][$];
  logic   rolls_over_check[N_HWPE];

  // Add CORES + DMA + EXT transactions to input queues
  generate
    for (genvar ii = 0; ii < N_MASTER - N_HWPE; ii++) begin : gen_queue_stimuli_all_except_hwpe
      initial begin
        stimuli_t in_except_hwpe;
        wait (rst_n);
        while (1) begin
          @(negedge clk);
          if (all_except_hwpe[ii].req) begin
            in_except_hwpe.wen  = all_except_hwpe[ii].wen;
            in_except_hwpe.data = all_except_hwpe[ii].data;
            in_except_hwpe.add  = all_except_hwpe[ii].add;
            queue_all_except_hwpe[ii].push_back(in_except_hwpe);
            while (1) begin
              if (all_except_hwpe[ii].gnt) begin
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
    for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_queue_stimuli_hwpe
      initial begin
        stimuli_t in_hwpe;
        wait (rst_n);
        while (1) begin
          @(negedge clk);
          if (hwpe_intc[ii].req) begin
            rolls_over_check[ii] = 0;
            for (int i = 0; i < HWPE_WIDTH; i++) begin
              in_hwpe.wen = hwpe_intc[ii].wen;
              begin
                tb_hci_pkg::hwpe_addr_data_t _hwpe_res;
                _hwpe_res = create_address_and_data_hwpe(
                  hwpe_intc[ii].add,
                  hwpe_intc[ii].data,
                  i,
                  rolls_over_check[ii]
                );
                in_hwpe.add = _hwpe_res.address;
                in_hwpe.data = _hwpe_res.data;
                rolls_over_check[ii] = _hwpe_res.rolls_over;
                queue_hwpe[i + ii * HWPE_WIDTH].push_back(in_hwpe);
              end
            end
            while (1) begin
              if (hwpe_intc[ii].gnt) begin
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