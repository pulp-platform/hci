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

import hwpe_stream_package::*;
import hci_package::*;

module hci_core_fifo #(
  parameter int unsigned FIFO_DEPTH = 8,
  parameter int unsigned DW = hci_package::DEFAULT_DW,
  parameter int unsigned BW = hci_package::DEFAULT_BW,
  parameter int unsigned AW = hci_package::DEFAULT_AW, /// addr width
  parameter int unsigned WW = hci_package::DEFAULT_WW, /// width of a "word" in bits (default 32)
  parameter int unsigned OW = AW, /// intra-bank offset width, defaults to addr width
  parameter int unsigned UW = hci_package::DEFAULT_UW,
  parameter int unsigned LATCH_FIFO = 0
)
(
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         clear_i,

  output flags_fifo_t  flags_o,

  hci_core_intf.slave  tcdm_slave,
  hci_core_intf.master tcdm_master
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
    .DATA_WIDTH ( DW )
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
    assign tcdm_slave.r_data = stream_incoming_pop.data[DW-1:0];
    assign tcdm_slave.r_user = stream_incoming_pop.data[UW+DW-1:DW];
  end else begin
    assign tcdm_slave.r_data = stream_incoming_pop.data;
    assign tcdm_slave.r_user = '0;
  end
  assign tcdm_slave.r_valid  = stream_incoming_pop.valid;
  assign stream_incoming_pop.ready = tcdm_slave.lrdy;

  // enforce protocol on incoming stream
  if (UW > 0)
    assign tcdm_master_r_data_d = {tcdm_master.r_user, tcdm_master.r_data};
  else
    assign tcdm_master_r_data_d = tcdm_master.r_data;
  assign tcdm_master_r_valid_d = tcdm_master.r_valid;

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
    assign stream_outgoing_push.data = { tcdm_slave.add, tcdm_slave.user, tcdm_slave.data, tcdm_slave.be, tcdm_slave.wen };
  else
    assign stream_outgoing_push.data = { tcdm_slave.add, tcdm_slave.data, tcdm_slave.be, tcdm_slave.wen };
  assign stream_outgoing_push.strb = '1;
  assign stream_outgoing_push.valid = tcdm_slave.req;
  assign tcdm_slave.gnt = stream_outgoing_push.ready;

  logic [AW+UW+DW+DW/BW+1-1:0] stream_outgoing_pop_data;
  assign stream_outgoing_pop_data = stream_outgoing_pop.data; 

  logic [AW-1:0]    tcdm_master_add;
  logic [DW-1:0]    tcdm_master_data;
  logic [UW-1:0]    tcdm_master_user;
  logic [DW/BW-1:0] tcdm_master_be;
  logic             tcdm_master_wen;
  assign tcdm_master.add  = tcdm_master_add;
  assign tcdm_master.data = tcdm_master_data;
  assign tcdm_master.user = tcdm_master_user;
  assign tcdm_master.be   = tcdm_master_be;
  assign tcdm_master.wen  = tcdm_master_wen;
  if (UW > 0)
    assign { >> { tcdm_master_add, tcdm_master_user, tcdm_master_data, tcdm_master_be, tcdm_master_wen }} = stream_outgoing_pop_data;
  else
  begin
    assign { >> { tcdm_master_add, tcdm_master_data, tcdm_master_be, tcdm_master_wen }} = stream_outgoing_pop_data;
    assign tcdm_master_user = '0;
  end
  assign tcdm_master.boffs = '0; // FIXME
  assign tcdm_master.req = stream_outgoing_pop.valid & incoming_fifo_not_full;
  assign tcdm_master.lrdy = incoming_fifo_not_full;
  assign stream_outgoing_pop.ready = tcdm_master.gnt; // if incoming_fifo_not_full=0, gnt is already 0, because req=0

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
