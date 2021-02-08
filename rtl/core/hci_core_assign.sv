/*
 * hci_core_assign.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2019-2020 ETH Zurich, University of Bologna
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

module hci_core_assign 
(
  hci_core_intf.slave  tcdm_slave,
  hci_core_intf.master tcdm_master
);

  assign tcdm_master.req    = tcdm_slave.req;
  assign tcdm_slave.gnt     = tcdm_master.gnt;
  assign tcdm_master.add    = tcdm_slave.add;
  assign tcdm_master.wen    = tcdm_slave.wen;
  assign tcdm_master.data   = tcdm_slave.data;
  assign tcdm_master.be     = tcdm_slave.be;
  assign tcdm_master.boffs  = tcdm_slave.boffs;
  assign tcdm_master.lrdy   = tcdm_slave.lrdy;
  assign tcdm_master.user   = tcdm_slave.user;
  assign tcdm_slave.r_data  = tcdm_master.r_data;
  assign tcdm_slave.r_valid = tcdm_master.r_valid;
  assign tcdm_slave.r_opc   = tcdm_master.r_opc;
  assign tcdm_slave.r_user  = tcdm_master.r_user;

endmodule // hci_core_assign
