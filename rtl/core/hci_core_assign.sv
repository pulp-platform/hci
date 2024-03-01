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

/**
 * The **hci_core_assign** module implements a simple assignment for
 * HCI-Core streams.
 *
 */

import hwpe_stream_package::*;

module hci_core_assign 
(
  hci_core_intf.target    tcdm_target,
  hci_core_intf.initiator tcdm_initiator
);

  assign tcdm_initiator.req     = tcdm_target.req;
  assign tcdm_target.gnt        = tcdm_initiator.gnt;
  assign tcdm_initiator.add     = tcdm_target.add;
  assign tcdm_initiator.wen     = tcdm_target.wen;
  assign tcdm_initiator.data    = tcdm_target.data;
  assign tcdm_initiator.be      = tcdm_target.be;
  assign tcdm_initiator.r_ready = tcdm_target.r_ready;
  assign tcdm_initiator.user    = tcdm_target.user;
  assign tcdm_target.r_data  = tcdm_initiator.r_data;
  assign tcdm_target.r_valid = tcdm_initiator.r_valid;
  assign tcdm_target.r_user  = tcdm_initiator.r_user;

endmodule // hci_core_assign
