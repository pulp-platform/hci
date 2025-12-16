/**
 * Read Transaction Checker Tasks
 *
 * Helper tasks for validating read transactions and read data.
 * These tasks are included in tb_hci.sv and work with queue references.
 *
 * Copyright (C) 2019-2025 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

`include "checker_helpers.svh"

// Helper task: Check read transaction in LOG branch
task automatic check_read_in_log_branch(
  input  int bank_id,
  input  tb_hci_pkg::stimuli_t recreated_trans,
  // Use queues for variable-length collections
  ref    tb_hci_pkg::stimuli_t queue_all_except_hwpe [tb_hci_pkg::N_MASTER - tb_hci_pkg::N_HWPE][$],
  ref    tb_hci_pkg::out_intc_to_mem_t queue_out_read [tb_hci_pkg::N_BANKS][$],
  ref    logic [tb_hci_pkg::DATA_WIDTH-1:0] log_rdata [tb_hci_pkg::N_MASTER - tb_hci_pkg::N_HWPE][$],
  ref    logic [tb_hci_pkg::DATA_WIDTH-1:0] mems_rdata [tb_hci_pkg::N_BANKS][$],
  input  logic [tb_hci_pkg::N_BANKS-1:0] HIDE_LOG,
  output logic found,
  output logic data_match,
  output int master_id
);
  found = 0;
  data_match = 0;
  master_id = -1;

  for (int i = 0; i < tb_hci_pkg::N_MASTER - tb_hci_pkg::N_HWPE; i++) begin
    if (queue_all_except_hwpe[i].size() == 0) begin
      continue;
    end
    if (queue_all_except_hwpe[i][0].wen &&
      (recreated_trans == queue_all_except_hwpe[i][0])) begin
      found = 1;
      master_id = i;
      queue_out_read[bank_id].delete(0);
      queue_all_except_hwpe[i].delete(0);

      if (HIDE_LOG[bank_id]) begin
        report_priority_violation("LOG", i);
      end

      // Wait for read data and verify
      wait (log_rdata[i].size() != 0 && mems_rdata[bank_id].size() != 0);
      if (log_rdata[i][0] == mems_rdata[bank_id][0]) begin
        data_match = 1;
        mems_rdata[bank_id].delete(0);
        log_rdata[i].delete(0);
      end
      return;
    end
  end
endtask

// Helper task: Check read transaction in HWPE branch
task automatic check_read_in_hwpe_branch(
  input  int bank_id,
  input  tb_hci_pkg::stimuli_t recreated_trans,
  ref    tb_hci_pkg::stimuli_t queue_hwpe [tb_hci_pkg::N_HWPE * tb_hci_pkg::HWPE_WIDTH][$],
  ref    tb_hci_pkg::out_intc_to_mem_t queue_out_read [tb_hci_pkg::N_BANKS][$],
  ref    logic [tb_hci_pkg::HWPE_WIDTH * tb_hci_pkg::DATA_WIDTH - 1:0] hwpe_rdata [tb_hci_pkg::N_HWPE][$],
  ref    logic [tb_hci_pkg::DATA_WIDTH-1:0] mems_rdata [tb_hci_pkg::N_BANKS][$],
  input  logic [tb_hci_pkg::N_BANKS-1:0] HIDE_HWPE,
  ref    logic hwpe_read_checked[tb_hci_pkg::N_HWPE],
  ref    int unsigned hwpe_read_addr_count[tb_hci_pkg::N_HWPE],
  ref    int unsigned hwpe_read_data_count[tb_hci_pkg::N_HWPE],
  ref    logic warning,
  output logic found,
  output logic data_match,
  output logic skip_check,
  output int hwpe_id,
  output int port_id
);
  found = 0;
  data_match = 0;
  skip_check = 0;
  hwpe_id = -1;
  port_id = -1;

  for (int k = 0; k < tb_hci_pkg::N_HWPE; k++) begin
    for (int i = 0; i < tb_hci_pkg::HWPE_WIDTH; i++) begin
      int queue_idx = i + k * tb_hci_pkg::HWPE_WIDTH;
      if (queue_hwpe[queue_idx].size() == 0) begin
        continue;
      end
        if (queue_hwpe[queue_idx][0].wen &&
          (recreated_trans == queue_hwpe[queue_idx][0])) begin
        found = 1;
        hwpe_id = k;
        port_id = i;

        if (HIDE_HWPE[bank_id]) begin
          report_priority_violation("HWPE", -1);
        end

        // Check if all HWPE ports have matching transactions
        if (!hwpe_read_checked[k]) begin
          check_hwpe(
            i,
            bank_id,
            queue_hwpe,
            tb_hci_pkg::HWPE_WIDTH * k,
            queue_out_read,
            skip_check
          );
          hwpe_read_checked[k] = !skip_check;
        end

        if (!skip_check) begin
          hwpe_read_addr_count[k]++;
          // Clear address queue when all ports checked
          if (hwpe_read_addr_count[k] == tb_hci_pkg::HWPE_WIDTH) begin
            for (int j = 0; j < tb_hci_pkg::HWPE_WIDTH; j++) begin
              queue_hwpe[tb_hci_pkg::HWPE_WIDTH*k + j].delete(0);
            end
            hwpe_read_addr_count[k] = 0;
            hwpe_read_checked[k] = 0;
          end
          queue_out_read[bank_id].delete(0);

          // Wait for read data and verify
          wait (hwpe_rdata[k].size() != 0 && mems_rdata[bank_id].size() != 0);
            if (hwpe_rdata[k][0][i*tb_hci_pkg::DATA_WIDTH +: tb_hci_pkg::DATA_WIDTH] ==
              mems_rdata[bank_id][0]) begin
            data_match = 1;
            hwpe_read_data_count[k]++;
            mems_rdata[bank_id].delete(0);
            if (hwpe_read_data_count[k] == tb_hci_pkg::HWPE_WIDTH) begin
              hwpe_rdata[k].delete(0);
              hwpe_read_data_count[k] = 0;
            end
          end
        end else begin
          // Skip data check if HWPE transaction incomplete
          queue_out_read[bank_id].delete(0);
          wait (mems_rdata[bank_id].size() != 0);
          mems_rdata[bank_id].delete(0);
          warning = 1;
        end
        return;
      end
    end
  end
endtask

