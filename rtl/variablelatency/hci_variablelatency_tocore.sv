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
  hci_core_intf.target               in,
  hci_variablelatency_intf.initiator out
);

  assign out.req_add     = in.add;
  assign out.req_wen     = in.wen;
  assign out.req_data    = in.data;
  assign out.req_be      = in.be;
  assign out.req_user    = in.user;
  assign out.req_id      = in.id;
  assign out.req_valid   = in.req;
  assign in.gnt          = out.req_valid & out.req_ready;
  // Mirror gnt on ECC (no ECC in hci-variablelatency)
  assign in.egnt         = out.req_valid & out.req_ready;
  
  assign in.r_data       = out.resp_data;
  assign in.r_user       = out.resp_user;
  assign in.r_id         = out.resp_id;
  assign in.r_opc        = out.resp_opc;
  assign in.r_ecc        = '0;
  assign in.r_valid      = out.resp_valid;
  // Mirror r_valid on ECC (no ECC in hci-variablelatency)
  assign in.r_evalid     = out.resp_valid;
  assign out.resp_ready  = in.r_ready;

endmodule // hci_variablelatency_tocore
