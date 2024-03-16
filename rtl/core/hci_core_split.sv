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
 * hci_core_r_id_filter that is used, for example, to implement HCI IDs for
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
  hci_core_intf.target    tcdm_target,
  hci_core_intf.initiator tcdm_initiator [0:NB_OUT_CHAN-1]
);

  localparam int unsigned DW_OUT = DW/NB_OUT_CHAN;
  localparam int unsigned BW_OUT = 8; 
  localparam int unsigned EHW = $bits(tcdm_target.ereq);

  hci_core_intf #(
    .DW ( DW_OUT )
  ) tcdm [0:NB_OUT_CHAN-1] (
    .clk ( clk_i )
  );

  hci_core_intf #(
    .DW ( DW_OUT )
  ) tcdm_fifo [0:NB_OUT_CHAN-1] (
    .clk ( clk_i )
  );

  logic [NB_OUT_CHAN-1:0][DW_OUT-1:0] tcdm_r_data;
  logic [NB_OUT_CHAN-1:0]             tcdm_req;
  logic [NB_OUT_CHAN-1:0][31:0]       tcdm_add;
  logic [NB_OUT_CHAN-1:0]             tcdm_gnt;
  logic [NB_OUT_CHAN-1:0]             tcdm_r_valid;
  logic [NB_OUT_CHAN-1:0]             tcdm_initiator_r_valid;
  logic [NB_OUT_CHAN-1:0]             tcdm_req_masked_d, tcdm_req_masked_q;
  logic [NB_OUT_CHAN-1:0]             tcdm_initiator_req;
  logic [NB_OUT_CHAN-1:0]             tcdm_initiator_r_ready;
  logic [NB_OUT_CHAN-1:0]             tcdm_initiator_lrdy_masked_d, tcdm_initiator_lrdy_masked_q;
  logic [NB_OUT_CHAN-1:0]             tcdm_initiator_ereq;
  logic [NB_OUT_CHAN-1:0]             tcdm_initiator_r_eready;

  typedef enum logic { GNT,    NO_GNT }    gnt_state_t;
  typedef enum logic { RVALID, NO_RVALID } rvalid_state_t;

  gnt_state_t    cs_gnt, ns_gnt;
  rvalid_state_t cs_rvalid, ns_rvalid;

  // Signal binding
  for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin: tcdm_binding
    assign tcdm[ii].add     = tcdm_target.add + ii*DW_OUT/BW_OUT;
    assign tcdm[ii].wen     = tcdm_target.wen;
    assign tcdm[ii].be      = tcdm_target.be[(ii+1)*DW_OUT/BW_OUT-1:ii*DW_OUT/BW_OUT];
    assign tcdm[ii].data    = tcdm_target.data[(ii+1)*DW_OUT-1:ii*DW_OUT];
    assign tcdm[ii].user    = tcdm_target.user;
    assign tcdm[ii].id      = tcdm_target.id;
    assign tcdm[ii].ecc     = tcdm_target.ecc;
    assign tcdm[ii].r_ready = cs_rvalid==RVALID ?  tcdm_target.r_ready :         // if state is RVALID, propagate load-ready directly
                                                  &tcdm_initiator_lrdy_masked_q; // if state is NO-RVALID, stop HCI FIFOs by lowering their r_ready

    assign tcdm_r_data [ii] = tcdm[ii].r_data;
    assign tcdm_r_valid[ii] = cs_rvalid==RVALID ?  tcdm[ii].r_valid :            // if state is RVALID, propagate r_valid directly
                                                  &tcdm_initiator_lrdy_masked_q; // if state is NO-RVALID, stop streamers by lowering their r_valid
    assign tcdm_gnt    [ii] = tcdm[ii].gnt;
    assign tcdm_add    [ii] = tcdm[ii].add;
    assign tcdm_req    [ii] = tcdm[ii].req;

    assign tcdm_initiator_r_valid[ii] = tcdm_initiator[ii].r_valid;
  end
  assign tcdm_target.gnt     = &(tcdm_gnt);
  assign tcdm_target.r_valid = &(tcdm_r_valid);
  assign tcdm_target.r_data  = { >> {tcdm_r_data} };
  assign tcdm_target.r_user  = tcdm[0].r_user; // we assume they are identical at this stage (if not, it's broken!)
  assign tcdm_target.r_id    = tcdm[0].r_id;   // we assume they are identical at this stage (if not, it's broken!)
  assign tcdm_target.r_opc   = tcdm[0].r_opc;  // we assume they are identical at this stage (if not, it's broken!)
  assign tcdm_target.r_ecc   = tcdm[0].r_ecc;  // we assume they are identical at this stage (if not, it's broken!)

  if(FIFO_DEPTH == 0) begin : no_fifo_gen
    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : assign_loop_gen
      assign tcdm[ii].req   = tcdm_target.req;
      hci_core_assign i_assign (
        .tcdm_target    ( tcdm           [ii] ),
        .tcdm_initiator ( tcdm_initiator [ii] )
      );
    end
  end
  else begin : fifo_gen
    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : fifo_loop_gen
      assign tcdm[ii].req = cs_gnt==GNT ?  tcdm_target.req :      // if state is GNT, propagate requests directly
                                          ~tcdm_req_masked_q[ii]; // if state is NO-GNT, only propagate request that were not granted before
      hci_core_fifo #(
        .FIFO_DEPTH ( FIFO_DEPTH ),
        .DW         ( DW_OUT     ),
        .UW         ( UW         )
      ) i_fifo (
        .clk_i          ( clk_i          ),
        .rst_ni         ( rst_ni         ),
        .clear_i        ( clear_i        ),
        .flags_o        (                ),
        .tcdm_target    ( tcdm      [ii] ),
        .tcdm_initiator ( tcdm_fifo [ii] )
      );
    end

    // Grant/No-Grant state machine
    // When a request is not granted, switch to NO-GNT state.
    // Switch back to a GNT state when all pending requests are granted.
    always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        cs_gnt <= GNT;
      end
      else if (clear_i) begin
        cs_gnt <= GNT;
      end
      else begin
        cs_gnt <= ns_gnt;
      end
    end

    always_comb
    begin
      ns_gnt = cs_gnt;
      if(cs_gnt == GNT) begin
        if(tcdm_target.req & ~(&tcdm_gnt))
          ns_gnt = NO_GNT;
      end
      else begin
        if(&(tcdm_gnt | tcdm_req_masked_q))
          ns_gnt = GNT;
      end
    end

    // REQ masking
    assign tcdm_req_masked_d = cs_gnt==NO_GNT ? tcdm_req_masked_q | tcdm_gnt : tcdm_gnt;
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
        cs_rvalid <= RVALID;
      end
      else if (clear_i) begin
        cs_rvalid <= RVALID;
      end
      else begin
        cs_rvalid <= ns_rvalid;
      end
    end

    always_comb
    begin
      ns_rvalid = cs_rvalid;
      if(cs_rvalid == RVALID) begin
        if(|tcdm_initiator_r_valid & ~(&tcdm_initiator_r_valid)) // if there is some valid response, but not all
          ns_rvalid = NO_RVALID;
      end
      else begin
        if(&(tcdm_initiator_r_valid | tcdm_initiator_lrdy_masked_q))
          ns_rvalid = RVALID;
      end
    end

    // r_ready masking
    assign tcdm_initiator_lrdy_masked_d = cs_rvalid==NO_RVALID ? tcdm_initiator_lrdy_masked_q | tcdm_initiator_r_valid | ~tcdm_initiator_req : tcdm_initiator_r_valid | ~tcdm_initiator_req;
    always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        tcdm_initiator_lrdy_masked_q <= '0;
      end
      else if (clear_i) begin
        tcdm_initiator_lrdy_masked_q <= '0;
      end
      else begin
        tcdm_initiator_lrdy_masked_q <= tcdm_initiator_lrdy_masked_d;
      end
    end

    // initiator port binding
    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin: tcdm_binding
      assign tcdm_initiator[ii].req     = tcdm_fifo[ii].req;
      assign tcdm_initiator[ii].add     = tcdm_fifo[ii].add;
      assign tcdm_initiator[ii].wen     = tcdm_fifo[ii].wen;
      assign tcdm_initiator[ii].be      = tcdm_fifo[ii].be;
      assign tcdm_initiator[ii].data    = tcdm_fifo[ii].data;
      assign tcdm_initiator[ii].user    = tcdm_fifo[ii].user;
      assign tcdm_initiator[ii].id      = tcdm_fifo[ii].id;
      assign tcdm_initiator[ii].ecc     = tcdm_fifo[ii].ecc;
      assign tcdm_initiator[ii].r_ready = tcdm_fifo[ii].r_ready;
      assign tcdm_initiator[ii].ereq    = tcdm_initiator_ereq[ii];
      assign tcdm_initiator[ii].r_ready = tcdm_initiator_r_eready[ii];

      assign tcdm_initiator_req[ii] = tcdm_initiator[ii].req
      assign tcdm_initiator_r_ready[ii] = tcdm_initiator[ii].r_ready;;

      assign tcdm_fifo[ii].gnt     = tcdm_initiator[ii].gnt;
      assign tcdm_fifo[ii].r_valid = tcdm_initiator[ii].r_valid;
      assign tcdm_fifo[ii].r_data  = tcdm_initiator[ii].r_data;
      assign tcdm_fifo[ii].r_id    = tcdm_initiator[ii].r_id;
      assign tcdm_fifo[ii].r_opc   = tcdm_initiator[ii].r_opc;
      assign tcdm_fifo[ii].r_ecc   = tcdm_initiator[ii].r_ecc;
    end

  end

/*
 * ECC Handshake signals
 */
  if(EHW > 0) begin : ecc_handshake_gen
    assign tcdm_target.egnt     = '{default: {tcdm_target.gnt}};
    assign tcdm_target.r_evalid = '{default: {tcdm_target.r_evalid}};
    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : out_chan_gen
      assign tcdm_initiator_ereq     [ii] = '{default: {tcdm_initiator_req[ii]}};
      assign tcdm_initiator_r_eready [ii] = '{default: {tcdm_initiator_r_ready[ii]}};
    end
  end
  else begin : no_ecc_handshake_gen
    assign tcdm_target.egnt     = '1;
    assign tcdm_target.r_evalid = '0;
    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : out_chan_gen
      assign tcdm_initiator_ereq     [ii] = '0;
      assign tcdm_initiator_r_eready [ii] = '1;
    end
  end

/*
 * Interface size asserts
 */
`ifndef SYNTHESIS
`ifndef VERILATOR
  for(genvar i=0; i<NB_OUT_CHAN; i++) begin
    initial
      aw :  assert(tcdm_initiator[i].AW  == tcdm_target.AW);
    initial
      uw :  assert(tcdm_initiator[i].UW  == tcdm_target.UW);
    initial
      ew :  assert(tcdm_initiator[i].EW  == tcdm_target.EW);
    initial
      ehw : assert(tcdm_initiator[i].EHW == tcdm_target.EHW);
  end
`endif
`endif;

endmodule // hci_core_split
