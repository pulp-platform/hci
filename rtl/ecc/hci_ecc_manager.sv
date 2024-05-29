// Copyright 2024 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// ECC hci manager

module hci_ecc_manager
  import hci_ecc_manager_reg_pkg::*;
#(
  parameter int unsigned N_CHUNK = 1,
  parameter int unsigned ParData = 1,
  parameter int unsigned ParMeta = 1,
  parameter type         hci_ecc_req_t = logic,
  parameter type         hci_ecc_rsp_t = logic
) (
  input  logic                clk_i,
  input  logic                rst_ni,

  input  hci_ecc_req_t        hci_ecc_req_i,
  output hci_ecc_rsp_t        hci_ecc_rsp_o,

  input  logic [ParData-1:0][N_CHUNK-1:0] data_correctable_err_i,
  input  logic [ParData-1:0][N_CHUNK-1:0] data_uncorrectable_err_i,
  input  logic [ParMeta-1:0]              meta_correctable_err_i,
  input  logic [ParMeta-1:0]              meta_uncorrectable_err_i
);

  hci_ecc_manager_reg2hw_t reg2hw;
  hci_ecc_manager_hw2reg_t hw2reg;

  logic [$clog2(ParData*N_CHUNK):0] data_correctable_err_num;
  logic [$clog2(ParData*N_CHUNK):0] data_uncorrectable_err_num;
  logic [$clog2(ParMeta):0] meta_correctable_err_num;
  logic [$clog2(ParMeta):0] meta_uncorrectable_err_num;

  popcount #(
    .INPUT_WIDTH ( ParData*N_CHUNK )
  ) i_popcount_data_single (
    .data_i      ( data_correctable_err_i   ),
    .popcount_o  ( data_correctable_err_num )
  );

  popcount #(
    .INPUT_WIDTH ( ParData*N_CHUNK )
  ) i_popcount_data_multi (
    .data_i      ( data_uncorrectable_err_i   ),
    .popcount_o  ( data_uncorrectable_err_num )
  );

  popcount #(
    .INPUT_WIDTH ( ParMeta )
  ) i_popcount_meta_single (
    .data_i      ( meta_correctable_err_i   ),
    .popcount_o  ( meta_correctable_err_num )
  );

  popcount #(
    .INPUT_WIDTH ( ParMeta )
  ) i_popcount_meta_multi (
    .data_i      ( meta_correctable_err_i     ),
    .popcount_o  ( meta_uncorrectable_err_num )
  );

  hci_ecc_manager_reg_top #(
    .reg_req_t ( hci_ecc_req_t ),
    .reg_rsp_t ( hci_ecc_rsp_t )
  ) i_registers (
    .clk_i,
    .rst_ni,
    .reg_req_i ( hci_ecc_req_i ),
    .reg_rsp_o ( hci_ecc_rsp_o ),
    .reg2hw    ( reg2hw  ),
    .hw2reg    ( hw2reg  ),
    .devmode_i ( '0      )
  );

  // Count ECC correctable errors on data
  assign hw2reg.data_correctable_errors.d = reg2hw.data_correctable_errors.q + data_correctable_err_num;
  assign hw2reg.data_correctable_errors.de = |(data_correctable_err_i);

  // Count ECC uncorrectable errors on data
  assign hw2reg.data_uncorrectable_errors.d = reg2hw.data_uncorrectable_errors.q + data_uncorrectable_err_num;
  assign hw2reg.data_uncorrectable_errors.de = |(data_uncorrectable_err_i);

  // Count ECC correctable errors on metadata
  assign hw2reg.metadata_correctable_errors.d = reg2hw.metadata_correctable_errors.q + meta_correctable_err_num;
  assign hw2reg.metadata_correctable_errors.de = |(meta_correctable_err_i);

  // Count ECC uncorrectable errors on metadata
  assign hw2reg.metadata_uncorrectable_errors.d = reg2hw.metadata_uncorrectable_errors.q + meta_uncorrectable_err_num;
  assign hw2reg.metadata_uncorrectable_errors.de = |(meta_uncorrectable_err_i);

endmodule
