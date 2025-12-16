/**
 * Write Transaction Checker Tasks
 *
 * Helper tasks for validating write transactions.
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

// Helper task: Check write transaction in LOG branch
task automatic check_write_in_log_branch(
  input  int bank_id,
  input  tb_hci_pkg::stimuli_t recreated_trans,
  // queues are passed by reference; use dynamic-size queues
  ref    tb_hci_pkg::stimuli_t queue_all_except_hwpe [tb_hci_pkg::N_MASTER - tb_hci_pkg::N_HWPE][$],
  input  logic [tb_hci_pkg::N_BANKS-1:0] HIDE_LOG,
  output logic found,
  output int master_id
);
  found = 0;
  master_id = -1;
  for (int i = 0; i < tb_hci_pkg::N_MASTER - tb_hci_pkg::N_HWPE; i++) begin
    if (queue_all_except_hwpe[i].size() == 0) begin
      continue;
    end
    if (recreated_trans == queue_all_except_hwpe[i][0]) begin
      found = 1;
      master_id = i;
      queue_all_except_hwpe[i].delete(0);
      if (HIDE_LOG[bank_id]) begin
        report_priority_violation("LOG", i);
      end
      return;
    end
  end
endtask

// Helper task: Check write transaction in HWPE branch
task automatic check_write_in_hwpe_branch(
  input  int bank_id,
  input  tb_hci_pkg::stimuli_t recreated_trans,
  ref    tb_hci_pkg::stimuli_t queue_hwpe [tb_hci_pkg::N_HWPE * tb_hci_pkg::HWPE_WIDTH][$],
  ref    tb_hci_pkg::out_intc_to_mem_t queue_out_write [tb_hci_pkg::N_BANKS][$],
  input  logic [tb_hci_pkg::N_BANKS-1:0] HIDE_HWPE,
  ref    logic hwpe_write_checked[tb_hci_pkg::N_HWPE],
  ref    int unsigned hwpe_write_port_count[tb_hci_pkg::N_HWPE],
  ref    logic warning,
  output logic found,
  output int hwpe_id,
  output int port_id,
  output logic hwpe_incomplete
);
  found = 0;
  hwpe_id = -1;
  port_id = -1;
  hwpe_incomplete = 0;

  for (int k = 0; k < tb_hci_pkg::N_HWPE; k++) begin
    for (int i = 0; i < tb_hci_pkg::HWPE_WIDTH; i++) begin
      int queue_idx = i + k * tb_hci_pkg::HWPE_WIDTH;
      if (queue_hwpe[queue_idx].size() == 0) begin
        continue;
      end
      if (recreated_trans == queue_hwpe[queue_idx][0]) begin
        found = 1;
        hwpe_id = k;
        port_id = i;

        if (HIDE_HWPE[bank_id]) begin
          report_priority_violation("HWPE", -1);
        end

        if (!hwpe_write_checked[k]) begin
          logic skip_check;
          check_hwpe(
            i,
            bank_id,
            queue_hwpe,
            tb_hci_pkg::HWPE_WIDTH * k,
            queue_out_write,
            skip_check
          );
          hwpe_incomplete = skip_check;
          hwpe_write_checked[k] = 1;
        end

        if (!hwpe_incomplete) begin
          hwpe_write_port_count[k]++;
        end else begin
          warning = 1'b1;
        end
        return;
      end
    end
  end
endtask

// Helper task: Clear HWPE write queue when all ports checked
task automatic clear_hwpe_write_queue(
  input int hwpe_id,
  ref tb_hci_pkg::stimuli_t queue_hwpe [tb_hci_pkg::N_HWPE * tb_hci_pkg::HWPE_WIDTH][$],
  ref logic hwpe_write_checked[tb_hci_pkg::N_HWPE],
  ref int unsigned hwpe_write_port_count[tb_hci_pkg::N_HWPE]
);
  if (hwpe_write_port_count[hwpe_id] == tb_hci_pkg::HWPE_WIDTH) begin
    hwpe_write_port_count[hwpe_id] = 0;
    hwpe_write_checked[hwpe_id] = 0;
    for (int i = 0; i < tb_hci_pkg::HWPE_WIDTH; i++) begin
      queue_hwpe[i + hwpe_id * tb_hci_pkg::HWPE_WIDTH].delete(0);
    end
  end
endtask

