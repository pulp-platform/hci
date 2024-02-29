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
 * HCI-Core interfaces, used to withstand data scarcity (`req`=0) or
 * backpressure (`gnt`=0), decoupling two architectural domains.
 * This FIFO is single-clock and therefore cannot be used to cross two
 * distinct clock domains.
 * The FIFO treats a HCI-Core load stream as a combination of two
 * 32-bit HWPE-Streams, one going from the `tcdm_initiator` to the `tcdm_target` interface
 * carrying the `addr` (*outgoing stream*); the other from the `tcdm_target` to the
 * `tcdm_initiator` interface, carrying the `r_data` (*incoming stream*).
 *
 * On the slave side, the `req` and `gnt` of the HCI-Core interfaces
 * are mapped on `valid` and `ready` respectively in the outgoing stream.
 * Backpressure on the incoming stream (slave side) cannot be enforced by means
 * of the HCI-Core slave interface and thus is carried by a specific
 * input `ready_i` that must be generated outside of the TCDM FIFO, typically
 * by a **hwpe_stream_source** module (output `tcdm_fifo_ready_o`).
 * On the master side, `req` is mapped to the AND of the incoming stream `ready`
 * signal and the outgoing stream `valid` signal. `gnt` is hooked to the
 * outgoing stream `ready` signal.
 * The `r_valid` is mapped on `valid` in the incoming stream.
 * :numref:`_hci_core_fifo_mapping` shows this mapping.
 *
 * .. _hci_core_fifo_mapping:
 * .. figure:: img/hci_core_fifo.*
 *   :figwidth: 90%
 *   :width: 90%
 *   :align: center
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


import hwpe_stream_package::*;
import hci_package::*;

module hci_core_fifo #(
  parameter int unsigned FIFO_DEPTH = 8,
  parameter int unsigned DW = hci_package::DEFAULT_DW,
  parameter int unsigned BW = hci_package::DEFAULT_BW,
  parameter int unsigned AW = hci_package::DEFAULT_AW, /// addr width
  parameter int unsigned UW = hci_package::DEFAULT_UW,
  parameter int unsigned LATCH_FIFO = 0
)
(
  input  logic            clk_i,
  input  logic            rst_ni,
  input  logic            clear_i,

  output flags_fifo_t     flags_o,

  hci_core_intf.target    tcdm_target,
  hci_core_intf.initiator tcdm_initiator
);

  flags_fifo_t flags_incoming, flags_outgoing;

  logic incoming_fifo_not_full;

  logic             tcdm_master_r_valid_d, tcdm_master_r_valid_q;
  logic [UW+DW-1:0] tcdm_master_r_data_d, tcdm_master_r_data_q;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( AW+UW+DW+DW/BW+1 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_outgoing_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( AW+UW+DW+DW/BW+1 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_outgoing_pop (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( UW+DW )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_incoming_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( UW+DW )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT ( 1'b1 ),
    .BYPASS_VDR_ASSERT ( 1'b1 )
`endif
  ) stream_incoming_pop (
    .clk ( clk_i )
  );

  // wrap tcdm incoming ports into a stream
  assign stream_incoming_push.data  = tcdm_master_r_valid_d ? tcdm_master_r_data_d : tcdm_master_r_data_q;
  assign stream_incoming_push.valid = tcdm_master_r_valid_d | tcdm_master_r_valid_q;
  assign stream_incoming_push.strb = '1;

  assign incoming_fifo_not_full = stream_incoming_push.ready;

  if (UW > 0) begin
    assign tcdm_target.r_data = stream_incoming_pop.data[DW-1:0];
    assign tcdm_target.r_user = stream_incoming_pop.data[UW+DW-1:DW];
  end else begin
    assign tcdm_target.r_data = stream_incoming_pop.data;
    assign tcdm_target.r_user = '0;
  end
  assign tcdm_target.r_valid  = stream_incoming_pop.valid;
  assign stream_incoming_pop.ready = tcdm_target.lrdy;

  // enforce protocol on incoming stream
  if (UW > 0)
    assign tcdm_master_r_data_d = {tcdm_initiator.r_user, tcdm_initiator.r_data};
  else
    assign tcdm_master_r_data_d = tcdm_initiator.r_data;
  assign tcdm_master_r_valid_d = tcdm_initiator.r_valid;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      tcdm_master_r_valid_q <= 1'b0;
    else if(clear_i)
      tcdm_master_r_valid_q <= 1'b0;
    else begin
      if(tcdm_master_r_valid_d & stream_incoming_push.ready)
        tcdm_master_r_valid_q <= 1'b0;
      else if(tcdm_master_r_valid_d)
        tcdm_master_r_valid_q <= 1'b1;
      else if(tcdm_master_r_valid_q & stream_incoming_push.ready)
        tcdm_master_r_valid_q <= 1'b0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      tcdm_master_r_data_q <= '0;
    else if(clear_i)
      tcdm_master_r_data_q <= '0;
    else if(tcdm_master_r_valid_d)
        tcdm_master_r_data_q <= tcdm_master_r_data_d;
  end

  hwpe_stream_fifo #(
    .DATA_WIDTH ( UW+DW      ),
    .FIFO_DEPTH ( FIFO_DEPTH ),
    .LATCH_FIFO ( LATCH_FIFO )
  ) i_fifo_incoming (
    .clk_i   ( clk_i                      ),
    .rst_ni  ( rst_ni                     ),
    .clear_i ( clear_i                    ),
    .flags_o ( flags_incoming             ),
    .push_i  ( stream_incoming_push.sink  ),
    .pop_o   ( stream_incoming_pop.source )
  );

  // wrap tcdm outgoing ports into a stream
  if (UW > 0)
    assign stream_outgoing_push.data = { tcdm_target.add, tcdm_target.user, tcdm_target.data, tcdm_target.be, tcdm_target.wen };
  else
    assign stream_outgoing_push.data = { tcdm_target.add, tcdm_target.data, tcdm_target.be, tcdm_target.wen };
  assign stream_outgoing_push.strb = '1;
  assign stream_outgoing_push.valid = tcdm_target.req;
  assign tcdm_target.gnt = stream_outgoing_push.ready;

  logic [AW+UW+DW+DW/BW+1-1:0] stream_outgoing_pop_data;
  assign stream_outgoing_pop_data = stream_outgoing_pop.data; 

  logic [AW-1:0]    tcdm_master_add;
  logic [DW-1:0]    tcdm_master_data;
  logic [UW-1:0]    tcdm_master_user;
  logic [DW/BW-1:0] tcdm_master_be;
  logic             tcdm_master_wen;
  assign tcdm_initiator.add  = tcdm_master_add;
  assign tcdm_initiator.data = tcdm_master_data;
  assign tcdm_initiator.user = tcdm_master_user;
  assign tcdm_initiator.be   = tcdm_master_be;
  assign tcdm_initiator.wen  = tcdm_master_wen;
  if (UW > 0)
    assign { >> { tcdm_master_add, tcdm_master_user, tcdm_master_data, tcdm_master_be, tcdm_master_wen }} = stream_outgoing_pop_data;
  else
  begin
    assign { >> { tcdm_master_add, tcdm_master_data, tcdm_master_be, tcdm_master_wen }} = stream_outgoing_pop_data;
    assign tcdm_master_user = '0;
  end
  assign tcdm_initiator.req = stream_outgoing_pop.valid & incoming_fifo_not_full;
  assign tcdm_initiator.lrdy = incoming_fifo_not_full;
  assign stream_outgoing_pop.ready = tcdm_initiator.gnt; // if incoming_fifo_not_full=0, gnt is already 0, because req=0

  hwpe_stream_fifo #(
    .DATA_WIDTH ( AW+UW+DW+DW/BW+1 ),
    .FIFO_DEPTH ( FIFO_DEPTH    ),
    .LATCH_FIFO ( LATCH_FIFO    )
  ) i_fifo_outgoing (
    .clk_i   ( clk_i                      ),
    .rst_ni  ( rst_ni                     ),
    .clear_i ( clear_i                    ),
    .flags_o ( flags_outgoing             ),
    .push_i  ( stream_outgoing_push.sink  ),
    .pop_o   ( stream_outgoing_pop.source )
  );

  assign flags_o.empty = flags_incoming.empty & flags_outgoing.empty;

endmodule // hci_core_fifo
