/**
 * Unified Driver Assignment Module
 *
 * Connects application drivers to HCI initiator interfaces.
 * Supports both log branch (standard width) and HWPE branch (wide word) connections.
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

module assign_drivers
  import hci_package::*;
#(
  parameter int unsigned     DRIVER_ID = 1,
  parameter int unsigned     IS_HWPE = 0,        // 0 for log branch, 1 for HWPE branch
  parameter int unsigned     HWPE_WIDTH = 4,     // Only used when IS_HWPE = 1
  parameter int unsigned     DATA_WIDTH_CORE = 32 // Only used when IS_HWPE = 1
)(
  hci_core_intf.target       driver_target,
  hci_core_intf.initiator    hci_initiator
);

  // For HWPE branch, replicate DRIVER_ID across the wide word
  // For log branch, use DRIVER_ID directly (auto-sized to interface width)
  generate
    if (IS_HWPE) begin : gen_hwpe_data
      localparam logic[DATA_WIDTH_CORE-1:0] DRIVER_ID_logic = DRIVER_ID[DATA_WIDTH_CORE-1:0];
      assign hci_initiator.data = hci_initiator.wen ? {HWPE_WIDTH{DRIVER_ID_logic}} : driver_target.data;
    end else begin : gen_log_data
      assign hci_initiator.data = hci_initiator.wen ? DRIVER_ID : driver_target.data;
    end
  endgenerate

  // Standard signal assignments (same for both branches)
  assign hci_initiator.req     = driver_target.req;
  assign driver_target.gnt     = hci_initiator.gnt;
  assign hci_initiator.add     = driver_target.add;
  assign hci_initiator.wen     = driver_target.wen;
  assign hci_initiator.be      = driver_target.be;
  assign hci_initiator.r_ready = driver_target.r_ready;
  assign hci_initiator.user    = driver_target.user;
  assign hci_initiator.id      = driver_target.id;
  assign driver_target.r_data  = hci_initiator.r_data;
  assign driver_target.r_valid = hci_initiator.r_valid;
  assign driver_target.r_user  = hci_initiator.r_user;
  assign driver_target.r_id    = hci_initiator.r_id;
  assign driver_target.r_opc   = hci_initiator.r_opc;

  // ECC signals
  assign hci_initiator.ereq     = driver_target.ereq;
  assign driver_target.egnt     = hci_initiator.egnt;
  assign driver_target.r_evalid = hci_initiator.r_evalid;
  assign hci_initiator.r_eready = driver_target.r_eready;
  assign hci_initiator.ecc      = driver_target.ecc;
  assign driver_target.r_ecc    = hci_initiator.r_ecc;

endmodule

