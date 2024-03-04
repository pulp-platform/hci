/*
 * hci_core_r_valid_filter.sv
 * Francesco Conti <f.conti@unibo.it>
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
import hci_package::*;

module hci_core_r_valid_filter
(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic clear_i,
  input  logic enable_i,
  hci_core_intf.target    tcdm_target,
  hci_core_intf.initiator tcdm_initiator
);

  logic wen_q;

  assign tcdm_initiator.add     = tcdm_target.add;
  assign tcdm_initiator.data    = tcdm_target.data;
  assign tcdm_initiator.be      = tcdm_target.be;
  assign tcdm_initiator.wen     = tcdm_target.wen;
  assign tcdm_initiator.req     = tcdm_target.req;
  assign tcdm_initiator.r_ready = tcdm_target.r_ready;
  assign tcdm_initiator.user    = tcdm_target.user;
  assign tcdm_initiator.ecc     = tcdm_target.ecc;
  assign tcdm_target.gnt        = tcdm_initiator.gnt;
  assign tcdm_target.r_data     = tcdm_initiator.r_data;
  assign tcdm_target.r_user     = tcdm_initiator.r_user;
  assign tcdm_target.r_ecc      = tcdm_initiator.r_ecc;
  assign tcdm_target.r_valid    = enable_i ? tcdm_initiator.r_valid & wen_q : tcdm_initiator.r_valid;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      wen_q <= '0;
    end
    else if (clear_i) begin
      wen_q <= '0;
    end
    else if(enable_i & tcdm_target.req) begin
      wen_q <= tcdm_target.wen;
    end
  end
  
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

endmodule // hci_core_r_valid_filter
