/*
 * hci_core_split.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2020-2024 ETH Zurich, University of Bologna
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
 * The **hci_core_split** module uses FIFOs to enqueue a split version of the
 * HCI transactions. The FIFO queues evolve in a synchronized fashion on the
 * accelerator side and evolve freely on the TCDM side.
 * In this way, split transactions that can not be immediately brought back
 * to the accelerator do not need to be repeated, massively reducing TCDM
 * traffic.
 * The hci_core_split requires to be followed (not preceded!) by any
 * hci_core_r_user_filter that is used, for example, to implement HCI IDs for
 * the purpose of supporting out-of-order access from a hci_core_mux.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_core_split_params:
 * .. table:: **hci_core_split** design-time parameters.
 *
 *   +---------------------+-------------+-----------------------------------+
 *   | **Name**            | **Default** | **Description**                   |
 *   +---------------------+-------------+-----------------------------------+
 *   | *NB_OUT_CHAN*       | 2           | Number of output channels.        |
 *   +---------------------+-------------+-----------------------------------+
 *   | *FIFO_DEPTH*        | 0           | Depth of internal HCI Core FIFOs. |
 *   +---------------------+-------------+-----------------------------------+
 *
 */

import hwpe_stream_package::*;

module hci_core_split #(
  parameter int unsigned DW          = 64, // DW_IN
  parameter int unsigned BW          = 8,
  parameter int unsigned UW          = 2,
  parameter int unsigned NB_OUT_CHAN = 2,
  parameter int unsigned FIFO_DEPTH  = 0
) (
  input logic clk_i,
  input logic rst_ni,
  input logic clear_i,
  hci_core_intf.target    tcdm_slave,
  hci_core_intf.initiator tcdm_master [NB_OUT_CHAN-1:0]
);

  localparam DW_OUT = DW/NB_OUT_CHAN;
  localparam BW_OUT = DW_OUT/8; 

  hci_core_intf #(
    .DW ( DW_OUT )
  ) tcdm [NB_OUT_CHAN-1:0] (
    .clk ( clk_i )
  );

  hci_core_intf #(
    .DW ( DW_OUT )
  ) tcdm_fifo [NB_OUT_CHAN-1:0] (
    .clk ( clk_i )
  );

  logic [NB_OUT_CHAN-1:0][DW_OUT-1:0] tcdm_r_data;
  logic [NB_OUT_CHAN-1:0]             tcdm_req;
  logic [NB_OUT_CHAN-1:0][31:0]       tcdm_add;
  logic [NB_OUT_CHAN-1:0]             tcdm_gnt;
  logic [NB_OUT_CHAN-1:0]             tcdm_r_valid;
  logic [NB_OUT_CHAN-1:0]             tcdm_master_r_valid;
  logic [NB_OUT_CHAN-1:0]             tcdm_req_masked_d, tcdm_req_masked_q;
  logic [NB_OUT_CHAN-1:0]             tcdm_master_req;
  logic [NB_OUT_CHAN-1:0]             tcdm_master_lrdy_masked_d, tcdm_master_lrdy_masked_q;
  logic cs_gnt, ns_gnt;       // 0=gnt, 1=no-gnt
  logic cs_rvalid, ns_rvalid; // 0=rvalid, 1=no-rvalid

  // Signal binding
  for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin: tcdm_binding
    assign tcdm[ii].add   = tcdm_slave.add + ii*BW_OUT;
    assign tcdm[ii].wen   = tcdm_slave.wen;
    assign tcdm[ii].be    = tcdm_slave.be[(ii+1)*BW_OUT-1:ii*BW_OUT];
    assign tcdm[ii].data  = tcdm_slave.data[(ii+1)*DW_OUT-1:ii*DW_OUT];
    assign tcdm[ii].user  = tcdm_slave.user;
    assign tcdm[ii].lrdy  = ~cs_rvalid ?  tcdm_slave.lrdy :          // if state is RVALID, propagate load-ready directly
                                         &tcdm_master_lrdy_masked_q; // if state is NO-RVALID, stop HCI FIFOs by lowering their lrdy

    assign tcdm_r_data [ii] = tcdm[ii].r_data;
    assign tcdm_r_valid[ii] = ~cs_rvalid ?  tcdm[ii].r_valid :         // if state is RVALID, propagate r_valid directly
                                           &tcdm_master_lrdy_masked_q; // if state is NO-RVALID, stop streamers by lowering their r_valid
    assign tcdm_gnt    [ii] = tcdm[ii].gnt;
    assign tcdm_add    [ii] = tcdm[ii].add;
    assign tcdm_req    [ii] = tcdm[ii].req;

    assign tcdm_master_r_valid[ii] = tcdm_master[ii].r_valid;
  end
  assign tcdm_slave.gnt     = &(tcdm_gnt);
  assign tcdm_slave.r_valid = &(tcdm_r_valid);
  assign tcdm_slave.r_data  = { >> {tcdm_r_data} };
  assign tcdm_slave.r_user  = tcdm[0].r_user; // we assume they are identical at this stage (if not, it's broken!)

  if(FIFO_DEPTH == 0) begin : no_fifo_gen
    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : assign_loop_gen
      assign tcdm[ii].req   = tcdm_slave.req;
      hci_core_assign i_assign (
        .tcdm_slave  ( tcdm        [ii] ),
        .tcdm_master ( tcdm_master [ii] )
      );
    end
  end
  else begin : fifo_gen
    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : fifo_loop_gen
      assign tcdm[ii].req = ~cs_gnt ?  tcdm_slave.req :       // if state is GNT, propagate requests directly
                                      ~tcdm_req_masked_q[ii]; // if state is NO-GNT, only propagate request that were not granted before
      hci_core_fifo #(
        .FIFO_DEPTH ( FIFO_DEPTH ),
        .DW         ( DW_OUT     ),
        .UW         ( UW         )
      ) i_fifo (
        .clk_i       ( clk_i          ),
        .rst_ni      ( rst_ni         ),
        .clear_i     ( clear_i        ),
        .flags_o     (                ),
        .tcdm_slave  ( tcdm      [ii] ),
        .tcdm_master ( tcdm_fifo [ii] )
      );
    end

    // Grant/No-Grant state machine
    // When a request is not granted, switch to NO-GNT state.
    // Switch back to a GNT state when all pending requests are granted.
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
        if(tcdm_slave.req & ~(&tcdm_gnt))
          ns_gnt = 1'b1;
      end
      else begin // no-gnt
        if(&(tcdm_gnt | tcdm_req_masked_q))
          ns_gnt = 1'b0;
      end
    end

    // REQ masking
    assign tcdm_req_masked_d = cs_gnt ? tcdm_req_masked_q | tcdm_gnt : tcdm_gnt;
    always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        tcdm_req_masked_q <= '0;
      end
      else if (clear_i) begin
        tcdm_req_masked_q <= '0;
      end
      else begin
        tcdm_req_masked_q <= tcdm_req_masked_d;
      end
    end

    // RValid/No-RValid state machine
    // When a response is not valid, switch to NO-RVALID state.
    // Switch back to a RVALID state when all pending responses are valid.
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
      if(cs_rvalid == 1'b0) begin // rvalid
        if(|tcdm_master_r_valid & ~(&tcdm_master_r_valid)) // if there is some valid response, but not all
          ns_rvalid = 1'b1;
      end
      else begin // no-gnt
        if(&(tcdm_master_r_valid | tcdm_master_lrdy_masked_q))
          ns_rvalid = 1'b0;
      end
    end

    // LRDY masking
    assign tcdm_master_lrdy_masked_d = cs_rvalid ? tcdm_master_lrdy_masked_q | tcdm_master_r_valid | ~tcdm_master_req : tcdm_master_r_valid | ~tcdm_master_req;
    always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        tcdm_master_lrdy_masked_q <= '0;
      end
      else if (clear_i) begin
        tcdm_master_lrdy_masked_q <= '0;
      end
      else begin
        tcdm_master_lrdy_masked_q <= tcdm_master_lrdy_masked_d;
      end
    end

    // Master port binding
    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin: tcdm_binding
      assign tcdm_master[ii].req   = tcdm_fifo[ii].req;
      assign tcdm_master[ii].add   = tcdm_fifo[ii].add;
      assign tcdm_master[ii].wen   = tcdm_fifo[ii].wen;
      assign tcdm_master[ii].be    = tcdm_fifo[ii].be;
      assign tcdm_master[ii].data  = tcdm_fifo[ii].data;
      assign tcdm_master[ii].user  = tcdm_fifo[ii].user;
      assign tcdm_master[ii].lrdy  = tcdm_fifo[ii].lrdy;

      assign tcdm_master_req[ii] = tcdm_master[ii].req;

      assign tcdm_fifo[ii].gnt     = tcdm_master[ii].gnt;
      assign tcdm_fifo[ii].r_valid = tcdm_master[ii].r_valid;
      assign tcdm_fifo[ii].r_data  = tcdm_master[ii].r_data;
      assign tcdm_fifo[ii].r_opc   = tcdm_master[ii].r_opc;
      assign tcdm_fifo[ii].r_user  = tcdm_master[ii].r_user;
    end

  end

endmodule // hci_core_split
