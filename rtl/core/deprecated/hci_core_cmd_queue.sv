/*
 * hci_core_cmd_queue.sv
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

module hci_core_cmd_queue
#(
  // Stream interface params
  parameter int unsigned DEPTH = 2
)
(
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,
  input logic clear_i,
  input logic enable_i,

  input  hci_streamer_ctrl_t  ctrl_i,
  output hci_streamer_flags_t flags_o,
  output hci_streamer_ctrl_t  ctrl_o,
  input  hci_streamer_flags_t flags_i
);

//   typedef struct packed {
//     logic        [31:0] base_addr;
//     logic        [31:0] tot_len;    // former word_length
//     logic        [31:0] d0_len;     // former line_length
//     logic signed [31:0] d0_stride;  // former word_stride
//     logic        [31:0] d1_len;     // former block_length
//     logic signed [31:0] d1_stride;  // former line_stride
//     logic signed [31:0] d2_stride;  // former block_stride
//     logic         [1:0] dim_enable_1h;
//   } ctrl_addressgen_v3_t;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 226 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) ctrl_intf (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 226 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) ctrl_intf_fifo (
    .clk ( clk_i )
  );

  hwpe_stream_fifo #(
    .FIFO_DEPTH ( DEPTH ),
    .DATA_WIDTH ( 226   )
  ) i_fifo_ctrl (
    .clk_i   ( clk_i          ),
    .rst_ni  ( rst_ni         ),
    .clear_i ( clear_i        ),
    .flags_o (                ),
    .push_i  ( ctrl_intf      ),
    .pop_o   ( ctrl_intf_fifo )
  );

  assign ctrl_intf.data           = ctrl_i.addressgen_ctrl;
  assign ctrl_intf.valid          = ctrl_i.req_start;
  assign flags_o.ready_start      = ctrl_intf.ready;
  assign flags_o.done             = ctrl_intf.ready;
  assign flags_o.addressgen_flags = flags_i.addressgen_flags;
  assign ctrl_intf_fifo.ready     = flags_i.done;
  assign ctrl_o.req_start         = ctrl_intf_fifo.valid & flags_i.ready_start; // or done?
  assign ctrl_o.addressgen_ctrl   = ctrl_intf_fifo.data;

endmodule // hci_core_cmd_queue
