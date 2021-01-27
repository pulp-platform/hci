/*
 * hci_core_memmap_demux.sv
 * Francesco Conti <f.conti@unibo.it>
 * Igor Loi <igor.loi@unibo.it>
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

module hci_core_memmap_demux_interl #(
  parameter int unsigned NB_REGION = 2,
  parameter int unsigned AW  = hci_package::DEFAULT_AW, /// addr width
  parameter int unsigned AWC = hci_package::DEFAULT_AW, /// addr width core (useful part!)
  parameter int unsigned DW  = hci_package::DEFAULT_DW,
  parameter int unsigned UW  = hci_package::DEFAULT_UW
)
(
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         clear_i,

  input  logic [NB_REGION-1:0][AW-1:0] region_start_addr_i,
  input  logic [NB_REGION-1:0][AW-1:0] region_end_addr_i,

  hci_core_intf.slave  slave,
  hci_core_intf.master master [NB_REGION-1:0]
);

    enum logic [1:0] {IDLE, RESPONSE } state_q, state_d;

    logic [$clog2(NB_REGION)-1:0] region_d, region_q;
    logic region_sample;

    logic [NB_REGION-1:0]         master_req_aux, master_gnt_aux;
    logic [NB_REGION-1:0]         master_r_valid_aux;
    logic [NB_REGION-1:0][DW-1:0] master_r_data_aux;
    logic [NB_REGION-1:0]         master_r_opc_aux;
    logic [NB_REGION-1:0][UW-1:0] master_r_user_aux;

    logic [NB_REGION-1:0] destination_map;
    logic                 destination_valid;

    always_comb
    begin 
      destination_map = '0;
      for (int unsigned i=0; i<NB_REGION; i++) begin
        if ((slave.add >= region_start_addr_i[i]) && (slave.add < region_end_addr_i[i])) begin
          destination_map[i] = 1'b1;
        end
      end
    end

    always_comb
    begin 
      region_d = '0;
      for (int unsigned i=0; i<NB_REGION; i++) begin
        if ((slave.add >= region_start_addr_i[i]) && (slave.add < region_end_addr_i[i])) begin
          region_d = i;
        end
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni)
    begin : fsm_seq
      if(~rst_ni) begin
        state_q <= IDLE;
      end
      else if (clear_i) begin
        state_q <= IDLE;
      end
      else begin
        state_q <= state_d;
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni)
    begin : region_ff
      if(~rst_ni) begin
        region_q <= '0;
      end
      else if (clear_i) begin
        region_q <= '0;
      end
      else if(region_sample) begin
        region_q <= region_d;
      end
    end

    always_comb
    begin : fsm_comb_state
      state_d = state_q;
      region_sample = '0;
      if (slave.req) begin
        if(|(master_gnt_aux)) begin
          state_d = RESPONSE;
          region_sample = '1;
        end
        else begin
          state_d = IDLE;
        end
      end
    end

    always_comb
    begin : fsm_comb_out
      master_req_aux = '0;
      case(state_q)
        IDLE: begin
          slave.r_valid = '0;
          slave.r_data  = '0;
          slave.r_opc   = '0;
          slave.r_user  = '0;
        end
        RESPONSE: begin
          slave.r_valid = master_r_valid_aux [region_q];
          slave.r_data  = master_r_data_aux  [region_q];
          slave.r_opc   = master_r_opc_aux   [region_q];
          slave.r_user  = master_r_user_aux  [region_q];
        end
        default: begin
          slave.r_valid = '0;
          slave.r_data  = '0;
          slave.r_opc   = '0;
          slave.r_user  = '0;
        end
      endcase
      master_req_aux[region_d] = slave.req;
      slave.gnt = master_gnt_aux[region_d];
    end
    
    generate
      for(genvar ii=0; ii<NB_REGION; ii++) begin
        assign master[ii].add[AW-1:AWC] = '0;
        assign master[ii].add[AWC-1:0]  = slave.add[AWC-1:0] - region_start_addr_i[ii][AWC-1:0];
        assign master[ii].wen   = slave.wen;
        assign master[ii].data  = slave.data;
        assign master[ii].be    = slave.be;
        assign master[ii].boffs = slave.boffs;
        assign master[ii].lrdy  = slave.lrdy;
        assign master[ii].req = master_req_aux[ii];
        assign master_gnt_aux     [ii] = master[ii].gnt;
        assign master_r_valid_aux [ii] = master[ii].r_valid;
        assign master_r_data_aux  [ii] = master[ii].r_data;
        assign master_r_opc_aux   [ii] = master[ii].r_opc;
        assign master_r_user_aux  [ii] = master[ii].r_user;
      end
    endgenerate

endmodule // hci_core_memmap_demux_interl
