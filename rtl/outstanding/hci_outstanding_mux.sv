/*
 * hci_core_mux_ooo.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2017-2023 ETH Zurich, University of Bologna
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
 * The **HCI dynamic OoO N-to-1 multiplexer** enables to funnel multiple HCI ports
 * into a single one. It supports out-of-order responses by means of ID.
 * As the ID is implemented as user signal, any FIFO coming after (i.e., 
 * nearer to memory side) with respect to this block must respect id
 * signals - specifically it must return them identical in the response.
 * At the end of the chain, there will typically be a `hci_core_r_id_filter`
 * block reflecting back all the IDs. This must be placed at the 0-latency 
 * boundary with the memory system.
 * Priority is normally round-robin but can also be forced from the outside
 * by setting `priority_force_i` to 1 and driving the `priority_i` array
 * to the desired priority values.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_core_mux_ooo_params:
 * .. table:: **hci_core_mux_ooo** design-time parameters.
 *
 *   +------------+-------------+--------------------------------+
 *   | **Name**   | **Default** | **Description**                |
 *   +------------+-------------+--------------------------------+
 *   | *NB_CHAN*  | 2           | Number of input HCI channels.  |
 *   +------------+-------------+--------------------------------+
 *
 */

`include "hci_helpers.svh"

module hci_outstanding_mux
  import hwpe_stream_package::*;
  import hci_package::*;
#(
  parameter int unsigned NB_CHAN = 2,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(out) = '0
)
(
  input  logic                                    clk_i,
  input  logic                                    rst_ni,
  input  logic                                    clear_i,

  input  logic                                    priority_force_i,
  input  logic [NB_CHAN-1:0][$clog2(NB_CHAN)-1:0] priority_i,

  hci_outstanding_intf.target                            in  [0:NB_CHAN-1],
  hci_outstanding_intf.initiator                         out
);

  localparam int unsigned DW  = `HCI_SIZE_GET_DW(out);
  localparam int unsigned BW  = `HCI_SIZE_GET_BW(out);
  localparam int unsigned AW  = `HCI_SIZE_GET_AW(out);
  localparam int unsigned UW  = `HCI_SIZE_GET_UW(out);
  localparam int unsigned IW  = `HCI_SIZE_GET_IW(out);

  // tcdm ports binding
  logic        [NB_CHAN-1:0]                           in_req_valid;
  logic        [NB_CHAN-1:0][AW-1:0]                   in_req_add;
  logic        [NB_CHAN-1:0]                           in_req_wen;
  logic        [NB_CHAN-1:0][DW-1:0]                   in_req_data;
  logic        [NB_CHAN-1:0][DW/BW-1:0]                in_req_be;
  logic        [NB_CHAN-1:0][hci_package::iomsb(UW):0] in_req_user;
  logic        [NB_CHAN-1:0][hci_package::iomsb(IW):0] in_req_id;

  logic        [NB_CHAN-1:0]                           in_resp_valid;
  logic        [NB_CHAN-1:0]                           in_resp_ready;

  logic [$clog2(NB_CHAN)-1:0]              rr_counter_q;
  logic [NB_CHAN-1:0][$clog2(NB_CHAN)-1:0] rr_priority_d;
  logic [$clog2(NB_CHAN)-1:0]              winner_d, winner_q;

  logic rr_counter_en_d, rr_counter_en_q;
  assign rr_counter_en_d = out.req_valid & out.req_ready;

  logic any_req_q;

  // round-robin counter
  always_ff @(posedge clk_i, negedge rst_ni)
  begin : round_robin_counter
    if(rst_ni == 1'b0) begin
      rr_counter_q <= '0;
    end
    else if (clear_i == 1'b1) begin
      rr_counter_q <= '0;
    end
    else if (rr_counter_en_d) begin
      if (rr_counter_q == NB_CHAN-1)
        rr_counter_q <= '0;
      else
        rr_counter_q <= (rr_counter_q + {{($clog2(NB_CHAN)-1){1'b0}},1'b1}); 
    end
  end

  // keep previous winner in case of no-gnt
  always_ff @(posedge clk_i, negedge rst_ni)
  begin : winner_reg
    if(rst_ni == 1'b0) begin
      winner_q <= '0;
    end
    else if (clear_i == 1'b1) begin
      winner_q <= '0;
    end
    else begin
      winner_q <= winner_d;
    end
  end

  // keep track of round-robin counter updates (= output handshakes) to enable WTA circuit
  always_ff @(posedge clk_i, negedge rst_ni)
  begin : rr_counter_en_reg
    if(rst_ni == 1'b0) begin
      rr_counter_en_q <= '0;
    end
    else if (clear_i == 1'b1) begin
      rr_counter_en_q <= '0;
    end
    else begin
      rr_counter_en_q <= rr_counter_en_d;
    end
  end

  // keep track of any input requests to enable WTA circuit
  always_ff @(posedge clk_i, negedge rst_ni)
  begin : any_req_reg
    if(rst_ni == 1'b0) begin
      any_req_q <= '0;
    end
    else if (clear_i == 1'b1) begin
      any_req_q <= '0;
    end
    else begin
      any_req_q <= |(in_req_valid);
    end
  end

  for(genvar ii=0; ii<NB_CHAN; ii++) begin: in_port_binding

    assign in_req_add       [ii] = in[ii].req_add;
    assign in_req_wen       [ii] = in[ii].req_wen;
    assign in_req_be        [ii] = in[ii].req_be;
    assign in_req_data      [ii] = in[ii].req_data;
    assign in_req_user      [ii] = in[ii].req_user;
    assign in_req_id        [ii] = ii;
    assign in_req_valid     [ii] = in[ii].req_valid;
    assign in[ii].req_ready      = (winner_d == ii) ? (in[ii].req_valid & out.req_ready) : 1'b0;

    assign in[ii].resp_data      = out.resp_data;
    assign in[ii].resp_opc       = out.resp_opc;
    assign in[ii].resp_user      = out.resp_user;
    assign in[ii].resp_id        = out.resp_id;
    assign in[ii].resp_valid     = (out.resp_id == ii) ? (out.resp_valid & in[ii].resp_ready) : 1'b0;
    assign in_resp_ready    [ii] = in[ii].resp_ready;

    // assign priorities to each port depending on round-robin counter
    assign rr_priority_d[ii] = priority_force_i ? priority_i[ii] : (rr_counter_q + ii) % NB_CHAN;

  end

  // winner-takes-all circuit for arbitration, depending on round-robin priorities
  always_comb
  begin : wta_comb
    winner_d = winner_q;
    // only re-evaluate WTA output after an output handshake or if any
    // in_req was 0, otherwise a more recent in_req could overtake an
    // older one causing a RQ3-STABILITY issue on the output side.
    if(rr_counter_en_q | ~any_req_q) begin
      winner_d = rr_counter_q;
      for(int jj=0; jj<NB_CHAN; jj++) begin
        if (in_req_valid[rr_priority_d[NB_CHAN-jj-1]] == 1'b1)
          winner_d = rr_priority_d[NB_CHAN-jj-1];
      end 
    end
  end

  // select input port depending on winner-takes-all arbitration
  assign out.req_add     = in_req_add   [winner_d];
  assign out.req_wen     = in_req_wen   [winner_d];
  assign out.req_be      = in_req_be    [winner_d];
  assign out.req_data    = in_req_data  [winner_d];
  assign out.req_user    = in_req_user  [winner_d];
  assign out.req_id      = in_req_id    [winner_d];
  assign out.req_valid   = in_req_valid [winner_d];
  assign out.resp_ready  = in_resp_ready[out.resp_id];

endmodule // hci_outstanding_mux
