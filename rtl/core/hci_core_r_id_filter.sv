/*
 * hci_core_r_valid_filter.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2014-2023 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * This block filters the id field of the TCDM request, and forwards it to
 * the r_id field of the TCDM response.
 */

import hwpe_stream_package::*;
import hci_package::*;

module hci_core_r_id_filter 
(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic clear_i,
  input  logic enable_i,
  hci_core_intf.target    tcdm_target,
  hci_core_intf.initiator tcdm_initiator
);

  localparam int unsigned IW = tcdm_target.IW;
  localparam int unsigned EHW = tcdm_target.EHW;

  logic [IW-1:0] id_q;

  assign tcdm_initiator.add     = tcdm_target.add;
  assign tcdm_initiator.data    = tcdm_target.data;
  assign tcdm_initiator.be      = tcdm_target.be;
  assign tcdm_initiator.wen     = tcdm_target.wen;
  assign tcdm_initiator.req     = tcdm_target.req;
  assign tcdm_initiator.r_ready = tcdm_target.r_ready;
  assign tcdm_initiator.user    = tcdm_target.user;
  assign tcdm_initiator.id      = '0;
  assign tcdm_initiator.ecc     = tcdm_target.ecc;
  assign tcdm_target.gnt        = tcdm_initiator.gnt;
  assign tcdm_target.r_data     = tcdm_initiator.r_data;
  assign tcdm_target.r_user     = tcdm_initiator.r_user;
  assign tcdm_target.r_id       = id_q;
  assign tcdm_target.r_ecc      = tcdm_initiator.r_ecc;
  assign tcdm_target.r_valid    = tcdm_initiator.r_valid;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      id_q <= '0;
    end
    else if (clear_i) begin
      id_q <= '0;
    end
    else if(enable_i & tcdm_target.req) begin
      id_q <= tcdm_target.id;
    end
  end

/*
 * ECC Handshake signals
 */
  if(EHW > 0) begin : ecc_handshake_gen
    assign tcdm_initiator.ereq     = {(EHW){tcdm_initiator.req}};
    assign tcdm_target.egnt        = {(EHW){tcdm_target.gnt}};
    assign tcdm_target.r_evalid    = {(EHW){tcdm_target.r_valid}};
    assign tcdm_initiator.r_eready = {(EHW){tcdm_initiator.r_ready}};
  end
  else begin : no_ecc_handshake_gen
    assign tcdm_initiator.ereq     = '0;
    assign tcdm_target.egnt        = '1; // assign all gnt's to 1
    assign tcdm_target.r_evalid    = '0;
    assign tcdm_initiator.r_eready = '1; // assign all gnt's to 1 
  end

/*
 * The hci_core_r_id_filter works *only* if it is positioned at the 1-cycle latency boundary, i.e.,
 * the boundary in a cluster where we are guaranteed that a grant on a read results in a response in
 * the following cycle. Positioning it in another place results in hard-to-debug problems, typically
 * showing up as r_valid's never being taken or being served to the wrong initiator by a OoO mux or a
 * dynamic mux.
 * These asserts try to avoid this scenario!
 */
`ifndef SYNTHESIS
`ifndef VERILATOR
  // gnt=1 & wen=1 => the following cycle r_valid=1
  property p_gnt_wen_high_then_r_valid_high_next_cycle;
    @(posedge clk_i) (tcdm_initiator.gnt && tcdm_initiator.wen) |-> ##1 tcdm_initiator.r_valid;
  endproperty

  assert_gnt_wen_high_then_r_valid_high_next_cycle: assert property (p_gnt_wen_high_then_r_valid_high_next_cycle)
    else $warning("`r_valid` did not follow `gnt` by 1 cycle in a read: are you sure the `r_id` filter is at the 1-cycle latency boundary?");

  // gnt=0 => the following cycle r_valid=0
  property p_gnt_low_then_r_valid_low_next_cycle;
    @(posedge clk_i) (!tcdm_initiator.gnt) |-> ##1 !tcdm_initiator.r_valid;
  endproperty

  assert_gnt_low_then_r_valid_low_next_cycle: assert property (p_gnt_low_then_r_valid_low_next_cycle)
    else $warning("`r_valid` did not follow `gnt` by 1 cycle in a read: are you sure the `r_id` filter is at the 1-cycle latency boundary?");
`endif
`endif

/*
 * Interface size asserts
 */
`ifndef SYNTHESIS
`ifndef VERILATOR
  initial
    dw : assert(tcdm_target.DW == tcdm_initiator.DW);
  initial
    bw : assert(tcdm_target.BW == tcdm_initiator.BW);
  initial
    aw : assert(tcdm_target.AW == tcdm_initiator.AW);
  initial
    uw : assert(tcdm_target.UW == tcdm_initiator.UW);
  initial
    ew : assert(tcdm_target.EW == tcdm_initiator.EW);
  initial
    ehw : assert(tcdm_target.EHW == tcdm_initiator.EHW);
`endif
`endif;

endmodule // hci_core_r_id_filter