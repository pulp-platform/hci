/*
 * hci_core_sink.sv
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

module hci_core_sink
#(
  // Stream interface params
  parameter int unsigned DATA_WIDTH      = hci_package::DEFAULT_DW,
  parameter int unsigned TCDM_FIFO_DEPTH = 0,
  parameter int unsigned TRANS_CNT       = 16
)
(
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,
  input logic clear_i,
  input logic enable_i,

  hci_core_intf.master           tcdm,
  hwpe_stream_intf_stream.sink   stream,

  // control plane
  input  hci_streamer_ctrl_t  ctrl_i,
  output hci_streamer_flags_t flags_o
);

  hci_streamer_state_t cs, ns;
  flags_fifo_t addr_fifo_flags;

  logic address_gen_en;
  logic address_gen_clr;
  logic done;

  logic tcdm_inflight;

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

  hci_core_intf #(
    .DW ( DATA_WIDTH )
  ) tcdm_prefifo (
    .clk ( clk_i )
  );

  hwpe_stream_addressgen_v3 i_addressgen (
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

  logic address_cnt_en, address_cnt_clr;
  logic [TRANS_CNT-1:0] address_cnt_d, address_cnt_q;

  logic [DATA_WIDTH-1:0]   stream_data_misaligned;
  logic [DATA_WIDTH/8-1:0] stream_strb_misaligned;
  logic [DATA_WIDTH-1:0]   stream_data_aligned;
  logic [DATA_WIDTH/8-1:0] stream_strb_aligned;

  assign stream_data_misaligned = stream.data;
  assign stream_strb_misaligned = stream.strb;

  always_comb
  begin
    stream_data_aligned = '0;
    stream_strb_aligned = '0;
    case(addr_fifo.data[1:0])
      2'b00: begin
        stream_data_aligned[DATA_WIDTH-32-1:0]     = stream_data_misaligned[DATA_WIDTH-32-1:0];
        stream_strb_aligned[(DATA_WIDTH-32)/8-1:0] = stream_strb_misaligned[(DATA_WIDTH-32)/8-1:0];
      end
      2'b01: begin
        stream_data_aligned[DATA_WIDTH-24-1:8]     = stream_data_misaligned[DATA_WIDTH-32-1:0];
        stream_strb_aligned[(DATA_WIDTH-24)/8-1:1] = stream_strb_misaligned[(DATA_WIDTH-32)/8-1:0];
      end
      2'b10: begin
        stream_data_aligned[DATA_WIDTH-16-1:16]    = stream_data_misaligned[DATA_WIDTH-32-1:0];
        stream_strb_aligned[(DATA_WIDTH-16)/8-1:2] = stream_strb_misaligned[(DATA_WIDTH-32)/8-1:0];
      end
      2'b11: begin
        stream_data_aligned[DATA_WIDTH-8-1:24]     = stream_data_misaligned[DATA_WIDTH-32-1:0];
        stream_strb_aligned[(DATA_WIDTH-8)/8-1:3]  = stream_strb_misaligned[(DATA_WIDTH-32)/8-1:0];
      end
    endcase
  end

  // hci port binding
  assign tcdm_prefifo.req   = (cs != STREAMER_IDLE) ? stream.valid & addr_fifo.valid : '0;
  assign tcdm_prefifo.add   = (cs != STREAMER_IDLE) ? {addr_fifo.data[31:2],2'b0}    : '0;
  assign tcdm_prefifo.wen   = '0;
  assign tcdm_prefifo.be    = (cs != STREAMER_IDLE) ? stream_strb_aligned            : '0;
  assign tcdm_prefifo.data  = (cs != STREAMER_IDLE) ? stream_data_aligned            : '0;
  assign tcdm_prefifo.boffs = '0;
  assign tcdm_prefifo.lrdy  = '1;
  assign stream.ready    = ~stream.valid | (tcdm_prefifo.gnt & addr_fifo.valid);
  assign addr_fifo.ready =  stream.valid & stream.ready;

  // unimplemented user bits = 0
  assign tcdm_prefifo.user = '0;

  generate

    if(TCDM_FIFO_DEPTH != 0) begin: tcdm_fifos_gen

      hwpe_stream_tcdm_fifo_store #(
        .FIFO_DEPTH ( TCDM_FIFO_DEPTH )
      ) i_tcdm_fifo (
        .clk_i       ( clk_i        ),
        .rst_ni      ( rst_ni       ),
        .clear_i     ( clear_i      ),
        .tcdm_slave  ( tcdm_prefifo ),
        .tcdm_master ( tcdm         ),
        .flags_o     (              )
      );

    end
    else begin: no_tcdm_fifos_gen

      hci_core_assign i_tcdm_assign (
        .tcdm_slave  ( tcdm_prefifo ),
        .tcdm_master ( tcdm         )
      );

    end

  endgenerate

  assign tcdm_inflight = tcdm.req;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin : done_sink_ff
    if(~rst_ni)
      flags_o.done <= 1'b0;
    else if(clear_i)
      flags_o.done <= 1'b0;
    else if(enable_i)
      flags_o.done <= done;
  end

  always_ff @(posedge clk_i, negedge rst_ni)
  begin : fsm_seq
    if(rst_ni == 1'b0) begin
      cs <= STREAMER_IDLE;
    end
    else if(clear_i == 1'b1) begin
      cs <= STREAMER_IDLE;
    end
    else if(enable_i) begin
      cs <= ns;
    end
  end

  always_comb
  begin : fsm_comb
    ns                  = cs;
    done                = 1'b0;
    flags_o.ready_start = 1'b0;
    address_gen_en      = 1'b0;
    address_gen_clr     = clear_i;
    address_cnt_clr = 1'b0;
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
        if(address_cnt_q==ctrl_i.addressgen_ctrl.tot_len) begin
          ns = STREAMER_IDLE;
          done = 1'b1;
          address_gen_en  = 1'b0;
          address_gen_clr = 1'b1;
          address_cnt_clr = 1'b1;
        end
      end
    endcase
  end

  assign address_cnt_en = addr_fifo.valid & addr_fifo.ready;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      address_cnt_q <= '0;
    else if(clear_i | address_cnt_clr)
      address_cnt_q <= '0;
    else if(enable_i & address_cnt_en)
      address_cnt_q <= address_cnt_d;
  end
  assign address_cnt_d = address_cnt_q + 1;

endmodule // hci_core_sink
