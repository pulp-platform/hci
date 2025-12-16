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
 * Tracks transaction latency from request to response for all masters
 */

module latency_monitor #(
  parameter int unsigned N_MASTER = 4,
  parameter int unsigned N_HWPE = 1
) (
  hci_core_intf.target all_except_hwpe [0:N_MASTER-N_HWPE-1],
  hci_core_intf.target hwpe_intc [0:N_HWPE-1],
  input logic          rst_n,
  input logic          clk,
  output real          SUM_LATENCY_PER_TRANSACTION_HWPE[N_HWPE],
  output real          SUM_LATENCY_PER_TRANSACTION_LOG[N_MASTER-N_HWPE]
);

  import tb_hci_pkg::MAX_CYCLES_BETWEEN_GNT_RVALID;
  localparam int unsigned MAX_CYCLES_BETWEEN_GNT_RVALID_LOCAL = MAX_CYCLES_BETWEEN_GNT_RVALID + 2;  // Maximum expected number of cycles between the gnt signal and the r_valid signal

  static logic [N_MASTER-1:0][MAX_CYCLES_BETWEEN_GNT_RVALID_LOCAL-1:0] START_COMPUTE_LATENCY;
  static logic [N_MASTER-1:0][MAX_CYCLES_BETWEEN_GNT_RVALID_LOCAL-1:0] FINISH_COMPUTE_LATENCY;

  generate
    for (genvar test = 0; test < MAX_CYCLES_BETWEEN_GNT_RVALID_LOCAL - 1; test++) begin
      for (genvar ii = 0; ii < N_MASTER - N_HWPE; ii++) begin
        initial begin
          int unsigned latency;
          logic stop;
          SUM_LATENCY_PER_TRANSACTION_LOG[ii] = 0;
          START_COMPUTE_LATENCY[ii][0] = 1'b1;
          wait (rst_n);
          while (1) begin
            stop = 0;
            wait (START_COMPUTE_LATENCY[ii][test]);
            FINISH_COMPUTE_LATENCY[ii][test] = 0;
            latency = 1;
            @(posedge clk);
            if (all_except_hwpe[ii].req && START_COMPUTE_LATENCY[ii][test]) begin
              while (1) begin
                if (all_except_hwpe[ii].gnt) begin
                  if (all_except_hwpe[ii].wen) begin
                    if (test == 0) begin
                      START_COMPUTE_LATENCY[ii][test+1] = 1;
                    end else if (test == 1) begin
                      START_COMPUTE_LATENCY[ii][test+1] = |FINISH_COMPUTE_LATENCY[ii][0];
                    end else begin
                      START_COMPUTE_LATENCY[ii][test+1] = |FINISH_COMPUTE_LATENCY[ii][test-1:0];
                    end
                    while (1) begin
                      latency++;
                      @(posedge clk);
                      if (all_except_hwpe[ii].r_valid) begin
                        START_COMPUTE_LATENCY[ii][test+1] = 1'b0;
                        stop = 1;
                        break;
                      end
                    end
                  end else begin
                    break;
                  end
                  if (stop) begin
                    break;
                  end
                end
                @(posedge clk);
                latency++;
              end
              FINISH_COMPUTE_LATENCY[ii][test] = 1;
              SUM_LATENCY_PER_TRANSACTION_LOG[ii] = SUM_LATENCY_PER_TRANSACTION_LOG[ii] + latency;
            end
          end
        end
      end
    end
    for (genvar test = 0; test < MAX_CYCLES_BETWEEN_GNT_RVALID_LOCAL - 1; test++) begin
      for (genvar ii = 0; ii < N_HWPE; ii++) begin
        initial begin
          int unsigned latency;
          logic stop;
          SUM_LATENCY_PER_TRANSACTION_HWPE[ii] = 0;
          START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][0] = 1'b1;
          wait (rst_n);
          while (1) begin
            stop = 0;
            wait (START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test]);
            FINISH_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test] = 0;
            latency = 1;
            @(posedge clk);
            if (hwpe_intc[ii].req && START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test]) begin
              while (1) begin
                if (hwpe_intc[ii].gnt) begin
                  if (hwpe_intc[ii].wen) begin
                    if (test == 0) begin
                      START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test+1] = 1;
                    end else if (test == 1) begin
                      START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test+1] = |FINISH_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][0];
                    end else begin
                      START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test+1] = |FINISH_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test-1:0];
                    end
                    while (1) begin
                      latency++;
                      @(posedge clk);
                      if (hwpe_intc[ii].r_valid) begin
                        START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test+1] = 1'b0;
                        stop = 1;
                        break;
                      end
                    end
                  end else begin
                    break;
                  end
                  if (stop) begin
                    break;
                  end
                end
                @(posedge clk);
                latency++;
              end
              FINISH_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test] = 1;
              SUM_LATENCY_PER_TRANSACTION_HWPE[ii] = SUM_LATENCY_PER_TRANSACTION_HWPE[ii] + latency;
            end
          end
        end
      end
    end
  endgenerate

endmodule