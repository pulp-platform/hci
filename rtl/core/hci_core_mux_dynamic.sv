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
 * TCDM channels `in` into a smaller set of initiator ports `out`.
 * It uses a round robin counter to avoid starvation, and differs
 * from the modules used within the logarithmic interconnect in
 * that arbitration is performed depending on the round robin
 * counter and not on the target port; in other words, its task is
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
  parameter int unsigned NB_OUT_CHAN = 1
)
(
  input  logic            clk_i,
  input  logic            rst_ni,
  input  logic            clear_i,

  hci_core_intf.target    in  [0:NB_IN_CHAN-1],
  hci_core_intf.initiator out [0:NB_OUT_CHAN-1]
);

  localparam int unsigned DW = in[0].DW;
  localparam int unsigned AW = in[0].AW;
  localparam int unsigned BW = in[0].BW;
  localparam int unsigned UW = in[0].UW;
  localparam int unsigned IW = in[0].IW;
  localparam int unsigned EW = in[0].EW;
  localparam int unsigned EHW = in[0].EHW;

  // based on MUX2Req.sv from LIC
  logic [NB_IN_CHAN-1:0]                     in_req;
  logic [NB_IN_CHAN-1:0]                     in_gnt;
  logic [NB_IN_CHAN-1:0]                     in_lrdy;
  logic [NB_IN_CHAN-1:0][AW-1:0]             in_add;
  logic [NB_IN_CHAN-1:0]                     in_wen;
  logic [NB_IN_CHAN-1:0][DW/BW-1:0]          in_be;
  logic [NB_IN_CHAN-1:0][DW-1:0]             in_data;
  logic [NB_IN_CHAN-1:0][UW-1:0]             in_user;
  logic [NB_IN_CHAN-1:0][IW-1:0]             in_id;
  logic [NB_IN_CHAN-1:0][EW-1:0]             in_ecc;
  logic [NB_IN_CHAN-1:0][DW-1:0]             in_r_data;
  logic [NB_IN_CHAN-1:0]                     in_r_valid;
  logic [NB_IN_CHAN-1:0][UW-1:0]             in_r_user;
  logic [NB_IN_CHAN-1:0][IW-1:0]             in_r_id;
  logic [NB_IN_CHAN-1:0][EW-1:0]             in_r_ecc;

  logic [NB_OUT_CHAN-1:0]                    out_req;
  logic [NB_OUT_CHAN-1:0]                    out_gnt;
  logic [NB_OUT_CHAN-1:0]                    out_lrdy;
  logic [NB_OUT_CHAN-1:0][AW-1:0]            out_add;
  logic [NB_OUT_CHAN-1:0]                    out_wen;
  logic [NB_OUT_CHAN-1:0][DW/BW-1:0]         out_be;
  logic [NB_OUT_CHAN-1:0][DW-1:0]            out_data;
  logic [NB_OUT_CHAN-1:0][UW-1:0]            out_user;
  logic [NB_OUT_CHAN-1:0][IW-1:0]            out_id;
  logic [NB_OUT_CHAN-1:0][EW-1:0]            out_ecc;
  logic [NB_OUT_CHAN-1:0][DW-1:0]            out_r_data;
  logic [NB_OUT_CHAN-1:0]                    out_r_valid;
  logic [NB_OUT_CHAN-1:0][UW-1:0]            out_r_user;
  logic [NB_OUT_CHAN-1:0][IW-1:0]            out_r_id;
  logic [NB_OUT_CHAN-1:0][EW-1:0]            out_r_ecc;

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
    else if (s_rr_counter_reg_en) begin
      if (rr_counter < NB_IN_CHAN)
        rr_counter <= (rr_counter + {{($clog2(NB_IN_CHAN/NB_OUT_CHAN)-1){1'b0}},1'b1}); //[$clog2(NB_IN_CHAN)-1:0];
      else
        rr_counter <= '0;
    end
  end

  genvar i,j;
  generate

    for(j=0; j<NB_IN_CHAN; j++) begin : in_chan_binding

      assign in_req   [j] = in[j].req;
      assign in_add   [j] = in[j].add;
      assign in_wen   [j] = in[j].wen;
      assign in_be    [j] = in[j].be;
      assign in_data  [j] = in[j].data;
      assign in_lrdy  [j] = in[j].r_ready;
      assign in_user  [j] = in[j].user;
      assign in_id    [j] = in[j].id;
      assign in_ecc   [j] = in[j].ecc;
      assign in[j].gnt     = in_gnt     [j];
      assign in[j].r_data  = in_r_data  [j];
      assign in[j].r_valid = in_r_valid [j];
      assign in[j].r_user  = in_r_user  [j];
      assign in[j].r_id    = in_r_id    [j];
      assign in[j].r_ecc   = in_r_ecc   [j];

    end // in_chan_binding

    for(i=0; i<NB_OUT_CHAN; i++) begin : out_chan_binding

      assign out[i].req     = out_req  [i];
      assign out[i].add     = out_add  [i];
      assign out[i].wen     = out_wen  [i];
      assign out[i].be      = out_be   [i];
      assign out[i].data    = out_data [i];
      assign out[i].r_ready = out_lrdy [i];
      assign out[i].user    = out_user [i];
      assign out[i].id      = out_id   [i];
      assign out[i].ecc     = out_ecc  [i];
      assign out_gnt     [i] = out[i].gnt;
      assign out_r_data  [i] = out[i].r_data;
      assign out_r_valid [i] = out[i].r_valid;
      assign out_r_id    [i] = out[i].r_id;
      assign out_r_user  [i] = out[i].r_user;
      assign out_r_ecc   [i] = out[i].r_ecc;

      always_comb
      begin : rotating_priority_encoder_i
        for(int j=0; j<NB_IN_CHAN/NB_OUT_CHAN; j++)
          rr_priority[i][j] = (rr_counter + i + j < NB_IN_CHAN) ? rr_counter + i + j : rr_counter + i + j + 1;
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
            winner_d[i] = (rr_priority[i][jj] < NB_IN_CHAN) ? rr_priority[i][jj] : rr_priority[i][jj] + 1;
        end
      end

      always_comb
      begin : mux_req_comb
        out_add  [i] = in_add  [winner_d[i]*NB_OUT_CHAN+i];
        out_wen  [i] = in_wen  [winner_d[i]*NB_OUT_CHAN+i];
        out_data [i] = in_data [winner_d[i]*NB_OUT_CHAN+i];
        out_be   [i] = in_be   [winner_d[i]*NB_OUT_CHAN+i];
        out_lrdy [i] = in_lrdy [winner_d[i]*NB_OUT_CHAN+i];
        out_user [i] = in_user [winner_d[i]*NB_OUT_CHAN+i];
        out_id   [i] = in_id   [winner_d[i]*NB_OUT_CHAN+i];
        out_ecc  [i] = in_ecc  [winner_d[i]*NB_OUT_CHAN+i];
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
          in_r_user  [j*NB_OUT_CHAN+i] = '0;
          in_r_id    [j*NB_OUT_CHAN+i] = '0;
          in_r_ecc   [j*NB_OUT_CHAN+i] = '0;
        end
        in_r_data  [winner_q[i]*NB_OUT_CHAN+i] = out_r_data[i];
        in_r_valid [winner_q[i]*NB_OUT_CHAN+i] = out_r_valid[i] & out_req_q[i];
        in_gnt     [winner_d[i]*NB_OUT_CHAN+i] = out_gnt[i];
        in_r_user  [winner_d[i]*NB_OUT_CHAN+i] = out_r_user[i];
        in_r_id    [winner_d[i]*NB_OUT_CHAN+i] = out_r_id[i];
        in_r_ecc   [winner_d[i]*NB_OUT_CHAN+i] = out_r_ecc[i];
      end
    end

  endgenerate

/*
 * ECC Handshake signals
 */
  if(EHW > 0) begin : ecc_handshake_gen
    for(genvar ii=0; ii<NB_IN_CHAN; ii++) begin : in_chan_gen
      assign in[ii].egnt     = {(EHW){in[ii].gnt}};
      assign in[ii].r_evalid = {(EHW){in[ii].r_evalid}};
    end
    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : out_chan_gen
      assign out[ii].ereq     = {(EHW){out[ii].req}};
      assign out[ii].r_eready = {(EHW){out[ii].r_ready}};
    end
  end
  else begin : no_ecc_handshake_gen
    for(genvar ii=0; ii<NB_IN_CHAN; ii++) begin : in_chan_gen
      assign in[ii].egnt     = '1;
      assign in[ii].r_evalid = '0;
    end
    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : out_chan_gen
      assign out[ii].ereq     = '0;
      assign out[ii].r_eready = '1;
    end
  end

/*
 * Interface size asserts
 */
`ifndef SYNTHESIS
`ifndef VERILATOR
  for(genvar i=1; i<NB_IN_CHAN; i++) begin
    initial
      dw :  assert(in[i].DW  == in[0].DW);
    initial
      bw :  assert(in[i].BW  == in[0].BW);
    initial
      aw :  assert(in[i].AW  == in[0].AW);
    initial
      uw :  assert(in[i].UW  == in[0].UW);
    initial
      iw :  assert(in[i].IW  == in[0].IW);
    initial
      ew :  assert(in[i].EW  == in[0].EW);
    initial
      ehw : assert(in[i].EHW == in[0].EHW);
  end
  for(genvar i=0; i<NB_OUT_CHAN; i++) begin
    initial
      dw :  assert(out[i].DW  == in[0].DW);
    initial
      bw :  assert(out[i].BW  == in[0].BW);
    initial
      aw :  assert(out[i].AW  == in[0].AW);
    initial
      uw :  assert(out[i].UW  == in[0].UW);
    initial
      iw :  assert(out[i].IW  == in[0].IW);
    initial
      ew :  assert(out[i].EW  == in[0].EW);
    initial
      ehw : assert(out[i].EHW == in[0].EHW);
  end
`endif
`endif;

endmodule // hci_core_mux
