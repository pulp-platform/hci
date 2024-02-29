/*
 * hci_core_sink.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2014-2022 ETH Zurich, University of Bologna
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
 * The **hci_core_sink** module is the high-level sink streamer
 * performing a series of stores on a HCI-Core interface
 * from an incoming HWPE-Stream data stream from a HWPE engine/datapath.
 * The sink streamer is a composite module that makes use of many other
 * fundamental IPs.
 *
 * Fundamentally, a sink streamer acts as a specialized DMA engine acting
 * out a predefined pattern from an **hwpe_stream_addressgen_v3** to perform
 * a burst of stores via a HCI-Core interface, consuming a HWPE-Stream data
 * stream into the HCI-Core `data` field.
 * The sink streamer is insensitive to memory latency.
 * This is due to the nature of store streams, which are unidirectional
 * (i.e. `addr` and `data` move in the same direction).
 *
 * Misaligned accesses are supported by widening the HCI-Core data width of 32
 * bits compared to the HWPE-Stream that gets consumed by the streamer.
 * The stream is shifted according to the address alignment and invalid bytes
 * are disabled by unsetting their `strb`. This feature can be deactivated by
 * unsetting the `MISALIGNED_ACCESS` parameter; in this case, the sink will
 * only work correctly if all data is aligned to a word boundary.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_core_sink_params:
 * .. table:: **hci_core_sink** design-time parameters.
 *
 *   +---------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | **Name**            | **Default** | **Description**                                                                                                        |
 *   +---------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *TCDM_FIFO_DEPTH*   | 2           | If >0, the module produces a HWPE-MemDecoupled interface and includes a TCDM FIFO of this depth.                       |
 *   +---------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *DATA_WIDTH*        | 32          | Width of input/output streams.                                                                                         |
 *   +---------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *TRANS_CNT*         | 16          | Number of bits supported in the transaction counter of the address generator, which will overflow at 2^ `TRANS_CNT`.   |
 *   +---------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *   | *MISALIGNED_ACCESS* | 1           | If set to 0, the sink will not support non-word-aligned HWPE-Mem accesses.                                             |
 *   +---------------------+-------------+------------------------------------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_core_sink_ctrl:
 * .. table:: **hci_core_sink** input control signals.
 *
 *   +-------------------+------------------------+----------------------------------------------------------------------------+
 *   | **Name**          | **Type**               | **Description**                                                            |
 *   +-------------------+------------------------+----------------------------------------------------------------------------+
 *   | *req_start*       | `logic`                | When 1, the sink streamer operation is started if it is ready.             |
 *   +-------------------+------------------------+----------------------------------------------------------------------------+
 *   | *addressgen_ctrl* | `ctrl_addressgen_v3_t` | Configuration of the address generator (see **hwpe_stream_addresgen_v3**). |
 *   +-------------------+------------------------+----------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_core_sink_flags:
 * .. table:: **hci_core_sink** output flags.
 *
 *   +--------------------+------------------------+-----------------------------------------------------------------------------------------------+
 *   | **Name**           | **Type**               | **Description**                                                                               |
 *   +--------------------+------------------------+-----------------------------------------------------------------------------------------------+
 *   | *ready_start*      | `logic`                | 1 when the sink streamer is ready to start operation, from the first IDLE state cycle on.     |
 *   +--------------------+------------------------+-----------------------------------------------------------------------------------------------+
 *   | *done*             | `logic`                | 1 for one cycle when the streamer ends operation, in the cycle before it goes to IDLE state . |
 *   +--------------------+------------------------+-----------------------------------------------------------------------------------------------+
 *   | *addressgen_flags* | `flags_addressgen_v3_t`| Address generator flags (see **hwpe_stream_addresgen_v3**).                                   |
 *   +--------------------+------------------------+-----------------------------------------------------------------------------------------------+
 *
 */

import hwpe_stream_package::*;
import hci_package::*;

module hci_core_sink
#(
  // Stream interface params
  parameter int unsigned DATA_WIDTH      = 32, //hci_package::DEFAULT_DW,
  parameter int unsigned TCDM_FIFO_DEPTH = 0,
  parameter int unsigned TRANS_CNT       = 16,
  parameter int unsigned MISALIGNED_ACCESSES = 1
)
(
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,
  input logic clear_i,
  input logic enable_i,

  hci_core_intf.initiator      tcdm,
  hwpe_stream_intf_stream.sink stream,

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

  if (MISALIGNED_ACCESSES==1 ) begin : missaligned_access_gen
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
  end
  else begin
    assign stream_data_aligned[DATA_WIDTH-1:0]   = stream_data_misaligned[DATA_WIDTH-1:0];
    assign stream_strb_aligned[DATA_WIDTH/8-1:0] = stream_strb_misaligned[DATA_WIDTH/8-1:0];
  end

  // hci port binding
  assign tcdm_prefifo.req   = (cs != STREAMER_IDLE) ? stream.valid & addr_fifo.valid : '0;
  assign tcdm_prefifo.add   = (cs != STREAMER_IDLE) ? {addr_fifo.data[31:2],2'b0}    : '0;
  assign tcdm_prefifo.wen   = '0;
  assign tcdm_prefifo.be    = (cs != STREAMER_IDLE) ? stream_strb_aligned            : '0;
  assign tcdm_prefifo.data  = (cs != STREAMER_IDLE) ? stream_data_aligned            : '0;
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
        .clk_i          ( clk_i        ),
        .rst_ni         ( rst_ni       ),
        .clear_i        ( clear_i      ),
        .tcdm_target    ( tcdm_prefifo ),
        .tcdm_initiator ( tcdm         ),
        .flags_o        (              )
      );

    end
    else begin: no_tcdm_fifos_gen

      hci_core_assign i_tcdm_assign (
        .tcdm_target    ( tcdm_prefifo ),
        .tcdm_initiator ( tcdm         )
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
