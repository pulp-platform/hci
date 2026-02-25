/*
 * simulation_report.sv
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
 * Simulation report
 * Collects and prints verification summary metrics.
 */

module simulation_report
  import tb_hci_pkg::*;
(
  input logic [0:N_MASTER-1] end_stimuli_i,
  input logic [0:N_MASTER-1] end_latency_i,
  input real                 throughput_complete_i,
  input real                 stim_latency_i,
  input real                 tot_latency_i,
  input real                 latency_per_master_i[N_MASTER],
  input real                 sum_req_to_gnt_latency_log_i[N_MASTER-N_HWPE],
  input real                 sum_req_to_gnt_latency_hwpe_i[N_HWPE],
  input int unsigned         n_gnt_transactions_log_i[N_MASTER-N_HWPE],
  input int unsigned         n_gnt_transactions_hwpe_i[N_HWPE],
  input int unsigned         n_read_granted_transactions_log_i[N_MASTER-N_HWPE],
  input int unsigned         n_read_granted_transactions_hwpe_i[N_HWPE],
  input int unsigned         n_write_granted_transactions_log_i[N_MASTER-N_HWPE],
  input int unsigned         n_write_granted_transactions_hwpe_i[N_HWPE],
  input int unsigned         n_read_complete_transactions_log_i[N_MASTER-N_HWPE],
  input int unsigned         n_read_complete_transactions_hwpe_i[N_HWPE]
);

  initial begin : proc_simulation_report
    real sum_req_to_gnt_latency_all;
    real average_req_to_gnt_latency_weighted;
    real average_req_to_gnt_latency_unweighted;
    real sum_req_to_gnt_latency_log_all;
    real sum_req_to_gnt_latency_hwpe_all;
    real average_req_to_gnt_latency_log_weighted;
    real average_req_to_gnt_latency_hwpe_weighted;
    real average_req_to_gnt_latency_log_unweighted;
    real average_req_to_gnt_latency_hwpe_unweighted;
    int unsigned expected_reads;
    int unsigned observed_reads;
    int unsigned total_read_granted_transactions;
    int unsigned total_write_granted_transactions;
    int unsigned total_read_complete_transactions;
    int unsigned total_gnt_transactions_all;
    int unsigned total_gnt_transactions_log_all;
    int unsigned total_gnt_transactions_hwpe_all;
    int unsigned masters_with_grants;
    int unsigned log_masters_with_grants;
    int unsigned hwpe_masters_with_grants;
    logic missing_reads;

    sum_req_to_gnt_latency_all = 0.0;
    average_req_to_gnt_latency_weighted = 0.0;
    average_req_to_gnt_latency_unweighted = 0.0;
    sum_req_to_gnt_latency_log_all = 0.0;
    sum_req_to_gnt_latency_hwpe_all = 0.0;
    average_req_to_gnt_latency_log_weighted = 0.0;
    average_req_to_gnt_latency_hwpe_weighted = 0.0;
    average_req_to_gnt_latency_log_unweighted = 0.0;
    average_req_to_gnt_latency_hwpe_unweighted = 0.0;
    total_read_granted_transactions = '0;
    total_write_granted_transactions = '0;
    total_read_complete_transactions = '0;
    total_gnt_transactions_all = '0;
    total_gnt_transactions_log_all = '0;
    total_gnt_transactions_hwpe_all = '0;
    masters_with_grants = '0;
    log_masters_with_grants = '0;
    hwpe_masters_with_grants = '0;
    missing_reads = 1'b0;

    wait (&end_stimuli_i);
    wait (stim_latency_i >= 0);
    wait (&end_latency_i);
    wait (throughput_complete_i >= 0);
    wait (tot_latency_i >= 0);
    for (int i = 0; i < N_CORE_REAL; i++) begin
      total_read_granted_transactions += n_read_granted_transactions_log_i[i];
      total_write_granted_transactions += n_write_granted_transactions_log_i[i];
      total_read_complete_transactions += n_read_complete_transactions_log_i[i];
      if (n_gnt_transactions_log_i[i] != 0) begin
        sum_req_to_gnt_latency_all += sum_req_to_gnt_latency_log_i[i];
        total_gnt_transactions_all += n_gnt_transactions_log_i[i];
        average_req_to_gnt_latency_unweighted +=
            sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i]);
        masters_with_grants++;

        sum_req_to_gnt_latency_log_all += sum_req_to_gnt_latency_log_i[i];
        total_gnt_transactions_log_all += n_gnt_transactions_log_i[i];
        average_req_to_gnt_latency_log_unweighted +=
            sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i]);
        log_masters_with_grants++;
      end
    end
    for (int i = N_CORE; i < N_CORE + N_DMA_REAL; i++) begin
      total_read_granted_transactions += n_read_granted_transactions_log_i[i];
      total_write_granted_transactions += n_write_granted_transactions_log_i[i];
      total_read_complete_transactions += n_read_complete_transactions_log_i[i];
      if (n_gnt_transactions_log_i[i] != 0) begin
        sum_req_to_gnt_latency_all += sum_req_to_gnt_latency_log_i[i];
        total_gnt_transactions_all += n_gnt_transactions_log_i[i];
        average_req_to_gnt_latency_unweighted +=
            sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i]);
        masters_with_grants++;

        sum_req_to_gnt_latency_log_all += sum_req_to_gnt_latency_log_i[i];
        total_gnt_transactions_log_all += n_gnt_transactions_log_i[i];
        average_req_to_gnt_latency_log_unweighted +=
            sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i]);
        log_masters_with_grants++;
      end
    end
    for (int i = N_CORE + N_DMA; i < N_CORE + N_DMA + N_EXT_REAL; i++) begin
      total_read_granted_transactions += n_read_granted_transactions_log_i[i];
      total_write_granted_transactions += n_write_granted_transactions_log_i[i];
      total_read_complete_transactions += n_read_complete_transactions_log_i[i];
      if (n_gnt_transactions_log_i[i] != 0) begin
        sum_req_to_gnt_latency_all += sum_req_to_gnt_latency_log_i[i];
        total_gnt_transactions_all += n_gnt_transactions_log_i[i];
        average_req_to_gnt_latency_unweighted +=
            sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i]);
        masters_with_grants++;

        sum_req_to_gnt_latency_log_all += sum_req_to_gnt_latency_log_i[i];
        total_gnt_transactions_log_all += n_gnt_transactions_log_i[i];
        average_req_to_gnt_latency_log_unweighted +=
            sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i]);
        log_masters_with_grants++;
      end
    end
    for (int i = 0; i < N_HWPE_REAL; i++) begin
      total_read_granted_transactions += n_read_granted_transactions_hwpe_i[i];
      total_write_granted_transactions += n_write_granted_transactions_hwpe_i[i];
      total_read_complete_transactions += n_read_complete_transactions_hwpe_i[i];
      if (n_gnt_transactions_hwpe_i[i] != 0) begin
        sum_req_to_gnt_latency_all += sum_req_to_gnt_latency_hwpe_i[i];
        total_gnt_transactions_all += n_gnt_transactions_hwpe_i[i];
        average_req_to_gnt_latency_unweighted +=
            sum_req_to_gnt_latency_hwpe_i[i] / real'(n_gnt_transactions_hwpe_i[i]);
        masters_with_grants++;

        sum_req_to_gnt_latency_hwpe_all += sum_req_to_gnt_latency_hwpe_i[i];
        total_gnt_transactions_hwpe_all += n_gnt_transactions_hwpe_i[i];
        average_req_to_gnt_latency_hwpe_unweighted +=
            sum_req_to_gnt_latency_hwpe_i[i] / real'(n_gnt_transactions_hwpe_i[i]);
        hwpe_masters_with_grants++;
      end
    end

    if (total_gnt_transactions_all != 0) begin
      average_req_to_gnt_latency_weighted =
          sum_req_to_gnt_latency_all / real'(total_gnt_transactions_all);
    end
    if (total_gnt_transactions_log_all != 0) begin
      average_req_to_gnt_latency_log_weighted =
          sum_req_to_gnt_latency_log_all / real'(total_gnt_transactions_log_all);
    end
    if (total_gnt_transactions_hwpe_all != 0) begin
      average_req_to_gnt_latency_hwpe_weighted =
          sum_req_to_gnt_latency_hwpe_all / real'(total_gnt_transactions_hwpe_all);
    end
    if (masters_with_grants != 0) begin
      average_req_to_gnt_latency_unweighted =
          average_req_to_gnt_latency_unweighted / real'(masters_with_grants);
    end
    if (log_masters_with_grants != 0) begin
      average_req_to_gnt_latency_log_unweighted =
          average_req_to_gnt_latency_log_unweighted / real'(log_masters_with_grants);
    end
    if (hwpe_masters_with_grants != 0) begin
      average_req_to_gnt_latency_hwpe_unweighted =
          average_req_to_gnt_latency_hwpe_unweighted / real'(hwpe_masters_with_grants);
    end

    $display("------ Simulation Summary ------");
    $display("\\\\HW CONFIG\\\\");
    $display(
      "Masters: CORE=%0d DMA=%0d EXT=%0d HWPE=%0d (total=%0d)",
      N_CORE_REAL, N_DMA_REAL, N_EXT_REAL, N_HWPE_REAL, N_MASTER_REAL
    );
    $display(
      "Memory: banks=%0d total_size=%0d kB data_width=%0d bits hwpe_width=%0d lanes",
      N_BANKS, TOT_MEM_SIZE, DATA_WIDTH, HWPE_WIDTH
    );
    $display(
      "Interconnect: SEL_LIC=%0d TS_BIT=%0d EXPFIFO=%0d",
      SEL_LIC, TS_BIT, EXPFIFO
    );
    $display(
      "ID/address: IW=%0d ADD_WIDTH=%0d AddrMemWidth=%0d",
      IW, ADD_WIDTH, AddrMemWidth
    );

    $display("\n\\\\BANDWIDTH\\\\");
    $display(
      "Completion bandwidth (writes granted + reads completed): %0.1f bit/cycle",
      throughput_complete_i
    );
    $display("Stimulus phase duration: %0.1f cycles", stim_latency_i);
    $display("Completion phase duration: %0.1f cycles", tot_latency_i);
    $display(
      "Granted transactions: reads=%0d writes=%0d total=%0d",
      total_read_granted_transactions,
      total_write_granted_transactions,
      total_read_granted_transactions + total_write_granted_transactions
    );
    $display(
      "Read-complete responses: %0d",
      total_read_complete_transactions
    );

    $display("\n\\\\SIMULATION TIME\\\\");
    $display("Total simulation time: %0.1f cycles", tot_latency_i);
    for (int i = 0; i < N_CORE_REAL; i++) begin
      $display(
        "Core%0d (master_log_%0d): %0.1f cycles",
        i, i, latency_per_master_i[i]
      );
    end
    for (int i = N_CORE; i < N_CORE + N_DMA_REAL; i++) begin
      $display(
        "DMA%0d (master_log_%0d): %0.1f cycles",
        i - N_CORE, i, latency_per_master_i[i]
      );
    end
    for (int i = N_CORE + N_DMA; i < N_CORE + N_DMA + N_EXT_REAL; i++) begin
      $display(
        "EXT%0d (master_log_%0d): %0.1f cycles",
        i - (N_CORE + N_DMA), i, latency_per_master_i[i]
      );
    end
    for (int i = N_MASTER - N_HWPE; i < N_MASTER - N_HWPE + N_HWPE_REAL; i++) begin
      $display(
        "HWPE%0d (master_hwpe_%0d): %0.1f cycles",
        i - (N_MASTER - N_HWPE),
        i - (N_MASTER - N_HWPE),
        latency_per_master_i[i]
      );
    end

    $display("\n\\\\READ RESPONSE COVERAGE\\\\");
    for (int i = 0; i < N_CORE_REAL; i++) begin
      expected_reads = n_read_granted_transactions_log_i[i];
      observed_reads = n_read_complete_transactions_log_i[i];
      $display(
        "master_log_%0d: observed %0d / expected %0d",
        i, observed_reads, expected_reads
      );
      if (observed_reads != expected_reads) begin
        missing_reads = 1'b1;
      end
    end
    for (int i = N_CORE; i < N_CORE + N_DMA_REAL; i++) begin
      expected_reads = n_read_granted_transactions_log_i[i];
      observed_reads = n_read_complete_transactions_log_i[i];
      $display(
        "master_log_%0d: observed %0d / expected %0d",
        i, observed_reads, expected_reads
      );
      if (observed_reads != expected_reads) begin
        missing_reads = 1'b1;
      end
    end
    for (int i = N_CORE + N_DMA; i < N_CORE + N_DMA + N_EXT_REAL; i++) begin
      expected_reads = n_read_granted_transactions_log_i[i];
      observed_reads = n_read_complete_transactions_log_i[i];
      $display(
        "master_log_%0d: observed %0d / expected %0d",
        i, observed_reads, expected_reads
      );
      if (observed_reads != expected_reads) begin
        missing_reads = 1'b1;
      end
    end
    for (int i = 0; i < N_HWPE_REAL; i++) begin
      expected_reads = n_read_granted_transactions_hwpe_i[i];
      observed_reads = n_read_complete_transactions_hwpe_i[i];
      $display(
        "master_hwpe_%0d: observed %0d / expected %0d",
        i, observed_reads, expected_reads
      );
      if (observed_reads != expected_reads) begin
        missing_reads = 1'b1;
      end
    end
    if (missing_reads) begin
      $display("** WARNING **: one or more masters have incomplete read-response counts.");
    end

    $display("\n\\\\TRANSACTION COUNTS\\\\");
    for (int i = 0; i < N_CORE_REAL; i++) begin
      $display(
        "master_log_%0d: granted reads=%0d writes=%0d, read-complete=%0d",
        i,
        n_read_granted_transactions_log_i[i],
        n_write_granted_transactions_log_i[i],
        n_read_complete_transactions_log_i[i]
      );
    end
    for (int i = N_CORE; i < N_CORE + N_DMA_REAL; i++) begin
      $display(
        "master_log_%0d: granted reads=%0d writes=%0d, read-complete=%0d",
        i,
        n_read_granted_transactions_log_i[i],
        n_write_granted_transactions_log_i[i],
        n_read_complete_transactions_log_i[i]
      );
    end
    for (int i = N_CORE + N_DMA; i < N_CORE + N_DMA + N_EXT_REAL; i++) begin
      $display(
        "master_log_%0d: granted reads=%0d writes=%0d, read-complete=%0d",
        i,
        n_read_granted_transactions_log_i[i],
        n_write_granted_transactions_log_i[i],
        n_read_complete_transactions_log_i[i]
      );
    end
    for (int i = 0; i < N_HWPE_REAL; i++) begin
      $display(
        "master_hwpe_%0d: granted reads=%0d writes=%0d, read-complete=%0d",
        i,
        n_read_granted_transactions_hwpe_i[i],
        n_write_granted_transactions_hwpe_i[i],
        n_read_complete_transactions_hwpe_i[i]
      );
    end

    $display("\n\\\\REQUEST-TO-GRANT LATENCY\\\\");
    for (int i = 0; i < N_CORE_REAL; i++) begin
      $display(
        "master_log_%0d: avg req->gnt latency %0.1f cycles over %0d grants",
        i,
        (n_gnt_transactions_log_i[i] != 0) ?
            (sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i])) :
            0.0,
        n_gnt_transactions_log_i[i]
      );
    end
    for (int i = N_CORE; i < N_CORE + N_DMA_REAL; i++) begin
      $display(
        "master_log_%0d: avg req->gnt latency %0.1f cycles over %0d grants",
        i,
        (n_gnt_transactions_log_i[i] != 0) ?
            (sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i])) :
            0.0,
        n_gnt_transactions_log_i[i]
      );
    end
    for (int i = N_CORE + N_DMA; i < N_CORE + N_DMA + N_EXT_REAL; i++) begin
      $display(
        "master_log_%0d: avg req->gnt latency %0.1f cycles over %0d grants",
        i,
        (n_gnt_transactions_log_i[i] != 0) ?
            (sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i])) :
            0.0,
        n_gnt_transactions_log_i[i]
      );
    end
    for (int i = 0; i < N_HWPE_REAL; i++) begin
      $display(
        "master_hwpe_%0d: avg req->gnt latency %0.1f cycles over %0d grants",
        i,
        (n_gnt_transactions_hwpe_i[i] != 0) ?
            (sum_req_to_gnt_latency_hwpe_i[i] / real'(n_gnt_transactions_hwpe_i[i])) :
            0.0,
        n_gnt_transactions_hwpe_i[i]
      );
    end
    $display("");
    $display(
      "Total accumulated req->gnt latency: %0.1f cycles over %0d grants",
      sum_req_to_gnt_latency_all,
      total_gnt_transactions_all
    );
    $display(
      "LOG avg req->gnt latency (weighted by grant count): %0.1f cycles",
      average_req_to_gnt_latency_log_weighted
    );
    $display(
      "LOG avg req->gnt latency (mean of per-master averages): %0.1f cycles",
      average_req_to_gnt_latency_log_unweighted
    );
    $display(
      "HWPE avg req->gnt latency (weighted by grant count): %0.1f cycles",
      average_req_to_gnt_latency_hwpe_weighted
    );
    $display(
      "HWPE avg req->gnt latency (mean of per-master averages): %0.1f cycles",
      average_req_to_gnt_latency_hwpe_unweighted
    );
    $display(
      "Global avg req->gnt latency (weighted by grant count): %0.1f cycles",
      average_req_to_gnt_latency_weighted
    );
    $display(
      "Global avg req->gnt latency (mean of per-master averages): %0.1f cycles",
      average_req_to_gnt_latency_unweighted
    );
    $display("");

    $finish();
  end

endmodule
