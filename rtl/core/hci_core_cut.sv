// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>
// Luigi Ghionda

`include "hci_helpers.svh"

module hci_core_cut
  import hci_package::*;
#(
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(in) = '0,
  /// Bypass enable, can be individually overridden!
  parameter bit                Bypass       = 1'b0,
  /// Bypass enable for Request side.
  parameter bit                BypassReq    = Bypass,
  /// Bypass enable for Response side.
  parameter bit                BypassRsp    = Bypass
) (
  input  logic     clk_i,
  input  logic     rst_ni,

  hci_core_intf.target    in,
  hci_core_intf.initiator out
);

  localparam int unsigned AW  = `HCI_SIZE_GET_AW(in);
  localparam int unsigned DW  = `HCI_SIZE_GET_DW(in);
  localparam int unsigned BW  = `HCI_SIZE_GET_BW(in);
  localparam int unsigned UW  = `HCI_SIZE_GET_UW(in);
  localparam int unsigned IW  = `HCI_SIZE_GET_IW(in);
  localparam int unsigned EW  = `HCI_SIZE_GET_EW(in);

  localparam int unsigned REQW = AW + 1 + DW + DW/BW + UW + IW + EW;
  localparam int unsigned RSPW = DW + UW + IW + 1 + EW;

  // logic [REQW-1:0] req_payload_in, req_payload_out;

  typedef struct packed {
    logic [AW-1:0]      add;
    logic               wen;
    logic [DW-1:0]      data;
    logic [DW/BW-1:0]   be;
    logic [UW-1:0]      user;
    logic [IW-1:0]      id;
    logic [EW-1:0]      ecc;
  } req_payload_t;

  typedef struct packed {
    logic [DW-1:0]      r_data;
    logic [UW-1:0]      r_user;
    logic [IW-1:0]      r_id;
    logic [EW-1:0]      r_ecc;
  } rsp_payload_t;

  req_payload_t req_payload_in, req_payload_out;

  assign req_payload_in = '{
    add:  in.add,
    wen:  in.wen,
    data: in.data,
    be:   in.be,
    user: in.user,
    id:   in.id,
    ecc:  in.ecc
  };

  // assign req_payload_in = {in.ecc, in.id, in.user, in.be, in.data, in.wen, in.add};


  spill_register #(
    .T      ( req_payload_t ), // create a similar struct to be passed to the spill register
    .Bypass ( BypassReq    )
  ) i_reg_a (
    .clk_i,
    .rst_ni,
    .valid_i ( in.req ),
    .ready_o ( in.gnt ),
    .data_i  ( req_payload_in   ),
    .valid_o ( out.req ),
    .ready_i ( out.gnt ),
    .data_o  ( req_payload_out   )
  );

  always_comb
  begin : out_assign
    out.add  = req_payload_out.add;
    out.wen  = req_payload_out.wen;
    out.data = req_payload_out.data;
    out.be   = req_payload_out.be;
    out.user = req_payload_out.user;
    out.id   = req_payload_out.id;
    out.ecc  = req_payload_out.ecc;
  end

  // always_comb
  // begin : out_assign
  //   out.add = req_payload_out[AW-1:0];
  //   out.wen = req_payload_out[AW];
  //   out.data = req_payload_out[AW+1+DW-1:0];
  //   out.be = req_payload_out[AW+1+DW+DW/BW-1:0];
  //   out.user = req_payload_out[AW+1+DW+DW/BW+UW-1:0];
  //   out.id = req_payload_out[AW+1+DW+DW/BW+UW+ID-1:0];
  //   out.ecc = req_payload_out[AW+1+DW+DW/BW+UW+ID+ECC-1:0];
  // end

  rsp_payload_t rsp_payload_in, rsp_payload_out;

  assign rsp_payload_in = '{
    r_data: out.r_data,
    r_user: out.r_user,
    r_id:   out.r_id,
    r_ecc:  out.r_ecc
  };

  spill_register #(
    .T      ( rsp_payload_t ),
    .Bypass ( BypassRsp    )
  ) i_req_r (
    .clk_i,
    .rst_ni,
    .valid_i ( out.r_valid     ),
    .ready_o ( out.r_ready     ),
    .data_i  ( rsp_payload_in  ),
    .valid_o ( in.r_valid      ),
    .ready_i ( in.r_ready      ),
    .data_o  ( rsp_payload_out )
  );

  always_comb
  begin : in_assign
    in.r_data = rsp_payload_out.r_data;
    in.r_user = rsp_payload_out.r_user;
    in.r_id   = rsp_payload_out.r_id;
    in.r_ecc  = rsp_payload_out.r_ecc;
  end

endmodule
