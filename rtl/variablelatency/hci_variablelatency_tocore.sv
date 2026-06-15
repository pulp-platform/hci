/*
 * hci_variablelatency_tocore.sv
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
 * The **hci_variablelatency_tocore** module implements a simple conversion for
 * HCI-variablelatency streams.
 *
 */

module hci_variablelatency_tocore
  import hwpe_stream_package::*;
(
  hci_variablelatency_intf.initiator tcdm_target,
  hci_core_intf.initiator        tcdm_initiator
);

  assign tcdm_target.req_add     = tcdm_initiator.add;
  assign tcdm_target.req_wen     = tcdm_initiator.wen;
  assign tcdm_target.req_data    = tcdm_initiator.data;
  assign tcdm_target.req_be      = tcdm_initiator.be;
  assign tcdm_target.req_user    = tcdm_initiator.user;
  assign tcdm_target.req_id      = tcdm_initiator.id;
  assign tcdm_target.req_valid   = tcdm_initiator.req;
  assign tcdm_initiator.gnt      = tcdm_target.req_valid & tcdm_target.req_ready;
  
  assign tcdm_initiator.r_data   = tcdm_target.resp_data;
  assign tcdm_initiator.r_user   = tcdm_target.resp_user;
  assign tcdm_initiator.r_id     = tcdm_target.resp_id;
  assign tcdm_initiator.r_opc    = tcdm_target.resp_opc;
  assign tcdm_initiator.r_ecc    = '0;
  assign tcdm_initiator.r_evalid = 1'b0;
  assign tcdm_initiator.r_valid  = tcdm_target.resp_valid;
  assign tcdm_target.resp_ready  = tcdm_initiator.r_ready;

endmodule // hci_variablelatency_tocore
