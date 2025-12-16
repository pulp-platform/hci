/*
 * sim_report.sv
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

/**
 * Simulation report generator
 * Generates final report with test results, throughput, and latency metrics
 */

module sim_report
import tb_hci_pkg::calculate_theoretical_throughput;
import tb_hci_pkg::calculate_average_latency;
#(
  parameter int unsigned TOT_CHECK = 1,
  parameter int unsigned N_CORE = 1,
  parameter int unsigned N_CORE_REAL = 1,
  parameter int unsigned N_DMA = 1,
  parameter int unsigned N_DMA_REAL = 1,
  parameter int unsigned N_EXT_REAL = 1,
  parameter int unsigned N_MASTER = 1,
  parameter int unsigned N_MASTER_REAL = 1,
  parameter int unsigned N_HWPE = 1,
  parameter int unsigned N_HWPE_REAL = 1,
  parameter int unsigned HWPE_WIDTH = 4
) (
  input int unsigned n_checks,
  input int unsigned n_correct,
  input logic        WARNING,
  input real         throughput_real,
  input real         tot_latency,
  input real         latency_per_master[N_MASTER],
  input real         SUM_LATENCY_PER_TRANSACTION_LOG[N_MASTER-N_HWPE],
  input real         SUM_LATENCY_PER_TRANSACTION_HWPE[N_HWPE]

);

  initial begin
    real throughput_theo;
    real average_latency;
    average_latency = 0;
    wait (n_checks >= TOT_CHECK);
    $display("n_checks final = %0d", n_checks);
    $display("------ Simulation End ------");
    if (n_correct == TOT_CHECK) begin
      $display("    Test ***PASSED*** \n");
    end else begin
      $display("    Test ***FAILED*** \n");
    end
    $display("\\\\CHECKS\\\\");
    $display("n_correct = %0d out of n_check = %0d", n_correct, n_checks);
    $display("expected n_check = %0d", TOT_CHECK);
    $display("note: each hwpe transaction consists of HWPE_WIDTH=%0d checks \n", HWPE_WIDTH);
    if (WARNING) begin
      $display("** WARNING **: Unnecessary spurious writes are occurring when the HWPE's wide word is written to the banks.");
      $display("The interconnect still works correctly, but this could be an unintended behaviour.\n");
    end

    calculate_theoretical_throughput(throughput_theo);
    wait (throughput_real >= 0);
    $display("\\\\BANDWIDTH\\\\");
    $display("IDEAL APPLICATION PEAK BANDWIDTH (KERNEL DEPENDENT): %f bit per cycle", throughput_theo);
    $display("REAL APPLICATION BANDWIDTH: %f bit per cycle", throughput_real);
    $display("PERFORMANCE RATING %f%%\n", throughput_real / throughput_theo * 100);

    wait (tot_latency >= 0);
    $display("\\\\SIMULATION TIME\\\\");
    $display("TOTAL SIMULATION TIME: %0d cycles", tot_latency);
    for (int i = 0; i < N_CORE_REAL; i++) begin
      $display("TOTAL SIMULATION TIME for CORE%0d (stimuli file: master_log_%0d.txt): %f", i, i, latency_per_master[i]);
    end
    for (int i = N_CORE; i < N_CORE + N_DMA_REAL; i++) begin
      $display("TOTAL SIMULATION TIME for DMA%0d (stimuli file: master_log_%0d.txt): %f", i - N_CORE, i, latency_per_master[i]);
    end
    for (int i = N_CORE + N_DMA; i < N_CORE + N_DMA + N_EXT_REAL; i++) begin
      $display("TOTAL SIMULATION TIME for EXT%0d (stimuli file: master_log_%0d.txt): %f", i - (N_CORE + N_DMA), i, latency_per_master[i]);
    end
    for (int i = N_MASTER - N_HWPE; i < N_MASTER - N_HWPE + N_HWPE_REAL; i++) begin
      $display("TOTAL SIMULATION TIME for HWPE%0d (stimuli file: master_hwpe_%0d.txt): %f", i - (N_MASTER - N_HWPE), i - (N_MASTER - N_HWPE), latency_per_master[i]);
    end

    calculate_average_latency(SUM_LATENCY_PER_TRANSACTION_LOG, SUM_LATENCY_PER_TRANSACTION_HWPE);
    $display("\n\\\\LATENCY PER TRANSACTION\\\\");
    for (int i = 0; i < N_MASTER_REAL - N_HWPE_REAL; i++) begin
      $display("Average latency for each transaction in master_log_%0d: %f", i, SUM_LATENCY_PER_TRANSACTION_LOG[i]);
      average_latency += SUM_LATENCY_PER_TRANSACTION_LOG[i];
    end
    for (int i = 0; i < N_HWPE_REAL; i++) begin
      $display("Average latency for each transaction in master_hwpe_%0d: %f", i, SUM_LATENCY_PER_TRANSACTION_HWPE[i]);
      average_latency += SUM_LATENCY_PER_TRANSACTION_HWPE[i];
    end
    average_latency = average_latency / N_MASTER_REAL;
    $display("Average latency for each transaction (all masters): %f", average_latency);
    $finish();
  end

endmodule