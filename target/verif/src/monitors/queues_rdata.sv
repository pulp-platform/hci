/**
 * Queues Read Data Monitor
 *
 * Monitors read data from HCI interfaces and TCDM banks,
 * storing them in queues for verification.
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

module queues_rdata #(
  parameter int unsigned N_MASTER = 1,
  parameter int unsigned N_HWPE = 1,
  parameter int unsigned N_BANKS = 8,
  parameter int unsigned HWPE_WIDTH = 1,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADD_WIDTH = 32
) (
  hci_core_intf.target all_except_hwpe      [0:N_MASTER-N_HWPE-1],
  hci_core_intf.target hwpe_intc            [0:N_HWPE-1],
  hci_core_intf.target intc_mem_wiring      [0:N_BANKS-1],
  input logic          EMPTY_queue_out_read [0:N_BANKS-1],
  input logic          rst_n,
  input logic          clk
);

  logic flag_read_master[N_MASTER-N_HWPE];
  logic flag_read_hwpe[N_HWPE];
  logic flag_read[N_BANKS];

  // Use queues to collect variable-length sequences of read data
  logic [DATA_WIDTH-1:0]            log_rdata [N_MASTER-N_HWPE][$];
  logic [HWPE_WIDTH*DATA_WIDTH-1:0] hwpe_rdata [N_HWPE][$];
  logic [DATA_WIDTH-1:0]            mems_rdata [N_BANKS][$];

  // LOG branch: monitor read data from log masters
  generate
    for (genvar ii = 0; ii < N_MASTER - N_HWPE; ii++) begin : gen_queue_rdata_log_branch
      always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
          flag_read_master[ii] <= 0;
        end else if (all_except_hwpe[ii].req && all_except_hwpe[ii].wen && all_except_hwpe[ii].gnt) begin
          flag_read_master[ii] <= 1'b1;
        end else begin
          flag_read_master[ii] <= 0;
        end
      end

      initial begin : proc_add_queue_read_master
        wait (rst_n);
        while (1) begin
          @(posedge clk);
          if (all_except_hwpe[ii].r_valid && flag_read_master[ii]) begin
            log_rdata[ii].push_back(all_except_hwpe[ii].r_data);
          end
        end
      end
    end
  endgenerate

  // HWPE branch: monitor read data from HWPE masters
  generate
    for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_queue_rdata_hwpe_branch
      always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
          flag_read_hwpe[ii] <= 0;
        end else if (hwpe_intc[ii].req && hwpe_intc[ii].wen && hwpe_intc[ii].gnt) begin
          flag_read_hwpe[ii] <= 1'b1;
        end else begin
          flag_read_hwpe[ii] <= 0;
        end
      end

      initial begin : proc_add_queue_read_hwpe_master
        wait (rst_n);
        while (1) begin
          @(posedge clk);
          if (hwpe_intc[ii].r_valid && flag_read_hwpe[ii]) begin
            hwpe_rdata[ii].push_back(hwpe_intc[ii].r_data);
          end
        end
      end
    end
  endgenerate

  // TCDM side: monitor read data from memory banks
  generate
    for (genvar ii = 0; ii < N_BANKS; ii++) begin : gen_flag_read
      always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
          flag_read[ii] <= 0;
        end else if (intc_mem_wiring[ii].req && intc_mem_wiring[ii].gnt && intc_mem_wiring[ii].wen) begin
          flag_read[ii] <= 1'b1;
        end else begin
          flag_read[ii] <= 0;
        end
      end
    end
  endgenerate

  generate
    for (genvar ii = 0; ii < N_BANKS; ii++) begin : gen_queue_read_tcdm
      initial begin : proc_queue_read_tcdm
        wait (rst_n);
        while (1) begin
          @(posedge clk);
          if (intc_mem_wiring[ii].r_valid && flag_read[ii]) begin
            mems_rdata[ii].push_back(intc_mem_wiring[ii].r_data);
            wait (EMPTY_queue_out_read[ii]);
          end
        end
      end
    end
  endgenerate

endmodule