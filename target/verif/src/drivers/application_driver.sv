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
  parameter int unsigned APPL_DELAY = 2, //delay on the input signals
  parameter int unsigned IW = 1
) (
  hci_core_intf.initiator master,
  input logic             rst_ni,
  input logic             clear_i,
  input logic             clk,
  output logic            end_stimuli,
  output logic            end_latency
);

  int stim_fd;
  int ret_code;
  logic [IW-1:0] id;
  string file_path;
  integer stim;
  logic wen;
  logic req;
  logic [DATA_WIDTH-1:0] data;
  logic [ADD_WIDTH-1:0]  add;
  logic last_wen;

  initial begin : proc_application_driver
    master.id = -1;
    master.add = '0;
    master.data = '0;
    master.req = 0;
    master.wen = 0;
    master.ecc = 0;
    master.ereq = 0;
    master.r_eready = 0;
    master.be = -1;  // All bits are 1
    master.r_ready = 1;
    master.user = 0;
    end_stimuli = 1'b0;
    end_latency = 1'b0;

    wait (rst_ni);
    if (IS_HWPE) begin
      file_path = $sformatf("../simvectors/stimuli_processed/master_hwpe_%0d.txt", MASTER_NUMBER);
    end else begin
      file_path = $sformatf("../simvectors/stimuli_processed/master_log_%0d.txt", MASTER_NUMBER);
    end
    stim = $fopen(file_path, "r");
    if (stim == 0) begin
      $fatal("ERROR: Could not open stimuli file!");
    end
    @(posedge clk);
    while (!$feof(stim)) begin
      ret_code = $fscanf(stim, "%b %b %b %b %b\n", req, id, wen, data, add);
      #(APPL_DELAY);
      master.id = id;
      master.data = data;
      master.add = add;
      master.wen = wen;
      master.req = req;
      last_wen = wen;
      if (req) begin
        while (1) begin
          @(posedge clk);
          if (master.gnt) begin
            master.id = '0;
            master.data = '0;
            master.add = '0;
            master.wen = '0;
            master.req = '0;
            break;
          end
        end
      end else begin
        @(posedge clk);
      end
    end
    end_stimuli = 1'b1;
    if (last_wen) begin
      while (1) begin
        @(posedge clk);
        if (master.r_valid) begin
          end_latency = 1'b1;
        end
      end
    end else begin
      end_latency = 1'b1;
    end
    $fclose(stim);
  end
endmodule
