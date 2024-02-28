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
  parameter int unsigned DW          = 64, // DW_IN
  parameter int unsigned BW          = 8,
  parameter int unsigned NB_OUT_CHAN = 2,
  parameter int unsigned FIFO_DEPTH  = 0
) (
  input logic clk_i,
  input logic rst_ni,
  input logic clear_i,
  hci_core_intf.slave  tcdm_slave,
  hci_core_intf.master tcdm_master [NB_OUT_CHAN-1:0]
);

  localparam DW_OUT = DW/NB_OUT_CHAN;
  localparam BW_OUT = DW_OUT/8; 

  hci_core_intf #(
    .DW ( DW_OUT )
  ) tcdm_int [NB_OUT_CHAN-1:0] (
    .clk ( clk_i )
  );

  logic [NB_OUT_CHAN-1:0][DW_OUT-1:0] tcdm_r_data;
  logic [NB_OUT_CHAN-1:0]             tcdm_gnt;
  logic [NB_OUT_CHAN-1:0]             tcdm_r_valid;
  logic [NB_OUT_CHAN-1:0]             tcdm_req_masked_d, tcdm_req_masked_q;
  logic cs_gnt, ns_gnt; // 0=gnt, 1=no-gnt

  // Signal binding
  for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin: tcdm_binding
    assign tcdm_int[ii].add   = tcdm_slave.add + ii*BW_OUT;
    assign tcdm_int[ii].wen   = tcdm_slave.wen;
    assign tcdm_int[ii].be    = tcdm_slave.be[(ii+1)*BW_OUT-1:ii*BW_OUT];
    assign tcdm_int[ii].data  = tcdm_slave.data[(ii+1)*DW_OUT-1:ii*DW_OUT];
    assign tcdm_int[ii].user  = '0;
    assign tcdm_int[ii].boffs = '0;
    assign tcdm_int[ii].lrdy  = &(tcdm_r_valid) & tcdm_slave.lrdy;

    assign tcdm_r_data [ii] = tcdm_int[ii].r_data;
    assign tcdm_r_valid[ii] = tcdm_int[ii].r_valid;
    assign tcdm_gnt    [ii] = tcdm_int[ii].gnt;
  end
  assign tcdm_slave.gnt     = &(tcdm_gnt);
  assign tcdm_slave.r_valid = &(tcdm_r_valid);
  assign tcdm_slave.r_data  = { >> {tcdm_r_data} };

  // if(FIFO_DEPTH == 0) begin : no_fifo_gen
    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : assign_loop_gen
      assign tcdm_int[ii].req   = tcdm_slave.req;
      hci_core_assign i_assign (
        .tcdm_slave  ( tcdm_int    [ii] ),
        .tcdm_master ( tcdm_master [ii] )
      );
    end
  // end
  // else begin : fifo_gen
  //   for(genvar ii=0; ii<NB_OUT_CHAN; ii++) begin : fifo_loop_gen
  //     assign tcdm_int[ii].req = ~cs_gnt ?  tcdm_slave.req :       // if state is GNT, propagate requests directly
  //                                         ~tcdm_req_masked_q[ii]; // if state is NO-GNT, only propagate request that were not granted before
  //     hci_core_fifo #(
  //       .FIFO_DEPTH ( FIFO_DEPTH ),
  //       .DW         ( DW_OUT     )
  //     ) i_fifo (
  //       .clk_i       ( clk_i            ),
  //       .rst_ni      ( rst_ni           ),
  //       .clear_i     ( clear_i          ),
  //       .flags_o     (                  ),
  //       .tcdm_slave  ( tcdm_int    [ii] ),
  //       .tcdm_master ( tcdm_master [ii] )
  //     );
  //   end

  //   // Grant/No-Grant state machine
  //   // When a request is not granted, switch to NO-GNT state.
  //   // Switch back to a GNT state when all pending requests are granted.
  //   always_ff @(posedge clk_i or negedge rst_ni)
  //   begin
  //     if(~rst_ni) begin
  //       cs_gnt <= '0;
  //     end
  //     else if (clear_i) begin
  //       cs_gnt <= '0;
  //     end
  //     else begin
  //       cs_gnt <= ns_gnt;
  //     end
  //   end

  //   always_comb
  //   begin
  //     ns_gnt = cs_gnt;
  //     if(cs_gnt == 1'b0) begin // gnt
  //       if(tcdm_slave.req & ~(&tcdm_gnt))
  //         ns_gnt = 1'b1;
  //     end
  //     else begin // no-gnt
  //       if(&(tcdm_gnt | tcdm_req_masked_q))
  //         ns_gnt = 1'b0;
  //     end
  //   end

  //   // REQ masking
  //   assign tcdm_req_masked_d = cs_gnt ? tcdm_req_masked_q | tcdm_gnt : tcdm_gnt;
  //   always_ff @(posedge clk_i or negedge rst_ni)
  //   begin
  //     if(~rst_ni) begin
  //       tcdm_req_masked_q <= '0;
  //     end
  //     else if (clear_i) begin
  //       tcdm_req_masked_q <= '0;
  //     end
  //     else begin
  //       tcdm_req_masked_q <= tcdm_req_masked_d;
  //     end
  //   end
  // end

endmodule // hci_core_split
