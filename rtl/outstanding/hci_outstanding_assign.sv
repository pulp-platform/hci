/*
 * hci_outstanding_assign.sv
 * Marco Bertuletti <mbertuletti@iis.ee.ethz.ch>
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
 * The **hci_outstanding_assign** module implements a simple assignment for
 * HCI-Outstanding streams.
 *
 */

module hci_outstanding_assign 
  import hwpe_stream_package::*;
(
  hci_outstanding_intf.target    tcdm_target,
  hci_outstanding_intf.initiator tcdm_initiator
);

  assign tcdm_initiator.req_add     = tcdm_target.req_add;
  assign tcdm_initiator.req_wen     = tcdm_target.req_wen;
  assign tcdm_initiator.req_data    = tcdm_target.req_data;
  assign tcdm_initiator.req_be      = tcdm_target.req_be;
  assign tcdm_initiator.req_user    = tcdm_target.req_user;
  assign tcdm_initiator.req_id      = tcdm_target.req_id;
  assign tcdm_initiator.req_valid   = tcdm_target.req_valid;
  assign tcdm_target.req_ready      = tcdm_initiator.req_ready;
  
  assign tcdm_target.resp_data     = tcdm_initiator.resp_data;
  assign tcdm_target.resp_user     = tcdm_initiator.resp_user;
  assign tcdm_target.resp_id       = tcdm_initiator.resp_id;
  assign tcdm_target.resp_opc      = tcdm_initiator.resp_opc;
  assign tcdm_target.resp_valid    = tcdm_initiator.resp_valid;
  assign tcdm_initiator.resp_ready = tcdm_target.resp_ready;

endmodule // hci_outstanding_assign
