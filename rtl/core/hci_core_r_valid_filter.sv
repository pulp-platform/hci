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
  hci_core_intf.slave  tcdm_slave,
  hci_core_intf.master tcdm_master
);

  logic wen_q;

  assign tcdm_master.add   = tcdm_slave.add;
  assign tcdm_master.data  = tcdm_slave.data;
  assign tcdm_master.be    = tcdm_slave.be;
  assign tcdm_master.wen   = tcdm_slave.wen;
  assign tcdm_master.boffs = tcdm_slave.boffs;
  assign tcdm_master.req   = tcdm_slave.req;
  assign tcdm_master.lrdy  = tcdm_slave.lrdy;
  assign tcdm_master.user  = tcdm_slave.user;
  assign tcdm_slave.gnt     = tcdm_master.gnt;
  assign tcdm_slave.r_data  = tcdm_master.r_data;
  assign tcdm_slave.r_opc   = tcdm_master.r_opc;
  assign tcdm_slave.r_user  = tcdm_master.r_user;
  assign tcdm_slave.r_valid = enable_i ? tcdm_master.r_valid & wen_q : tcdm_master.r_valid;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      wen_q <= '0;
    end
    else if (clear_i) begin
      wen_q <= '0;
    end
    else if(enable_i & tcdm_slave.req) begin
      wen_q <= tcdm_slave.wen;
    end
  end

endmodule // hci_core_r_valid_filter
