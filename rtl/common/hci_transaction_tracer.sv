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
 *   payload and, when `UW` is non-zero, the `user` side channel;
 * - the *response* log records one entry per **consumed** response, i.e. per
 *   cycle in which `r_valid & lrdy` holds, with the `r_data` and `r_opc`
 *   payload and, when `UW` is non-zero, the `r_user` side channel.
 *
 * Their formats are described by the `hci_transaction_request-v1` and
 * `hci_transaction_response-v1` JSON schemas in `tracer/`. The resulting logs
 * can be compared against each other -- or against HWPE-Stream logs produced
 * by **hwpe_stream_transaction_tracer** -- with the `hci-tracer` utility found
 * in `tracer/`.
 *
 * This is the version of the tracer for the v1.1 HCI-Core interface, which
 * differs from later ones in a few respects. The logs it writes are however
 * described by the very same schemas, so a v1.1 trace can be compared directly
 * against a trace taken on a newer interface:
 *
 * - the response-side ready signal is called `lrdy` here rather than `r_ready`;
 * - there are no `id`/`r_id`, `ecc`/`r_ecc` or handshake-ECC signals, so `IW`
 *   and `EW` are reported as 0 in the log header and those fields are simply
 *   left out of every record. `hci-tracer` leaves absent side channels out of
 *   the comparison, so their absence cannot misalign a diff;
 * - `WW` and `OW` have no counterpart in the schema and are therefore not
 *   reported; `boffs` is recorded as an extra, purely informational field,
 *   which the schema permits and `hci-tracer` ignores;
 * - the `r_opc` and `r_user` response side channels are frequently left
 *   entirely undriven by v1.1 producers, and hence sample as `x`. Since an `x`
 *   in `r_opc` would not even be valid JSON, both are logged as zero whenever
 *   they carry unknown bits; neither takes part in the comparison performed by
 *   `hci-tracer` by default, so nothing can be hidden by the substitution.
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

module hci_transaction_tracer
  import hci_package::*;
#(
  parameter int unsigned DW = hci_package::DEFAULT_DW, /// Data Width
  parameter int unsigned AW = hci_package::DEFAULT_AW, /// Address Width
  parameter int unsigned BW = hci_package::DEFAULT_BW, /// Width of a "byte" in bits
  parameter int unsigned UW = hci_package::DEFAULT_UW, /// User Width
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

  // The v1.1 interface carries no ID nor ECC side channels; reporting their
  // widths as zero is what tells `hci-tracer` to leave them out of the
  // comparison rather than to compare them against a stub value.
  localparam int unsigned IW = 0;
  localparam int unsigned EW = 0;

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
        // As on the response side, an undriven `user` is logged as zero rather
        // than as `x` nibbles; it too is left out of the default comparison.
        record = {record, $sformatf(", \"user\": \"0x%h\"",
          $isunknown(tcdm.user) ? '0 : tcdm.user)};
      end
      // `boffs` is specific to this version of the interface: it is recorded
      // for information only, and ignored by `hci-tracer`.
      record = {record, $sformatf(", \"boffs\": \"0x%h\"", tcdm.boffs)};
      $fwrite(fd_req, "%s\n    %s}", sep_req, record);
      sep_req = ",";
      seq_req = seq_req + 1;
    end
  end

/*
 * Response logging: one record per consumed response (r_valid & lrdy)
 */
  always @(posedge clk_i)
  begin
    if(rst_ni & enable_i & tcdm.r_valid & tcdm.lrdy & (fd_rsp != 0)) begin
      // `r_opc` and `r_user` are commonly left undriven on a v1.1 interface and
      // then sample as x. `%0d` renders that as a bare, unquoted `x`, which is
      // not valid JSON, and `%h` renders it as `x` nibbles, which would be read
      // back as unknown bits. Substituting zero for any unknown value avoids
      // both; `hci-tracer` keys on neither field unless explicitly asked to, so
      // the substitution cannot hide a mismatch. `r_data`, by contrast, is
      // always logged as sampled: `x` nibbles are legal there and are meant to
      // be seen.
      record = $sformatf("{\"seq\": %0d, \"cycle\": %0d, \"r_data\": \"0x%h\", \"r_opc\": %0d",
        seq_rsp, cycle_q, tcdm.r_data, $isunknown(tcdm.r_opc) ? 1'b0 : tcdm.r_opc);
      if(UW > 0) begin
        record = {record, $sformatf(", \"r_user\": \"0x%h\"",
          $isunknown(tcdm.r_user) ? '0 : tcdm.r_user)};
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
  initial
    dw : assert(DW == tcdm.DW);
  initial
    aw : assert(AW == tcdm.AW);
  initial
    bw : assert(BW == tcdm.BW);
  initial
    uw : assert(UW == tcdm.UW);
`endif
`endif

`endif /* `ifndef SYNTHESIS */

endmodule // hci_transaction_tracer
