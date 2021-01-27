/*
 * hci_core_load_store_mixer.sv
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

module hci_core_load_store_mixer
#(
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

  hci_core_intf.slave  in_load,
  hci_core_intf.slave  in_store,
  hci_core_intf.master out
);

  // this is a variant of the dynamic mux, supporting only two channels:
  //  LOAD  channel
  //  STORE channel

  localparam LOAD  = 0;
  localparam STORE = 1;
  localparam int unsigned NB_IN_CHAN  = 2;
  localparam int unsigned NB_OUT_CHAN = 1;

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

    assign in_req   [LOAD] = in_load.req;
    assign in_add   [LOAD] = in_load.add;
    assign in_wen   [LOAD] = in_load.wen;
    assign in_be    [LOAD] = in_load.be;
    assign in_data  [LOAD] = in_load.data;
    assign in_lrdy  [LOAD] = in_load.lrdy;
    assign in_boffs [LOAD] = in_load.boffs;
    assign in_user  [LOAD] = in_load.user;
    assign in_load.gnt     = in_gnt     [LOAD];
    assign in_load.r_data  = in_r_data  [LOAD];
    assign in_load.r_valid = in_r_valid [LOAD];
    assign in_load.r_opc   = in_r_opc   [LOAD];
    assign in_load.r_user  = in_r_user  [LOAD];

    assign in_req   [STORE] = in_store.req;
    assign in_add   [STORE] = in_store.add;
    assign in_wen   [STORE] = in_store.wen;
    assign in_be    [STORE] = in_store.be;
    assign in_data  [STORE] = in_store.data;
    assign in_lrdy  [STORE] = in_store.lrdy;
    assign in_boffs [STORE] = in_store.boffs;
    assign in_user  [STORE] = in_store.user;
    assign in_store.gnt     = in_gnt     [STORE];
    assign in_store.r_data  = in_r_data  [STORE];
    assign in_store.r_valid = in_r_valid [STORE];
    assign in_store.r_opc   = in_r_opc   [STORE];
    assign in_store.r_user  = in_r_user  [STORE];

    assign out.req   = out_req   [0];
    assign out.add   = out_add   [0];
    assign out.wen   = out_wen   [0];
    assign out.be    = out_be    [0];
    assign out.data  = out_data  [0];
    assign out.lrdy  = out_lrdy  [0];
    assign out.boffs = out_boffs [0];
    assign out.user  = out_user  [0];
    assign out_gnt     [0] = out.gnt;
    assign out_r_data  [0] = out.r_data;
    assign out_r_valid [0] = out.r_valid;
    assign out_r_opc   [0] = out.r_opc;
    assign out_r_user  [0] = out.r_user;

    for(i=0; i<NB_OUT_CHAN; i++) begin : out_chan_binding

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

    // differently from the dynamic mux, the response in the load/store mixer is propagated by looking at the nature of the request
    always_comb
    begin : mux_gnt_comb
      for(int i=0; i<NB_OUT_CHAN; i++) begin
        for (int j=0; j<NB_IN_CHAN/NB_OUT_CHAN; j++) begin
          in_gnt     [j*NB_OUT_CHAN+i] = 1'b0;
        end
        in_gnt     [winner_d[i]*NB_OUT_CHAN+i] = out_gnt[i];
      end
    end
    
    always_comb
    begin : mux_resp_comb
      for(int i=0; i<NB_OUT_CHAN; i++) begin
        for (int j=0; j<NB_IN_CHAN/NB_OUT_CHAN; j++) begin
          in_r_data  [j*NB_OUT_CHAN+i] = '0;
          in_r_valid [j*NB_OUT_CHAN+i] = 1'b0;
          in_r_opc   [j*NB_OUT_CHAN+i] = 1'b0;
          in_r_user  [j*NB_OUT_CHAN+i] = '0;
        end
        if (out_r_valid[i]) begin
          in_r_data  [LOAD] = out_r_data[i];
          in_r_valid [LOAD] = out_r_valid[i];
          in_r_opc   [LOAD] = out_r_opc[i];
          in_r_user  [LOAD] = out_r_user[i];
        end
        else begin
          in_r_data  [STORE] = out_r_data[i];
          in_r_valid [STORE] = out_r_valid[i];
          in_r_opc   [STORE] = out_r_opc[i];
          in_r_user  [STORE] = out_r_user[i];
        end
      end
    end

  endgenerate

endmodule // hci_core_load_store_mixer
