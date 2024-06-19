/*
 * hci_copy_sink.sv
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
 * The **hci_copy_sink** module is used to monitor an input normal hci interface
 * stream `tcdm_main` and compare it with a copy  stream `tcdm_copy` element.
 * Together with hci_copy_sink this allows for fault detection on a chain of
 * HCI modules.
 */

`include "hci_helpers.svh"

module hci_copy_sink
  import hci_package::*;
(
  input logic           clk_i,
  input logic           rst_ni,
  hci_core_intf.monitor tcdm_main,
  hci_core_intf.target  tcdm_copy,
  output logic          fault_detected_o
);

  assign tcdm_copy.gnt      = tcdm_main.gnt;
  assign tcdm_copy.r_data   = tcdm_main.r_data;
  assign tcdm_copy.r_valid  = tcdm_main.r_valid;
  assign tcdm_copy.r_user   = tcdm_main.r_user;
  assign tcdm_copy.r_id     = tcdm_main.r_id;
  assign tcdm_copy.r_opc    = tcdm_main.r_opc;
  assign tcdm_copy.egnt     = tcdm_main.egnt;
  assign tcdm_copy.r_evalid = tcdm_main.r_evalid;
  assign tcdm_copy.r_ecc    = tcdm_main.r_ecc;

  // Compare Signals
  logic fault_detected;
  assign fault_detected =
    ( tcdm_main.req      != tcdm_copy.req      ) |
    ( tcdm_main.ereq     != tcdm_copy.ereq     ) |
    ( tcdm_main.r_eready != tcdm_copy.r_eready ) |
    ( tcdm_main.ecc      != tcdm_copy.ecc      ) |
    ( tcdm_main.add      != tcdm_copy.add      ) |
    ( tcdm_main.wen      != tcdm_copy.wen      ) |
    ( tcdm_main.data     != tcdm_copy.data     ) |
    ( tcdm_main.be       != tcdm_copy.be       ) |
    ( tcdm_main.r_ready  != tcdm_copy.r_ready  ) |
    ( tcdm_main.user     != tcdm_copy.user     ) |
    ( tcdm_main.id       != tcdm_copy.id       );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fault_detected_o <= '0;
    end else begin
      fault_detected_o <= fault_detected;
    end
  end

endmodule // hci_copy_sink
