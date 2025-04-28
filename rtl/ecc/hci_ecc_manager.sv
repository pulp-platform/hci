/*
 * hci_ecc_manager.sv
 * Luigi Ghionda <luigi.ghionda2@unibo.it>
 *
 * Copyright 2024 ETH Zurich and University of Bologna.
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
 * The **hci_ecc_manager** module logs faults on data and metadata fields,
 * distinguishing correctable and uncorrectable errors, as detected along the
 * **hci_ecc_interconnect**, and collects them into software-accessible registers.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_ecc_manager_params:
 * .. table:: **hci_ecc_manager** design-time parameters.
 *
 *   +---------------------+-------------+--------------------------------------------------------------------------------------------+
 *   | **Name**            | **Default** | **Description**                                                                            |
 *   +---------------------+-------------+--------------------------------------------------------------------------------------------+
 *   | *N_CHUNK*           | 1           | Number of chunks in which the wide data channel is split for independent ECC processing.   |
 *   +---------------------+-------------+--------------------------------------------------------------------------------------------+
 *   | *PAR_DATA*          | 1           | Number of independent parallel data error sources monitored across the interconnect.       |
 *   +---------------------+-------------+--------------------------------------------------------------------------------------------+
 *   | *PAR_META*          | 1           | Number of independent parallel metadata error sources monitored across the interconnect.   |
 *   +---------------------+-------------+--------------------------------------------------------------------------------------------+
 * */


module hci_ecc_manager
  import hci_package::*;
  import hci_ecc_manager_reg_pkg::*;
#(
  parameter int unsigned N_CHUNK = 1,
  parameter int unsigned PAR_DATA = 1,
  parameter int unsigned PAR_META = 1
) (
  input  logic                clk_i,
  input  logic                rst_ni,

  input  hci_ecc_req_t        hci_ecc_req_i,
  output hci_ecc_rsp_t        hci_ecc_rsp_o,

  input  logic [PAR_DATA-1:0][N_CHUNK-1:0] data_correctable_err_i,
  input  logic [PAR_DATA-1:0][N_CHUNK-1:0] data_uncorrectable_err_i,
  input  logic [PAR_META-1:0]              meta_correctable_err_i,
  input  logic [PAR_META-1:0]              meta_uncorrectable_err_i
);

  hci_ecc_manager_reg2hw_t reg2hw;
  hci_ecc_manager_hw2reg_t hw2reg;

  logic [$clog2(PAR_DATA*N_CHUNK):0] data_correctable_err_num;
  logic [$clog2(PAR_DATA*N_CHUNK):0] data_uncorrectable_err_num;
  logic [$clog2(PAR_META):0] meta_correctable_err_num;
  logic [$clog2(PAR_META):0] meta_uncorrectable_err_num;

  popcount #(
    .INPUT_WIDTH ( PAR_DATA*N_CHUNK )
  ) i_popcount_data_single (
    .data_i      ( data_correctable_err_i   ),
    .popcount_o  ( data_correctable_err_num )
  );

  popcount #(
    .INPUT_WIDTH ( PAR_DATA*N_CHUNK )
  ) i_popcount_data_multi (
    .data_i      ( data_uncorrectable_err_i   ),
    .popcount_o  ( data_uncorrectable_err_num )
  );

  popcount #(
    .INPUT_WIDTH ( PAR_META )
  ) i_popcount_meta_single (
    .data_i      ( meta_correctable_err_i   ),
    .popcount_o  ( meta_correctable_err_num )
  );

  popcount #(
    .INPUT_WIDTH ( PAR_META )
  ) i_popcount_meta_multi (
    .data_i      ( meta_uncorrectable_err_i   ),
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

endmodule // hci_ecc_manager
