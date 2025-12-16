/*
 * throughput_monitor.sv
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
 * Throughput monitor
 * Measures actual throughput and simulation time for each master
 */

module throughput_monitor #(
  parameter int unsigned N_MASTER,
  parameter int unsigned N_TRANSACTION_LOG,
  parameter int unsigned CLK_PERIOD,
  parameter int unsigned DATA_WIDTH,
  parameter int unsigned N_MASTER_REAL,
  parameter int unsigned N_HWPE_REAL,
  parameter int unsigned N_TRANSACTION_HWPE,
  parameter int unsigned HWPE_WIDTH
) (
  input logic [0:N_MASTER-1] END_STIMULI,
  input logic [0:N_MASTER-1] END_LATENCY,
  input logic                rst_n,
  input logic                clk,
  output real                throughput_real,
  output real                tot_latency,
  output real                latency_per_master[N_MASTER]
);

  // Throughput measurement
  initial begin
    time start_time, end_time;
    real tot_time, tot_data;
    throughput_real = -1;
    wait (rst_n);
    #(CLK_PERIOD/100);
    @(posedge clk);
    start_time = $time;
    wait (&END_STIMULI);
    end_time = $time;
    tot_time = (end_time - start_time) / CLK_PERIOD;  // cycles
    tot_data = ((N_TRANSACTION_LOG * DATA_WIDTH) * (N_MASTER_REAL - N_HWPE_REAL) +
                (N_TRANSACTION_HWPE * HWPE_WIDTH * DATA_WIDTH) * N_HWPE_REAL);  // bits
    throughput_real = tot_data / tot_time;  // bits per cycle
  end

  // Simulation time per master
  generate
    for (genvar ii = 0; ii < N_MASTER; ii++) begin
      initial begin
        time start_time, end_time;
        latency_per_master[ii] = 0;
        wait (rst_n);
        #(CLK_PERIOD/100);
        @(posedge clk);
        start_time = $time;
        wait (END_LATENCY[ii]);
        end_time = $time;
        latency_per_master[ii] = (end_time - start_time) / CLK_PERIOD;
      end
    end
  endgenerate

  // Total simulation latency
  initial begin
    time start_time, end_time;
    tot_latency = 0;
    wait (rst_n);
    #(CLK_PERIOD/100);
    @(posedge clk);
    start_time = $time;
    wait (&END_LATENCY);
    end_time = $time;
    tot_latency = (end_time - start_time) / CLK_PERIOD;
  end

endmodule