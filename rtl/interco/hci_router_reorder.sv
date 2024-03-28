/*
 * hci_router_reorder.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2014-2024 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

/*
 * See `hci_router` - this block contains the actual routing.
 */

module hci_router_reorder
  import hwpe_stream_package::*;
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

  hci_core_intf.target    in  [0:NB_IN_CHAN-1],
  hci_core_intf.initiator out [0:NB_OUT_CHAN-1]

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
  logic [NB_IN_CHAN-1:0][NB_OUT_CHAN-1:0] ma_req;

  generate

    // broadcasting in_req[0] and in_gnt[0] is key to optimize area (2-3x) in hci_router_reorder

    // in_gnt out of in_chan_gen because only [0] is used
    assign in_gnt[0] = &(~out_req | out_gnt);
    assign in_gnt[NB_IN_CHAN-1:1] = '0;

    for(genvar i=0; i<NB_IN_CHAN; i++) begin : in_chan_gen

      // only in_req_q[0] is actually used... keep the rest for symmetry only
      if (FILTER_WRITE_R_VALID) begin : filter_write_r_valid_gen
        always_ff @(posedge clk_i or negedge rst_ni)
        begin
          if(~rst_ni)
            in_req_q[i] <= '0;
          else if(clear_i)
            in_req_q[i] <= '0;
          else
            in_req_q[i] <= in_req[0] & in_wen[0];
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
            in_req_q[i] <= in_req[0];
        end
      end

      logic unsigned [$clog2(NB_OUT_CHAN)-1:0] add;
      assign add = order_i + i;

      // address decoder mux from TCDM XBAR
      addr_dec_resp_mux #(
        .NumOut        ( NB_OUT_CHAN ),
        .ReqDataWidth  ( 1           ),
        .RespDataWidth ( 32          ),
        .RespLat       ( 1           ),
        .BroadCastOn   ( 0           ),
        .WriteRespOn   ( 1           )
      ) i_addr_dec_resp_mux (
        .clk_i   ( clk_i         ),
        .rst_ni  ( rst_ni        ),
        .req_i   ( in_req[0]     ),
        .add_i   ( add           ),
        .wen_i   ( in_wen[0]     ),
        .data_i  ( '0            ),
        .gnt_o   (               ), // unused
        .vld_o   (               ), // unused
        .rdata_o ( in_r_data[i]  ),
        .req_o   ( ma_req[i]     ),
        .gnt_i   ( '0            ),
        .data_o  (               ), // unused
        .rdata_i ( out_r_data    )
      );
    
      // bindings
      assign in_req  [i] = in[i].req  ;
      assign in_add  [i] = in[i].add  ;
      assign in_wen  [i] = in[i].wen  ;
      assign in_be   [i] = in[i].be   ;
      assign in_data [i] = in[i].data ;
      assign in[i].gnt     = in_gnt     [i];
      assign in[i].r_data  = in_r_data  [i];
      assign in[i].r_valid = in_req_q[0]; // fixed latency = 1
      // tie unused/unsupported signals
      assign in[i].r_user   = '0;
      assign in[i].r_id     = '0;
      assign in[i].r_opc    = '0;
      assign in[i].r_ecc    = '0;
      assign in[i].egnt     = '1;
      assign in[i].r_evalid = '0;

    end

    for(genvar i=0; i<NB_OUT_CHAN; i++) begin : out_chan_gen

      // we just OR the req signals
      always_comb
      begin
        out_req[i]  = '0;
        out_add[i]  = '0;
        out_wen[i]  = in_wen[0];
        out_be[i]   = '0;
        out_data[i] = '0;
        for(int j=0; j<NB_IN_CHAN; j++) begin
          out_req[i]  |= ma_req [j][i];
          out_add[i]  |= ma_req [j][i] ? in_add  [j] : '0;
          out_be[i]   |= ma_req [j][i] ? in_be   [j] : '0;
          out_data[i] |= ma_req [j][i] ? in_data [j] : '0;
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
      // tie r_ready to '1;
      assign out[i].r_ready = '1;
      // tie unused/unsupported signals
      assign out[i].user     = '0;
      assign out[i].id       = '0;
      assign out[i].ecc      = '0;
      assign out[i].ereq     = '0;
      assign out[i].r_eready = '1;

    end // out_chan_gen

  endgenerate

endmodule // hci_router_reorder
