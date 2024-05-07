/*
 * hci_ecc_enc.sv
 * Luigi Ghionda <luigi.ghionda@studio.unibo.it>
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
  parameter int unsigned CHUNK_SIZE  = 32
)
(
  hci_core_intf.target    tcdm_target,
  hci_core_intf.initiator tcdm_initiator
);

  localparam int unsigned DW  = `HCI_SIZE_GET_DW(tcdm_target);
  localparam int unsigned BW  = `HCI_SIZE_GET_BW(tcdm_target);
  localparam int unsigned AW  = `HCI_SIZE_GET_AW(tcdm_target);
  localparam int unsigned UW  = `HCI_SIZE_GET_UW(tcdm_target);
  localparam int unsigned EW  = `HCI_SIZE_GET_EW(tcdm_target);
  localparam int unsigned EHW = `HCI_SIZE_GET_EHW(tcdm_target);

  if (!(EW > 0)) $error("EW must be greater than 0");

  localparam int unsigned RQMETAW = AW + DW/BW + UW + 1;
  localparam int unsigned RSMETAW = UW + 1;

  localparam int unsigned N_CHUNK = DW / CHUNK_SIZE;
  localparam int unsigned EW_DW = $clog2(CHUNK_SIZE)+2;
  localparam int unsigned EW_RQMETA = $clog2(RQMETAW)+2;
  localparam int unsigned EW_RSMETA = $clog2(RSMETAW)+2;

  logic [N_CHUNK-1][1:0]              r_data_err;
  logic [1:0]                         r_meta_err;

  logic [N_CHUNK-1:0][CHUNK_SIZE-1:0] data_enc;
  logic [N_CHUNK-1:0][EW_DW-1:0]      data_ecc;
  logic [RQMETAW-1:0]                 meta_enc;
  logic [EW_RQMETA-1:0]               meta_ecc;

  logic [N_CHUNK-1:0][CHUNK_SIZE-1:0] r_data_dec;
  logic [N_CHUNK-1:0][EW_DW-1:0]      r_data_ecc;

  // REQUEST PHASE PAYLOAD ENCODING
  // data hsiao encoders
  generate
    for(genvar ii=0; ii<N_CHUNK; ii++) begin : data_encoding
      hsiao_ecc_enc #(
        .DataWidth ( CHUNK_SIZE ),
        .ProtWidth ( EW_DW      )
      ) i_hsiao_ecc_data_enc (
        .in  ( tcdm_target.data[ii*CHUNK_SIZE+CHUNK_SIZE-1:ii*CHUNK_SIZE] ),
        .out ( { data_ecc[ii], data_enc[ii] } )
      );
    end
  endgenerate

  // metadata (add/wen/be/user) hsiao encoder
  generate
    if (UW > 0) begin : meta_user_enc // need to specificy UW>0 case; ASK
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
  assign r_data_ecc = tcdm_initiator.r_ecc[EW_DW*N_CHUNK+EW_RSMETA-1:EW_RSMETA];

  // r_data hsiao decoders
  generate
    for(genvar ii=0; ii<N_CHUNK; ii++) begin : r_data_decoding
      hsiao_ecc_dec #(
        .DataWidth ( CHUNK_SIZE ),
        .ProtWidth ( EW_DW  )
      ) i_hsiao_ecc_r_data_dec (
        .in         ( { r_data_ecc[ii], tcdm_initiator.r_data[ii*CHUNK_SIZE+CHUNK_SIZE-1:ii*CHUNK_SIZE] } ),
        .out        ( r_data_dec[ii] ),
        .syndrome_o (  ), // is syndrome useless?
        .err_o      ( r_data_err[ii] )
      );
    end
  endgenerate

  // metadata (r_opc/r_user) hsiao decoder
  generate
    if (UW > 0) begin : meta_user_dec // need to specificy UW>0 case; ASK
      hsiao_ecc_dec #(
        .DataWidth ( RSMETAW ),
        .ProtWidth ( EW_RSMETA )
      ) i_hsiao_ecc_meta_dec (
        .in         ( { tcdm_initiator.r_ecc[EW_RSMETA-1:0], tcdm_initiator.r_opc, tcdm_initiator.r_user } ),
        .out        ( { tcdm_target.r_opc, tcdm_target.r_user } ),
        .syndrome_o (  ), // is syndrome useless?
        .err_o      ( r_meta_err )
      );
    end
    else begin : meta_no_user_dec
      hsiao_ecc_dec #(
        .DataWidth ( RSMETAW ),
        .ProtWidth ( EW_RSMETA )
      ) i_hsiao_ecc_meta_dec (
        .in         ( { tcdm_initiator.r_ecc[EW_RSMETA-1:0], tcdm_initiator.r_opc } ),
        .out        ( tcdm_target.r_opc ),
        .syndrome_o (  ), // is syndrome useless?
        .err_o      ( r_meta_err )
      );

      assign tcdm_target.r_user = '0;
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

  for(genvar ii=0; ii<N_CHUNK; ii++) begin
    assign tcdm_target.r_data[ii*CHUNK_SIZE+CHUNK_SIZE-1:ii*CHUNK_SIZE] = r_data_dec[ii];
  end
  assign tcdm_target.r_id    = tcdm_initiator.r_id;
  assign tcdm_target.r_valid = tcdm_initiator.r_valid;

  // ECC signals
  assign tcdm_initiator.ereq     = tcdm_target.ereq;
  assign tcdm_target.egnt        = tcdm_initiator.egnt;
  assign tcdm_target.r_evalid    = tcdm_initiator.r_evalid;
  assign tcdm_initiator.r_eready = tcdm_target.r_eready;
  assign tcdm_initiator.ecc      = { data_ecc, meta_ecc };
  assign tcdm_target.r_ecc       = '0;

endmodule // hci_ecc_enc
