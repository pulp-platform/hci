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
  input logic [N_DRIVERS-1:0] end_resp_i,
  input real                  throughput_complete_i,
  input real                  tot_latency_i,
  input real                 latency_per_master_i[N_DRIVERS],
  input real                 sum_req_to_gnt_latency_log_i[N_DRIVERS-N_HWPE],
  input real                 sum_req_to_gnt_latency_hwpe_i[N_HWPE],
  input int unsigned         n_gnt_transactions_log_i[N_DRIVERS-N_HWPE],
  input int unsigned         n_gnt_transactions_hwpe_i[N_HWPE],
  input int unsigned         n_read_granted_transactions_log_i[N_DRIVERS-N_HWPE],
  input int unsigned         n_read_granted_transactions_hwpe_i[N_HWPE],
  input int unsigned         n_write_granted_transactions_log_i[N_DRIVERS-N_HWPE],
  input int unsigned         n_write_granted_transactions_hwpe_i[N_HWPE],
  input int unsigned         n_read_complete_transactions_log_i[N_DRIVERS-N_HWPE],
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
    // Ideal bandwidth: maximum data the memory system can serve per cycle.
    // Memory side: N_BANKS narrow ports, each DATA_WIDTH bits wide.
    real ideal_bw_mem_side_bpc;    // bits per cycle (memory-side ceiling)
    // Master side: sum of all master bandwidths at 100% traffic.
    real ideal_bw_master_side_bpc; // bits per cycle (master-side ceiling)
    real ideal_bw_bpc;             // min(mem, master) = bottleneck ideal BW
    real actual_bw_utilization;    // throughput_complete / ideal_bw

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

    wait (&end_resp_i);
    wait (throughput_complete_i >= 0);
    wait (tot_latency_i >= 0);
    for (int i = 0; i < N_CORE; i++) begin
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
    for (int i = N_CORE; i < N_CORE + N_DMA; i++) begin
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
    for (int i = N_CORE + N_DMA; i < N_CORE + N_DMA + N_EXT; i++) begin
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
    for (int i = 0; i < N_HWPE; i++) begin
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

    // Ideal bandwidth computation.
    // Memory side: each of the N_BANKS banks can serve one DATA_WIDTH word per cycle.
    ideal_bw_mem_side_bpc = real'(N_BANKS) * real'(DATA_WIDTH);
    // Master side: N_LOG_MASTERS narrow ports + N_HWPE wide ports, all at 100% traffic.
    ideal_bw_master_side_bpc = real'(N_LOG_MASTERS) * real'(DATA_WIDTH)
                             + real'(N_HWPE)         * real'(HWPE_WIDTH_FACT * DATA_WIDTH);
    // Bottleneck = minimum of the two sides.
    ideal_bw_bpc = (ideal_bw_mem_side_bpc < ideal_bw_master_side_bpc)
                 ? ideal_bw_mem_side_bpc : ideal_bw_master_side_bpc;
    // Utilization = actual / ideal.
    actual_bw_utilization = (ideal_bw_bpc > 0.0)
                          ? (throughput_complete_i / ideal_bw_bpc * 100.0) : 0.0;

    $display("------ Simulation Summary ------");
    $display("\\\\HW CONFIG\\\\");
    $display(
      "Masters: CORE=%0d DMA=%0d EXT=%0d HWPE=%0d (total=%0d)",
      N_CORE, N_DMA, N_EXT, N_HWPE, N_DRIVERS
    );
    $display(
      "Memory: banks=%0d total_size=%0d kB data_width=%0d bits hwpe_width=%0d lanes",
      N_BANKS, TOT_MEM_SIZE, DATA_WIDTH, HWPE_WIDTH_FACT
    );
    $display(
      "Interconnect: SEL_LIC=%0d TS_BIT=%0d EXPFIFO=%0d",
      SEL_LIC, TS_BIT, EXPFIFO
    );
    $display(
      "ID/address: IW=%0d ADDR_WIDTH=%0d ADDR_WIDTH_BANK=%0d",
      IW, ADDR_WIDTH, ADDR_WIDTH_BANK
    );

    $display("\n\\\\BANDWIDTH\\\\");
    $display(
      "Ideal BW (memory side):  %0.0f bit/cycle  [%0d banks x %0d bits]",
      ideal_bw_mem_side_bpc, N_BANKS, DATA_WIDTH
    );
    $display(
      "Ideal BW (master side):  %0.0f bit/cycle  [%0d log x %0d bits + %0d hwpe x %0d bits]",
      ideal_bw_master_side_bpc,
      N_LOG_MASTERS, DATA_WIDTH,
      N_HWPE, HWPE_WIDTH_FACT * DATA_WIDTH
    );
    $display(
      "Ideal BW (bottleneck):   %0.0f bit/cycle",
      ideal_bw_bpc
    );
    $display(
      "Actual BW (completion):  %0.2f bit/cycle  [utilization: %0.1f%%]",
      throughput_complete_i, actual_bw_utilization
    );
    $display("Completion phase duration: %0.2f cycles", tot_latency_i);
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
    $display("Total simulation time: %0.2f cycles", tot_latency_i);
    for (int i = 0; i < N_CORE; i++) begin
      $display(
        "Core%0d (master_log_%0d): %0.2f cycles",
        i, i, latency_per_master_i[i]
      );
    end
    for (int i = N_CORE; i < N_CORE + N_DMA; i++) begin
      $display(
        "DMA%0d (master_log_%0d): %0.2f cycles",
        i - N_CORE, i, latency_per_master_i[i]
      );
    end
    for (int i = N_CORE + N_DMA; i < N_CORE + N_DMA + N_EXT; i++) begin
      $display(
        "EXT%0d (master_log_%0d): %0.2f cycles",
        i - (N_CORE + N_DMA), i, latency_per_master_i[i]
      );
    end
    for (int i = N_DRIVERS - N_HWPE; i < N_DRIVERS - N_HWPE + N_HWPE; i++) begin
      $display(
        "HWPE%0d (master_hwpe_%0d): %0.2f cycles",
        i - (N_DRIVERS - N_HWPE),
        i - (N_DRIVERS - N_HWPE),
        latency_per_master_i[i]
      );
    end

    $display("\n\\\\READ RESPONSE COVERAGE\\\\");
    for (int i = 0; i < N_CORE; i++) begin
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
    for (int i = N_CORE; i < N_CORE + N_DMA; i++) begin
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
    for (int i = N_CORE + N_DMA; i < N_CORE + N_DMA + N_EXT; i++) begin
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
    for (int i = 0; i < N_HWPE; i++) begin
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
    for (int i = 0; i < N_CORE; i++) begin
      $display(
        "master_log_%0d: granted reads=%0d writes=%0d, read-complete=%0d",
        i,
        n_read_granted_transactions_log_i[i],
        n_write_granted_transactions_log_i[i],
        n_read_complete_transactions_log_i[i]
      );
    end
    for (int i = N_CORE; i < N_CORE + N_DMA; i++) begin
      $display(
        "master_log_%0d: granted reads=%0d writes=%0d, read-complete=%0d",
        i,
        n_read_granted_transactions_log_i[i],
        n_write_granted_transactions_log_i[i],
        n_read_complete_transactions_log_i[i]
      );
    end
    for (int i = N_CORE + N_DMA; i < N_CORE + N_DMA + N_EXT; i++) begin
      $display(
        "master_log_%0d: granted reads=%0d writes=%0d, read-complete=%0d",
        i,
        n_read_granted_transactions_log_i[i],
        n_write_granted_transactions_log_i[i],
        n_read_complete_transactions_log_i[i]
      );
    end
    for (int i = 0; i < N_HWPE; i++) begin
      $display(
        "master_hwpe_%0d: granted reads=%0d writes=%0d, read-complete=%0d",
        i,
        n_read_granted_transactions_hwpe_i[i],
        n_write_granted_transactions_hwpe_i[i],
        n_read_complete_transactions_hwpe_i[i]
      );
    end

    $display("\n\\\\REQUEST-TO-GRANT LATENCY\\\\");
    for (int i = 0; i < N_CORE; i++) begin
      $display(
        "master_log_%0d: avg req->gnt stall latency %0.2f cycles over %0d grants",
        i,
        (n_gnt_transactions_log_i[i] != 0) ?
            (sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i])) :
            0.0,
        n_gnt_transactions_log_i[i]
      );
    end
    for (int i = N_CORE; i < N_CORE + N_DMA; i++) begin
      $display(
        "master_log_%0d: avg req->gnt stall latency %0.2f cycles over %0d grants",
        i,
        (n_gnt_transactions_log_i[i] != 0) ?
            (sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i])) :
            0.0,
        n_gnt_transactions_log_i[i]
      );
    end
    for (int i = N_CORE + N_DMA; i < N_CORE + N_DMA + N_EXT; i++) begin
      $display(
        "master_log_%0d: avg req->gnt stall latency %0.2f cycles over %0d grants",
        i,
        (n_gnt_transactions_log_i[i] != 0) ?
            (sum_req_to_gnt_latency_log_i[i] / real'(n_gnt_transactions_log_i[i])) :
            0.0,
        n_gnt_transactions_log_i[i]
      );
    end
    for (int i = 0; i < N_HWPE; i++) begin
      $display(
        "master_hwpe_%0d: avg req->gnt stall latency %0.2f cycles over %0d grants",
        i,
        (n_gnt_transactions_hwpe_i[i] != 0) ?
            (sum_req_to_gnt_latency_hwpe_i[i] / real'(n_gnt_transactions_hwpe_i[i])) :
            0.0,
        n_gnt_transactions_hwpe_i[i]
      );
    end
    $display("");
    $display(
      "Total accumulated req->gnt latency: %0d cycles over %0d grants",
      sum_req_to_gnt_latency_all,
      total_gnt_transactions_all
    );
    $display(
      "LOG avg req->gnt stall latency (weighted by grant count): %0.2f cycles",
      average_req_to_gnt_latency_log_weighted
    );
    $display(
      "LOG avg req->gnt stall latency (mean of per-master averages): %0.2f cycles",
      average_req_to_gnt_latency_log_unweighted
    );
    $display(
      "HWPE avg req->gnt stall latency (weighted by grant count): %0.2f cycles",
      average_req_to_gnt_latency_hwpe_weighted
    );
    $display(
      "HWPE avg req->gnt stall latency (mean of per-master averages): %0.2f cycles",
      average_req_to_gnt_latency_hwpe_unweighted
    );
    $display(
      "Global avg req->gnt stall latency (weighted by grant count): %0.2f cycles",
      average_req_to_gnt_latency_weighted
    );
    $display(
      "Global avg req->gnt stall latency (mean of per-master averages): %0.2f cycles",
      average_req_to_gnt_latency_unweighted
    );
    $display("");

    $finish();
  end

endmodule
