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
  parameter int unsigned ADDR_WIDTH = 1,
  parameter int unsigned APPL_DELAY = 2,  // Delay on the input signals
  parameter int unsigned IW = 1,
  parameter bit USE_STREAMER_FIFO = 1'b1,
  parameter int unsigned STREAMER_FIFO_DEPTH = 2,
  parameter string STIM_FILE = ""
) (
  input logic             clk_i,
  input logic             rst_ni,
  hci_core_intf.initiator hci_if,
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
  logic [ADDR_WIDTH-1:0]  add;
  int unsigned n_completed_read_transactions;
  logic pending_rsp_is_read[$];
  localparam hci_package::hci_size_parameter_t HCI_SIZE_driver = '{
    DW:  DATA_WIDTH,
    AW:  ADDR_WIDTH,
    BW:  hci_package::DEFAULT_BW,
    UW:  hci_package::DEFAULT_UW,
    IW:  IW,
    EW:  hci_package::DEFAULT_EW,
    EHW: hci_package::DEFAULT_EHW
  };

  hci_core_intf #(
    .DW(HCI_SIZE_driver.DW),
    .AW(HCI_SIZE_driver.AW),
    .BW(HCI_SIZE_driver.BW),
    .UW(HCI_SIZE_driver.UW),
    .IW(HCI_SIZE_driver.IW),
    .EW(HCI_SIZE_driver.EW),
    .EHW(HCI_SIZE_driver.EHW)
  ) hci_drv_if (
    .clk(clk_i)
  );

  generate
    if (USE_STREAMER_FIFO) begin : gen_driver_streamer_fifo
      hci_core_fifo #(
        .FIFO_DEPTH(STREAMER_FIFO_DEPTH),
        .HCI_SIZE_tcdm_initiator(HCI_SIZE_driver)
      ) i_driver_streamer_fifo (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .clear_i(1'b0),
        .flags_o(),
        .tcdm_target(hci_drv_if),
        .tcdm_initiator(hci_if)
      );
    end else begin : gen_driver_direct
      hci_core_assign i_driver_direct_assign (
        .tcdm_target(hci_drv_if),
        .tcdm_initiator(hci_if)
      );
    end
  endgenerate

  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_read_response_counter
    logic retired_is_read;
    if (!rst_ni) begin
      n_completed_read_transactions <= '0;
      pending_rsp_is_read.delete();
    end else begin
      if (hci_drv_if.req && hci_drv_if.gnt) begin
        pending_rsp_is_read.push_back(hci_drv_if.wen);
      end
      if (hci_drv_if.r_valid && hci_drv_if.r_ready) begin
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
    hci_drv_if.id = '0;
    hci_drv_if.add = '0;
    hci_drv_if.data = '0;
    hci_drv_if.req = 1'b0;
    hci_drv_if.wen = 1'b0;
    hci_drv_if.ecc = '0;
    hci_drv_if.ereq = '0;
    hci_drv_if.r_eready = '0;
    hci_drv_if.be = '1;
    hci_drv_if.r_ready = 1'b1;
    hci_drv_if.user = '0;
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
      hci_drv_if.id = id;
      hci_drv_if.data = data;
      hci_drv_if.add = add;
      hci_drv_if.wen = wen;
      hci_drv_if.req = req;

      if (req) begin
        @(posedge clk_i iff hci_drv_if.gnt);
        n_issued_transactions_o++;
        if (wen) begin
          n_issued_read_transactions_o++;
        end
        // Deassert in NBA region so monitors sampling this edge see the handshake.
        hci_drv_if.id <= '0;
        hci_drv_if.data <= '0;
        hci_drv_if.add <= '0;
        hci_drv_if.wen <= 1'b0;
        hci_drv_if.req <= 1'b0;
        wait (hci_drv_if.req == 1'b0);
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
