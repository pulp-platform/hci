/*
 * hci_core_fifo.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2014-2020 ETH Zurich, University of Bologna
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
 * The **hci_core_fifo** module implements a hardware FIFO queue for
 * HCI-Core interfaces, used to withstand data scarcity (`req=0`) or
 * backpressure (`gnt=0`), decoupling two architectural domains.
 * This FIFO is single-clock and therefore cannot be used to cross two
 * distinct clock domains.
 * The FIFO treats a HCI-Core load stream as a combination of two
 * 32-bit HWPE-Streams, one going from the `tcdm_initiator` to the `tcdm_target` interface
 * carrying the `addr` (*outgoing stream*); the other from the `tcdm_target` to the
 * `tcdm_initiator` interface, carrying the `r_data` (*incoming stream*).
 *
 * On the target side, the `req` and `gnt` of the HCI-Core interfaces
 * are mapped on `valid` and `ready` respectively in the outgoing stream.
 * Backpressure on the incoming stream (target side) cannot be enforced by means
 * of the HCI-Core target interface and thus is carried by a specific
 * input `ready_i` that must be generated outside of the TCDM FIFO, typically
 * by a **hwpe_stream_source** module (output `tcdm_fifo_ready_o`).
 * On the initiator side, `req` is mapped to the AND of the incoming stream `ready`
 * signal and the outgoing stream `valid` signal. `gnt` is hooked to the
 * outgoing stream `ready` signal.
 * The `r_valid` is mapped on `valid` in the incoming stream.
 * :numref:`_hci_core_fifo_mapping` shows this mapping.
 *
 *   Mapping of HCI-Core and HWPE-Stream signals inside the load FIFO.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_core_fifo_params:
 * .. table:: **hci_core_fifo** design-time parameters.
 *
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *   | **Name**               | **Default**  | **Description**                                                                      |
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *   | *FIFO_DEPTH*           | 8            | Depth of the FIFO queue (multiple of 2).                                             |
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *   | *LATCH_FIFO*           | 0            | If 1, use latches instead of flip-flops (requires special constraints in synthesis). |
 *   +------------------------+--------------+--------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_core_fifo_flags:
 * .. table:: **hci_core_fifo** output flags.
 *
 *   +----------------+--------------+-----------------------------------+
 *   | **Name**       | **Type**     | **Description**                   |
 *   +----------------+--------------+-----------------------------------+
 *   | *empty*        | `logic`      | 1 if the FIFO is currently empty. |
 *   +----------------+--------------+-----------------------------------+
 *   | *full*         | `logic`      | 1 if the FIFO is currently full.  |
 *   +----------------+--------------+-----------------------------------+
 *   | *push_pointer* | `logic[7:0]` | Unused.                           |
 *   +----------------+--------------+-----------------------------------+
 *   | *pop_pointer*  | `logic[7:0]` | Unused.                           |
 *   +----------------+--------------+-----------------------------------+
 *
 */

`include "hci_helpers.svh"

module hci_core_fifo
  import hwpe_stream_package::*;
  import hci_package::*;
#(
  parameter int unsigned FIFO_DEPTH = 8,
  parameter int unsigned LATCH_FIFO = 0,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm_initiator) = '0
)
(
  input  logic            clk_i,
  input  logic            rst_ni,
  input  logic            clear_i,

  output flags_fifo_t     flags_o,

  hci_core_intf.target    tcdm_target,
  hci_core_intf.initiator tcdm_initiator
);

  localparam int unsigned DW  = `HCI_SIZE_GET_DW(tcdm_initiator);
  localparam int unsigned BW  = `HCI_SIZE_GET_BW(tcdm_initiator);
  localparam int unsigned AW  = `HCI_SIZE_GET_AW(tcdm_initiator);
  localparam int unsigned UW  = `HCI_SIZE_GET_UW(tcdm_initiator);
  localparam int unsigned IW  = `HCI_SIZE_GET_IW(tcdm_initiator);
  localparam int unsigned EW  = `HCI_SIZE_GET_EW(tcdm_initiator);
  localparam int unsigned EHW = `HCI_SIZE_GET_EHW(tcdm_initiator);

  flags_fifo_t flags_incoming, flags_outgoing;

  logic incoming_fifo_not_full;
  logic incoming_fifo_almost_full;

  logic                   tcdm_initiator_r_valid_d, tcdm_initiator_r_valid_q;
  logic [EW+UW+IW+DW-1:0] tcdm_initiator_r_data_d, tcdm_initiator_r_data_q;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( AW+UW+IW+DW+DW/BW+EW+1 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_outgoing_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( AW+UW+IW+DW+DW/BW+EW+1 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_outgoing_pop (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( UW+IW+DW+EW )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_incoming_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( UW+IW+DW+EW )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_incoming_pop (
    .clk ( clk_i )
  );

  // wrap tcdm incoming ports into a stream
  assign stream_incoming_push.data  = tcdm_initiator_r_valid_d ? tcdm_initiator_r_data_d : tcdm_initiator_r_data_q;
  assign stream_incoming_push.valid = tcdm_initiator_r_valid_d | tcdm_initiator_r_valid_q;
  assign stream_incoming_push.strb = '1;

  assign incoming_fifo_not_full = stream_incoming_push.ready;
  assign incoming_fifo_almost_full = flags_incoming.almost_full;

  assign tcdm_target.r_data = stream_incoming_pop.data[DW-1:0];
  if (UW > 0) begin
    assign tcdm_target.r_user = stream_incoming_pop.data[UW+DW-1:DW];
  end else begin
    assign tcdm_target.r_user = '0;
  end
  if (IW > 0) begin
    assign tcdm_target.r_id = stream_incoming_pop.data[UW+DW+IW-1:UW+DW];
  end else begin
    assign tcdm_target.r_id = '0;
  end
  if (EW > 0) begin
    assign tcdm_target.r_ecc = stream_incoming_pop.data[UW+DW+IW+EW-1:UW+DW+IW];
  end else begin
    assign tcdm_target.r_ecc = '0;
  end
  assign tcdm_target.r_opc = '0; // ignore r_opc in FIFO
  assign tcdm_target.r_valid  = stream_incoming_pop.valid;
  assign stream_incoming_pop.ready = tcdm_target.r_ready;

  // enforce protocol on incoming stream
  if      (UW > 0 && EW > 0 && IW > 0)
    assign tcdm_initiator_r_data_d = {tcdm_initiator.r_ecc, tcdm_initiator.r_id, tcdm_initiator.r_user, tcdm_initiator.r_data };
  else if (UW > 0 && EW > 0 && IW == 0)
    assign tcdm_initiator_r_data_d = {tcdm_initiator.r_ecc,                      tcdm_initiator.r_user, tcdm_initiator.r_data };
  else if (UW > 0 && EW == 0 && IW > 0)
    assign tcdm_initiator_r_data_d = {                      tcdm_initiator.r_id, tcdm_initiator.r_user, tcdm_initiator.r_data };
  else if (UW > 0 && EW == 0 && IW == 0)
    assign tcdm_initiator_r_data_d = {                                           tcdm_initiator.r_user, tcdm_initiator.r_data };
  else if (UW == 0 && EW > 0 && IW > 0)
    assign tcdm_initiator_r_data_d = {tcdm_initiator.r_ecc, tcdm_initiator.r_id,                        tcdm_initiator.r_data };
  else if (UW == 0 && EW > 0 && IW == 0)
    assign tcdm_initiator_r_data_d = {tcdm_initiator.r_ecc,                                             tcdm_initiator.r_data };
  else if (UW == 0 && EW == 0 && IW > 0)
    assign tcdm_initiator_r_data_d = {                      tcdm_initiator.r_id,                        tcdm_initiator.r_data };
  else // UW==EW==IW==0
    assign tcdm_initiator_r_data_d = tcdm_initiator.r_data;
  assign tcdm_initiator_r_valid_d = tcdm_initiator.r_valid;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      tcdm_initiator_r_valid_q <= 1'b0;
    else if(clear_i)
      tcdm_initiator_r_valid_q <= 1'b0;
    else begin
      if(tcdm_initiator_r_valid_d & stream_incoming_push.ready)
        tcdm_initiator_r_valid_q <= 1'b0;
      else if(tcdm_initiator_r_valid_d)
        tcdm_initiator_r_valid_q <= 1'b1;
      else if(tcdm_initiator_r_valid_q & stream_incoming_push.ready)
        tcdm_initiator_r_valid_q <= 1'b0;
    end
  end

  // through this buffer, the HCI Core FIFO actually tolerates mismatches with the
  // HCI protocol (rule RSP-5)
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      tcdm_initiator_r_data_q <= '0;
    else if(clear_i)
      tcdm_initiator_r_data_q <= '0;
    else if(tcdm_initiator_r_valid_d)
        tcdm_initiator_r_data_q <= tcdm_initiator_r_data_d;
  end

  hwpe_stream_fifo #(
    .DATA_WIDTH ( UW+IW+EW+DW ),
    .FIFO_DEPTH ( FIFO_DEPTH  ),
    .LATCH_FIFO ( LATCH_FIFO  )
  ) i_fifo_incoming (
    .clk_i   ( clk_i                      ),
    .rst_ni  ( rst_ni                     ),
    .clear_i ( clear_i                    ),
    .flags_o ( flags_incoming             ),
    .push_i  ( stream_incoming_push.sink  ),
    .pop_o   ( stream_incoming_pop.source )
  );

  // wrap tcdm outgoing ports into a stream
  if      (UW > 0 && EW > 0 && IW > 0)
    assign stream_outgoing_push.data = { tcdm_target.ecc, tcdm_target.add, tcdm_target.id, tcdm_target.user, tcdm_target.data, tcdm_target.be, tcdm_target.wen };
  else if (UW > 0 && EW > 0 && IW == 0)
    assign stream_outgoing_push.data = { tcdm_target.ecc, tcdm_target.add,                 tcdm_target.user, tcdm_target.data, tcdm_target.be, tcdm_target.wen };
  else if (UW > 0 && EW == 0 && IW > 0)
    assign stream_outgoing_push.data = {                  tcdm_target.add, tcdm_target.id, tcdm_target.user, tcdm_target.data, tcdm_target.be, tcdm_target.wen };
  else if (UW > 0 && EW == 0 && IW == 0)
    assign stream_outgoing_push.data = {                  tcdm_target.add,                 tcdm_target.user, tcdm_target.data, tcdm_target.be, tcdm_target.wen };
  else if (UW == 0 && EW > 0 && IW > 0)
    assign stream_outgoing_push.data = { tcdm_target.ecc, tcdm_target.add, tcdm_target.id,                   tcdm_target.data, tcdm_target.be, tcdm_target.wen };
  else if (UW == 0 && EW > 0 && IW == 0)
    assign stream_outgoing_push.data = { tcdm_target.ecc, tcdm_target.add,                                   tcdm_target.data, tcdm_target.be, tcdm_target.wen };
  else if (UW == 0 && EW == 0 && IW > 0)
    assign stream_outgoing_push.data = {                  tcdm_target.add, tcdm_target.id,                   tcdm_target.data, tcdm_target.be, tcdm_target.wen };
  else // UW==EW==IW==0
    assign stream_outgoing_push.data = {                  tcdm_target.add,                                   tcdm_target.data, tcdm_target.be, tcdm_target.wen };

  assign stream_outgoing_push.strb = '1;
  assign stream_outgoing_push.valid = tcdm_target.req;
  assign tcdm_target.gnt = stream_outgoing_push.ready;

  logic [AW+UW+IW+EW+DW+DW/BW+1-1:0] stream_outgoing_pop_data;
  assign stream_outgoing_pop_data = stream_outgoing_pop.data; 

  logic [AW-1:0]    tcdm_initiator_add;
  logic [DW-1:0]    tcdm_initiator_data;
  logic [UW-1:0]    tcdm_initiator_user;
  logic [IW-1:0]    tcdm_initiator_id;
  logic [EW-1:0]    tcdm_initiator_ecc;
  logic [DW/BW-1:0] tcdm_initiator_be;
  logic             tcdm_initiator_wen;
  assign tcdm_initiator.add  = tcdm_initiator_add;
  assign tcdm_initiator.data = tcdm_initiator_data;
  assign tcdm_initiator.user = tcdm_initiator_user;
  assign tcdm_initiator.id   = tcdm_initiator_id;
  assign tcdm_initiator.ecc  = tcdm_initiator_ecc;
  assign tcdm_initiator.be   = tcdm_initiator_be;
  assign tcdm_initiator.wen  = tcdm_initiator_wen;
  if      (UW > 0 && EW > 0 && IW > 0) begin
    assign { >> { tcdm_initiator_ecc, tcdm_initiator_add, tcdm_initiator_id, tcdm_initiator_user, tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen }} = stream_outgoing_pop_data;
  end
  else if (UW > 0 && EW > 0 && IW == 0) begin
    assign { >> { tcdm_initiator_ecc, tcdm_initiator_add,                    tcdm_initiator_user, tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen }} = stream_outgoing_pop_data;
    assign tcdm_initiator_id = '0;
  end
  else if (UW > 0 && EW == 0 && IW > 0) begin
    assign { >> {                     tcdm_initiator_add, tcdm_initiator_id, tcdm_initiator_user, tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen }} = stream_outgoing_pop_data;
    assign tcdm_initiator_ecc = '0;
  end
  else if (UW > 0 && EW == 0 && IW == 0) begin
    assign { >> {                     tcdm_initiator_add,                    tcdm_initiator_user, tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen }} = stream_outgoing_pop_data;
    assign tcdm_initiator_ecc = '0;
    assign tcdm_initiator_id = '0;
  end
  else if (UW == 0 && EW > 0 && IW > 0) begin
    assign { >> { tcdm_initiator_ecc, tcdm_initiator_add, tcdm_initiator_id,                      tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen }} = stream_outgoing_pop_data;
    assign tcdm_initiator_user = '0;
  end
  else if (UW == 0 && EW > 0 && IW == 0) begin
    assign { >> { tcdm_initiator_ecc, tcdm_initiator_add,                                         tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen }} = stream_outgoing_pop_data;
    assign tcdm_initiator_id = '0;
    assign tcdm_initiator_user = '0;
  end
  else if (UW == 0 && EW == 0 && IW > 0) begin
    assign { >> {                     tcdm_initiator_add, tcdm_initiator_id,                      tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen }} = stream_outgoing_pop_data;
    assign tcdm_initiator_ecc = '0;
    assign tcdm_initiator_user = '0;
  end
  else begin // UW==EW==IW==0
    assign { >> {                     tcdm_initiator_add,                                         tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen }} = stream_outgoing_pop_data;
    assign tcdm_initiator_ecc = '0;
    assign tcdm_initiator_id = '0;
    assign tcdm_initiator_user = '0;
  end
  // FIXME: if incoming_fifo_not_full makes a 1->0 transition in the cycle after a non-granted request (req=1, gnt=0),
  //        tcdm_initiator.req will go down, causing a RQ-4 protocol violation.
  //        This should be harmless, but should still be fixed in a future commit.
  // Lower the request if
  //  1) the incoming FIFO is already full
  //  2) the incoming FIFO is almost full, a valid incoming response is arriving, and the incoming FIFO consumer side is not ready to receive the response
  assign tcdm_initiator.req = stream_outgoing_pop.valid & incoming_fifo_not_full & ~(incoming_fifo_almost_full & tcdm_initiator.r_valid & ~tcdm_target.r_ready);
  assign tcdm_initiator.r_ready = incoming_fifo_not_full;
  assign stream_outgoing_pop.ready = tcdm_initiator.gnt; // if incoming_fifo_not_full=0, gnt is already 0, because req=0

  hwpe_stream_fifo #(
    .DATA_WIDTH ( AW+UW+IW+EW+DW+DW/BW+1 ),
    .FIFO_DEPTH ( FIFO_DEPTH             ),
    .LATCH_FIFO ( LATCH_FIFO             )
  ) i_fifo_outgoing (
    .clk_i   ( clk_i                      ),
    .rst_ni  ( rst_ni                     ),
    .clear_i ( clear_i                    ),
    .flags_o ( flags_outgoing             ),
    .push_i  ( stream_outgoing_push.sink  ),
    .pop_o   ( stream_outgoing_pop.source )
  );

  assign flags_o.empty = flags_incoming.empty & flags_outgoing.empty;

/*
 * ECC Handshake signals
 */
  if(EHW > 0) begin : ecc_handshake_gen
    assign tcdm_initiator.ereq     = '{default: {tcdm_initiator.req}};
    assign tcdm_target.egnt        = '{default: {tcdm_target.gnt}};
    assign tcdm_target.r_evalid    = '{default: {tcdm_target.r_valid}};
    assign tcdm_initiator.r_eready = '{default: {tcdm_initiator.r_ready}};
  end
  else begin : no_ecc_handshake_gen
    assign tcdm_initiator.ereq     = '0;
    assign tcdm_target.egnt        = '1; // assign all gnt's to 1
    assign tcdm_target.r_evalid    = '0;
    assign tcdm_initiator.r_eready = '1; // assign all gnt's to 1 
  end

/*
 * Interface size asserts
 */
`ifndef SYNTHESIS
`ifndef VERILATOR
  initial
    dw : assert(tcdm_target.DW == tcdm_initiator.DW);
  initial
    bw : assert(tcdm_target.BW == tcdm_initiator.BW);
  initial
    aw : assert(tcdm_target.AW == tcdm_initiator.AW);
  initial
    uw : assert(tcdm_target.UW == tcdm_initiator.UW);
  initial
    iw : assert(tcdm_target.IW == tcdm_initiator.IW);
  initial
    ew : assert(tcdm_target.EW == tcdm_initiator.EW);
  initial
    ehw : assert(tcdm_target.EHW == tcdm_initiator.EHW);
  initial begin : depth_check
    if (FIFO_DEPTH % 2 != 0) begin
      $error("hci_core_fifo FIFO_DEPTH must be a multiple of 2!");
    end
  end
  `HCI_SIZE_CHECK_ASSERTS(tcdm_initiator);

`endif
`endif

endmodule : hci_core_fifo
