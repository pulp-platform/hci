/*
 * hci_transaction_tracer.sv
 * Francesco Conti <f.conti@unibo.it>
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
 * The **hci_transaction_tracer** module is a purely passive, simulation-only
 * monitor: it observes an HCI-Core stream through the `monitor` modport of an
 * `hci_core_intf` interface and appends every transaction to a JSON log file.
 * Since HCI-Core is bidirectional, two log files are produced, whose names are
 * given by the `REQ_LOG_FILE` and `RSP_LOG_FILE` parameters:
 *
 * - the *request* log records one entry per **accepted** request, i.e. per
 *   cycle in which `req & gnt` holds, with the `add`, `wen`, `data` and `be`
 *   payload and, when the corresponding width is non-zero, the `user`, `id`
 *   and `ecc` side channels;
 * - the *response* log records one entry per **consumed** response, i.e. per
 *   cycle in which `r_valid & r_ready` holds, with the `r_data` and `r_opc`
 *   payload and, when the corresponding width is non-zero, the `r_user`,
 *   `r_id` and `r_ecc` side channels.
 *
 * Their formats are described by the `hci_transaction_request-v1` and
 * `hci_transaction_response-v1` JSON schemas in `tracer/`. The resulting logs
 * can be compared against each other -- or against HWPE-Stream logs produced
 * by **hwpe_stream_transaction_tracer** -- with the `hci-tracer` utility found
 * in `tracer/`.
 *
 * Each log is a single well-formed JSON document: the header and the opening of
 * the `transactions` array are emitted by an `initial` block, one object per
 * transaction is emitted as the simulation progresses, and the array and object
 * are closed by a `final` block. Should the simulation be aborted before the
 * `final` block runs, the resulting truncated files are still accepted (and
 * repaired) by `hci-tracer`.
 *
 * Logging is gated by `enable_i`, which can be used to restrict tracing to a
 * region of interest; `cycle` counts clock cycles from the release of `rst_ni`
 * and is reported for waveform cross-reference only -- transaction *time* is
 * never used when comparing two logs.
 *
 * The body of the module is enclosed in a `ifndef SYNTHESIS guard, so that the
 * tracer can be instantiated unconditionally: under synthesis it elaborates to
 * an empty module.
 */

`include "hci_helpers.svh"

module hci_transaction_tracer
  import hci_package::*;
#(
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0,
  parameter string REQ_LOG_FILE = "hci_trace_req.json",
  parameter string RSP_LOG_FILE = "hci_trace_rsp.json"
)
(
  input logic           clk_i,
  input logic           rst_ni,
  input logic           enable_i,
  hci_core_intf.monitor tcdm
);

`ifndef SYNTHESIS

  localparam int unsigned DW = `HCI_SIZE_GET_DW(tcdm);
  localparam int unsigned AW = `HCI_SIZE_GET_AW(tcdm);
  localparam int unsigned BW = `HCI_SIZE_GET_BW(tcdm);
  localparam int unsigned UW = `HCI_SIZE_GET_UW(tcdm);
  localparam int unsigned IW = `HCI_SIZE_GET_IW(tcdm);
  localparam int unsigned EW = `HCI_SIZE_GET_EW(tcdm);

  int              fd_req;
  int              fd_rsp;
  longint unsigned cycle_q;
  longint unsigned seq_req;
  longint unsigned seq_rsp;
  string           sep_req;
  string           sep_rsp;
  string           record;

  function automatic string interface_json();
    return $sformatf({"{ \"DW\": %0d, \"AW\": %0d, \"BW\": %0d,",
                      " \"UW\": %0d, \"IW\": %0d, \"EW\": %0d }"},
      DW, AW, BW, UW, IW, EW);
  endfunction // interface_json

  initial
  begin
    fd_req = $fopen(REQ_LOG_FILE, "w");
    if(fd_req == 0) begin
      $fatal(1, "[hci_transaction_tracer] could not open log file %s", REQ_LOG_FILE);
    end
    fd_rsp = $fopen(RSP_LOG_FILE, "w");
    if(fd_rsp == 0) begin
      $fatal(1, "[hci_transaction_tracer] could not open log file %s", RSP_LOG_FILE);
    end
    seq_req = 0;
    seq_rsp = 0;
    sep_req = "";
    sep_rsp = "";
    $fwrite(fd_req, "{\n  \"schema\": \"hci_transaction_request-v1\",\n");
    $fwrite(fd_rsp, "{\n  \"schema\": \"hci_transaction_response-v1\",\n");
    $fwrite(fd_req, "  \"interface\": %s,\n", interface_json());
    $fwrite(fd_rsp, "  \"interface\": %s,\n", interface_json());
    $fwrite(fd_req, "  \"path\": \"%m\",\n  \"transactions\": [");
    $fwrite(fd_rsp, "  \"path\": \"%m\",\n  \"transactions\": [");
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      cycle_q <= '0;
    end
    else begin
      cycle_q <= cycle_q + 1;
    end
  end

/*
 * Request logging: one record per accepted request (req & gnt)
 */
  always @(posedge clk_i)
  begin
    if(rst_ni & enable_i & tcdm.req & tcdm.gnt & (fd_req != 0)) begin
      record = $sformatf("{\"seq\": %0d, \"cycle\": %0d, \"add\": \"0x%h\", \"wen\": %0d",
        seq_req, cycle_q, tcdm.add, tcdm.wen);
      record = {record, $sformatf(", \"data\": \"0x%h\", \"be\": \"0x%h\"", tcdm.data, tcdm.be)};
      if(UW > 0) begin
        record = {record, $sformatf(", \"user\": \"0x%h\"", tcdm.user)};
      end
      if(IW > 0) begin
        record = {record, $sformatf(", \"id\": \"0x%h\"", tcdm.id)};
      end
      if(EW > 0) begin
        record = {record, $sformatf(", \"ecc\": \"0x%h\"", tcdm.ecc)};
      end
      $fwrite(fd_req, "%s\n    %s}", sep_req, record);
      sep_req = ",";
      seq_req = seq_req + 1;
    end
  end

/*
 * Response logging: one record per consumed response (r_valid & r_ready)
 */
  always @(posedge clk_i)
  begin
    if(rst_ni & enable_i & tcdm.r_valid & tcdm.r_ready & (fd_rsp != 0)) begin
      record = $sformatf("{\"seq\": %0d, \"cycle\": %0d, \"r_data\": \"0x%h\", \"r_opc\": %0d",
        seq_rsp, cycle_q, tcdm.r_data, tcdm.r_opc);
      if(UW > 0) begin
        record = {record, $sformatf(", \"r_user\": \"0x%h\"", tcdm.r_user)};
      end
      if(IW > 0) begin
        record = {record, $sformatf(", \"r_id\": \"0x%h\"", tcdm.r_id)};
      end
      if(EW > 0) begin
        record = {record, $sformatf(", \"r_ecc\": \"0x%h\"", tcdm.r_ecc)};
      end
      $fwrite(fd_rsp, "%s\n    %s}", sep_rsp, record);
      sep_rsp = ",";
      seq_rsp = seq_rsp + 1;
    end
  end

  final
  begin
    if(fd_req != 0) begin
      $fwrite(fd_req, "\n  ]\n}\n");
      $fclose(fd_req);
    end
    if(fd_rsp != 0) begin
      $fwrite(fd_rsp, "\n  ]\n}\n");
      $fclose(fd_rsp);
    end
  end

/*
 * Interface size asserts
 */
`ifndef VERILATOR
`ifndef VCS
  `HCI_SIZE_CHECK_ASSERTS(tcdm);
`endif
`endif

`endif /* `ifndef SYNTHESIS */

endmodule // hci_transaction_tracer
