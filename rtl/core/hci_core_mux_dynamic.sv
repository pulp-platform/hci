/*
 * hci_core_mux_dynamic.sv
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
 * The **TCDM multiplexer** can be used to funnel more input "virtual"
 * TCDM channels `in` into a smaller set of master ports `out`.
 * It uses a round robin counter to avoid starvation, and differs
 * from the modules used within the logarithmic interconnect in
 * that arbitration is performed depending on the round robin
 * counter and not on the slave port; in other words, its task is
 * to fill all out ports with requests from the in port, and not
 * to route in requests to a specific out port.
 *
 * Notice that the multiplexer is not "optimal" in the sense
 * that there is no reorder buffer, so transactions cannot be swapped
 * in-flight to optimally fill the downstream available bandwidth.
 * However, in real accelerators many systematic issues with bandwidth
 * sharing can be solved by upstream TCDM FIFOs and by clever reordering
 * of channels, since the dataflow schedule is known.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_core_mux_params:
 * .. table:: **hci_core_mux** design-time parameters.
 *
 *   +---------------+-------------+-------------------------------------+
 *   | **Name**      | **Default** | **Description**                     |
 *   +---------------+-------------+-------------------------------------+
 *   | *NB_IN_CHAN*  | 2           | Number of input HWPE-Mem channels.  |
 *   +---------------+-------------+-------------------------------------+
 *   | *NB_OUT_CHAN* | 1           | Number of output HWPE-Mem channels. |
 *   +---------------+-------------+-------------------------------------+
 *
 */

import hwpe_stream_package::*;
import hci_package::*;

module hci_core_mux_dynamic
#(
  parameter int unsigned NB_IN_CHAN  = 2,
  parameter int unsigned NB_OUT_CHAN = 1,
  parameter int unsigned DW = hci_package::DEFAULT_DW,
  parameter int unsigned AW = hci_package::DEFAULT_AW,
  parameter int unsigned BW = hci_package::DEFAULT_BW,
  parameter int unsigned WW = hci_package::DEFAULT_WW,
  parameter int unsigned OW = 1,
  parameter int unsigned UW = hci_package::DEFAULT_UW
)
(
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         clear_i,

  hci_core_intf.slave  in  [NB_IN_CHAN-1:0],
  hci_core_intf.master out [NB_OUT_CHAN-1:0]
);

  // based on MUX2Req.sv from LIC
  logic [NB_IN_CHAN-1:0]                     in_req;
  logic [NB_IN_CHAN-1:0]                     in_gnt;
  logic [NB_IN_CHAN-1:0]                     in_lrdy;
  logic [NB_IN_CHAN-1:0][AW-1:0]             in_add;
  logic [NB_IN_CHAN-1:0]                     in_wen;
  logic [NB_IN_CHAN-1:0][DW/BW-1:0]          in_be;
  logic [NB_IN_CHAN-1:0][DW-1:0]             in_data;
  logic [NB_IN_CHAN-1:0][DW/WW-1:0][OW-1:0]  in_boffs;
  logic [NB_IN_CHAN-1:0][UW-1:0]             in_user;
  logic [NB_IN_CHAN-1:0][DW-1:0]             in_r_data;
  logic [NB_IN_CHAN-1:0]                     in_r_valid;
  logic [NB_IN_CHAN-1:0]                     in_r_opc;
  logic [NB_IN_CHAN-1:0][UW-1:0]             in_r_user;

  logic [NB_OUT_CHAN-1:0]                    out_req;
  logic [NB_OUT_CHAN-1:0]                    out_gnt;
  logic [NB_OUT_CHAN-1:0]                    out_lrdy;
  logic [NB_OUT_CHAN-1:0][AW-1:0]            out_add;
  logic [NB_OUT_CHAN-1:0]                    out_wen;
  logic [NB_OUT_CHAN-1:0][DW/BW-1:0]         out_be;
  logic [NB_OUT_CHAN-1:0][DW-1:0]            out_data;
  logic [NB_OUT_CHAN-1:0][DW/WW-1:0][OW-1:0] out_boffs;
  logic [NB_OUT_CHAN-1:0][UW-1:0]            out_user;
  logic [NB_OUT_CHAN-1:0][DW-1:0]            out_r_data;
  logic [NB_OUT_CHAN-1:0]                    out_r_valid;
  logic [NB_OUT_CHAN-1:0]                    out_r_opc;
  logic [NB_OUT_CHAN-1:0][UW-1:0]            out_r_user;

  logic [$clog2(NB_IN_CHAN/NB_OUT_CHAN)-1:0]                                              rr_counter;
  logic [NB_OUT_CHAN-1:0][NB_IN_CHAN/NB_OUT_CHAN-1:0][$clog2(NB_IN_CHAN/NB_OUT_CHAN)-1:0] rr_priority;
  logic [NB_OUT_CHAN-1:0][$clog2(NB_IN_CHAN/NB_OUT_CHAN)-1:0]                             winner_d;
  logic [NB_OUT_CHAN-1:0][$clog2(NB_IN_CHAN/NB_OUT_CHAN)-1:0]                             winner_q;
  logic [NB_OUT_CHAN-1:0]                                                                 out_req_q;

  logic s_rr_counter_reg_en;
  assign s_rr_counter_reg_en = (|out_req) & (|out_gnt);

  always_ff @(posedge clk_i, negedge rst_ni)
  begin : round_robin_counter
    if(rst_ni == 1'b0)
      rr_counter <= '0;
    else if (clear_i == 1'b1)
      rr_counter <= '0;
    else if (s_rr_counter_reg_en)
      rr_counter <= (rr_counter + {{($clog2(NB_IN_CHAN/NB_OUT_CHAN)-1){1'b0}},1'b1}); //[$clog2(NB_IN_CHAN)-1:0];
  end

  genvar i,j;
  generate

    for(j=0; j<NB_IN_CHAN; j++) begin : in_chan_binding

      assign in_req   [j] = in[j].req;
      assign in_add   [j] = in[j].add;
      assign in_wen   [j] = in[j].wen;
      assign in_be    [j] = in[j].be;
      assign in_data  [j] = in[j].data;
      assign in_lrdy  [j] = in[j].lrdy;
      assign in_boffs [j] = in[j].boffs;
      assign in_user  [j] = in[j].user;
      assign in[j].gnt     = in_gnt     [j];
      assign in[j].r_data  = in_r_data  [j];
      assign in[j].r_valid = in_r_valid [j];
      assign in[j].r_opc   = in_r_opc   [j];
      assign in[j].r_user  = in_r_user  [j];

    end // in_chan_binding

    for(i=0; i<NB_OUT_CHAN; i++) begin : out_chan_binding

      assign out[i].req   = out_req  [i];
      assign out[i].add   = out_add  [i];
      assign out[i].wen   = out_wen  [i];
      assign out[i].be    = out_be   [i];
      assign out[i].data  = out_data [i];
      assign out[i].lrdy  = out_lrdy [i];
      assign out[i].boffs = out_boffs [i];
      assign out[i].user  = out_user [i];
      assign out_gnt     [i] = out[i].gnt;
      assign out_r_data  [i] = out[i].r_data;
      assign out_r_valid [i] = out[i].r_valid;
      assign out_r_opc   [i] = out[i].r_opc;
      assign out_r_user  [i] = out[i].r_user;

      always_comb
      begin : rotating_priority_encoder_i
        for(int j=0; j<NB_IN_CHAN/NB_OUT_CHAN; j++)
          rr_priority[i][j] = rr_counter + i + j;
      end

      always_comb
      begin : out_req_comb
        out_req[i] = 1'b0;
        for(int j=0; j<NB_IN_CHAN/NB_OUT_CHAN; j++)
          out_req[i] = out_req[i] | in_req[j*NB_OUT_CHAN+i];
      end

      always_comb
      begin : wta_comb
        winner_d[i] = rr_counter + i;
        for(int jj=0; jj<NB_IN_CHAN/NB_OUT_CHAN; jj++) begin
          if (in_req[rr_priority[i][jj]*NB_OUT_CHAN+i] == 1'b1)
            winner_d[i] = rr_priority[i][jj];
        end
      end

      always_comb
      begin : mux_req_comb
        out_add  [i] = in_add  [winner_d[i]*NB_OUT_CHAN+i];
        out_wen  [i] = in_wen  [winner_d[i]*NB_OUT_CHAN+i];
        out_data [i] = in_data [winner_d[i]*NB_OUT_CHAN+i];
        out_be   [i] = in_be   [winner_d[i]*NB_OUT_CHAN+i];
        out_boffs[i] = in_boffs[winner_d[i]*NB_OUT_CHAN+i];
        out_lrdy [i] = in_lrdy [winner_d[i]*NB_OUT_CHAN+i];
        out_user [i] = in_user [winner_d[i]*NB_OUT_CHAN+i];
      end

      always_ff @(posedge clk_i or negedge rst_ni)
      begin : wta_resp_reg
        if(rst_ni == 1'b0) begin
          winner_q  [i] <= '0;
          out_req_q [i] <= 1'b0;
        end
        else if(clear_i == 1'b1) begin
          winner_q  [i] <= '0;
          out_req_q [i] <= 1'b0;
        end
        else begin
          winner_q  [i] <= winner_d [i];
          out_req_q [i] <= out_req  [i];
        end
      end

    end // out_chan_binding

    always_comb
    begin : mux_resp_comb
      for(int i=0; i<NB_OUT_CHAN; i++) begin
        for (int j=0; j<NB_IN_CHAN/NB_OUT_CHAN; j++) begin
          in_r_data  [j*NB_OUT_CHAN+i] = '0;
          in_r_valid [j*NB_OUT_CHAN+i] = 1'b0;
          in_gnt     [j*NB_OUT_CHAN+i] = 1'b0;
          in_r_opc   [j*NB_OUT_CHAN+i] = 1'b0;
          in_r_user  [j*NB_OUT_CHAN+i] = '0;
        end
        in_r_data  [winner_q[i]*NB_OUT_CHAN+i] = out_r_data[i];
        in_r_valid [winner_q[i]*NB_OUT_CHAN+i] = out_r_valid[i] & out_req_q[i];
        in_gnt     [winner_d[i]*NB_OUT_CHAN+i] = out_gnt[i];
        in_r_opc   [winner_d[i]*NB_OUT_CHAN+i] = out_r_opc[i];
        in_r_user  [winner_d[i]*NB_OUT_CHAN+i] = out_r_user[i];
      end
    end

  endgenerate

endmodule // hci_core_mux
