/*
 * hci_ecc_enc.sv
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
 * ADD DESCRIPTION
 */

`include "hci_helpers.svh"

module hci_ecc_enc
  import hci_package::*;
#(
  parameter int unsigned DW = hci_package::DEFAULT_DW,
  parameter int unsigned CHUNK_SIZE  = 32,
  parameter bit EnableData = 1,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm_target) = '0,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm_initiator) = '0,
  // Dependent parameters, do not override
  parameter int unsigned N_CHUNK = DW / CHUNK_SIZE
)
(
  output logic [N_CHUNK-1:0] r_data_single_err_o,
  output logic [N_CHUNK-1:0] r_data_multi_err_o,
  output logic               r_meta_single_err_o,
  output logic               r_meta_multi_err_o,
  hci_core_intf.target    tcdm_target,
  hci_core_intf.initiator tcdm_initiator
);

  localparam int unsigned BW  = `HCI_SIZE_GET_BW(tcdm_target);
  localparam int unsigned AW  = `HCI_SIZE_GET_AW(tcdm_target);
  localparam int unsigned UW  = `HCI_SIZE_GET_UW(tcdm_target);
  localparam int unsigned EW  = `HCI_SIZE_GET_EW(tcdm_initiator);
  localparam int unsigned EHW = `HCI_SIZE_GET_EHW(tcdm_initiator);

  localparam bit          UseUW   = (UW > 1) ? 1 : 0;

  localparam int unsigned RQMETAW = (UseUW) ? AW + DW/BW + UW + 1 : AW + DW/BW + 1;
  localparam int unsigned RSMETAW = (UseUW) ? UW : 0;

  localparam int unsigned EW_DW = $clog2(CHUNK_SIZE)+2;
  localparam int unsigned EW_RQMETA = $clog2(RQMETAW)+2;
  localparam int unsigned EW_RSMETA = (UseUW) ? $clog2(RSMETAW)+2 : 0;

  logic [N_CHUNK-1:0][EW_DW-1:0]      data_ecc;
  logic [1:0]                         r_meta_err;
  logic [RQMETAW-1:0]                 meta_enc;
  logic [EW_RQMETA-1:0]               meta_ecc;

  // REQUEST PHASE PAYLOAD ENCODING
  // data hsiao encoders
  if (EnableData) begin : gen_data_encoding

    logic [N_CHUNK-1:0][CHUNK_SIZE-1:0] data_enc;

    for(genvar ii=0; ii<N_CHUNK; ii++) begin : data_encoding
      hsiao_ecc_enc #(
        .DataWidth ( CHUNK_SIZE ),
        .ProtWidth ( EW_DW      )
      ) i_hsiao_ecc_data_enc (
        .in  ( tcdm_target.data[ii*CHUNK_SIZE+CHUNK_SIZE-1:ii*CHUNK_SIZE] ),
        .out ( { data_ecc[ii], data_enc[ii] } )
      );
    end
  end else
    assign data_ecc = tcdm_target.ecc;

  // metadata (add/wen/be/user) hsiao encoder
  generate
    if (UseUW) begin : meta_user_enc
      hsiao_ecc_enc #(
        .DataWidth ( RQMETAW ),
        .ProtWidth ( EW_RQMETA )
      ) i_hsiao_ecc_meta_enc (
        .in  ( { tcdm_target.add, tcdm_target.wen, tcdm_target.be, tcdm_target.user } ),
        .out ( { meta_ecc, meta_enc } )
      );
    end
    else begin : meta_no_user_enc
      hsiao_ecc_enc #(
        .DataWidth ( RQMETAW ),
        .ProtWidth ( EW_RQMETA )
      ) i_hsiao_ecc_meta_enc (
        .in  ( { tcdm_target.add, tcdm_target.wen, tcdm_target.be } ),
        .out ( { meta_ecc, meta_enc } )
      );
    end
  endgenerate

  // RESPONSE PHASE PAYLOAD DECODING
  if (EnableData) begin : gen_r_data_decoding

    logic [N_CHUNK-1:0][CHUNK_SIZE-1:0] r_data_dec;
    logic [N_CHUNK-1:0][EW_DW-1:0]      r_data_ecc;
    logic [N_CHUNK-1:0][1:0]            r_data_err;

    assign r_data_ecc = tcdm_initiator.r_ecc[EW_RSMETA+:EW_DW*N_CHUNK];

    // r_data hsiao decoders
    for(genvar ii=0; ii<N_CHUNK; ii++) begin : r_data_decoding
      hsiao_ecc_dec #(
        .DataWidth ( CHUNK_SIZE ),
        .ProtWidth ( EW_DW  )
      ) i_hsiao_ecc_r_data_dec (
        .in         ( { r_data_ecc[ii], tcdm_initiator.r_data[ii*CHUNK_SIZE+CHUNK_SIZE-1:ii*CHUNK_SIZE] } ),
        .out        ( r_data_dec[ii] ),
        .syndrome_o (  ),
        .err_o      ( r_data_err[ii] )
      );

      assign tcdm_target.r_data[ii*CHUNK_SIZE+CHUNK_SIZE-1:ii*CHUNK_SIZE] = r_data_dec[ii];

      // error signals
      assign r_data_single_err_o[ii] = r_data_err[ii][0];
      assign r_data_multi_err_o[ii]  = r_data_err[ii][1];
    end

  end else begin : gen_no_r_data_decoding
    assign data_single_err_o = '0;
    assign data_multi_err_o  = '0;
    assign tcdm_target.r_data  = tcdm_initiator.r_data;
  end

  // metadata (r_user) hsiao decoder
  generate
    if (UseUW) begin : meta_user_dec
      hsiao_ecc_dec #(
        .DataWidth ( RSMETAW ),
        .ProtWidth ( EW_RSMETA )
      ) i_hsiao_ecc_meta_dec (
        .in         ( { tcdm_initiator.r_ecc[EW_RSMETA-1:0], tcdm_initiator.r_user } ),
        .out        ( tcdm_target.r_user ),
        .syndrome_o (  ),
        .err_o      ( r_meta_err )
      );
    end else begin : meta_no_dec
      assign tcdm_target.r_user = '0;
      assign r_meta_err         = '0;
    end
  endgenerate

  assign tcdm_initiator.req     = tcdm_target.req;
  assign tcdm_target.gnt        = tcdm_initiator.gnt;

  assign tcdm_initiator.add     = tcdm_target.add;
  assign tcdm_initiator.wen     = tcdm_target.wen;
  assign tcdm_initiator.data    = tcdm_target.data;
  assign tcdm_initiator.be      = tcdm_target.be;
  assign tcdm_initiator.r_ready = tcdm_target.r_ready;
  assign tcdm_initiator.user    = tcdm_target.user;
  assign tcdm_initiator.id      = tcdm_target.id;

  assign tcdm_target.r_id    = tcdm_initiator.r_id;
  assign tcdm_target.r_opc   = tcdm_initiator.r_opc;
  assign tcdm_target.r_valid = tcdm_initiator.r_valid;

  // ECC signals
  assign tcdm_initiator.ereq     = tcdm_target.ereq;
  assign tcdm_target.egnt        = tcdm_initiator.egnt;
  assign tcdm_target.r_evalid    = tcdm_initiator.r_evalid;
  assign tcdm_initiator.r_eready = tcdm_target.r_eready;
  assign tcdm_initiator.ecc      = { data_ecc, meta_ecc };
  assign tcdm_target.r_ecc       = (!EnableData) ? tcdm_initiator.r_ecc[EW_RSMETA+:EW_DW*N_CHUNK] : '0;

  assign r_meta_single_err_o = r_meta_err[0];
  assign r_meta_multi_err_o  = r_meta_err[1];

  `ifndef SYNTHESIS
  `ifndef VERILATOR
    initial
      ew : assert(EW >= EW_DW*N_CHUNK+EW_RQMETA);
  `endif
  `endif

endmodule // hci_ecc_enc
