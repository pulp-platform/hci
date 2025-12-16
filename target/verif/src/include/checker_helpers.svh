/**
 * Checker Helper Tasks
 *
 * Common helper tasks and constants used by write and read checker tasks.
 * This header is included by both write_checker_tasks.svh and read_checker_tasks.svh.
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

`ifndef CHECKER_HELPERS_SVH
`define CHECKER_HELPERS_SVH

/* Checker constants */
localparam int unsigned WRITE_EN = 1'b0;
localparam int unsigned READ_EN  = 1'b1;

/* Address manipulation task */
task automatic recreate_address(
  input  logic [tb_hci_pkg::AddrMemWidth-1:0] address_before,
  input  int bank,
  output logic [tb_hci_pkg::ADD_WIDTH-1:0] address_after
);
  logic [tb_hci_pkg::BIT_BANK_INDEX-1:0] bank_index;
  bank_index = bank;
  address_after = {address_before[tb_hci_pkg::AddrMemWidth-1:2], bank_index, address_before[1:0]};
endtask

/* HWPE coherency check task */
// Check if all HWPE ports have matching transactions across banks
// Returns skip=1 if any port/bank mismatch is found
task automatic check_hwpe(
  input  int unsigned hwpe_port_idx,
  input  int unsigned bank_idx,
  input  tb_hci_pkg::stimuli_t queue_stimuli_hwpe_base [tb_hci_pkg::N_HWPE*tb_hci_pkg::HWPE_WIDTH][$],
  input  int unsigned hwpe_base_idx,
  input  tb_hci_pkg::out_intc_to_mem_t queue_out_intc_to_mem [tb_hci_pkg::N_BANKS][$],
  output logic skip
);
  int signed port_idx_to_check;
  int signed bank_idx_to_check;
  tb_hci_pkg::stimuli_t recreated_queue;
  int unsigned queue_idx;

  skip = 0;
  for (int i = 1; i < tb_hci_pkg::HWPE_WIDTH; i++) begin
    port_idx_to_check = hwpe_port_idx + i;
    bank_idx_to_check = bank_idx + i;

    // Wrap port index within HWPE_WIDTH
    if (port_idx_to_check > tb_hci_pkg::HWPE_WIDTH - 1) begin
      port_idx_to_check -= tb_hci_pkg::HWPE_WIDTH;
      bank_idx_to_check -= tb_hci_pkg::HWPE_WIDTH;
    end

    // Wrap bank index within N_BANKS
    if (bank_idx_to_check >= int'(tb_hci_pkg::N_BANKS)) begin
      bank_idx_to_check -= tb_hci_pkg::N_BANKS;
    end
    if (bank_idx_to_check < 0) begin
      bank_idx_to_check += tb_hci_pkg::N_BANKS;
    end

    // Check if transaction matches expected stimulus
    if (queue_out_intc_to_mem[bank_idx_to_check].size() == 0) begin
      skip = 1;
      return;
    end

    recreate_address(
      queue_out_intc_to_mem[bank_idx_to_check][0].add,
      bank_idx_to_check,
      recreated_queue.add
    );
    recreated_queue.data = queue_out_intc_to_mem[bank_idx_to_check][0].data;

    // Calculate queue index: base + port index
    queue_idx = hwpe_base_idx + port_idx_to_check;
    if (queue_stimuli_hwpe_base[queue_idx].size() == 0 ||
        recreated_queue != queue_stimuli_hwpe_base[queue_idx][0]) begin
      skip = 1;
      return;
    end
  end
endtask

/* Error reporting tasks */

task automatic report_test_failure(input string message);
  $display("-----------------------------------------");
  $display("Time %0t:    Test ***FAILED***", $time);
  $display("%s", message);
  $finish();
endtask

task automatic report_transaction_mismatch(
  input int bank_id,
  input string transaction_type,
  input logic [tb_hci_pkg::DATA_WIDTH-1:0] data,
  input logic [tb_hci_pkg::ADD_WIDTH-1:0] address
);
  $display("-----------------------------------------");
  $display("Time %0t:    Test ***FAILED***", $time);
  $display("Bank %0d received the following %s transaction:", bank_id, transaction_type);
  $display("  data = %b, address = %b", data, address);
  $display("NO CORRESPONDENCE FOUND among the input queues");
  $display("POSSIBLE ERRORS:");
  $display("  -Incorrect data or address");
  $display("  -Incorrect order");
  $finish();
endtask

task automatic report_priority_violation(
  input string branch_name,
  input int master_id
);
  string message;
  if (branch_name == "LOG") begin
    $sformat(message, "The arbiter prioritized master_log_%0d in LOG branch, but it should have given priority to the HWPE branch", master_id);
  end else begin
    message = "The arbiter prioritized the HWPE branch, but it should have given priority to the LOG branch";
  end
  report_test_failure(message);
endtask

`endif // CHECKER_HELPERS_SVH
