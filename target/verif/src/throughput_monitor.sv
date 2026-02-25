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
  parameter int unsigned N_HWPE,
  parameter int unsigned CLK_PERIOD,
  parameter int unsigned DATA_WIDTH,
  parameter int unsigned HWPE_WIDTH
) (
  input logic                clk_i,
  input logic                rst_ni,
  input logic [0:N_MASTER-1] end_stimuli_i,
  input logic [0:N_MASTER-1] end_latency_i,
  // Read transactions number
  input int unsigned         n_read_complete_log_i[N_MASTER-N_HWPE],
  input int unsigned         n_read_complete_hwpe_i[N_HWPE],
  // Write transactions number
  input int unsigned         n_write_granted_log_i[N_MASTER-N_HWPE],
  input int unsigned         n_write_granted_hwpe_i[N_HWPE],
  // Completion-side throughput: accepted writes + completed reads per elapsed completion cycle.
  output real                throughput_complete_o,
  // Elapsed cycles from reset release to end_stimuli.
  output real                stim_latency_o,
  // Total simulation time (cycles) and simulation time per master (cycles)
  output real                tot_latency_o,
  output real                latency_per_master_o[N_MASTER]
);

  // Stimulus duration at stimulus completion.
  initial begin
    time start_time, end_time;
    real stim_time_cycles;
    stim_latency_o = -1;
    wait (rst_ni);
    #(CLK_PERIOD/100);
    @(posedge clk_i);
    start_time = $time;
    wait (&end_stimuli_i);
    end_time = $time;
    stim_time_cycles = real'(end_time - start_time) / real'(CLK_PERIOD);  // cycles
    stim_latency_o = stim_time_cycles;
  end

  // Completion-side throughput at full completion.
  initial begin
    time start_time, end_time;
    real completion_time_cycles;
    real tot_data;
    throughput_complete_o = -1;
    tot_latency_o = -1;
    wait (rst_ni);
    #(CLK_PERIOD/100);
    @(posedge clk_i);
    start_time = $time;
    wait (&end_latency_i);
    end_time = $time;
    completion_time_cycles = real'(end_time - start_time) / real'(CLK_PERIOD);  // cycles
    tot_latency_o = completion_time_cycles;
    tot_data = 0.0;
    for (int i = 0; i < N_MASTER - N_HWPE; i++) begin
      tot_data += real'(
        n_write_granted_log_i[i] + n_read_complete_log_i[i]
      ) * real'(DATA_WIDTH);
    end
    for (int i = 0; i < N_HWPE; i++) begin
      tot_data += real'(
        n_write_granted_hwpe_i[i] + n_read_complete_hwpe_i[i]
      ) * real'(HWPE_WIDTH * DATA_WIDTH);
    end
    if (completion_time_cycles > 0.0) begin
      throughput_complete_o = tot_data / completion_time_cycles;  // bits per cycle
    end else begin
      throughput_complete_o = 0.0;
    end
  end

  // Simulation completion time per master.
  generate
    for (genvar ii = 0; ii < N_MASTER; ii++) begin
      initial begin
        time start_time, end_time;
        latency_per_master_o[ii] = 0;
        wait (rst_ni);
        #(CLK_PERIOD/100);
        @(posedge clk_i);
        start_time = $time;
        wait (end_latency_i[ii]);
        end_time = $time;
        latency_per_master_o[ii] = real'(end_time - start_time) / real'(CLK_PERIOD);
      end
    end
  endgenerate

endmodule
