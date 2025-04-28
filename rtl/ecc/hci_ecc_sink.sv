/*
 * hci_ecc_sink.sv
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
 * The **hci_ecc_sink** module acts as an ECC-extended wrapper around the **hci_core_sink** module.
 * It extends the functionality with ECC support, while preserving it's original behavior.
 * Please refer to **hci_core_sink** for detailed functional information.
 *
 */

`include "hci_helpers.svh"

module hci_ecc_sink
  import hci_package::*;
#(
  // Stream interface params
  parameter int unsigned TCDM_FIFO_DEPTH  = 0,
  parameter int unsigned TRANS_CNT = 16,
  parameter int unsigned MISALIGNED_ACCESSES = 1,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0
)
(
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,
  input logic clear_i,
  input logic enable_i,

  hci_core_intf.initiator        tcdm,
  hwpe_stream_intf_stream.sink stream,

  // control plane
  input  hci_streamer_ctrl_t   ctrl_i,
  output hci_streamer_flags_t  flags_o
);

  localparam int unsigned DW  = `HCI_SIZE_GET_DW(tcdm);
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
    .r_data_single_err_o ( ),
    .r_data_multi_err_o  ( ),
    .r_meta_single_err_o ( ),
    .r_meta_multi_err_o  ( ),
    .tcdm_target         ( virt_tcdm ),
    .tcdm_initiator      ( tcdm      )
  );

  hci_core_sink #(
    .TCDM_FIFO_DEPTH     ( TCDM_FIFO_DEPTH ),
    .TRANS_CNT           ( TRANS_CNT ),
    .MISALIGNED_ACCESSES ( MISALIGNED_ACCESSES ),
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(virt_tcdm) )
  ) i_hci_core_sink (
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

endmodule // hci_ecc_sink
