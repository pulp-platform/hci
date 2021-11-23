/*
 * hci_hwpe_reorder.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2014-2021 ETH Zurich, University of Bologna
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

module hci_hwpe_reorder
#(
  parameter int unsigned NB_IN_CHAN  = 2,
  parameter int unsigned NB_OUT_CHAN = 2,
  parameter int unsigned FILTER_WRITE_R_VALID = 0
)
(
  input  logic                       clk_i,
  input  logic                       rst_ni,
  input  logic                       clear_i,

  input  logic [$clog2(NB_OUT_CHAN)-1:0] order_i,

  hwpe_stream_intf_tcdm.slave        in  [NB_IN_CHAN-1:0],
  hwpe_stream_intf_tcdm.master       out [NB_OUT_CHAN-1:0]

);

  logic [NB_IN_CHAN-1:0]       in_req;
  logic [NB_IN_CHAN-1:0]       in_req_q;
  logic [NB_IN_CHAN-1:0][31:0] in_add;
  logic [NB_IN_CHAN-1:0]       in_wen;
  logic [NB_IN_CHAN-1:0][3:0]  in_be;
  logic [NB_IN_CHAN-1:0][31:0] in_data;
  logic [NB_IN_CHAN-1:0]       in_gnt;
  logic [NB_IN_CHAN-1:0][31:0] in_r_data;
  logic [NB_IN_CHAN-1:0]       in_r_valid;
  logic [NB_OUT_CHAN-1:0]       out_req;
  logic [NB_OUT_CHAN-1:0][31:0] out_add;
  logic [NB_OUT_CHAN-1:0]       out_wen;
  logic [NB_OUT_CHAN-1:0][3:0]  out_be;
  logic [NB_OUT_CHAN-1:0][31:0] out_data;
  logic [NB_OUT_CHAN-1:0]       out_gnt;
  logic [NB_OUT_CHAN-1:0][31:0] out_r_data;
  logic [NB_OUT_CHAN-1:0]       out_r_valid;
  logic [NB_IN_CHAN-1:0][NB_OUT_CHAN-1:0]       ma_req;
  // logic [NB_IN_CHAN-1:0][NB_OUT_CHAN-1:0][31:0] ma_add;
  logic [NB_IN_CHAN-1:0][NB_OUT_CHAN-1:0][31:0] ma_data;
  logic [NB_IN_CHAN-1:0][NB_OUT_CHAN-1:0]       ma_gnt;
  logic [NB_OUT_CHAN-1:0][NB_IN_CHAN-1:0]       mat_req;
  // logic [NB_OUT_CHAN-1:0][NB_IN_CHAN-1:0][31:0] mat_add;
  // logic [NB_OUT_CHAN-1:0][NB_IN_CHAN-1:0][31:0] mat_data;
  logic [NB_OUT_CHAN-1:0][NB_IN_CHAN-1:0]       mat_gnt;
  logic [NB_IN_CHAN-1:0][NB_OUT_CHAN-1:0]       ma_r_valid;
  logic [NB_OUT_CHAN-1:0][NB_IN_CHAN-1:0]       mat_r_valid;

  generate

    for(genvar i=0; i<NB_IN_CHAN; i++) begin : in_chan_gen

      if (FILTER_WRITE_R_VALID) begin : filter_write_r_valid_gen
        always_ff @(posedge clk_i or negedge rst_ni)
        begin
          if(~rst_ni)
            in_req_q[i] <= '0;
          else if(clear_i)
            in_req_q[i] <= '0;
          else
            in_req_q[i] <= in_req[i] & in_wen[i];
        end
      end
      else begin : no_filter_write_r_valid_gen
        always_ff @(posedge clk_i or negedge rst_ni)
        begin
          if(~rst_ni)
            in_req_q[i] <= '0;
          else if(clear_i)
            in_req_q[i] <= '0;
          else
            in_req_q[i] <= in_req[i];
        end
      end

      // address decoder mux from TCDM XBAR
      addr_dec_resp_mux #(
        .NumOut        ( NB_OUT_CHAN ),
        .ReqDataWidth  ( 32      ),
        .RespDataWidth ( 32      ),
        .RespLat       ( 1       ),
        .BroadCastOn   ( 0       ),
        .WriteRespOn   ( 1       )
      ) i_addr_dec_resp_mux (
        .clk_i   ( clk_i         ),
        .rst_ni  ( rst_ni        ),
        .req_i   ( in_req[i]     ),
        .add_i   ( (NB_OUT_CHAN - order_i) + i   ),
        .wen_i   ( in_wen[i]     ),
        .data_i  ( in_data[i]    ),
        .gnt_o   ( in_gnt[i]     ),
        .vld_o   ( in_r_valid[i] ),
        .rdata_o ( in_r_data[i]  ),
        .req_o   ( ma_req[i]     ),
        .gnt_i   ( ma_gnt[i]     ),
        .data_o  (               ), // unused ?
        .rdata_i ( out_r_data    )
      );

      for(genvar j=0; j<NB_OUT_CHAN; j++) begin : transpose_gen
        // assign ma_add [i][j] = in_add [i];
        assign mat_req  [j][i] = ma_req  [i][j];
        // assign mat_add  [j][i] = ma_add  [i][j];
        // assign mat_data [j][i] = ma_data [i][j];
        assign ma_r_valid [i][j] = mat_r_valid [i][j];
      end
      assign ma_gnt [i] = &(~out_req | out_gnt);
    
      // bindings
      assign in_req  [i] = in[i].req  ;
      assign in_add  [i] = in[i].add  ;
      assign in_wen  [i] = in[i].wen  ;
      assign in_be   [i] = in[i].be   ;
      assign in_data [i] = in[i].data ;
      assign in[i].gnt     = in_gnt     [i];
      assign in[i].r_data  = in_r_data  [i];
      assign in[i].r_valid = in_r_valid [i] & in_req_q[i];

    end

    for(genvar i=0; i<NB_OUT_CHAN; i++) begin : out_chan_gen

      // we know that the input requests are non-colliding! so we just OR them!
      always_comb
      begin
        out_req[i]  = '0;
        out_add[i]  = '0;
        out_wen[i]  = in_wen[0];
        out_be[i]   = '0;
        out_data[i] = '0;
        for(int j=0; j<NB_IN_CHAN; j++) begin
          out_req[i]  |= mat_req [i][j];
          out_add[i]  |= mat_req [i][j] ? in_add  [j] : '0;
          out_be[i]   |= mat_req [i][j] ? in_be   [j] : '0;
          out_data[i] |= mat_req [i][j] ? in_data [j] : '0;
        end
      end

      // bindings
      assign out[i].req  = out_req  [i];
      assign out[i].add  = out_add  [i];
      assign out[i].wen  = out_wen  [i];
      assign out[i].be   = out_be   [i];
      assign out[i].data = out_data [i];
      assign out_gnt     [i] = out[i].gnt;
      assign out_r_data  [i] = out[i].r_data;
      assign out_r_valid [i] = out[i].r_valid;

    end // out_chan_gen

  endgenerate

endmodule // hci_hwpe_reorder
