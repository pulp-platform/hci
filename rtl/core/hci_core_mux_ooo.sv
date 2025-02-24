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

module hci_core_mux_ooo
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

  hci_core_intf.target                            in  [0:NB_CHAN-1],
  hci_core_intf.initiator                         out
);

  localparam int unsigned DW  = `HCI_SIZE_GET_DW(out);
  localparam int unsigned BW  = `HCI_SIZE_GET_BW(out);
  localparam int unsigned AW  = `HCI_SIZE_GET_AW(out);
  localparam int unsigned UW  = `HCI_SIZE_GET_UW(out);
  localparam int unsigned IW  = `HCI_SIZE_GET_IW(out);
  localparam int unsigned EW  = `HCI_SIZE_GET_EW(out);
  localparam int unsigned EHW = `HCI_SIZE_GET_EHW(out);

  // tcdm ports binding
  logic        [NB_CHAN-1:0]                    in_req;
  logic        [NB_CHAN-1:0]                    in_gnt;
  logic        [NB_CHAN-1:0]                    in_r_valid;
  logic        [NB_CHAN-1:0]                    in_lrdy;
  logic        [NB_CHAN-1:0][AW-1:0]            in_add;
  logic        [NB_CHAN-1:0]                    in_wen;
  logic        [NB_CHAN-1:0][DW-1:0]            in_data;
  logic        [NB_CHAN-1:0][DW/BW-1:0]         in_be;
  logic        [NB_CHAN-1:0][hci_package::iomsb(UW):0]            in_user;
  logic        [NB_CHAN-1:0][hci_package::iomsb(IW):0]            in_id;
  logic        [NB_CHAN-1:0][hci_package::iomsb(EW):0]            in_ecc;
  logic        [NB_CHAN-1:0][hci_package::iomsb(EHW):0]           in_egnt;
  logic        [NB_CHAN-1:0][hci_package::iomsb(EHW):0]           in_r_evalid;

  logic [$clog2(NB_CHAN)-1:0]              rr_counter_q;
  logic [NB_CHAN-1:0][$clog2(NB_CHAN)-1:0] rr_priority_d;
  logic [$clog2(NB_CHAN)-1:0]              winner_d, winner_q;

  logic rr_counter_en_d, rr_counter_en_q;
  assign rr_counter_en_d = out.req & out.gnt;

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
      any_req_q <= |(in_req);
    end
  end

  for(genvar ii=0; ii<NB_CHAN; ii++) begin: in_port_binding

    assign in_req     [ii] = in[ii].req;
    assign in_lrdy    [ii] = in[ii].r_ready;
    assign in_add     [ii] = in[ii].add;
    assign in_wen     [ii] = in[ii].wen;
    assign in_data    [ii] = in[ii].data;
    assign in_be      [ii] = in[ii].be;
    assign in_user    [ii] = in[ii].user;
    assign in_id      [ii] = ii;
    assign in_ecc     [ii] = in[ii].ecc;

    // out.r_user used as an ID signal
    assign in_gnt[ii]      = (winner_d == ii)   ? in[ii].req & out.gnt : 1'b0;
    assign in[ii].gnt      = in_gnt[ii];
    assign in_r_valid[ii]  = (out.r_id == ii) ? out.r_valid : 1'b0;
    assign in[ii].r_valid  = in_r_valid[ii];
    assign in[ii].r_data   = out.r_data;
    assign in[ii].r_opc    = out.r_opc;
    assign in[ii].r_user   = out.r_user;
    assign in[ii].r_ecc    = out.r_ecc;
    assign in[ii].r_id     = out.r_id;
    assign in[ii].egnt     = in_egnt;
    assign in[ii].r_evalid = in_r_evalid;

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
        if (in_req[rr_priority_d[NB_CHAN-jj-1]] == 1'b1)
          winner_d = rr_priority_d[NB_CHAN-jj-1];
      end
    end
  end

  // select input port depending on winner-takes-all arbitration
  assign out.req     = in_req   [winner_d];
  assign out.add     = in_add   [winner_d];
  assign out.wen     = in_wen   [winner_d];
  assign out.be      = in_be    [winner_d];
  assign out.data    = in_data  [winner_d];
  assign out.r_ready = in_lrdy  [out.r_id];
  assign out.user    = in_user  [winner_d];
  assign out.id      = in_id    [winner_d];
  assign out.ecc     = in_ecc   [winner_d];

/*
 * ECC Handshake signals
 */
  if(EHW > 0) begin : ecc_handshake_gen
    for(genvar ii=0; ii<NB_CHAN; ii++) begin : in_chan_gen
      assign in_egnt[ii]     = '{default: {in_gnt[ii]}};
      assign in_r_evalid[ii] = '{default: {in_r_valid[ii]}};
    end
    assign out.ereq     = '{default: {out.req}};
    assign out.r_eready = '{default: {out.r_ready}};
  end
  else begin : no_ecc_handshake_gen
    for(genvar ii=0; ii<NB_CHAN; ii++) begin : in_chan_gen
      assign in_egnt[ii]     = '1;
      assign in_r_evalid[ii] = '0;
    end
    assign out.ereq     = '0;
    assign out.r_eready = '1;
  end

/*
 * Interface size asserts
 */
`ifndef SYNTHESIS
`ifndef VERILATOR
`ifndef VCS
  for(genvar i=0; i<NB_CHAN; i++) begin
    initial
      dw :  assert(in[i].DW  == out.DW);
    initial
      bw :  assert(in[i].BW  == out.BW);
    initial
      aw :  assert(in[i].AW  == out.AW);
    initial
      uw :  assert(in[i].UW  == out.UW);
    // initial
    //   iw_in :  assert(in[i].IW  == 0);
    initial
      iw_out :  assert(out.IW  >= $clog2(NB_CHAN));
    initial
      ew :  assert(in[i].EW  == out.EW);
    initial
      ehw : assert(in[i].EHW == out.EHW);
  end

  `HCI_SIZE_CHECK_ASSERTS(out);

`endif
`endif
`endif;

endmodule // hci_core_mux_ooo
