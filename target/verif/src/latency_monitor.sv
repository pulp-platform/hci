/*
 * latency_monitor.sv
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
 * Latency monitor
 * Tracks request-to-grant latency and transaction counters for all masters
 */

module latency_monitor #(
  parameter int unsigned N_MASTER = 4,
  parameter int unsigned N_HWPE = 1
) (
  input logic                clk_i,
  input logic                rst_ni,
  // Monitored interfaces
  hci_core_intf.monitor      hci_log_if [0:N_MASTER-N_HWPE-1],
  hci_core_intf.monitor      hci_hwpe_if [0:N_HWPE-1],
  // Accumulated request-to-grant latency.
  output real                sum_req_to_gnt_latency_log_o[N_MASTER-N_HWPE],
  output real                sum_req_to_gnt_latency_hwpe_o[N_HWPE],
  // Number of granted transactions.
  output int unsigned        n_gnt_transactions_log_o[N_MASTER-N_HWPE],
  output int unsigned        n_gnt_transactions_hwpe_o[N_HWPE],
  // Read transactions number.
  output int unsigned        n_read_granted_log_o[N_MASTER-N_HWPE],
  output int unsigned        n_read_granted_hwpe_o[N_HWPE],
  // Write transactions number.
  output int unsigned        n_write_granted_log_o[N_MASTER-N_HWPE],
  output int unsigned        n_write_granted_hwpe_o[N_HWPE],
  // Completed read transactions number.
  output int unsigned        n_read_complete_log_o[N_MASTER-N_HWPE],
  output int unsigned        n_read_complete_hwpe_o[N_HWPE]
);

  typedef longint unsigned cycle_t;

  cycle_t cycle_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cycle_q <= '0;
    end else begin
      cycle_q <= cycle_q + 1;
    end
  end

  // LOG masters (cores/dma/ext)
  generate
    for (genvar gi = 0; gi < N_MASTER - N_HWPE; gi++) begin : gen_log
      logic pending_rsp_is_read_log[$];
      cycle_t req_start_cycle_log;
      logic req_prev_log;

      always_ff @(posedge clk_i or negedge rst_ni) begin
        logic retired_is_read_log;
        if (!rst_ni) begin
          sum_req_to_gnt_latency_log_o[gi] <= 0.0;
          n_gnt_transactions_log_o[gi] <= '0;
          n_read_granted_log_o[gi] <= '0;
          n_write_granted_log_o[gi] <= '0;
          n_read_complete_log_o[gi] <= '0;
          pending_rsp_is_read_log.delete();
          req_start_cycle_log <= '0;
          req_prev_log <= 1'b0;
        end else begin
          if (hci_log_if[gi].req && !req_prev_log) begin
            req_start_cycle_log <= cycle_q;
          end

          if (hci_log_if[gi].req && hci_log_if[gi].gnt) begin
            if (req_prev_log) begin
              sum_req_to_gnt_latency_log_o[gi] <=
                  sum_req_to_gnt_latency_log_o[gi] +
                  real'(cycle_q - req_start_cycle_log);
            end
            n_gnt_transactions_log_o[gi] <= n_gnt_transactions_log_o[gi] + 1;
            pending_rsp_is_read_log.push_back(hci_log_if[gi].wen);
          end
          req_prev_log <= hci_log_if[gi].req;

          if (hci_log_if[gi].req && hci_log_if[gi].gnt && hci_log_if[gi].wen) begin
            n_read_granted_log_o[gi] <=
                n_read_granted_log_o[gi] + 1;
          end
          if (hci_log_if[gi].req && hci_log_if[gi].gnt && !hci_log_if[gi].wen) begin
            n_write_granted_log_o[gi] <=
                n_write_granted_log_o[gi] + 1;
          end
          if (hci_log_if[gi].r_valid && hci_log_if[gi].r_ready) begin
            if (pending_rsp_is_read_log.size() != 0) begin
              retired_is_read_log = pending_rsp_is_read_log.pop_front();
              if (retired_is_read_log) begin
                n_read_complete_log_o[gi] <=
                    n_read_complete_log_o[gi] + 1;
              end
            end
          end
        end
      end
    end
  endgenerate

  // HWPE masters
  generate
    for (genvar gi = 0; gi < N_HWPE; gi++) begin : gen_hwpe
      logic pending_rsp_is_read_hwpe[$];
      cycle_t req_start_cycle_hwpe;
      logic req_prev_hwpe;

      always_ff @(posedge clk_i or negedge rst_ni) begin
        logic retired_is_read_hwpe;
        if (!rst_ni) begin
          sum_req_to_gnt_latency_hwpe_o[gi] <= 0.0;
          n_gnt_transactions_hwpe_o[gi] <= '0;
          n_read_granted_hwpe_o[gi] <= '0;
          n_write_granted_hwpe_o[gi] <= '0;
          n_read_complete_hwpe_o[gi] <= '0;
          pending_rsp_is_read_hwpe.delete();
          req_start_cycle_hwpe <= '0;
          req_prev_hwpe <= 1'b0;
        end else begin
          if (hci_hwpe_if[gi].req && !req_prev_hwpe) begin
            req_start_cycle_hwpe <= cycle_q;
          end

          if (hci_hwpe_if[gi].req && hci_hwpe_if[gi].gnt) begin
            if (req_prev_hwpe) begin
              sum_req_to_gnt_latency_hwpe_o[gi] <=
                  sum_req_to_gnt_latency_hwpe_o[gi] +
                  real'(cycle_q - req_start_cycle_hwpe);
            end
            n_gnt_transactions_hwpe_o[gi] <= n_gnt_transactions_hwpe_o[gi] + 1;
            pending_rsp_is_read_hwpe.push_back(hci_hwpe_if[gi].wen);
          end
          req_prev_hwpe <= hci_hwpe_if[gi].req;

          if (hci_hwpe_if[gi].req && hci_hwpe_if[gi].gnt && hci_hwpe_if[gi].wen) begin
            n_read_granted_hwpe_o[gi] <=
                n_read_granted_hwpe_o[gi] + 1;
          end
          if (hci_hwpe_if[gi].req && hci_hwpe_if[gi].gnt && !hci_hwpe_if[gi].wen) begin
            n_write_granted_hwpe_o[gi] <=
                n_write_granted_hwpe_o[gi] + 1;
          end
          if (hci_hwpe_if[gi].r_valid && hci_hwpe_if[gi].r_ready) begin
            if (pending_rsp_is_read_hwpe.size() != 0) begin
              retired_is_read_hwpe = pending_rsp_is_read_hwpe.pop_front();
              if (retired_is_read_hwpe) begin
                n_read_complete_hwpe_o[gi] <=
                    n_read_complete_hwpe_o[gi] + 1;
              end
            end
          end
        end
      end
    end
  endgenerate

endmodule
