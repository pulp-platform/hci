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
 * Reads stimuli from file and drives transactions on HCI interface.
 *
 * Stimulus file format (one line per cycle):
 *   req(1b) id(IWb) wen(1b) data(Nb) add(Ab)   -- active transaction
 *   PAUSE                                        -- fence synchronization point
 *
 * When a PAUSE token is encountered the driver drains all in-flight reads
 * (waits in DRAIN_FOR_PAUSE), then enters PAUSED and holds fence_reached_o=1
 * until resume_i is asserted. This allows multi-phase execution on a single
 * driver without resetting counters between phases.
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
  input logic             resume_i,       // asserted by tb_hci when fence dependencies are met
  hci_core_intf.initiator hci_if,
  output logic            fence_reached_o, // held HIGH while driver is paused at a fence
  output logic            end_resp_o,      // held HIGH after all transactions and responses done
  output int unsigned     n_issued_tr_o,
  output int unsigned     n_issued_rd_tr_o,
  output int unsigned     n_retired_rd_tr_o
);

  int unsigned n_req_issued_q, n_req_issued_d;
  int unsigned n_rd_req_issued_q, n_rd_req_issued_d;
  int unsigned n_rd_resp_retired_q, n_rd_resp_retired_d;

  // Transaction queue from file. is_pause=1 entries are fence tokens, not real transactions.
  typedef struct {
    logic                  is_pause;
    logic                  req;
    logic [IW-1:0]         id;
    logic                  wen;
    logic [DATA_WIDTH-1:0] data;
    logic [ADDR_WIDTH-1:0] add;
  } transaction_t;
  transaction_t transactions[$];

  // Fill up the queue by reading the stimuli file until the end.
  // PAUSE lines are read as fence tokens with is_pause=1.
  initial begin
    string file_path;
    int    stim;
    string line;

    if (STIM_FILE != "") begin
      file_path = STIM_FILE;
    end else begin
      $fatal("ERROR: Specify STIM_FILE path");
    end
    stim = $fopen(file_path, "r");
    if (stim == 0) begin
      $fatal("ERROR: Could not open stimuli file: %s", file_path);
    end
    while (!$feof(stim)) begin
      transaction_t t;
      int scan_status;
      void'($fgets(line, stim));
      // Strip trailing newline/CR for comparison
      if (line.len() > 0 && (line[line.len()-1] == "\n" || line[line.len()-1] == "\r"))
        line = line.substr(0, line.len()-2);
      if (line.len() > 1 && line[line.len()-1] == "\r")
        line = line.substr(0, line.len()-2);
      if (line == "PAUSE") begin
        t.is_pause = 1'b1;
        t.req      = 1'b0;
        t.id       = '0;
        t.wen      = 1'b0;
        t.data     = '0;
        t.add      = '0;
        transactions.push_back(t);
      end else if (line.len() > 0) begin
        t.is_pause = 1'b0;
        scan_status = $sscanf(line, "%b %b %b %b %b",
            t.req, t.id, t.wen, t.data, t.add);
        if (scan_status != 5) begin
          if (!$feof(stim)) begin
            $fatal(1, "ERROR: malformed stimuli line in %s: '%s'", file_path, line);
          end
          break;
        end
        transactions.push_back(t);
      end
    end
    $fclose(stim);
  end

  //////////////////
  // Requests FSM //
  //////////////////

  typedef enum logic [2:0] {
    REQ_IDLE,
    WAIT_GNT,
    REQ_DONE,
    DRAIN_FOR_PAUSE, // drain in-flight reads before asserting fence_reached_o
    PAUSED,          // fence synchronization: hold fence_reached_o until resume_i
    RSP_DONE
  } req_state_t;

  req_state_t  req_state_q, req_state_d;
  int unsigned tr_idx_q, tr_idx_d;
  int unsigned last_op_issued_q, last_op_issued_d;

  assign n_issued_tr_o    = n_req_issued_q;
  assign n_issued_rd_tr_o = n_rd_req_issued_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      req_state_q        <= REQ_IDLE;
      tr_idx_q           <= '0;
      n_req_issued_q     <= '0;
      n_rd_req_issued_q  <= '0;
      last_op_issued_q   <= '0;
    end else begin
      req_state_q        <= req_state_d;
      tr_idx_q           <= tr_idx_d;
      n_req_issued_q     <= n_req_issued_d;
      n_rd_req_issued_q  <= n_rd_req_issued_d;
      last_op_issued_q   <= last_op_issued_d;
    end
  end

  always_comb begin
    // FSM defaults
    req_state_d      = req_state_q;
    tr_idx_d         = tr_idx_q;
    n_req_issued_d   = n_req_issued_q;
    n_rd_req_issued_d = n_rd_req_issued_q;
    last_op_issued_d = last_op_issued_q;
    // HCI output defaults
    hci_if.id       = '0;
    hci_if.add      = '0;
    hci_if.data     = '0;
    hci_if.req      = 1'b0;
    hci_if.wen      = 1'b0;
    hci_if.ecc      = '0;
    hci_if.ereq     = '0;
    hci_if.r_eready = '0;
    hci_if.be       = '1;
    hci_if.r_ready  = 1'b1;
    hci_if.user     = '0;
    // Output defaults
    fence_reached_o = 1'b0;
    end_resp_o      = 1'b0;

    case (req_state_q)
      REQ_IDLE: begin
        if (tr_idx_q < transactions.size()) begin
          if (transactions[tr_idx_q].is_pause) begin
            // Consume the PAUSE token and drain any in-flight reads before pausing
            tr_idx_d = tr_idx_q + 1;
            if (n_rd_req_issued_q > n_rd_resp_retired_q) begin
              req_state_d = DRAIN_FOR_PAUSE;
            end else begin
              req_state_d = PAUSED;
            end
          end else begin
            tr_idx_d = tr_idx_q + 1;
            if (transactions[tr_idx_q].req) begin
              hci_if.req  = 1'b1;
              hci_if.id   = transactions[tr_idx_q].id;
              hci_if.wen  = transactions[tr_idx_q].wen;
              hci_if.data = transactions[tr_idx_q].data;
              hci_if.add  = transactions[tr_idx_q].add;
              n_req_issued_d = n_req_issued_q + 1;
              if (transactions[tr_idx_q].wen) begin
                n_rd_req_issued_d = n_rd_req_issued_q + 1;
              end
              last_op_issued_d = tr_idx_q;
              req_state_d = hci_if.gnt ? REQ_IDLE : WAIT_GNT;
            end
          end
        end else begin
          // No more transactions
          if (n_rd_req_issued_q > n_rd_resp_retired_q) begin
            req_state_d = REQ_DONE;
          end else begin
            req_state_d = RSP_DONE;
          end
        end
      end

      WAIT_GNT: begin
        hci_if.req  = 1'b1;
        hci_if.id   = transactions[last_op_issued_q].id;
        hci_if.wen  = transactions[last_op_issued_q].wen;
        hci_if.data = transactions[last_op_issued_q].data;
        hci_if.add  = transactions[last_op_issued_q].add;
        if (tr_idx_q < transactions.size()) begin
          // Advance over any idle (req=0, not-pause) entries to hide memory latency
          if (!transactions[tr_idx_q].req && !transactions[tr_idx_q].is_pause) begin
            tr_idx_d = tr_idx_q + 1;
          end
          req_state_d = hci_if.gnt ? REQ_IDLE : WAIT_GNT;
        end else begin
          if (hci_if.gnt) begin
            if (transactions[last_op_issued_q].req && transactions[last_op_issued_q].wen) begin
              req_state_d = REQ_DONE;
            end else begin
              req_state_d = RSP_DONE;
            end
          end
        end
      end

      REQ_DONE: begin
        if (n_rd_resp_retired_q >= n_rd_req_issued_q) begin
          req_state_d = RSP_DONE;
        end
      end

      DRAIN_FOR_PAUSE: begin
        // Wait for all in-flight reads to retire before asserting the fence
        if (n_rd_resp_retired_q >= n_rd_req_issued_q) begin
          req_state_d = PAUSED;
        end
      end

      PAUSED: begin
        // Hold fence_reached_o HIGH until tb_hci asserts resume_i.
        // If the next token is also a PAUSE (e.g. trailing free-pass followed by
        // a blocking synthetic idle), consume it immediately and stay in PAUSED
        // to avoid a spurious one-cycle REQ_IDLE bounce between consecutive fences.
        fence_reached_o = 1'b1;
        if (resume_i) begin
          if (tr_idx_q < transactions.size() && transactions[tr_idx_q].is_pause) begin
            tr_idx_d    = tr_idx_q + 1;
            req_state_d = PAUSED;
          end else begin
            req_state_d = REQ_IDLE;
          end
        end
      end

      RSP_DONE: begin
        end_resp_o = 1'b1;
      end

      default: begin
        req_state_d = REQ_IDLE;
      end
    endcase
  end

  ///////////////////////
  // Read response FSM //
  ///////////////////////

  typedef enum logic [1:0] {
    RESP_IDLE,
    RESP_WAIT_RVALID
  } resp_state_t;

  resp_state_t resp_state_q, resp_state_d;
  int unsigned n_rd_in_flight_q, n_rd_in_flight_d;

  assign n_retired_rd_tr_o = n_rd_resp_retired_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      resp_state_q        <= RESP_IDLE;
      n_rd_resp_retired_q <= '0;
      n_rd_in_flight_q    <= '0;
    end else begin
      resp_state_q        <= resp_state_d;
      n_rd_resp_retired_q <= n_rd_resp_retired_d;
      n_rd_in_flight_q    <= n_rd_in_flight_d;
    end
  end

  always_comb begin
    resp_state_d        = resp_state_q;
    n_rd_resp_retired_d = n_rd_resp_retired_q;
    n_rd_in_flight_d    = n_rd_in_flight_q;

    case (resp_state_q)
      RESP_IDLE: begin
        if (hci_if.req && hci_if.wen && hci_if.gnt) begin
          n_rd_in_flight_d = n_rd_in_flight_q + 1;
          resp_state_d     = RESP_WAIT_RVALID;
        end
      end

      RESP_WAIT_RVALID: begin
        if (hci_if.req && hci_if.wen && hci_if.gnt) begin
          n_rd_in_flight_d = n_rd_in_flight_q + 1;
        end
        if (hci_if.r_valid && hci_if.r_ready) begin
          n_rd_resp_retired_d = n_rd_resp_retired_q + 1;
          if (hci_if.req && hci_if.wen && hci_if.gnt) begin
            n_rd_in_flight_d = n_rd_in_flight_q; // +1 grant -1 retire = net 0
          end else begin
            n_rd_in_flight_d = n_rd_in_flight_q - 1;
          end
          if (n_rd_in_flight_q == 1 && !(hci_if.req && hci_if.wen && hci_if.gnt)) begin
            resp_state_d = RESP_IDLE;
          end
        end
      end

      default: begin
        resp_state_d = RESP_IDLE;
      end
    endcase
  end

endmodule
