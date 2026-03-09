/*
 * application_driver.sv
 *
 * Sergio Mazzola <smazzola@iis.ee.ethz.ch>
 *
 * Copyright (C) 2019-2026 ETH Zurich, University of Bologna
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
 * Application driver module
 * Reads stimuli from file and drives transactions on HCI interface
 */

module application_driver #(
  parameter int unsigned MASTER_NUMBER = 1,
  parameter int unsigned DATA_WIDTH = 1,
  parameter int unsigned ADDR_WIDTH = 1,
  parameter int unsigned IW = 1,
  parameter string STIM_FILE = ""
) (
  input logic             clk_i,
  input logic             rst_ni,
  input logic             clear_i, // used to gate the driver or to reset it
  hci_core_intf.initiator hci_if,
  output logic            end_resp_o,
  output int unsigned     n_issued_tr_o,
  output int unsigned     n_issued_rd_tr_o,
  output int unsigned     n_retired_rd_tr_o
);

  int unsigned n_req_issued_q, n_req_issued_d; // total number of issued requests
  int unsigned n_rd_req_issued_q, n_rd_req_issued_d; // total number of issued read requests
  int unsigned n_rd_resp_retired_q, n_rd_resp_retired_d; // total number of retired read responses

  // Transaction queue from file
  typedef struct {
    logic req;
    logic [IW-1:0] id;
    logic wen;
    logic [DATA_WIDTH-1:0] data;
    logic [ADDR_WIDTH-1:0] add;
  } transaction_t;
  transaction_t transactions[$];

  // Fill up the queue by reading the stimuli file until the end
  initial begin
    string file_path;
    int stim;
    int scan_status;

    if (STIM_FILE != "") begin
      file_path = STIM_FILE;
    end else begin
      $fatal("ERROR: Specify STIM_FILE path");
    end
    // Open file
    stim = $fopen(file_path, "r");
    if (stim == 0) begin
      $fatal("ERROR: Could not open stimuli file");
    end
    // Read every line
    while (!$feof(stim)) begin
      transaction_t transaction;
      scan_status = $fscanf(stim, "%b %b %b %b %b\n", transaction.req, transaction.id, transaction.wen, transaction.data, transaction.add);
      if (scan_status != 5) begin
        if (!$feof(stim)) begin
          $fatal(1, "ERROR: malformed stimuli line in %s", file_path);
        end
        break;
      end
      // First-in, first-out queue
      transactions.push_back(transaction);
    end
    $fclose(stim);
  end

  //////////////////
  // Requests FSM //
  //////////////////

  typedef enum logic [2:0] {
    REQ_RESET,
    REQ_IDLE,
    WAIT_GNT,
    REQ_DONE,
    RSP_DONE
  } req_state_t;

  req_state_t req_state_q, req_state_d;
  int unsigned tr_idx_q, tr_idx_d; // transaction ID
  int unsigned last_op_issued_q, last_op_issued_d; // ID of the last issued operation (read or write)

  assign n_issued_tr_o = n_req_issued_q;
  assign n_issued_rd_tr_o = n_rd_req_issued_q;

  // Sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni || clear_i) begin
      req_state_q <= REQ_RESET;
      tr_idx_q <= '0;
      n_req_issued_q <= '0;
      n_rd_req_issued_q <= '0;
      last_op_issued_q <= '0;
    end else begin
      req_state_q <= req_state_d;
      tr_idx_q <= tr_idx_d;
      n_req_issued_q <= n_req_issued_d;
      n_rd_req_issued_q <= n_rd_req_issued_d;
      last_op_issued_q <= last_op_issued_d;
    end
  end

  // Combinational state logic
  always_comb begin
    // Defaults (FSM)
    req_state_d = req_state_q;
    tr_idx_d = tr_idx_q;
    n_req_issued_d = n_req_issued_q;
    n_rd_req_issued_d = n_rd_req_issued_q;
    last_op_issued_d = last_op_issued_q;
    // Defaults (HCI outputs)
    hci_if.id = '0;
    hci_if.add = '0;
    hci_if.data = '0;
    hci_if.req = 1'b0;
    hci_if.wen = 1'b0;
    hci_if.ecc = '0;
    hci_if.ereq = '0;
    hci_if.r_eready = '0;
    hci_if.be = '1;
    hci_if.r_ready = 1'b1;
    hci_if.user = '0;
    // Defaults (outputs)
    end_resp_o = 1'b0;
    // inputs: gnt, r_data, r_valid, r_user, r_id

    case (req_state_q)
      REQ_RESET: begin
        if (!clear_i) begin
          req_state_d = REQ_IDLE;
        end
      end
      REQ_IDLE: begin
        // Check if there are still transactions to issue
        if (tr_idx_q < transactions.size()) begin
          // If so, increase transaction index for next iteration
          tr_idx_d = tr_idx_q + 1;
          // If this transaction is a request
          if (transactions[tr_idx_q].req) begin
            hci_if.req = 1'b1;
            hci_if.id = transactions[tr_idx_q].id;
            hci_if.wen = transactions[tr_idx_q].wen;
            hci_if.data = transactions[tr_idx_q].data;
            hci_if.add = transactions[tr_idx_q].add;
            // Update counters
            n_req_issued_d = n_req_issued_q + 1;
            if (transactions[tr_idx_q].wen) begin
              n_rd_req_issued_d = n_rd_req_issued_q + 1;
            end
            last_op_issued_d = tr_idx_q;
            // If granted already, stay in REQ_IDLE, otherwise go to WAIT_GNT
            if (hci_if.gnt) begin
              req_state_d = REQ_IDLE;
            end else begin
              req_state_d = WAIT_GNT;
            end
          end
        end else begin
          // If no more transactions to issue
          if (n_rd_req_issued_q > n_rd_resp_retired_q) begin
            // If there are still read responses to retire, wait for them before finishing
            req_state_d = REQ_DONE;
          end else begin
            req_state_d = RSP_DONE;
          end
        end
      end
      WAIT_GNT: begin
        hci_if.req = 1'b1;
        hci_if.id = transactions[last_op_issued_q].id;
        hci_if.wen = transactions[last_op_issued_q].wen;
        hci_if.data = transactions[last_op_issued_q].data;
        hci_if.add = transactions[last_op_issued_q].add;
        // Check if there are still transactions to issue
        if (tr_idx_q < transactions.size()) begin
          // Check whether to stall or not transaction fetching, in case this is a idle transaction that can hide mem latency
          if (!transactions[tr_idx_q].req) begin
            tr_idx_d = tr_idx_q + 1;
          end else begin
            tr_idx_d = tr_idx_q;
          end
          // If grant received, go back to REQ_IDLE and pop another transaction, otherwise stay in WAIT_GNT
          if (hci_if.gnt) begin
            req_state_d = REQ_IDLE;
          end else begin
            req_state_d = WAIT_GNT;
          end
        end else begin
          // If there are no more transactions, wait for last grant and then finish
          if (hci_if.gnt) begin
            if (transactions[last_op_issued_q].req && transactions[last_op_issued_q].wen) begin
              // If the last transaction was a read, we need to wait for its response before finishing
              req_state_d = REQ_DONE;
            end else begin
              // If the last transaction was a write, we can finish right away
              req_state_d = RSP_DONE;
            end
          end else begin
            req_state_d = WAIT_GNT;
          end
        end
      end
      REQ_DONE: begin
        if (n_rd_resp_retired_q >= n_rd_req_issued_q) begin
          // All read responses have been retired
          req_state_d = RSP_DONE;
        end else begin
          req_state_d = REQ_DONE;
        end
      end
      RSP_DONE: begin
        end_resp_o = 1'b1;
      end
      default: begin
        req_state_d = REQ_RESET;
      end
    endcase
  end

  ///////////////////////
  // Read response FSM //
  ///////////////////////

  // We only consider read responses as write responses are not mandatory in HCI

  typedef enum logic [1:0] {
    RESP_RESET,
    RESP_IDLE,
    RESP_WAIT_RVALID
  } resp_state_t;

  resp_state_t resp_state_q, resp_state_d;
  int unsigned n_rd_in_flight_q, n_rd_in_flight_d; // number of reads granted but not yet responded

  assign n_retired_rd_tr_o = n_rd_resp_retired_q;

  // Sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni || clear_i) begin
      resp_state_q <= RESP_IDLE;
      n_rd_resp_retired_q <= '0;
      n_rd_in_flight_q <= '0;
    end else begin
      resp_state_q <= resp_state_d;
      n_rd_resp_retired_q <= n_rd_resp_retired_d;
      n_rd_in_flight_q <= n_rd_in_flight_d;
    end
  end

  // Combinational state logic
  always_comb begin
    // Defaults (FSM)
    resp_state_d = resp_state_q;
    n_rd_resp_retired_d = n_rd_resp_retired_q;
    n_rd_in_flight_d = n_rd_in_flight_q;

    case (resp_state_q)
      RESP_RESET: begin
        if (!clear_i) begin
          resp_state_d = RESP_IDLE;
        end
      end
      RESP_IDLE: begin
        // If a read request is granted, increment in-flight counter and go to RESP_WAIT_RVALID
        if (hci_if.req && hci_if.wen && hci_if.gnt) begin
          n_rd_in_flight_d = n_rd_in_flight_q + 1;
          resp_state_d = RESP_WAIT_RVALID;
        end
      end
      RESP_WAIT_RVALID: begin
        // Track newly granted reads while waiting
        if (hci_if.req && hci_if.wen && hci_if.gnt) begin
          n_rd_in_flight_d = n_rd_in_flight_q + 1;
        end
        // When read response handshake happens, retire one response
        if (hci_if.r_valid && hci_if.r_ready) begin
          n_rd_resp_retired_d = n_rd_resp_retired_q + 1;
          // Adjust in-flight: account for simultaneous grant (already added above)
          if (hci_if.req && hci_if.wen && hci_if.gnt) begin
            // net in-flight = in_flight + 1 (new grant) - 1 (retired) = in_flight
            n_rd_in_flight_d = n_rd_in_flight_q; // undo the +1 above, net unchanged
          end else begin
            n_rd_in_flight_d = n_rd_in_flight_q - 1;
          end
          // If no more in-flight reads (after this retirement), go back to RESP_IDLE
          if (n_rd_in_flight_q == 1 && !(hci_if.req && hci_if.wen && hci_if.gnt)) begin
            resp_state_d = RESP_IDLE;
          end
        end
      end
      default: begin
        resp_state_d = RESP_RESET;
      end
    endcase
  end

endmodule
