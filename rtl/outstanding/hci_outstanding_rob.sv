// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author: Marco Bertuletti, ETH Zurich
//
// This generic module provides an interface through which responses can
// be read in order, despite being written out of order. The responses
// must be indexed with an ID that identifies it within the ROB.

`include "hci_helpers.svh"

module hci_outstanding_rob
  import hwpe_stream_package::*;
  import hci_package::*;
  import cf_math_pkg::idx_width;
#(
  parameter int unsigned ROB_NW = 0,
  parameter bit FallThrough     = 1'b0,
  // Dependant parameters. Do not change!
  parameter int unsigned ROB_IW = idx_width(ROB_NW),
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(out) = '0
) (
  input  logic  clk_i,
  input  logic  rst_ni,

  hci_outstanding_intf.target    in,
  hci_outstanding_intf.initiator out
);

  localparam int unsigned DW  = `HCI_SIZE_GET_DW(out);
  localparam int unsigned BW  = `HCI_SIZE_GET_BW(out);
  localparam int unsigned AW  = `HCI_SIZE_GET_AW(out);
  localparam int unsigned UW  = `HCI_SIZE_GET_UW(out);
  localparam int unsigned IW  = `HCI_SIZE_GET_IW(out);

  // Pointers to memory queue and total words counter
  logic [ROB_IW-1:0] read_pointer_p, read_pointer_q;
  logic [ROB_IW-1:0] write_pointer_p, write_pointer_q, resp_write_id;
  logic [ROB_IW-1:0] status_cnt_p, status_cnt_q;
  // Status flags
  logic full, empty;
  // Buffer commands
  logic push, pop, request_id;

  // Memory queue
  logic [ROB_NW-1:0][IW-1:0] mem_req_id_p, mem_req_id_q;
  logic [ROB_NW-1:0][DW-1:0] mem_resp_data_p, mem_resp_data_q;
  logic [ROB_NW-1:0] mem_resp_opc_p, mem_resp_opc_q;
  logic [ROB_NW-1:0] mem_resp_valid_p, mem_resp_valid_q;

  // HCI Port Left assignment
  assign out.req_add     = in.req_add;
  assign out.req_wen     = in.req_wen;
  assign out.req_be      = in.req_be;
  assign out.req_data    = in.req_data;
  // Assign unique ROB ID to the user field
  assign out.req_user    = write_pointer_q;
  assign out.req_id      = in.req_id;
  assign out.req_valid   = !full & in.req_valid;
  assign in.req_ready    = !full & out.req_ready;
  // HCI Port Right assignment
  assign in.resp_data    = mem_resp_data_q[read_pointer_q];
  assign in.resp_opc     = mem_resp_opc_q[read_pointer_q];
  assign in.resp_user    = '0;
  // ROB ID of the incoming response
  assign in.resp_id      = mem_req_id_q[read_pointer_q];
  assign in.resp_valid   = mem_resp_valid_q[read_pointer_q];
  assign out.resp_ready  = !empty;

  // Assign status flags
  assign full    = (status_cnt_q == ROB_NW-1);
  assign empty   = (status_cnt_q == 'd0);
  // Assign buffer commands
  assign request_id = in.req_valid & in.req_ready;
  assign pop 		= mem_resp_valid_q[read_pointer_q] & in.resp_ready;
  assign push 		= out.resp_valid & out.resp_ready;

  // Read and Write logic
  always_comb begin: read_write_comb

    // Maintain state
    read_pointer_p   = read_pointer_q;
    write_pointer_p  = write_pointer_q;
    status_cnt_p     = status_cnt_q;
    // Maintain response queue & initiator_id queue
    mem_req_id_p     = mem_req_id_q;
    mem_resp_data_p  = mem_resp_data_q;
    mem_resp_opc_p   = mem_resp_opc_q;
    mem_resp_valid_p = mem_resp_valid_q;

    // Request an ID.
    if (request_id) begin
      // Store in the initiator_id queue
      mem_req_id_p[write_pointer_q] = in.req_id;
      // Increment the write pointer
      if (write_pointer_q == ROB_NW-1)
        write_pointer_p = 0;
      else
        write_pointer_p = write_pointer_q + 1;
      // Increment the overall counter
      status_cnt_p = status_cnt_q + 1;
    end

    // Push data
    if (push) begin
      resp_write_id = out.resp_user;
      mem_resp_data_p  [resp_write_id] = out.resp_data;
      mem_resp_opc_p   [resp_write_id] = out.resp_opc;
      mem_resp_valid_p [resp_write_id] = out.resp_valid;
    end

    // Pop data
    if (pop) begin
      // Word was consumed
      mem_req_id_p[read_pointer_q] = 1'b0;
      mem_resp_valid_p[read_pointer_q] = 1'b0;
      // Increment the read pointer
      if (read_pointer_q == ROB_NW-1)
        read_pointer_p = '0;
      else
        read_pointer_p = read_pointer_q + 1;
      // Decrement the overall counter
      status_cnt_p = status_cnt_q - 1;
    end

    // Keep the overall counter stable if we request new ROB ID and pop at the same time
    if (request_id && pop) begin
      status_cnt_p = status_cnt_q;
    end
  end: read_write_comb

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      read_pointer_q  <= '0;
      write_pointer_q <= '0;
      status_cnt_q    <= '0;
      // Memory queues
	    mem_req_id_q     <= '0;
	    mem_resp_data_q  <= '0;
	    mem_resp_opc_q   <= '0;
	    mem_resp_valid_q <= '0;
    end else begin
      read_pointer_q  <= read_pointer_p;
      write_pointer_q <= write_pointer_p;
      status_cnt_q    <= status_cnt_p;
      // Memory queues
	  mem_req_id_q     <= mem_req_id_p;
	  mem_resp_data_q  <= mem_resp_data_p;
	  mem_resp_opc_q   <= mem_resp_opc_p;
	  mem_resp_valid_q <= mem_resp_valid_p;
    end
  end

  /****************
   *  Assertions  *
   ****************/

  if (ROB_NW == 0)
    $error("ROB_NW cannot be 0.");

  if (UW < ROB_IW)
  	$error("UW must contain the ROB ID. UW = %0d, ROB_IW = %0d", UW, ROB_IW);

endmodule: hci_outstanding_rob
