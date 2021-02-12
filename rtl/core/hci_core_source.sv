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
  parameter int unsigned DATA_WIDTH = hci_package::DEFAULT_DW,
  // parameter int unsigned USER_WIDTH = hci_package::DEFAULT_UW, // User signals not implemented
  parameter int unsigned LATCH_FIFO  = 0,
  parameter int unsigned TRANS_CNT = 16,
  parameter int unsigned ADDR_MIS_DEPTH = 8, // Beware: this must be >= the maximum latency between TCDM gnt and TCDM r_valid!!!
  parameter int unsigned MISALIGNED_ACCESSES = 1
)
(
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,
  input logic clear_i,
  input logic enable_i,

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
    .DATA_WIDTH ( 32 )
  ) addr (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 32 )
  ) addr_fifo (
    .clk ( clk_i )
  );

  // generate addresses
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

  logic                  stream_valid_q;
  logic [DATA_WIDTH-1:0] stream_data_q;
  logic [1:0]            addr_misaligned_q;
  logic                  addr_misaligned_valid;
  logic [DATA_WIDTH-1:0] stream_data_misaligned;
  logic [DATA_WIDTH-1:0] stream_data_aligned;

  logic stream_cnt_en, stream_cnt_clr;
  logic [TRANS_CNT-1:0] stream_cnt_d, stream_cnt_q;

  // this is simply exploiting the fact that we can make a wider data access than strictly necessary!
  assign stream_data_misaligned = tcdm.r_valid ? tcdm.r_data : stream_data_q; // is this strictly necessary to keep the HWPE-Stream protocol? or can be avoided with a FIFO q?

  if (MISALIGNED_ACCESSES==1 ) begin : missaligned_access_gen
    always_comb
    begin
      stream_data_aligned = '0;
      case(addr_misaligned_q)
        2'b00: begin
          stream_data_aligned[DATA_WIDTH-32-1:0] = stream_data_misaligned[DATA_WIDTH-32-1:0];
        end
        2'b01: begin
          stream_data_aligned[DATA_WIDTH-32-1:0] = stream_data_misaligned[DATA_WIDTH-24-1:8];
        end
        2'b10: begin
          stream_data_aligned[DATA_WIDTH-32-1:0] = stream_data_misaligned[DATA_WIDTH-16-1:16];
        end
        2'b11: begin
          stream_data_aligned[DATA_WIDTH-32-1:0] = stream_data_misaligned[DATA_WIDTH-8-1:24];
        end
      endcase
    end
  end
  else begin
    assign stream_data_aligned[DATA_WIDTH-1:0] = stream_data_misaligned[DATA_WIDTH-1:0];
  end

  assign tcdm.lrdy  = stream.ready;
  assign tcdm.req   = (cs != STREAMER_IDLE) ? addr_fifo.valid & stream.ready : '0;
  assign tcdm.add   = (cs != STREAMER_IDLE) ? {addr_fifo.data[31:2],2'b0}    : '0;
  assign tcdm.wen   = 1'b1;
  assign tcdm.be    = 4'h0;
  assign tcdm.data  = '0;
  assign tcdm.boffs = '0;
  assign tcdm.user  = '0;
  assign stream.strb  = '1;
  assign stream.data  = stream_data_aligned;
  assign stream.valid = enable_i & (tcdm.r_valid | stream_valid_q); // is this strictly necessary to keep the HWPE-Stream protocol? or can be avoided with a FIFO q?
  assign addr_fifo.ready = (cs != STREAMER_IDLE) ? addr_fifo.valid & stream.ready & tcdm.gnt : 1'b0;
  
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 8 ) // only 2 significant
  ) addr_misaligned_push (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 8 ) // only 2 significant
  ) addr_misaligned_pop (
    .clk ( clk_i )
  );
  assign addr_misaligned_push.data  = {6'b0, addr_fifo.data[1:0]};
  assign addr_misaligned_push.strb  = '1;
  assign addr_misaligned_push.valid = enable_i & tcdm.req & tcdm.gnt; // BEWARE: considered always ready!!!
  assign addr_misaligned_pop.ready  = (tcdm.r_valid | stream_valid_q) & stream.ready;
  assign addr_misaligned_q = addr_misaligned_pop.data[1:0];

  hwpe_stream_fifo #(
    .DATA_WIDTH ( 8              ), // only [1:0] significant
    .FIFO_DEPTH ( ADDR_MIS_DEPTH )
  ) i_addr_misaligned_fifo (
    .clk_i   ( clk_i                ),
    .rst_ni  ( rst_ni               ),
    .clear_i ( clear_i              ),
    .flags_o (                      ),
    .push_i  ( addr_misaligned_push ),
    .pop_o   ( addr_misaligned_pop  )
  );

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      stream_valid_q <= 1'b0;
    else if(clear_i)
      stream_valid_q <= 1'b0;
    else if(enable_i) begin
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
    else if(enable_i & tcdm.r_valid)
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
    else if(enable_i) begin
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
    stream_cnt_clr      = 1'b0;
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
        if((addr_fifo_flags.empty==1'b1) && (stream_cnt_q==ctrl_i.addressgen_ctrl.tot_len)) begin
          ns = STREAMER_IDLE;
          flags_o.done = 1'b1;
          done = 1'b1;
          address_gen_en  = 1'b0;
          address_gen_clr = 1'b1;
          stream_cnt_clr = 1'b1;
        end
      end
    endcase
  end

  assign stream_cnt_en = stream.valid & stream.ready;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      stream_cnt_q <= '0;
    else if(clear_i | stream_cnt_clr)
      stream_cnt_q <= '0;
    else if(enable_i & stream_cnt_en)
      stream_cnt_q <= stream_cnt_d;
  end
  assign stream_cnt_d = stream_cnt_q + 1;

endmodule // hci_core_source
