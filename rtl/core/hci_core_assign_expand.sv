/*
 * hci_core_assign_expand.sv
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
 * HCI-Core streams. This **expand** version cleanly expands the data width.
 *
 */

module hci_core_assign_expand
  import hwpe_stream_package::*;
#(
  parameter int unsigned TGT_DATA_WIDTH = -1,
  parameter int unsigned INIT_DATA_WIDTH = -1
)
(
  hci_core_intf.target    tcdm_target,
  hci_core_intf.initiator tcdm_initiator
);

  assign tcdm_initiator.req     = tcdm_target.req;
  assign tcdm_target.gnt        = tcdm_initiator.gnt;
  assign tcdm_initiator.add     = tcdm_target.add;
  assign tcdm_initiator.wen     = tcdm_target.wen;
  assign tcdm_initiator.data    = {{(INIT_DATA_WIDTH-TGT_DATA_WIDTH){1'b0}}, tcdm_target.data};
  assign tcdm_initiator.be      = {{(INIT_DATA_WIDTH-TGT_DATA_WIDTH)/8{1'b0}}, tcdm_target.be};
  assign tcdm_initiator.r_ready = tcdm_target.r_ready;
  assign tcdm_initiator.user    = tcdm_target.user;
  assign tcdm_initiator.id      = tcdm_target.id;
  assign tcdm_target.r_data  = {{(INIT_DATA_WIDTH-TGT_DATA_WIDTH){1'b0}}, tcdm_initiator.r_data};
  assign tcdm_target.r_valid = tcdm_initiator.r_valid;
  assign tcdm_target.r_user  = tcdm_initiator.r_user;
  assign tcdm_target.r_id    = tcdm_initiator.r_id;
  assign tcdm_target.r_opc   = tcdm_initiator.r_opc;

  // ECC signals
  assign tcdm_initiator.ereq     = tcdm_target.ereq;
  assign tcdm_target.egnt        = tcdm_initiator.egnt;
  assign tcdm_target.r_evalid    = tcdm_initiator.r_evalid;
  assign tcdm_initiator.r_eready = tcdm_target.r_eready;
  assign tcdm_initiator.ecc      = tcdm_target.ecc;
  assign tcdm_target.r_ecc       = tcdm_initiator.r_ecc;

`ifndef SYNTHESIS
  initial begin : width_checks
    if (TGT_DATA_WIDTH % 8 != 0 || INIT_DATA_WIDTH % 8 != 0)
      $error("TGT_DATA_WIDTH (%d) and INIT_DATA_WIDTH (%d) must be multiples of 8!", TGT_DATA_WIDTH, INIT_DATA_WIDTH);
    if (TGT_DATA_WIDTH > INIT_DATA_WIDTH)
      $error("TGT_DATA_WIDTH must be smaller or equal to INIT_DATA_WIDTH!");
  end
`endif
endmodule : hci_core_assign_expand
