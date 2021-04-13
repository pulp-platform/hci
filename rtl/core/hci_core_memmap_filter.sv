/*
 * hci_core_memmap_filter.sv
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

module hci_core_memmap_filter #(
  parameter int unsigned NB_REGION = 2,
  parameter int unsigned NB_INTERLEAVED_REGION = 1,
  parameter int unsigned AW = hci_package::DEFAULT_AW /// addr width
)
(
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         clear_i,

  input  logic [NB_REGION-1:0][AW-1:0] region_start_addr_i,
  input  logic [NB_REGION-1:0][AW-1:0] region_end_addr_i,

  hci_core_intf.slave  slave,
  hci_core_intf.master interl_master,
  hci_core_intf.master per_master
);

    enum logic [1:0] {IDLE, ON_TCDM, ON_PER, ERROR } state_q, state_d;

    logic [NB_REGION-1:0] destination_map;
    logic                 destination_interleaved;
    logic                 destination_non_interleaved;

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
      destination_interleaved = '0;
      for (int unsigned i=0; i<NB_INTERLEAVED_REGION; i++) begin
        destination_interleaved |= destination_map[i];
      end
    end

    always_comb
    begin
      destination_non_interleaved = '0;
      for (int unsigned i=NB_INTERLEAVED_REGION; i<NB_REGION; i++) begin
        destination_non_interleaved |= destination_map[i];
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

    always_comb
    begin : fsm_comb_state
      state_d = state_q;
      if((state_q != ON_PER) || (per_master.r_valid == 1'b1)) begin
        if (slave.req) begin
          if (destination_interleaved) begin
            if(interl_master.gnt)
              state_d = ON_TCDM;
            else
              state_d = IDLE;
          end
          else if(destination_non_interleaved) begin
            if(per_master.gnt)
              state_d = ON_PER;
            else
              state_d = IDLE;
            end
          else begin
            state_d = ERROR;
          end
        end
        else begin
          state_d = IDLE;
        end
      end
    end

    always_comb
    begin : fsm_comb_out
      // handshake
      interl_master.req = slave.req & destination_interleaved;
      per_master.req  = slave.req & ~destination_interleaved;
      slave.gnt  = interl_master.gnt | per_master.gnt | (slave.req & ~(|(destination_map)));
      // interl_master request
      interl_master.add   = slave.add;
      interl_master.wen   = slave.wen;
      interl_master.data  = slave.data;
      interl_master.be    = slave.be;
      interl_master.boffs = slave.boffs;
      interl_master.lrdy  = slave.lrdy;
      interl_master.user  = slave.user;
      // per_master request
      per_master.add   = slave.add;
      per_master.wen   = slave.wen;
      per_master.data  = slave.data;
      per_master.be    = slave.be;
      per_master.boffs = slave.boffs;
      per_master.lrdy  = slave.lrdy;
      per_master.user  = slave.user;
      // slave response
      case(state_q)
        IDLE: begin
          slave.r_valid = '0;
          slave.r_data  = '0;
          slave.r_opc   = '0;
          slave.r_user  = '0;
        end
        ON_TCDM: begin
          slave.r_valid = interl_master.r_valid;
          slave.r_data  = interl_master.r_data;
          slave.r_opc   = interl_master.r_opc;
          slave.r_user  = interl_master.r_user;
        end
        ON_PER: begin
          slave.r_valid = per_master.r_valid;
          slave.r_data  = per_master.r_data;
          slave.r_opc   = per_master.r_opc;
          slave.r_user  = per_master.r_user;
        end
        ERROR: begin
          slave.r_valid = 1'b1;
          slave.r_data  = 32'hbadacce5; // May need modification for DW != 32
          slave.r_opc   = 1;
          slave.r_user  = '0;
        end
        default: begin
          slave.r_valid = '0;
          slave.r_data  = '0;
          slave.r_opc   = '0;
          slave.r_user  = '0;
        end
      endcase
    end

endmodule // hci_core_memmap_filter
