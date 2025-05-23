/*
 * hci_ecc_dec.sv
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

 /**
 * The **hci_ecc_dec** module handles ECC decoding and encoding of the HCI-Core interface payloads.
 * It decodes the **request phase** payload, recovering both `data` and metadata (`add`, `wen`,
 * `be`, and optionally `user` fields) from the the ECC-protected request.
 * It encodes the **response phase** payload, adding ECC protection to the `r_data` and `r_user` fields.
 *
 * The **request phase** decoding covers:
 * - If `ENABLE_DATA` is set, ECC correction on the `data` field split into multiple chunks.
 * - Always performs ECC correction on the request metadata.
 *
 * The **response phase** encoding covers:
 * - ECC generation for the `r_data` field, chunked in the same manner as `data`.
 * - ECC generation for the `r_user` field, if used.
 *
 * The ECC encoding scheme follows a Hsiao code, providing single error correction and double
 * error detection (SEC-DED). See https://github.com/pulp-platform/redundancy_cells).
 * Errors are separately flagged for data and metadata, distinguishing single-bit and multi-bit corrections.
 *
 * This module is the complementary counterpart to `hci_ecc_enc`, which instead applies ECC encoding
 * during request and decoding during response.
 *
 * .. tabularcolumns:: |J|J|
 * .. _hci_ecc_dec_request_encoding:
 * .. table:: **hci_ecc_dec** Request Phase ECC layout (tcdm_target.ecc).
 *
 *   +-------------------------------+--------------------------+
 *   | **data_ecc**                  | **meta_ecc**             |
 *   | [EW-1 : EW_RQMETA]            | [EW_RQMETA-1 : 0]        |
 *   +-------------------------------+--------------------------+
 *
 * .. tabularcolumns:: |J|J|J|
 * .. _hci_ecc_dec_response_encoding:
 * .. table:: **hci_ecc_dec** Response Phase ECC layout (tcdm_target.r_ecc).
 *
 *   +----------------------------------+-----------------------------------------+-------------------+
 *   | **Zero padding**                 | **r_data_ecc**                          | **r_meta_ecc**    |
 *   | [EW-1 : EW_RQMETA+EW_DW*N_CHUNK] | [EW_RQMETA+EW_DW*N_CHUNK-1 : EW_RQMETA] | [EW_RQMETA-1 : 0] |
 *   +----------------------------------+-----------------------------------------+-------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_ecc_dec_params:
 * .. table:: **hci_ecc_dec** design-time parameters.
 *
 *   +----------------------------+-------------+------------------------------------------------------------------+
 *   | **Name**                   | **Default** | **Description**                                                  |
 *   +----------------------------+-------------+------------------------------------------------------------------+
 *   | *CHUNK_SIZE*               | 32          | Width in bits of each chunk of data to protect individually.     |
 *   +----------------------------+-------------+------------------------------------------------------------------+
 *   | *ENABLE_DATA*              | 1           | If set to 1, performs data field's decoding as well as metadata. |
 *   +----------------------------+-------------+------------------------------------------------------------------+
 *
 */

`include "hci_helpers.svh"

module hci_ecc_dec
  import hci_package::*;
#(
  parameter int unsigned CHUNK_SIZE  = 32,
  parameter bit ENABLE_DATA = 1,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm_target) = '0,
  // Dependent parameters, do not override
  parameter int unsigned DW  = `HCI_SIZE_GET_DW(tcdm_target),
  parameter int unsigned N_CHUNK = DW / CHUNK_SIZE
)
(
  output logic [N_CHUNK-1:0] data_single_err_o,
  output logic [N_CHUNK-1:0] data_multi_err_o,
  output logic               meta_single_err_o,
  output logic               meta_multi_err_o,
  hci_core_intf.target       tcdm_target,
  hci_core_intf.initiator    tcdm_initiator
);

  localparam int unsigned BW  = `HCI_SIZE_GET_BW(tcdm_target);
  localparam int unsigned AW  = `HCI_SIZE_GET_AW(tcdm_target);
  localparam int unsigned UW  = `HCI_SIZE_GET_UW(tcdm_target);
  localparam int unsigned EW  = `HCI_SIZE_GET_EW(tcdm_target);

  localparam bit          USE_UW   = (UW > 1) ? 1 : 0;

  localparam int unsigned RQMETAW = (USE_UW) ? AW + DW/BW + UW + 1 : AW + DW/BW + 1;
  localparam int unsigned RSMETAW = (USE_UW) ? UW : 0;

  localparam int unsigned EW_DW = $clog2(CHUNK_SIZE)+2;
  localparam int unsigned EW_RQMETA = $clog2(RQMETAW)+2;
  localparam int unsigned EW_RSMETA = (USE_UW) ? $clog2(RSMETAW)+2 : 0;
  localparam int unsigned ZEROBITS  = EW_RQMETA - EW_RSMETA;

  logic [N_CHUNK-1:0][EW_DW-1:0]      r_data_ecc;
  logic [1:0]                         meta_err;
  logic [RSMETAW-1:0]                 r_meta_enc;
  logic [EW_RSMETA-1:0]               r_meta_ecc;

  // REQUEST PHASE PAYLOAD DECODING

  // data hsiao decoders
  if (ENABLE_DATA) begin : gen_data_decoding

    logic [N_CHUNK-1:0][CHUNK_SIZE-1:0] data_dec;
    logic [N_CHUNK-1:0][EW_DW-1:0]      data_ecc;
    logic [N_CHUNK-1:0][1:0]            data_err;
    logic [N_CHUNK-1:0]                 data_single_err;
    logic [N_CHUNK-1:0]                 data_multi_err;

    assign data_ecc = tcdm_target.ecc[EW-1:EW_RQMETA];

    for(genvar ii=0; ii<N_CHUNK; ii++) begin : data_decoding
      hsiao_ecc_dec #(
        .DataWidth ( CHUNK_SIZE ),
        .ProtWidth ( EW_DW      )
      ) i_hsiao_ecc_data_dec (
        .in         ( { data_ecc[ii], tcdm_target.data[ii*CHUNK_SIZE+CHUNK_SIZE-1:ii*CHUNK_SIZE] } ),
        .out        ( data_dec[ii] ),
        .syndrome_o (  ),
        .err_o      ( data_err[ii] )
      );

      assign tcdm_initiator.data[ii*CHUNK_SIZE+CHUNK_SIZE-1:ii*CHUNK_SIZE] = data_dec[ii];

      // error signals
      assign data_single_err_o[ii] = data_err[ii][0];
      assign data_multi_err_o[ii]  = data_err[ii][1];
    end

  end else begin : gen_no_data_decoding
    assign data_single_err_o = '0;
    assign data_multi_err_o  = '0;
    assign tcdm_initiator.data  = tcdm_target.data;
  end

  // metadata (add/wen/be/user) hsiao decoder
  generate
    if (USE_UW) begin : meta_user_dec
      hsiao_ecc_dec #(
        .DataWidth ( RQMETAW   ),
        .ProtWidth ( EW_RQMETA )
      ) i_hsiao_ecc_meta_dec (
        .in         ( { tcdm_target.ecc[EW_RQMETA-1:0], tcdm_target.add, tcdm_target.wen, tcdm_target.be, tcdm_target.user } ),
        .out        ( {tcdm_initiator.add, tcdm_initiator.wen, tcdm_initiator.be, tcdm_initiator.user } ),
        .syndrome_o (  ),
        .err_o      ( meta_err )
      );
    end
    else begin : meta_no_user_dec
      hsiao_ecc_dec #(
        .DataWidth ( RQMETAW   ),
        .ProtWidth ( EW_RQMETA )
      ) i_hsiao_ecc_meta_dec (
        .in         ( { tcdm_target.ecc[EW_RQMETA-1:0], tcdm_target.add, tcdm_target.wen, tcdm_target.be } ),
        .out        ( { tcdm_initiator.add, tcdm_initiator.wen, tcdm_initiator.be } ),
        .syndrome_o (  ),
        .err_o      ( meta_err )
      );

      assign tcdm_initiator.user = '0;
    end
  endgenerate

  // RESPONSE PHASE PAYLOAD ENCODING
  // r_data hsiao encoders
  if (ENABLE_DATA) begin : gen_r_data_encoding

    logic [N_CHUNK-1:0][CHUNK_SIZE-1:0] r_data_enc;

    for(genvar ii=0; ii<N_CHUNK; ii++) begin : r_data_encoding
      hsiao_ecc_enc #(
        .DataWidth ( CHUNK_SIZE ),
        .ProtWidth ( EW_DW      )
      ) i_hsiao_ecc_r_data_enc (
        .in  ( tcdm_initiator.r_data[ii*CHUNK_SIZE+CHUNK_SIZE-1:ii*CHUNK_SIZE] ),
        .out ( { r_data_ecc[ii], r_data_enc[ii] } )
      );
    end
  end else
    assign r_data_ecc = tcdm_initiator.r_ecc;

  // metadata (r_user) hsiao encoder
  generate
    if (USE_UW) begin : meta_user_enc
      hsiao_ecc_enc #(
        .DataWidth ( RSMETAW ),
        .ProtWidth ( EW_RSMETA )
      ) i_hsiao_ecc_meta_enc (
        .in  ( tcdm_initiator.r_user ),
        .out ( { r_meta_ecc, r_meta_enc } )
      );
    end
    else begin : meta_no_user_enc
      assign r_meta_ecc = '0;
      assign r_meta_enc = '0;
    end
  endgenerate

  assign tcdm_initiator.req     = tcdm_target.req;
  assign tcdm_target.gnt        = tcdm_initiator.gnt;

  assign tcdm_initiator.id      = tcdm_target.id;
  assign tcdm_initiator.r_ready = tcdm_target.r_ready;

  assign tcdm_target.r_data  = tcdm_initiator.r_data;
  assign tcdm_target.r_valid = tcdm_initiator.r_valid;
  assign tcdm_target.r_user  = tcdm_initiator.r_user;
  assign tcdm_target.r_id    = tcdm_initiator.r_id;
  assign tcdm_target.r_opc   = tcdm_initiator.r_opc;

  // ECC signals
  assign tcdm_initiator.ereq     = tcdm_target.ereq;
  assign tcdm_target.egnt        = tcdm_initiator.egnt;
  assign tcdm_target.r_evalid    = tcdm_initiator.r_evalid;
  assign tcdm_initiator.r_eready = tcdm_target.r_eready;
  assign tcdm_initiator.ecc      = (!ENABLE_DATA) ? tcdm_target.ecc[EW_RQMETA+:EW_DW*N_CHUNK] : '0;
  assign tcdm_target.r_ecc       = (USE_UW) ? { {ZEROBITS{1'b0}}, r_data_ecc, r_meta_ecc }
                                            : { {ZEROBITS{1'b0}}, r_data_ecc };

  assign meta_single_err_o = meta_err[0];
  assign meta_multi_err_o  = meta_err[1];

  `ifndef SYNTHESIS
  `ifndef VERILATOR
  `ifndef VCS
    initial
      ew : assert(EW >= EW_DW*N_CHUNK+EW_RQMETA);
  `endif
  `endif
  `endif

endmodule // hci_ecc_dec
