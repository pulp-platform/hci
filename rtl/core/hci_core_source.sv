/*
 * hci_core_source.sv
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

module hci_core_source
#(
  // Stream interface params
  parameter int unsigned DATA_WIDTH = 32,
  // parameter int unsigned NB_TCDM_PORTS = DATA_WIDTH/32,
  // parameter int unsigned DECOUPLED = 0,
  parameter int unsigned LATCH_FIFO  = 0,
  parameter int unsigned TRANS_CNT = 16
)
(
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,
  input logic clear_i,

  hci_core_intf.master           tcdm,
  hwpe_stream_intf_stream.source stream,

  // control plane
  input  hci_streamer_ctrl_t   ctrl_i,
  output hci_streamer_flags_t  flags_o
);

  hci_streamer_state_t cs, ns;
  flags_fifo_t addr_fifo_flags;

  logic done;
  logic address_gen_en;
  logic address_gen_clr;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 36 )
  ) addr (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 36 )
  ) addr_fifo (
    .clk ( clk_i )
  );

  // generate addresses
  hwpe_stream_addressgen_v2 i_addressgen (
    .clk_i       ( clk_i                    ),
    .rst_ni      ( rst_ni                   ),
    .test_mode_i ( test_mode_i              ),
    .enable_i    ( address_gen_en           ),
    .clear_i     ( address_gen_clr          ),
    .presample_i ( ctrl_i.req_start         ),
    .addr_o      ( addr                     ),
    .ctrl_i      ( ctrl_i.addressgen_ctrl   ),
    .flags_o     ( flags_o.addressgen_flags )
  );

  hwpe_stream_fifo #(
    .DATA_WIDTH ( 36 ),
    .FIFO_DEPTH ( 2  )
  ) i_fifo_addr (
    .clk_i   ( clk_i           ),
    .rst_ni  ( rst_ni          ),
    .clear_i ( clear_i         ),
    .flags_o ( addr_fifo_flags ),
    .push_i  ( addr            ),
    .pop_o   ( addr_fifo       )
  );

  logic                  stream_valid_q;
  logic [DATA_WIDTH-1:0] stream_data_q;

  assign tcdm.lrdy  = stream.ready;
  assign tcdm.req   = (cs != STREAMER_IDLE) ? addr_fifo.valid & stream.ready : '0;
  assign tcdm.add   = (cs != STREAMER_IDLE) ? {addr_fifo.data[30:0],2'b0}    : '0;
  assign tcdm.wen   = 1'b1;
  assign tcdm.be    = 4'h0;
  assign tcdm.data  = '0;
  assign tcdm.boffs = '0;
  assign stream.strb  = '1;
  assign stream.data  = tcdm.r_valid ? tcdm.r_data : stream_data_q;  // is this strictly necessary to keep the HWPE-Stream protocol? or can be avoided with a FIFO q?
  assign stream.valid = tcdm.r_valid               | stream_valid_q; // is this strictly necessary to keep the HWPE-Stream protocol? or can be avoided with a FIFO q?
  assign addr_fifo.ready = (cs != STREAMER_IDLE) ? addr_fifo.valid & stream.ready & tcdm.gnt : 1'b0;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      stream_valid_q <= 1'b0;
    else if(clear_i)
      stream_valid_q <= 1'b0;
    else begin
      if(tcdm.r_valid & stream.ready)
        stream_valid_q <= 1'b0;
      else if(tcdm.r_valid)
        stream_valid_q <= 1'b1;
      else if(stream_valid_q & stream.ready)
        stream_valid_q <= 1'b0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      stream_data_q <= '0;
    else if(clear_i)
      stream_data_q <= '0;
    else if(tcdm.r_valid)
      stream_data_q <= tcdm.r_data;
  end

  always_ff @(posedge clk_i, negedge rst_ni)
  begin : fsm_seq
    if(rst_ni == 1'b0) begin
      cs <= STREAMER_IDLE;
    end
    else if(clear_i == 1'b1) begin
      cs <= STREAMER_IDLE;
    end
    else begin
      cs <= ns;
    end
  end

  always_comb
  begin : fsm_comb
    ns                  = cs;
    done                = 1'b0;
    flags_o.ready_start = 1'b0;
    flags_o.done        = 1'b0;
    address_gen_en      = 1'b0;
    address_gen_clr     = clear_i;
    case(cs)
      STREAMER_IDLE : begin
        flags_o.ready_start = 1'b1;
        if(ctrl_i.req_start) begin
          ns = STREAMER_WORKING;
          address_gen_en = 1'b1;
        end
      end
      STREAMER_WORKING : begin
        address_gen_en = 1'b1;
        if(flags_o.addressgen_flags.done) begin
          ns = STREAMER_DONE;
        end
      end
      STREAMER_DONE : begin
        address_gen_en = 1'b1;
        if(addr_fifo_flags.empty) begin
          ns = STREAMER_IDLE;
          flags_o.done = 1'b1;
          done = 1'b1;
          address_gen_en  = 1'b0;
          address_gen_clr = 1'b1;
        end
      end
      default : begin
        ns = STREAMER_IDLE;
        address_gen_en = 1'b0;
      end
    endcase
  end

endmodule // hci_core_source
