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

module hci_core_memmap_demux_interl
  import hwpe_stream_package::*;
#(
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

  hci_core_intf.target    target,
  hci_core_intf.initiator initiator [0:NB_REGION-1]
);

    enum logic [1:0] {IDLE, RESPONSE } state_q, state_d;

    logic [$clog2(NB_REGION)-1:0] region_d, region_q;
    logic region_sample;

    logic [NB_REGION-1:0]         initiator_req_aux, initiator_gnt_aux;
    logic [NB_REGION-1:0]         initiator_r_valid_aux;
    logic [NB_REGION-1:0][DW-1:0] initiator_r_data_aux;
    logic [NB_REGION-1:0][UW-1:0] initiator_r_user_aux;

    logic [NB_REGION-1:0] destination_map;
    logic                 destination_valid;

    always_comb
    begin 
      destination_map = '0;
      for (int unsigned i=0; i<NB_REGION; i++) begin
        if ((target.add >= region_start_addr_i[i]) && (target.add < region_end_addr_i[i])) begin
          destination_map[i] = 1'b1;
        end
      end
    end

    always_comb
    begin 
      region_d = '0;
      for (int unsigned i=0; i<NB_REGION; i++) begin
        if ((target.add >= region_start_addr_i[i]) && (target.add < region_end_addr_i[i])) begin
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
      if (target.req) begin
        if(|(initiator_gnt_aux)) begin
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
      initiator_req_aux = '0;
      case(state_q)
        IDLE: begin
          target.r_valid = '0;
          target.r_data  = '0;
          target.r_user  = '0;
        end
        RESPONSE: begin
          target.r_valid = initiator_r_valid_aux [region_q];
          target.r_data  = initiator_r_data_aux  [region_q];
          target.r_user  = initiator_r_user_aux  [region_q];
        end
        default: begin
          target.r_valid = '0;
          target.r_data  = '0;
          target.r_user  = '0;
        end
      endcase
      initiator_req_aux[region_d] = target.req;
      target.gnt = initiator_gnt_aux[region_d];
    end
    
    generate
      for(genvar ii=0; ii<NB_REGION; ii++) begin
        assign initiator[ii].add[AW-1:AWC] = '0;
        assign initiator[ii].add[AWC-1:0]  = target.add[AWC-1:0] - region_start_addr_i[ii][AWC-1:0];
        assign initiator[ii].wen           = target.wen;
        assign initiator[ii].data          = target.data;
        assign initiator[ii].be            = target.be;
        assign initiator[ii].r_ready       = target.r_ready;
        assign initiator[ii].req           = initiator_req_aux[ii];
        assign initiator_gnt_aux     [ii] = initiator[ii].gnt;
        assign initiator_r_valid_aux [ii] = initiator[ii].r_valid;
        assign initiator_r_data_aux  [ii] = initiator[ii].r_data;
        assign initiator_r_user_aux  [ii] = initiator[ii].r_user;
      end
    endgenerate

endmodule // hci_core_memmap_demux_interl
