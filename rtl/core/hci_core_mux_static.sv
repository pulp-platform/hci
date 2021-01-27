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
  parameter int unsigned NB_CHAN = 2,
  parameter int unsigned DW = hci_package::DEFAULT_DW,
  parameter int unsigned AW = hci_package::DEFAULT_AW,
  parameter int unsigned BW = hci_package::DEFAULT_BW,
  parameter int unsigned WW = hci_package::DEFAULT_WW,
  parameter int unsigned OW = AW,
  parameter int unsigned UW = hci_package::DEFAULT_UW
)
(
  input  logic                       clk_i,
  input  logic                       rst_ni,
  input  logic                       clear_i,

  input  logic [$clog2(NB_CHAN-1):0] sel_i,

  hci_core_intf.slave  in  [NB_CHAN-1:0],
  hci_core_intf.master out
);

  // tcdm ports binding
  generate

    logic        [NB_CHAN-1:0]                    in_req;
    logic        [NB_CHAN-1:0]                    in_gnt;
    logic        [NB_CHAN-1:0]                    in_lrdy;
    logic        [NB_CHAN-1:0][AW-1:0]            in_add;
    logic        [NB_CHAN-1:0]                    in_wen;
    logic        [NB_CHAN-1:0][DW-1:0]            in_data;
    logic        [NB_CHAN-1:0][DW/BW-1:0]         in_be;
    logic signed [NB_CHAN-1:0][DW/WW-1:0][OW-1:0] in_boffs;
    logic        [NB_CHAN-1:0][UW-1:0]            in_user;
    logic        [NB_CHAN-1:0][DW-1:0]            in_r_data;
    logic        [NB_CHAN-1:0]                    in_r_valid;
    logic        [NB_CHAN-1:0]                    in_r_opc;
    logic        [NB_CHAN-1:0][UW-1:0]            in_r_user;

    for(genvar ii=0; ii<NB_CHAN; ii++) begin: tcdm_binding

      assign in_req     [ii] = in[ii].req;
      assign in_gnt     [ii] = in[ii].gnt;
      assign in_lrdy    [ii] = in[ii].lrdy;
      assign in_add     [ii] = in[ii].add;
      assign in_wen     [ii] = in[ii].wen;
      assign in_data    [ii] = in[ii].data;
      assign in_be      [ii] = in[ii].be;
      assign in_boffs   [ii] = in[ii].boffs;
      assign in_user    [ii] = in[ii].user;
      assign in_r_data  [ii] = in[ii].r_data;
      assign in_r_valid [ii] = in[ii].r_valid;
      assign in_r_opc   [ii] = in[ii].r_opc;
      assign in_r_user  [ii] = in[ii].r_user;

      assign in[ii].gnt     = (sel_i == ii) ? out.gnt     : 1'b0;
      assign in[ii].r_valid = (sel_i == ii) ? out.r_valid : 1'b0;
      assign in[ii].r_data  = out.r_data;
      assign in[ii].r_opc   = out.r_opc;
      assign in[ii].r_user  = out.r_user;
    end

    assign out.req   = in_req   [sel_i];
    assign out.add   = in_add   [sel_i];
    assign out.wen   = in_wen   [sel_i];
    assign out.be    = in_be    [sel_i];
    assign out.data  = in_data  [sel_i];
    assign out.lrdy  = in_lrdy  [sel_i];
    assign out.boffs = in_boffs [sel_i];
    assign out.user  = in_user  [sel_i];

  endgenerate

endmodule // hci_core_mux_static
