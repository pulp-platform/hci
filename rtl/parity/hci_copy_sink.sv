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
 * The **hci_copy_sink** module closes a duplicated (lockstep-copy) path on an
 * HCI-Core interface. It is meant to be paired with a **hci_copy_source**
 * (see :ref:`hci_copy_source`) placed at the head of a chain of HCI modules:
 * the `tcdm_main` port monitors the primary HCI-Core stream (as a passive
 * `monitor` modport), while the `tcdm_copy` port consumes the redundant
 * stream produced by the matching `hci_copy_source`. Each cycle the sink
 * compares the two streams field-by-field and raises `fault_o` whenever they
 * diverge, providing single-fault detection on the protected segment.
 *
 * The granularity of the comparison is controlled by the `COPY_TYPE` and
 * `COMPARE_TYPE` parameters, which configure respectively the main-to-copy
 * driving and the copy-to-main checking. The selected mode **must** match
 * on both ends of the duplicated path.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_copy_sink_params:
 * .. table:: **hci_copy_sink** design-time parameters.
 *
 *   +-----------------+-------------+----------------------------------------------------------------------------------+
 *   | **Name**        | **Default** | **Description**                                                                  |
 *   +-----------------+-------------+----------------------------------------------------------------------------------+
 *   | *COPY_TYPE*     | `COPY`      | Depth of main-to-copy duplication (see `hci_copy_t` below).                      |
 *   +-----------------+-------------+----------------------------------------------------------------------------------+
 *   | *COMPARE_TYPE*  | `COPY`      | Depth of copy-to-main comparison.                                                |
 *   +-----------------+-------------+----------------------------------------------------------------------------------+
 *   | *DONT_CARE*     | 1           | Constant value driven on signals that are not propagated by the current mode.    |
 *   +-----------------+-------------+----------------------------------------------------------------------------------+
 *
 * The supported `hci_copy_t` modes (shared with **hci_copy_source**) are:
 *
 * - **COPY**:      Fully copy and compare every HCI signal.
 * - **NO_ECC**:    Copy and compare everything except the `ecc` side-channel.
 * - **NO_DATA**:   Copy and compare everything except the `data` payload.
 * - **CTRL_ONLY**: No copy or compare of `data` or `ecc` signals; only the
 *   control plane is duplicated.
 */

`include "hci_helpers.svh"

module hci_copy_sink
  import hci_package::*; 
#(
  parameter hci_package::hci_copy_t  COPY_TYPE = COPY, // Main -> Copy
  parameter hci_package::hci_copy_t  COMPARE_TYPE = COPY, // Copy -> Main
  parameter                   logic  DONT_CARE = 1 // Signal to use for don't care assignments
) (
  input logic           clk_i,
  input logic           rst_ni,
  hci_core_intf.monitor tcdm_main,
  hci_core_intf.target  tcdm_copy,
  output logic          fault_o
);
  
  logic fault, ctrl_fault, data_fault, ecc_fault;

  // Control signals always assigned and compared
  assign tcdm_copy.gnt      = tcdm_main.gnt;
  assign tcdm_copy.r_valid  = tcdm_main.r_valid;
  assign tcdm_copy.r_user   = tcdm_main.r_user;
  assign tcdm_copy.r_id     = tcdm_main.r_id;
  assign tcdm_copy.r_opc    = tcdm_main.r_opc;

  assign ctrl_fault = 
    ( tcdm_main.req      != tcdm_copy.req      ) |
    ( tcdm_main.add      != tcdm_copy.add      ) |
    ( tcdm_main.wen      != tcdm_copy.wen      ) |
    ( tcdm_main.be       != tcdm_copy.be       ) |
    ( tcdm_main.r_ready  != tcdm_copy.r_ready  ) |
    ( tcdm_main.user     != tcdm_copy.user     ) |
    ( tcdm_main.id       != tcdm_copy.id       );


  // Data
  if (COPY_TYPE == NO_DATA || COPY_TYPE == CTRL_ONLY) begin : data_nocopy
    assign tcdm_copy.r_data = DONT_CARE;
  end
  else begin : data_copy
    assign tcdm_copy.r_data = tcdm_main.r_data;
  end

  if (COMPARE_TYPE == NO_DATA || COMPARE_TYPE == CTRL_ONLY) begin : data_nocompare
    assign data_fault = 1'b0;
  end
  else begin : data_compare
    assign data_fault = tcdm_main.data != tcdm_copy.data;
  end

  // ECC
  if (COPY_TYPE == NO_ECC || COPY_TYPE == CTRL_ONLY) begin : ecc_nocopy
    assign tcdm_copy.egnt     = DONT_CARE;
    assign tcdm_copy.r_evalid = DONT_CARE;
    assign tcdm_copy.r_ecc    = DONT_CARE;
  end
  else begin : ecc_copy
    assign tcdm_copy.egnt     = tcdm_main.egnt;
    assign tcdm_copy.r_evalid = tcdm_main.r_evalid;
    assign tcdm_copy.r_ecc    = tcdm_main.r_ecc;
  end

  if (COMPARE_TYPE == NO_ECC || COMPARE_TYPE == CTRL_ONLY) begin : ecc_nocompare
    assign ecc_fault = 1'b0;
  end
  else begin : ecc_compare
    assign ecc_fault =
      ( tcdm_main.ereq     != tcdm_copy.ereq     ) |
      ( tcdm_main.r_eready != tcdm_copy.r_eready ) |
      ( tcdm_main.ecc      != tcdm_copy.ecc      );
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

endmodule // hci_copy_sink
