/*
 * hci_core_assign.sv
 * Maurus Item <itemm@student.ethz.ch>
 *
 * Copyright (C) 2024 ETH Zurich, University of Bologna
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
 * The **hci_copy_source** module is used to monitor an input hci interface
 * stream `tcdm_main` and copy it to an output hci interface `tcdm_copy`.
 * Together with hci_copy_sink this allows for fault detection on a chain of
 * HCI modules.
 *
 * How "deep" the copy is can be set with the parameter COPY_TYPE.
 * COPY_TYPE MUST match on connected sinks and sources!
 *
 * The available options are:
 * - COPY:      Fully copy of everything.
 * - NO_ECC:    No copy of ECC signals.
 * - NO_DATA:   No copy of data signals.
 * - CTRL_ONLY: o copy of data or ECC signals.
 */

`include "hci_helpers.svh"

module hci_copy_source
  import hci_package::*;
#(
  parameter hci_package::hci_copy_t  COPY_TYPE = COPY,
  parameter                   logic  DONT_CARE = 1 // Signal to use for don't care assignments
) (
  input logic             clk_i,
  input logic             rst_ni,
  hci_core_intf.monitor   tcdm_main,
  hci_core_intf.initiator tcdm_copy,
  output logic            fault_o
);
  
  logic fault, ctrl_fault, data_fault, ecc_fault;

  // Control signals always assigned
  assign tcdm_copy.req     = tcdm_main.req;
  assign tcdm_copy.add     = tcdm_main.add;
  assign tcdm_copy.wen     = tcdm_main.wen;
  assign tcdm_copy.be      = tcdm_main.be;
  assign tcdm_copy.r_ready = tcdm_main.r_ready;
  assign tcdm_copy.user    = tcdm_main.user;
  assign tcdm_copy.id      = tcdm_main.id;

  assign ctrl_fault = 
    ( tcdm_main.gnt      != tcdm_copy.gnt     ) |
    ( tcdm_main.r_valid  != tcdm_copy.r_valid ) |
    ( tcdm_main.r_user   != tcdm_copy.r_user  ) |
    ( tcdm_main.r_id     != tcdm_copy.r_id    ) |
    ( tcdm_main.r_opc    != tcdm_copy.r_opc   );


  // Data
  if (COPY_TYPE == NO_DATA || COPY_TYPE == CTRL_ONLY) begin
    assign data_fault = 1'b0;
    assign tcdm_copy.data = DONT_CARE;
  end
  else begin
    assign tcdm_copy.data = tcdm_main.data;
    assign data_fault = tcdm_main.r_data != tcdm_copy.r_data;
  end


  // ECC
  if (COPY_TYPE == NO_ECC || COPY_TYPE == CTRL_ONLY) begin
    assign ecc_fault = 1'b0;
    assign tcdm_copy.ereq     = DONT_CARE;
    assign tcdm_copy.r_eready = DONT_CARE;
    assign tcdm_copy.ecc      = DONT_CARE;
  end
  else begin
    assign tcdm_copy.ereq     = tcdm_main.ereq;
    assign tcdm_copy.r_eready = tcdm_main.r_eready;
    assign tcdm_copy.ecc      = tcdm_main.ecc;

    assign ecc_fault =
      ( tcdm_main.egnt     != tcdm_copy.egnt     ) |
      ( tcdm_main.r_evalid != tcdm_copy.r_evalid ) |
      ( tcdm_main.r_ecc    != tcdm_copy.r_ecc    );
  end


  assign fault = ctrl_fault | data_fault | ecc_fault;

  // Store in FF so critical path is broken
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fault_o <= '0;
    end else begin
      fault_o <= fault;
    end
  end

endmodule // hci_copy_source
