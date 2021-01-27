/*
 * hci_core_split.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2020 ETH Zurich, University of Bologna
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

module hci_core_split #(
  parameter int unsigned DW = 64, // DW_IN
  parameter int unsigned NB_OUT_CHAN = 2
) (
  input logic clk_i,
  input logic rst_ni,
  input logic clear_i,
  hci_core_intf.slave  tcdm_slave,
  hci_core_intf.master tcdm_master [NB_OUT_CHAN-1:0]
);

  localparam DW_OUT = DW/NB_OUT_CHAN;
  localparam BW_OUT = DW_OUT/8;

  logic [NB_OUT_CHAN-1:0]             tcdm_master_gnt;
  logic [NB_OUT_CHAN-1:0]             tcdm_master_r_valid_d, tcdm_master_r_valid_q;
  logic [NB_OUT_CHAN-1:0]             tcdm_slave_req_masked_d, tcdm_slave_req_masked_q;
  logic [NB_OUT_CHAN-1:0][DW_OUT-1:0] tcdm_master_r_data_d, tcdm_master_r_data_q;

  // User bits not implemented in split
  for (genvar i=0; i<NB_OUT_CHAN; i++) begin
    assign tcdm_master[i].user = '0;
  end
  assign tcdm_slave.r_user = '0;

  for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : gnt_r_valid_gen
    assign tcdm_master_gnt     [ii] = tcdm_master[ii].gnt;
    assign tcdm_master_r_data_d[ii] = tcdm_master[ii].r_data;
  end

  // Grant/No-Grant state machine
  // When a request is not granted, switch to NO-GNT state.
  // Switch back to a GNT state when all pending requests are granted.
  logic cs_gnt, ns_gnt; // 0=gnt, 1=no-gnt
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      cs_gnt <= '0;
    end
    else if (clear_i) begin
      cs_gnt <= '0;
    end
    else begin
      cs_gnt <= ns_gnt;
    end
  end

  always_comb
  begin
    ns_gnt = cs_gnt;
    if(cs_gnt == 1'b0) begin // gnt
      if(tcdm_slave.req & ~(&tcdm_master_gnt))
        ns_gnt = 1'b1;
    end
    else begin // no-gnt
      if(&(tcdm_master_gnt | tcdm_slave_req_masked_q))
        ns_gnt = 1'b0;
    end
  end

  // RValid/No-RValid state machine
  // When a request is not granted, switch to NO-RVALID state.
  // Switch back to a RVALID state when all pending responses have been fulfilled.
  logic cs_rvalid, ns_rvalid; // 0=rvalid, 1=no-rvalid
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      cs_rvalid <= '0;
    end
    else if (clear_i) begin
      cs_rvalid <= '0;
    end
    else begin
      cs_rvalid <= ns_rvalid;
    end
  end

  always_comb
  begin
    ns_rvalid = cs_rvalid;
    if(cs_rvalid == 1'b0) begin // gnt-rvalid
      if(tcdm_slave.req & ~(&tcdm_master_gnt))
        ns_rvalid = 1'b1;
    end
    else begin // no-rvalid
      if(&(tcdm_master_r_valid_d | tcdm_master_r_valid_q))
        ns_rvalid = 1'b0;
    end
  end

  // REQ masking
  assign tcdm_slave_req_masked_d = cs_gnt ? tcdm_slave_req_masked_q | tcdm_master_gnt : tcdm_master_gnt;
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      tcdm_slave_req_masked_q <= '0;
    end
    else if (clear_i) begin
      tcdm_slave_req_masked_q <= '0;
    end
    else begin
      tcdm_slave_req_masked_q <= tcdm_slave_req_masked_d;
    end
  end

  // binding
  for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : tcdm_master_binding

    // RDATA saving
    always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        tcdm_master_r_data_q[ii] <= '0;
      end
      else if (clear_i) begin
        tcdm_master_r_data_q[ii] <= '0;
      end
      else if(tcdm_master[ii].r_valid) begin
        tcdm_master_r_data_q[ii] <= tcdm_master_r_data_d[ii];
      end
    end

    // RVALID masking
    assign tcdm_master_r_valid_d[ii] = tcdm_master_r_valid_q[ii] | tcdm_master[ii].r_valid; // FIXME
    always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        tcdm_master_r_valid_q[ii] <= '0;
      end
      else if (clear_i) begin
        tcdm_master_r_valid_q[ii] <= '0;
      end
      else begin
        tcdm_master_r_valid_q[ii] <= tcdm_master_r_valid_d[ii];
      end
    end

    assign tcdm_master[ii].req   = ~cs_gnt ?  tcdm_slave.req :         // if state is GNT, propagate requests directly
                                             ~tcdm_slave_req_masked_q; // if state is NO-GNT, only propagate request that were not granted before
    assign tcdm_master[ii].lrdy  = tcdm_slave.lrdy;
    assign tcdm_master[ii].add   = tcdm_slave.add + ii*BW_OUT;
    assign tcdm_master[ii].wen   = tcdm_slave.wen;
    assign tcdm_master[ii].be    = tcdm_slave.be;
    assign tcdm_master[ii].data  = tcdm_slave.data[(ii+1)*DW_OUT-1:ii*DW_OUT];
    assign tcdm_master[ii].boffs = '0; // no meaningful way to split boffs, if present
    assign tcdm_slave.r_data[(ii+1)*32-1:ii*32] = ~cs_rvalid                   ? tcdm_master[ii].r_data :   // if state is RVALID, propagate responses directly
                                                   tcdm_slave_req_masked_q[ii] ? tcdm_master_r_data_q[ii] : // if state is NO-RVALID, propagate responses directly for non-masked
                                                                                 tcdm_master[ii].r_data;    // responses, and from the registers for masked ones
  end

  // Back-propagate r_valid only when all of the responses are valid
  assign tcdm_slave.r_valid = &(tcdm_master_r_valid_d | tcdm_master_r_valid_q);
  assign tcdm_slave.r_opc   = tcdm_master[0].r_opc;
  // Back-propagate gnt only when all requests have been granted
  assign tcdm_slave.gnt     = &(tcdm_master_gnt | tcdm_slave_req_masked_q);

endmodule // hci_core_split
