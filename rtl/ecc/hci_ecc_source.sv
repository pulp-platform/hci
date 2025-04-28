/*
 * hci_ecc_source.sv
 * Luigi Ghionda <luigi.ghionda2@unibo.it>
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

/*
 * The **hci_ecc_source** module acts as an ECC-extended wrapper around the **hci_core_source** module.
 * It extends the functionality with ECC support, while preserving it's original behavior.
 * Please refer to **hci_core_source** for detailed functional information.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_ecc_source_params:
 * .. table:: **hci_ecc_source** design-time parameters.
 *
 *   +---------------------+-------------+--------------------------------------------------------------+
 *   | **Name**             | **Default** | **Description**                                              |
 *   +---------------------+-------------+--------------------------------------------------------------+
 *   | *CHUNK_SIZE*         | 32          | Width in bits of each chunk of data to protect individually. |
 *   +---------------------+-------------+--------------------------------------------------------------+
 *
 */

`include "hci_helpers.svh"

module hci_ecc_source
  import hci_package::*;
#(
  // Stream interface params
  parameter int unsigned LATCH_FIFO  = 0,
  parameter int unsigned TRANS_CNT = 16,
  parameter int unsigned ADDR_MIS_DEPTH = 8, // Beware: this must be >= the maximum latency between TCDM gnt and TCDM r_valid!!!
  parameter int unsigned MISALIGNED_ACCESSES = 1,
  parameter int unsigned PASSTHROUGH_FIFO = 0,
  parameter int unsigned CHUNK_SIZE  = 32,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0,
  parameter int unsigned DW  = `HCI_SIZE_GET_DW(tcdm),
  // Dependent parameters, do not override
  parameter int unsigned N_CHUNK = DW / CHUNK_SIZE
)
(
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,
  input logic clear_i,
  input logic enable_i,

  hci_core_intf.initiator        tcdm,
  hwpe_stream_intf_stream.source stream,

  output logic [N_CHUNK-1:0] r_data_single_err_o,
  output logic [N_CHUNK-1:0] r_data_multi_err_o,
  output logic               r_meta_single_err_o,
  output logic               r_meta_multi_err_o,

  // control plane
  input  hci_streamer_ctrl_t   ctrl_i,
  output hci_streamer_flags_t  flags_o
);

  localparam int unsigned UW  = `HCI_SIZE_GET_UW(tcdm);
  localparam int unsigned IW  = `HCI_SIZE_GET_IW(tcdm);
  localparam int unsigned EW  = `HCI_SIZE_GET_EW(tcdm);
  localparam int unsigned EHW = `HCI_SIZE_GET_EHW(tcdm);

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(virt_tcdm) = '{
    DW:  DW,
    AW:  DEFAULT_AW,
    BW:  DEFAULT_BW,
    UW:  UW,
    IW:  IW,
    EW:  EW,
    EHW: EHW
  };
  `HCI_INTF(virt_tcdm, clk_i);

  hci_ecc_enc #(
    .`HCI_SIZE_PARAM(tcdm_target)    ( `HCI_SIZE_PARAM(virt_tcdm) ),
    .`HCI_SIZE_PARAM(tcdm_initiator) ( `HCI_SIZE_PARAM(tcdm)      )
  ) i_ecc_enc (
    .r_data_single_err_o ( r_data_single_err_o ),
    .r_data_multi_err_o  ( r_data_multi_err_o  ),
    .r_meta_single_err_o ( r_meta_single_err_o ),
    .r_meta_multi_err_o  ( r_meta_multi_err_o  ),
    .tcdm_target         ( virt_tcdm           ),
    .tcdm_initiator      ( tcdm                )
  );

  hci_core_source #(
    .LATCH_FIFO          ( LATCH_FIFO ),
    .TRANS_CNT           ( TRANS_CNT ),
    .ADDR_MIS_DEPTH      ( ADDR_MIS_DEPTH ),
    .MISALIGNED_ACCESSES ( MISALIGNED_ACCESSES ),
    .PASSTHROUGH_FIFO    ( PASSTHROUGH_FIFO ),
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(virt_tcdm) )
  ) i_hci_core_source (
    .clk_i       ( clk_i       ),
    .rst_ni      ( rst_ni      ),
    .test_mode_i ( test_mode_i ),
    .clear_i     ( clear_i     ),
    .enable_i    ( enable_i    ),
    .tcdm        ( virt_tcdm   ),
    .stream      ( stream      ),
    .ctrl_i      ( ctrl_i      ),
    .flags_o     ( flags_o     )
  );

endmodule // hci_ecc_source
