/*
 * application_driver.sv
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
 * Application driver module
 * Reads stimuli from file and drives transactions on HCI interface
 */

module application_driver #(
  parameter int unsigned MASTER_NUMBER = 1,
  parameter int unsigned IS_HWPE = 1,
  parameter int unsigned DATA_WIDTH = 1,
  parameter int unsigned ADD_WIDTH = 1,
  parameter int unsigned APPL_DELAY = 2,  // Delay on the input signals
  parameter int unsigned IW = 1,
  parameter string STIM_FILE = ""
) (
  hci_core_intf.initiator hci_if,
  input logic             rst_ni,
  input logic             clk_i,
  output logic            end_stimuli_o,
  output logic            end_latency_o,
  output int unsigned     n_issued_transactions_o,
  output int unsigned     n_issued_read_transactions_o
);

  logic [IW-1:0] id;
  string file_path;
  int stim;
  int scan_status;
  logic wen;
  logic req;
  logic [DATA_WIDTH-1:0] data;
  logic [ADD_WIDTH-1:0]  add;
  int unsigned n_completed_read_transactions;
  logic pending_rsp_is_read[$];

  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_read_response_counter
    logic retired_is_read;
    if (!rst_ni) begin
      n_completed_read_transactions <= '0;
      pending_rsp_is_read.delete();
    end else begin
      if (hci_if.req && hci_if.gnt) begin
        pending_rsp_is_read.push_back(hci_if.wen);
      end
      if (hci_if.r_valid && hci_if.r_ready) begin
        if (pending_rsp_is_read.size() != 0) begin
          retired_is_read = pending_rsp_is_read.pop_front();
          if (retired_is_read) begin
            n_completed_read_transactions <= n_completed_read_transactions + 1;
          end
        end
      end
    end
  end

  initial begin : proc_application_driver
    hci_if.id = '0;
    hci_if.add = '0;
    hci_if.data = '0;
    hci_if.req = 1'b0;
    hci_if.wen = 1'b0;
    hci_if.ecc = '0;
    hci_if.ereq = '0;
    hci_if.r_eready = '0;
    hci_if.be = '1;
    hci_if.r_ready = 1'b1;
    hci_if.user = '0;
    end_stimuli_o = 1'b0;
    end_latency_o = 1'b0;
    n_issued_transactions_o = '0;
    n_issued_read_transactions_o = '0;

    wait (rst_ni);
    if (STIM_FILE != "") begin
      file_path = STIM_FILE;
    end else begin
      if (IS_HWPE) begin
        file_path = $sformatf(
          "../simvectors/generated/stimuli_processed/master_hwpe_%0d.txt",
          MASTER_NUMBER
        );
      end else begin
        file_path = $sformatf(
          "../simvectors/generated/stimuli_processed/master_log_%0d.txt",
          MASTER_NUMBER
        );
      end
    end
    stim = $fopen(file_path, "r");
    if (stim == 0) begin
      $fatal("ERROR: Could not open stimuli file!");
    end
    @(posedge clk_i);
    while (!$feof(stim)) begin
      scan_status = $fscanf(stim, "%b %b %b %b %b\n", req, id, wen, data, add);
      if (scan_status != 5) begin
        if (!$feof(stim)) begin
          $fatal(1, "ERROR: malformed stimuli line in %s", file_path);
        end
        break;
      end
      #(APPL_DELAY);
      hci_if.id = id;
      hci_if.data = data;
      hci_if.add = add;
      hci_if.wen = wen;
      hci_if.req = req;

      if (req) begin
        @(posedge clk_i iff hci_if.gnt);
        n_issued_transactions_o++;
        if (wen) begin
          n_issued_read_transactions_o++;
        end
        // Deassert in NBA region so monitors sampling this edge see the handshake.
        hci_if.id <= '0;
        hci_if.data <= '0;
        hci_if.add <= '0;
        hci_if.wen <= 1'b0;
        hci_if.req <= 1'b0;
        wait (hci_if.req == 1'b0);
      end else begin
        @(posedge clk_i);
      end
    end

    $fclose(stim);
    end_stimuli_o = 1'b1;
    wait (n_completed_read_transactions >= n_issued_read_transactions_o);
    end_latency_o = 1'b1;
  end
endmodule
