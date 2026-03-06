/*
 * address_checker.sv
 *
 * Copyright (C) 2026 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

/**
 * Address mapping checker
 *
 * Verifies that every memory-side req&gnt can be mapped to a master-side
 * grant using the word-interleaved address scheme.
 *
 * Addressing:
 *   - LOG masters produce exactly 1 bank access per grant.
 *     The comparison key is add[ADD_WIDTH-1:2] (word address including bank
 *     select bits; byte-offset bits [1:0] are stripped).
 *   - HWPE masters produce HWPE_WIDTH bank accesses per grant via hci_router.
 *     The per-lane address is computed with create_address_and_data_hwpe
 *     (same logic as the router), with rolls_over chained lane-to-lane.
 *   - Memory side: key = {bank_local_add[AddrMemWidth-1:2], bank_id}.
 *
 * Collection runs throughout simulation in an initial+forever block.
 * Comparison runs in a final block (after simulation_report calls $finish).
 *
 * Errors   – memory accessed a word-address that no master ever granted.
 * Duplicates – memory saw more accesses than masters granted for a word-address;
 *              this is expected for some HWPE workloads and is reported as INFO.
 * Per-master summary distinguishes LOG-originated from HWPE-originated
 * duplicates using a stored "is_hwpe" flag per word-address (first sender).
 */

module address_checker
  import tb_hci_pkg::create_address_and_data_hwpe,
         tb_hci_pkg::hwpe_addr_data_t;
#(
  parameter int unsigned N_LOG      = 3,
  parameter int unsigned N_HWPE     = 1,
  parameter int unsigned N_BANKS    = 16,
  parameter int unsigned ADD_WIDTH  = 20,
  parameter int unsigned HWPE_WIDTH = 4
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic run_i,
  output logic done_o,
  hci_core_intf.monitor hci_log_if  [0:N_LOG-1],
  hci_core_intf.monitor hci_hwpe_if [0:N_HWPE-1],
  hci_core_intf.monitor hci_mem_if  [0:N_BANKS-1]
);

  localparam int unsigned BIT_BANK_INDEX = $clog2(N_BANKS);
  localparam int unsigned AddrMemWidth   = ADD_WIDTH - BIT_BANK_INDEX;

  // -----------------------------------------------------------------------
  // Comparison key: word address (ADD_WIDTH-2 bits), stored in longint.
  //   bits [ADD_WIDTH-3 : BIT_BANK_INDEX-1] = word offset within bank
  //   bits [BIT_BANK_INDEX-1 : 0]           = bank select
  // LOG master:  key = add[ADD_WIDTH-1:2]
  // HWPE master: key = lane_addr[ADD_WIDTH-1:2]  (create_address_and_data_hwpe)
  // Memory bank b: key = {baddr[AddrMemWidth-1:2], b[BIT_BANK_INDEX-1:0]}
  // -----------------------------------------------------------------------

  // key_t is declared first so it can be used in array declarations below.
  typedef longint unsigned key_t;

  // master_count[key]  = # times this word-addr was granted by any master
  int unsigned master_count [key_t];
  // mem_count[key]     = # times this word-addr appeared at a bank interface
  int unsigned mem_count    [key_t];
  // master_who[key]    = human-readable label of the first master that sent key
  string       master_who   [key_t];
  // master_is_hwpe[key] = 1 if first sender was an HWPE master
  bit          master_is_hwpe [key_t];

  // -----------------------------------------------------------------------
  // Helper: reconstruct word-address key from bank ID and bank-local address.
  // -----------------------------------------------------------------------

  function automatic key_t word_key_from_bank(
    input int unsigned             bank_id,
    input logic [AddrMemWidth-1:0] baddr
  );
    // Reconstruct: {baddr[high:2], bank_id}  (drop byte-offset bits [1:0])
    key_t k;
    k = {baddr[AddrMemWidth-1:2], bank_id[BIT_BANK_INDEX-1:0]};
    return k;
  endfunction

  // -----------------------------------------------------------------------
  // Helper: add one entry to the master pool.
  // -----------------------------------------------------------------------
  task automatic pool_add(
    input key_t  key,
    input string           who,
    input bit              is_hwpe
  );
    if (!master_count.exists(key)) begin
      master_count[key]   = 0;
      master_who[key]     = who;
      master_is_hwpe[key] = is_hwpe;
    end else begin
      master_who[key] = {master_who[key], ", ", who};
    end
    master_count[key]++;
  endtask

  // -----------------------------------------------------------------------
  // Collection: sample every posedge after reset.
  // This initial block runs until $finish kills it; the final block below
  // reads the accumulated data after simulation ends.
  // -----------------------------------------------------------------------
  for (genvar i = 0; i < N_LOG; i++) begin : gen_collect_log
    initial begin : proc_collect_log
      key_t            key;
      hwpe_addr_data_t lane;
      logic            rolls_prev;

      wait (rst_ni === 1'b1);

      forever @(posedge clk_i) begin

        // --- LOG masters (1:1 mapping to one bank) ---
        if (hci_log_if[i].req === 1'b1 && hci_log_if[i].gnt === 1'b1) begin
          key = hci_log_if[i].add[ADD_WIDTH-1:2];
          pool_add(key, $sformatf("log_%0d", i), 1'b0);
        end

      end // forever
    end : proc_collect_log
  end : gen_collect_log

  for (genvar i = 0; i < N_HWPE; i++) begin : gen_collect_hwpe
    initial begin : proc_collect_hwpe
      key_t            key;
      hwpe_addr_data_t lane;
      logic            rolls_prev;

      wait (rst_ni === 1'b1);

      forever @(posedge clk_i) begin

        // --- HWPE masters (1:HWPE_WIDTH fan-out via hci_router) ---
        // Per-lane address is computed by create_address_and_data_hwpe,
        // which mirrors the router's word-interleaved bank-level address
        // generation (same wrap-around logic). rolls_over is chained so
        // that a wrap at lane j correctly increments the bank-local word
        // address for all subsequent lanes.
        if (hci_hwpe_if[i].req === 1'b1 && hci_hwpe_if[i].gnt === 1'b1) begin
          rolls_prev = 1'b0;
          for (int j = 0; j < HWPE_WIDTH; j++) begin
            lane = create_address_and_data_hwpe(
                hci_hwpe_if[i].add, '0, j, rolls_prev);
            rolls_prev = lane.rolls_over;
            key = lane.address[ADD_WIDTH-1:2];
            pool_add(key, $sformatf("hwpe_%0d", i), 1'b1);
          end
        end

      end // forever
    end : proc_collect_hwpe
  end : gen_collect_hwpe

  for (genvar b = 0; b < N_BANKS; b++) begin : gen_collect_mem
    initial begin : proc_collect_mem
      key_t            key;
      hwpe_addr_data_t lane;
      logic            rolls_prev;

      wait (rst_ni === 1'b1);

      forever @(posedge clk_i) begin

        // --- Memory banks: check against master pool ---
        if (hci_mem_if[b].req === 1'b1 && hci_mem_if[b].gnt === 1'b1) begin
          key = word_key_from_bank(b, hci_mem_if[b].add);
          if (!mem_count.exists(key))
            mem_count[key] = 0;
          mem_count[key]++;
        end

      end // forever
    end : proc_collect_mem
  end : gen_collect_mem

  // -----------------------------------------------------------------------
  // Report: triggered by simulation_report before $finish.
  // -----------------------------------------------------------------------
  initial begin : proc_check
    key_t            key;
    int unsigned n_unmapped, n_dup_total, n_unique_mem;
    int unsigned n_dup_log_accesses, n_dup_hwpe_accesses;
    int unsigned m_cnt, c_mem;

    done_o = 1'b0;
    wait (run_i === 1'b1);

    n_unmapped       = 0;
    n_dup_total      = 0;
    n_unique_mem     = 0;
    n_dup_log_accesses = 0;
    n_dup_hwpe_accesses = 0;

    $display("\n\\\\ADDRESS MAPPING CHECK\\\\");
    $display(
      "Checking that every memory-side access maps to a master-side grant.");
    $display(
      "Word-interleaved scheme: bank = add[%0d:%0d], HWPE grants fan out to %0d lanes.",
      BIT_BANK_INDEX + 1, 2, HWPE_WIDTH);

    foreach (mem_count[key]) begin
      n_unique_mem++;
      m_cnt = master_count.exists(key) ? master_count[key] : 0;
      c_mem = mem_count[key];

      if (m_cnt == 0) begin
        $error(
          "[address_checker] UNMAPPED: word-addr 0x%0h seen %0d time(s) at memory but never granted by any master",
          key, c_mem
        );
        n_unmapped += c_mem;
      end else if (c_mem > m_cnt) begin
        n_dup_total += c_mem - m_cnt;
        if (master_is_hwpe.exists(key) && master_is_hwpe[key]) begin
          n_dup_hwpe_accesses += c_mem - m_cnt;
        end else begin
          $warning(
            "[address_checker] DUPLICATE (LOG branch): word-addr 0x%0h (byte-addr 0x%0h) granted %0d time(s) by [%s] but seen %0d time(s) at memory -- bank %0d, bank-local addr 0x%0h (byte 0x%0h)",
            key, key << 2,
            m_cnt, master_who[key], c_mem,
            key[BIT_BANK_INDEX-1:0],
            key >> BIT_BANK_INDEX,
            (key >> BIT_BANK_INDEX) << 2
          );
          n_dup_log_accesses += c_mem - m_cnt;
        end
      end
    end

    $display(
      "[address_checker] Checked %0d unique word-addresses at memory side.",
      n_unique_mem);

    if (n_unmapped == 0) begin
      $display(
        "PASS: all memory-side accesses map to a master-side grant.");
    end else begin
      $error(
        "FAIL: %0d access(es) to word-addr(s) never granted by any master.",
        n_unmapped);
    end

    if (n_dup_total > 0) begin
      $display(
        "INFO: %0d duplicate access(es) (%0d from LOG masters, %0d from HWPE masters).",
        n_dup_total, n_dup_log_accesses, n_dup_hwpe_accesses);
    end else begin
      $display("INFO: no duplicate accesses detected.");
    end

    done_o = 1'b1;
  end : proc_check

endmodule
