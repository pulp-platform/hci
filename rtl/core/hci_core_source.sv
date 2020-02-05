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

/**
 * The **hwpe_stream_source** module is the high-level source streamer
 * performing a series of loads on a HWPE-Mem or HWPE-MemDecoupled interface
 * and producing a HWPE-Stream data stream to feed a HWPE engine/datapath.
 * The source streamer is a composite module that makes use of many other
 * fundamental IPs. Its architecture is shown in :numfig: `_hwpe_stream_source_archi`.
 *
 * .. _hwpe_stream_source_archi:
 * .. figure:: img/hwpe_stream_source_archi.*
 *   :figwidth: 90%
 *   :width: 90%
 *   :align: center
 *
 *   Architecture of the source streamer.
 *
 * Fundamentally, a source streamer acts as a specialized DMA engine acting
 * out a predefined pattern from an **hwpe_stream_addressgen** to perform
 * a burst of loads via a HWPE-Mem interface, producing a HWPE-Stream
 * data stream from the HWPE-Mem `r_data` field.
 *
 * Depending on the `DECOUPLED` parameter, the streamer supports delayed
 * accesses using a HWPE-MemDecoupled interface.
 * The source streamer does not include any TCDM FIFO inside on its own;
 * rather, it provides a specific `tcdm_fifo_ready_o`
 * output signal that can be hooked to an external **hwpe_stream_tcdm_fifo_load**.
 * `tcdm_fifo_ready_o` provides a backpressure mechanism from the source
 * streamer to the TCDM FIFO (this is unnecessary in the case of TCDM FIFOs for
 * store).
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_source_params:
 * .. table:: **hwpe_stream_source** design-time parameters.
 *
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | **Name**          | **Default** | **Description**                                                                                                        |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *DECOUPLED*       | 0           | If 1, the module expects a HWPE-MemDecoupled interface instead of HWPE-Mem.                                            |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *DATA_WIDTH*      | 32          | Width of input/output streams (multiple of 32).                                                                        |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *LATCH_FIFO*      | 0           | If 1, use latches instead of flip-flops (requires special constraints in synthesis).                                   |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *TRANS_CNT*       | 16          | Number of bits supported in the transaction counter of the address generator, which will overflow at 2^ `TRANS_CNT`.   |
 *   +-------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_source_ctrl:
 * .. table:: **hwpe_stream_source** input control signals.
 *
 *   +-------------------+---------------------+-------------------------------------------------------------------------+
 *   | **Name**          | **Type**            | **Description**                                                         |
 *   +-------------------+---------------------+-------------------------------------------------------------------------+
 *   | *req_start*       | `logic`             | When 1, the source streamer operation is started if it is ready.        |
 *   +-------------------+---------------------+-------------------------------------------------------------------------+
 *   | *addressgen_ctrl* | `ctrl_addressgen_t` | Configuration of the address generator (see **hwpe_stream_addresgen**). |
 *   +-------------------+---------------------+-------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hwpe_stream_source_flags:
 * .. table:: **hwpe_stream_source** output flags.
 *
 *   +--------------------+----------------------+----------------------------------------------------------+
 *   | **Name**           | **Type**             | **Description**                                          |
 *   +--------------------+----------------------+----------------------------------------------------------+
 *   | *ready_start*      | `logic`              | 1 when the source streamer is ready to start operation.  |
 *   +--------------------+----------------------+----------------------------------------------------------+
 *   | *done*             | `logic`              | 1 for one cycle when the streamer ends operation.        |
 *   +--------------------+----------------------+----------------------------------------------------------+
 *   | *addressgen_flags* | `flags_addressgen_t` | Address generator flags (see **hwpe_stream_addresgen**). |
 *   +--------------------+----------------------+----------------------------------------------------------+
 *   | *ready_fifo*       | `logic`              | Unused.                                                  |
 *   +--------------------+----------------------+----------------------------------------------------------+
 *
 */

import hwpe_stream_package::*;

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
  input  ctrl_sourcesink_t   ctrl_i,
  output flags_sourcesink_t  flags_o
);

  state_sourcesink_t cs, ns;

  logic done;
  logic address_gen_en;
  logic address_gen_clr;

  logic [31:0]             gen_addr;
  logic [DATA_WIDTH/8-1:0] gen_strb;

  logic tcdm_int_req;
  logic tcdm_int_gnt;

  logic [TRANS_CNT-1:0] overall_cnt_q, overall_cnt_d;
  logic overall_none;

  logic kill_req;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( DATA_WIDTH )
  ) misaligned_stream (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( DATA_WIDTH )
  ) misaligned_fifo_stream (
    .clk ( clk_i )
  );

  // generate addresses
  hwpe_stream_addressgen #(
    .STEP         ( DATA_WIDTH/8               ),
    .TRANS_CNT    ( TRANS_CNT                  ),
    .REALIGN_TYPE ( HWPE_STREAM_REALIGN_SOURCE ),
    .DECOUPLED    ( 1                          )
  ) i_addressgen (
    .clk_i          ( clk_i                    ),
    .rst_ni         ( rst_ni                   ),
    .test_mode_i    ( test_mode_i              ),
    .enable_i       ( address_gen_en           ),
    .clear_i        ( address_gen_clr          ),
    .gen_addr_o     ( gen_addr                 ),
    .gen_strb_o     ( gen_strb                 ),
    .ctrl_i         ( ctrl_i.addressgen_ctrl   ),
    .flags_o        ( flags_o.addressgen_flags )
  );

  // realign the merged stream
  hwpe_stream_source_realign #(
    .DECOUPLED  ( 1          ),
    .DATA_WIDTH ( DATA_WIDTH )
  ) i_realign (
    .clk_i      ( clk_i                                  ),
    .rst_ni     ( rst_ni                                 ),
    .test_mode_i( test_mode_i                            ),
    .clear_i    ( clear_i                                ),
    .ctrl_i     ( flags_o.addressgen_flags.realign_flags ),
    .flags_o    (                                        ),
    .strb_i     ( gen_strb                               ),
    .push_i     ( misaligned_fifo_stream                 ),
    .pop_o      ( stream                                 )
  );

  // tcdm ports binding
  hwpe_stream_fifo #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .FIFO_DEPTH ( 2          ),
    .LATCH_FIFO ( LATCH_FIFO )
  ) i_misaligned_fifo (
    .clk_i   ( clk_i                  ),
    .rst_ni  ( rst_ni                 ),
    .clear_i ( clear_i                ),
    .flags_o (                        ),
    .push_i  ( misaligned_stream      ),
    .pop_o   ( misaligned_fifo_stream )
  );

  logic                  stream_valid_q;
  logic [DATA_WIDTH-1:0] stream_data_q;

  assign tcdm.lrdy  = misaligned_stream.ready;
  assign tcdm.req   = tcdm_int_req & ~kill_req;
  assign tcdm.add   = gen_addr;
  assign tcdm.wen   = 1'b1;
  assign tcdm.be    = 4'h0;
  assign tcdm.data  = '0;
  assign tcdm.boffs = '0;
  assign tcdm_int_gnt = tcdm.gnt;
  assign misaligned_stream.strb  = '1;
  assign misaligned_stream.data  = tcdm.r_valid ? tcdm.r_data : stream_data_q;  // is this strictly necessary to keep the HWPE-Stream protocol? or can be avoided with a FIFO q?
  assign misaligned_stream.valid = tcdm.r_valid               | stream_valid_q; // is this strictly necessary to keep the HWPE-Stream protocol? or can be avoided with a FIFO q?

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      stream_valid_q <= 1'b0;
    else if(clear_i)
      stream_valid_q <= 1'b0;
    else begin
      if(tcdm.r_valid & misaligned_stream.ready)
        stream_valid_q <= 1'b0;
      else if(tcdm.r_valid)
        stream_valid_q <= 1'b1;
      else if(stream_valid_q & misaligned_stream.ready)
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

  // finite-state machine
  always_ff @(posedge clk_i, negedge rst_ni)
  begin : fsm_seq
    if(rst_ni == 1'b0) begin
      cs <= STREAM_IDLE;
    end
    else if(clear_i == 1'b1) begin
      cs <= STREAM_IDLE;
    end
    else begin
      cs <= ns;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin : done_source_ff
    if(~rst_ni)
      flags_o.done <= 1'b0;
    else if(clear_i)
      flags_o.done <= 1'b0;
    else
      flags_o.done <= done;
  end

  logic [TRANS_CNT-1:0] request_cnt_q, request_cnt_d;

  // this is necessary to "kill" a final request that may be issued after all the legitimate
  // ones are already going through the network (may happen consequently to fencing constraints)
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      kill_req <= '0;
    end
    else if (clear_i) begin
      kill_req <= '0;
    end
    else begin
      if(cs == STREAM_IDLE)
        kill_req <= '0;
      else if(flags_o.addressgen_flags.realign_flags.enable==1'b1 && (tcdm_int_req & tcdm_int_gnt) && request_cnt_q == ctrl_i.addressgen_ctrl.trans_size) begin
        kill_req <= '1;
      end
      else if(flags_o.addressgen_flags.realign_flags.enable==1'b0 && (tcdm_int_req & tcdm_int_gnt) && request_cnt_q == ctrl_i.addressgen_ctrl.trans_size-1) begin
        kill_req <= '1;
      end
    end
  end

  always_comb
  begin : fsm_comb
    tcdm_int_req  = 1'b0;
    flags_o.ready_start = 1'b0;
    done = 1'b0;
    ns = cs;
    address_gen_en  = 1'b0;
    address_gen_clr = clear_i;
    case(cs)
      STREAM_IDLE: begin
        flags_o.ready_start = 1'b1;
        if(ctrl_i.req_start) begin
          ns = STREAM_WORKING;
        end
        else begin
          ns = STREAM_IDLE;
        end
        address_gen_en = 1'b0;
      end
      STREAM_WORKING: begin
        if(stream.ready) begin
          tcdm_int_req = 1'b1;
          if(tcdm_int_gnt)
            address_gen_en = 1'b1;
          else
            address_gen_en = 1'b0;
        end
        else begin
          tcdm_int_req = 1'b0;
          address_gen_en = 1'b0;
        end
        if(tcdm_int_req & tcdm_int_gnt) begin
          if(flags_o.addressgen_flags.in_progress == 1'b1) begin
            ns = STREAM_WORKING;
          end
          else if(overall_none == 1'b1 || overall_cnt_q != '0) begin
            ns = STREAM_DONE;
            address_gen_en = 1'b0;
          end
        end
        else begin
          ns = STREAM_WORKING;
        end
      end
      STREAM_DONE: begin
        ns = STREAM_DONE;
        if(overall_none == 1'b0 && overall_cnt_q == '0) begin
          ns = STREAM_IDLE;
          done = 1'b1;
          address_gen_clr = 1'b1;
        end
        address_gen_en = 1'b0;
      end
      default: begin
        ns = STREAM_IDLE;
        address_gen_en = 1'b0;
      end
    endcase
  end

  always_comb
  begin
    overall_cnt_d = overall_cnt_q;
    if(cs == STREAM_IDLE)
      overall_cnt_d = '0;
    else if(stream.valid & stream.ready) begin
      overall_cnt_d = overall_cnt_q + 1;
    end
    if((stream.valid & stream.ready) && overall_cnt_q == ctrl_i.addressgen_ctrl.trans_size-1) begin
      overall_cnt_d = '0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      overall_cnt_q <= '0;
    end
    else if(clear_i) begin
      overall_cnt_q <= '0;
    end
    else begin
      overall_cnt_q <= overall_cnt_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      overall_none <= 1'b1;
    end
    else if(clear_i) begin
      overall_none <= 1'b1;
    end
    else if(cs == STREAM_IDLE) begin
      overall_none <= 1'b1;
    end
    else if(stream.valid & stream.ready) begin
      overall_none <= 1'b0;
    end
  end

  always_comb
  begin
    request_cnt_d = request_cnt_q;
    if(cs == STREAM_IDLE)
      request_cnt_d = '0;
    else if(tcdm_int_req & tcdm_int_gnt) begin
      request_cnt_d = request_cnt_q + 1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      request_cnt_q <= '0;
    end
    else if(clear_i) begin
      request_cnt_q <= '0;
    end
    else begin
      request_cnt_q <= request_cnt_d;
    end
  end

endmodule // hci_core_source
