/*
 * hci_outstanding_rob.sv
 * Marco Bertuletti <mbertuletti@iis.ee.ethz.ch>
 *
 * Copyright (C) 2017-2023 ETH Zurich, University of Bologna
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
 * The **HCI-Outstanding reorder buffer** issues requests with up to ROB_NW
 * unique user-IDs. The responses can be retired out-of-order, by comparing
 * the incoming response user-ID with the issued IDs. As the user-ID is
 * implemented as user signal, any module coming after (i.e., nearer to memory
 * side) with respect to this block must respect user signals - specifically
 * it must return them identical in the response.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_outstanding_rob_params:
 * .. table:: **hci_outstanding_mux** design-time parameters.
 *
 *   +------------+-------------+-----------------------------------------------+
 *   | **Name**   | **Default** | **Description**                               |
 *   +------------+-------------+-----------------------------------------------+
 *   | *ROB_NW*   | 8           | Number of supported outstanding transactions. |
 *   +------------+-------------+-----------------------------------------------+
 *
 */

`include "hci_helpers.svh"

module hci_outstanding_rob
  import hwpe_stream_package::*;
  import hci_package::*;
  import cf_math_pkg::idx_width;
#(
  parameter int unsigned ROB_NW = 8,
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
  assign full  = (status_cnt_q == ROB_NW-1);
  assign empty = (status_cnt_q == 'd0);

  // Assign buffer commands
  assign request_id = in.req_valid & in.req_ready;
  assign pop 		    = mem_resp_valid_q[read_pointer_q] & in.resp_ready;
  assign push 		  = out.resp_valid & out.resp_ready;

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
      if (write_pointer_q == ROB_NW-1) begin
        write_pointer_p = 0;
      end
      else begin
        write_pointer_p = write_pointer_q + 1;
      end

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
      if (read_pointer_q == ROB_NW-1) begin
        read_pointer_p = '0;
      end
      else begin
        read_pointer_p = read_pointer_q + 1;
      end

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
    end
    else begin
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

`ifndef SYNTHESIS
`ifndef VERILATOR
`ifndef VCS

  if (ROB_NW == 0)
    $error("ROB_NW cannot be 0.");

  // Interface size asserts
  initial
    dw :  assert(in.DW  == out.DW);
  initial
    bw :  assert(in.BW  == out.BW);
  initial
    aw :  assert(in.AW  == out.AW);
  initial
    uw :  assert(in.UW  == out.UW);
  initial
    iw_out :  assert(out.UW  >= $clog2(ROB_NW));

  `HCI_OUTSTANDING_SIZE_CHECK_ASSERTS(out);

`endif
`endif
`endif;

endmodule: hci_outstanding_rob
