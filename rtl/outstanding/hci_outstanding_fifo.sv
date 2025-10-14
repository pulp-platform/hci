/*
 * hci_outstanding_fifo.sv
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
 * The **hci_outstanding_fifo** module implements a hardware FIFO queue for
 * HCI-outstanding interfaces.
 *
 *   Mapping of HCI-outstanding and HWPE-Stream signals inside the load FIFO.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_outstanding_fifo_params:
 * .. table:: **hci_outstanding_fifo** design-time parameters.
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
 * .. _hci_outstanding_fifo_flags:
 * .. table:: **hci_outstanding_fifo** output flags.
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

module hci_outstanding_fifo
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

  hci_outstanding_intf.target    tcdm_target,
  hci_outstanding_intf.initiator tcdm_initiator
);

  localparam int unsigned DW  = `HCI_SIZE_GET_DW(tcdm_initiator);
  localparam int unsigned BW  = `HCI_SIZE_GET_BW(tcdm_initiator);
  localparam int unsigned AW  = `HCI_SIZE_GET_AW(tcdm_initiator);
  localparam int unsigned UW  = `HCI_SIZE_GET_UW(tcdm_initiator);
  localparam int unsigned IW  = `HCI_SIZE_GET_IW(tcdm_initiator);

  flags_fifo_t flags_incoming, flags_outgoing;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( AW+UW+IW+DW+DW/BW )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_outgoing_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( AW+UW+IW+DW+DW/BW )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_outgoing_pop (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( UW+IW+DW )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_incoming_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( UW+IW+DW )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_incoming_pop (
    .clk ( clk_i )
  );

  /*******************************************/
  /** target.resp* <- stream_incoming_pop.* **/
  /*******************************************/

  assign tcdm_target.resp_data = stream_incoming_pop.data[DW-1:0];
  if (UW > 0) begin
    assign tcdm_target.resp_user = stream_incoming_pop.data[UW+DW-1:DW];
  end else begin
    assign tcdm_target.resp_user = '0;
  end
  if (IW > 0) begin
    assign tcdm_target.resp_id = stream_incoming_pop.data[UW+DW+IW-1:UW+DW];
  end else begin
    assign tcdm_target.resp_id = '0;
  end
  assign tcdm_target.resp_opc = '0; // ignore r_opc in FIFO
  assign tcdm_target.resp_valid  = stream_incoming_pop.valid;
  assign stream_incoming_pop.ready = tcdm_target.resp_ready;

  /****************************************************/
  /** stream_incoming_push.* <- tcdm_initiator.resp* **/
  /****************************************************/

  logic                tcdm_initiator_r_valid_d, tcdm_initiator_r_valid_q;
  logic [UW+IW+DW-1:0] tcdm_initiator_r_data_d, tcdm_initiator_r_data_q;

  if      (UW > 0 && IW > 0)
    assign stream_incoming_push.data = { tcdm_initiator.resp_id, tcdm_initiator.resp_user, tcdm_initiator.resp_data };
  else if (UW > 0 && IW == 0)
    assign stream_incoming_push.data = {                         tcdm_initiator.resp_user, tcdm_initiator.resp_data };
  else if (UW == 0 && IW > 0)
    assign stream_incoming_push.data = { tcdm_initiator.resp_id,                           tcdm_initiator.resp_data };
  else // UW==IW==0
    assign stream_incoming_push.data = tcdm_initiator.resp_data;

  assign stream_incoming_push.strb = '1;
  assign stream_incoming_push.valid = tcdm_initiator.resp_valid;
  assign tcdm_initiator.resp_ready = stream_incoming_push.ready;


  hwpe_stream_fifo #(
    .DATA_WIDTH ( UW+IW+DW ),
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

  /************************************************/
  /** stream_outgoing_push.* <- tcdm_target.req* **/
  /************************************************/

  // wrap tcdm outgoing ports into a stream
  if      (UW > 0 && IW > 0)
    assign stream_outgoing_push.data = { tcdm_target.req_add, tcdm_target.req_id, tcdm_target.req_user, tcdm_target.req_data, tcdm_target.req_be, tcdm_target.req_wen };
  else if (UW > 0 && IW == 0)
    assign stream_outgoing_push.data = { tcdm_target.req_add,                     tcdm_target.req_user, tcdm_target.req_data, tcdm_target.req_be, tcdm_target.req_wen };
  else if (UW == 0 && IW > 0)
    assign stream_outgoing_push.data = { tcdm_target.req_add, tcdm_target.req_id,                       tcdm_target.req_data, tcdm_target.req_be, tcdm_target.req_wen };
  else // UW==IW==0
    assign stream_outgoing_push.data = { tcdm_target.req_add,                                           tcdm_target.req_data, tcdm_target.req_be, tcdm_target.req_wen };

  assign stream_outgoing_push.strb = '1;
  assign stream_outgoing_push.valid = tcdm_target.req_valid;
  assign tcdm_target.req_ready = stream_outgoing_push.ready;

  /**************************************************/
  /** tcdm_initiator.req* <- stream_outgoing_pop.* **/
  /**************************************************/

  logic [AW+UW+IW+DW+DW/BW-1:0] stream_outgoing_pop_data;
  logic [AW-1:0]    tcdm_initiator_add;
  logic [DW-1:0]    tcdm_initiator_data;
  logic [hci_package::iomsb(UW):0]    tcdm_initiator_user;
  logic [hci_package::iomsb(IW):0]    tcdm_initiator_id;
  logic [DW/BW-1:0] tcdm_initiator_be;
  logic             tcdm_initiator_wen;

  assign stream_outgoing_pop_data = stream_outgoing_pop.data;

  if      (UW > 0 && IW > 0) begin
    assign { tcdm_initiator_add, tcdm_initiator_id, tcdm_initiator_user, tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen } = stream_outgoing_pop_data;
  end
  else if (UW > 0 && IW == 0) begin
    assign { tcdm_initiator_add,                    tcdm_initiator_user, tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen } = stream_outgoing_pop_data;
    assign tcdm_initiator_id = '0;
  end
  else if (UW == 0 && IW > 0) begin
    assign { tcdm_initiator_add, tcdm_initiator_id,                      tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen } = stream_outgoing_pop_data;
    assign tcdm_initiator_user = '0;
  end
  else begin // UW==IW==0
    assign { tcdm_initiator_add,                                         tcdm_initiator_data, tcdm_initiator_be, tcdm_initiator_wen } = stream_outgoing_pop_data;
    assign tcdm_initiator_id = '0;
    assign tcdm_initiator_user = '0;
  end

  assign tcdm_initiator.req_add  = tcdm_initiator_add;
  assign tcdm_initiator.req_data = tcdm_initiator_data;
  assign tcdm_initiator.req_user = tcdm_initiator_user;
  assign tcdm_initiator.req_id   = tcdm_initiator_id;
  assign tcdm_initiator.req_be   = tcdm_initiator_be;
  assign tcdm_initiator.req_wen  = tcdm_initiator_wen;

  assign tcdm_initiator.req_valid = stream_outgoing_pop.valid;
  assign stream_outgoing_pop.ready = tcdm_initiator.req_ready;

  hwpe_stream_fifo #(
    .DATA_WIDTH ( AW+UW+IW+DW+DW/BW ),
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
  assign flags_o.full = flags_incoming.full | flags_outgoing.full;

/*
 * Interface size asserts
 */
`ifndef SYNTHESIS
`ifndef VERILATOR
`ifndef VCS
  initial
    dw : assert(tcdm_target.DW == tcdm_initiator.DW);
  initial
    bw : assert(tcdm_target.BW == tcdm_initiator.BW);
  initial
    aw : assert(tcdm_target.AW == tcdm_initiator.AW);
  initial
    uw : assert(tcdm_target.UW == tcdm_initiator.UW);
  initial begin : depth_check
    if (FIFO_DEPTH % 2 != 0) begin
      $error("hci_outstanding_fifo FIFO_DEPTH must be a multiple of 2!");
    end
  end
`endif
`endif
`endif

endmodule : hci_outstanding_fifo
