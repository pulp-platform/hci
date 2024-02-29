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
 * This block filters the user field of the TCDM request, and forwards it to
 * the r_user field of the TCDM response.
 */

import hwpe_stream_package::*;
import hci_package::*;

module hci_core_r_user_filter #(
  parameter int unsigned UW = hci_package::DEFAULT_UW
) 
(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic clear_i,
  input  logic enable_i,
  hci_core_intf.slave  tcdm_slave,
  hci_core_intf.master tcdm_master
);

  logic [UW-1:0] user_q;

  assign tcdm_master.add   = tcdm_slave.add;
  assign tcdm_master.data  = tcdm_slave.data;
  assign tcdm_master.be    = tcdm_slave.be;
  assign tcdm_master.wen   = tcdm_slave.wen;
  assign tcdm_master.req   = tcdm_slave.req;
  assign tcdm_master.lrdy  = tcdm_slave.lrdy;
  assign tcdm_master.user  = '0;
  assign tcdm_slave.gnt     = tcdm_master.gnt;
  assign tcdm_slave.r_data  = tcdm_master.r_data;
  assign tcdm_slave.r_opc   = tcdm_master.r_opc;
  assign tcdm_slave.r_user  = user_q;
  assign tcdm_slave.r_valid = tcdm_master.r_valid;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      user_q <= '0;
    end
    else if (clear_i) begin
      user_q <= '0;
    end
    else if(enable_i & tcdm_slave.req) begin
      user_q <= tcdm_slave.user;
    end
  end

/*
 * The hci_core_r_user_filter works *only* if it is positioned at the 1-cycle latency boundary, i.e.,
 * the boundary in a cluster where we are guaranteed that a grant on a read results in a response in
 * the following cycle. Positioning it in another place results in hard-to-debug problems, typically
 * showing up as r_valid's never being taken or being served to the wrong master by a OoO mux or a
 * dynamic mux.
 * These asserts try to avoid this scenario!
 */
`ifndef SYNTHESIS
  // gnt=1 & wen=1 => the following cycle r_valid=1
  property p_gnt_wen_high_then_r_valid_high_next_cycle;
    @(posedge clk_i) (tcdm_master.gnt && tcdm_master.wen) |-> ##1 tcdm_master.r_valid;
  endproperty

  assert_gnt_wen_high_then_r_valid_high_next_cycle: assert property (p_gnt_wen_high_then_r_valid_high_next_cycle)
    else $warning("`r_valid` did not follow `gnt` by 1 cycle in a read: are you sure the `r_user` filter is at the 1-cycle latency boundary?");

  // gnt=0 => the following cycle r_valid=0
  property p_gnt_low_then_r_valid_low_next_cycle;
    @(posedge clk_i) (!tcdm_master.gnt) |-> ##1 !tcdm_master.r_valid;
  endproperty

  assert_gnt_low_then_r_valid_low_next_cycle: assert property (p_gnt_low_then_r_valid_low_next_cycle)
    else $warning("`r_valid` did not follow `gnt` by 1 cycle in a read: are you sure the `r_user` filter is at the 1-cycle latency boundary?");
`endif

endmodule // hci_core_r_user_filter
