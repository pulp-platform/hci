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
 *
 * The TCDM dynamic OoO N-to-1 multiplexer enables to funnel multiple HCI ports
 * into a single one. It supports out-of-order responses by means of ID.
 * As the ID is implemented as user signal, any FIFO coming after (i.e., 
 * nearer to memory side) with respect to this block must respect user
 * signals - specifically it must return them identical in the response.
 * At the end of the chain, there will typically be a `hci_core_r_user_filter`
 * block reflecting back all the IDs. This must be placed at the 0-latency 
 * boundary with the memory system.
 * Priority is normally round-robin but can also be forced from the outside.
 */

import hwpe_stream_package::*;

module hci_core_mux_ooo
#(
  parameter int unsigned NB_CHAN = 2,
  parameter int unsigned DW = hci_package::DEFAULT_DW,
  parameter int unsigned AW = hci_package::DEFAULT_AW,
  parameter int unsigned BW = hci_package::DEFAULT_BW,
  parameter int unsigned WW = hci_package::DEFAULT_WW,
  parameter int unsigned UW = hci_package::DEFAULT_UW,
  parameter int unsigned OW = AW
)
(
  input  logic                                    clk_i,
  input  logic                                    rst_ni,
  input  logic                                    clear_i,

  input  logic                                    priority_force_i,
  input  logic [NB_CHAN-1:0][$clog2(NB_CHAN)-1:0] priority_i,

  hci_core_intf.slave                             in  [NB_CHAN-1:0],
  hci_core_intf.master                            out
);

  // tcdm ports binding
  logic        [NB_CHAN-1:0]                    in_req;
  logic        [NB_CHAN-1:0]                    in_gnt;
  logic        [NB_CHAN-1:0]                    in_lrdy;
  logic        [NB_CHAN-1:0][AW-1:0]            in_add;
  logic        [NB_CHAN-1:0]                    in_wen;
  logic        [NB_CHAN-1:0][DW-1:0]            in_data;
  logic        [NB_CHAN-1:0][DW/BW-1:0]         in_be;
  logic signed [NB_CHAN-1:0][DW/WW-1:0][OW-1:0] in_boffs;
  logic        [NB_CHAN-1:0][DW-1:0]            in_r_data;
  logic        [NB_CHAN-1:0]                    in_r_valid;
  logic        [NB_CHAN-1:0]                    in_r_opc;
  logic        [NB_CHAN-1:0][UW-1:0]            in_user; // used as id
  logic        [NB_CHAN-1:0][UW-1:0]            in_r_user; // used as id

  logic [$clog2(NB_CHAN)-1:0]              rr_counter_q;
  logic [NB_CHAN-1:0][$clog2(NB_CHAN)-1:0] rr_priority_d;
  logic [$clog2(NB_CHAN)-1:0]              winner_d;

  logic s_rr_counter_reg_en;
  assign s_rr_counter_reg_en = out.req & out.gnt;

  // round-robin counter
  always_ff @(posedge clk_i, negedge rst_ni)
  begin : round_robin_counter
    if(rst_ni == 1'b0) begin
      rr_counter_q <= '0;
    end
    else if (clear_i == 1'b1) begin
      rr_counter_q <= '0;
    end
    else if (s_rr_counter_reg_en) begin
      if (rr_counter_q == NB_CHAN-1)
        rr_counter_q <= '0;
      else
        rr_counter_q <= (rr_counter_q + {{($clog2(NB_CHAN)-1){1'b0}},1'b1}); 
    end
  end

  for(genvar ii=0; ii<NB_CHAN; ii++) begin: in_port_binding

    assign in_req     [ii] = in[ii].req;
    assign in_gnt     [ii] = in[ii].gnt;
    assign in_lrdy    [ii] = in[ii].lrdy;
    assign in_add     [ii] = in[ii].add;
    assign in_wen     [ii] = in[ii].wen;
    assign in_data    [ii] = in[ii].data;
    assign in_be      [ii] = in[ii].be;
    assign in_boffs   [ii] = in[ii].boffs;
    assign in_r_data  [ii] = in[ii].r_data;
    assign in_r_valid [ii] = in[ii].r_valid;
    assign in_r_opc   [ii] = in[ii].r_opc;
    assign in_user    [ii] = ii;

    // out.r_user used as an ID signal
    assign in[ii].gnt     = (winner_d == ii)   ? in[ii].req & out.gnt : 1'b0;
    assign in[ii].r_valid = (out.r_user == ii) ? out.r_valid : 1'b0;
    assign in[ii].r_data  = out.r_data;
    assign in[ii].r_opc   = out.r_opc;

    // assign priorities to each port depending on round-robin counter
    assign rr_priority_d[ii] = priority_force_i ? priority_i[ii] : (rr_counter_q + ii) % NB_CHAN;

  end

  // winner-takes-all circuit for arbitration, depending on round-robin priorities
  always_comb
  begin : wta_comb
    winner_d = rr_counter_q;
    for(int jj=0; jj<NB_CHAN; jj++) begin
      if (in_req[rr_priority_d[NB_CHAN-jj-1]] == 1'b1)
        winner_d = rr_priority_d[NB_CHAN-jj-1];
    end
  end

  // select input port depending on winner-takes-all arbitration
  assign out.req   = in_req   [winner_d];
  assign out.add   = in_add   [winner_d];
  assign out.wen   = in_wen   [winner_d];
  assign out.be    = in_be    [winner_d];
  assign out.data  = in_data  [winner_d];
  assign out.lrdy  = in_lrdy  [out.r_user];
  assign out.boffs = in_boffs [winner_d];
  assign out.user  = in_user  [winner_d];

endmodule // hci_core_mux_ooo
