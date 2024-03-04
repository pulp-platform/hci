/*
 * hci_core_mux_static.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2017-2020 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * The TCDM static multiplexer is used in place of the dynamic one
 * when two sets of ports are guaranteed to be used in a strictly
 * alternative fashion.
 */

import hwpe_stream_package::*;

module hci_core_mux_static
#(
  parameter int unsigned NB_CHAN = 2
)
(
  input  logic                       clk_i,
  input  logic                       rst_ni,
  input  logic                       clear_i,

  input  logic [$clog2(NB_CHAN-1):0] sel_i,

  hci_core_intf.target               in  [NB_CHAN-1:0],
  hci_core_intf.initiator            out
);

  localparam int unsigned DW = in[0].DW;
  localparam int unsigned AW = in[0].AW;
  localparam int unsigned BW = in[0].BW;
  localparam int unsigned UW = in[0].UW;
  localparam int unsigned IW = in[0].IW;
  localparam int unsigned EW = in[0].EW;

  // tcdm ports binding
  generate

    logic        [NB_CHAN-1:0]                    in_req;
    logic        [NB_CHAN-1:0]                    in_lrdy;
    logic        [NB_CHAN-1:0][AW-1:0]            in_add;
    logic        [NB_CHAN-1:0]                    in_wen;
    logic        [NB_CHAN-1:0][DW-1:0]            in_data;
    logic        [NB_CHAN-1:0][DW/BW-1:0]         in_be;
    logic        [NB_CHAN-1:0][UW-1:0]            in_user;
    logic        [NB_CHAN-1:0][IW-1:0]            in_id;
    logic        [NB_CHAN-1:0][EW-1:0]            in_ecc;

    for(genvar ii=0; ii<NB_CHAN; ii++) begin: tcdm_binding

      assign in_req     [ii] = in[ii].req;
      assign in_lrdy    [ii] = in[ii].r_ready;
      assign in_add     [ii] = in[ii].add;
      assign in_wen     [ii] = in[ii].wen;
      assign in_data    [ii] = in[ii].data;
      assign in_be      [ii] = in[ii].be;
      assign in_user    [ii] = in[ii].user;
      assign in_id      [ii] = in[ii].id;
      assign in_ecc     [ii] = in[ii].ecc;

      assign in[ii].gnt     = (sel_i == ii) ? out.gnt     : 1'b0;
      assign in[ii].r_valid = (sel_i == ii) ? out.r_valid : 1'b0;
      assign in[ii].r_data  = out.r_data;
      assign in[ii].r_user  = out.r_user;
      assign in[ii].r_id    = out.r_id;
      assign in[ii].r_ecc   = out.r_ecc;
    end

    assign out.req     = in_req   [sel_i];
    assign out.add     = in_add   [sel_i];
    assign out.wen     = in_wen   [sel_i];
    assign out.be      = in_be    [sel_i];
    assign out.data    = in_data  [sel_i];
    assign out.r_ready = in_lrdy  [sel_i];
    assign out.user    = in_user  [sel_i];
    assign out.id      = in_id    [sel_i];

  endgenerate

/*
 * ECC Handshake signals
 */
  if(EHW > 0) begin : ecc_handshake_gen
    for(genvar ii=0; ii<NB_IN_CHAN; ii++) begin : in_chan_gen
      assign in[ii].egnt     = {(EHW){in[ii].gnt}};
      assign in[ii].r_evalid = {(EHW){in[ii].r_evalid}};
    end
    assign out.ereq     = {(EHW){out.req}};
    assign out.r_eready = {(EHW){out.r_ready}};
  end
  else begin : no_ecc_handshake_gen
    for(genvar ii=0; ii<NB_IN_CHAN; ii++) begin : in_chan_gen
      assign in[ii].egnt     = '1;
      assign in[ii].r_evalid = '0;
    end
    assign out.ereq     = '0;
    assign out.r_eready = '1;
  end

/*
 * Interface size asserts
 */
`ifndef SYNTHESIS
`ifndef VERILATOR
  for(genvar i=0; i<NB_CHAN; i++) begin
    initial
      dw :  assert(in[i].DW  == out.DW);
    initial
      bw :  assert(in[i].BW  == out.BW);
    initial
      aw :  assert(in[i].AW  == out.AW);
    initial
      uw :  assert(in[i].UW  == out.UW);
    initial
      ew :  assert(in[i].EW  == out.EW);
    initial
      ehw : assert(in[i].EHW == out.EHW);
  end
`endif
`endif;

endmodule // hci_core_mux_static
