/*
 * hci_core_source_v2.sv
 * Francesco Conti <f.conti@unibo.it>
 * Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 * Diego Gorfini <diego.gorfini@studio.unibo.it>
 *
 * Copyright (C) 2014-2026 ETH Zurich, University of Bologna
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
 * The **hci_core_source_v2** module acts as a job-queued wrapper around the
 * **hci_core_source** module. It extends the functionality with a queue of
 * streamer jobs, while preserving its original behavior; please refer to
 * **hci_core_source** for detailed functional information on the underlying
 * streamer and on all parameters not listed below.
 *
 * Whereas **hci_core_source** accepts one job at a time through a
 * `req_start` / `ready_start` pair, the job queue lets jobs be enqueued through
 * a `valid` / `ready` handshake (`hci_streamer_v2_ctrl_t`) well before the
 * streamer is able to serve them, so that a queued job can be started as soon
 * as the previous one is over. The queue carries a full
 * `ctrl_addressgen_v4_t`; a job is popped only once the underlying streamer
 * reports it done, so the running job's configuration stays stable for its
 * entire duration.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_core_source_v2_params:
 * .. table:: **hci_core_source_v2** additional design-time parameters.
 *
 *   +------------------------+-------------+------------------------------------------------------------------------------------------------------------+
 *   | **Name**               | **Default** | **Description**                                                                                            |
 *   +------------------------+-------------+------------------------------------------------------------------------------------------------------------+
 *   | *JOB_FIFO_DEPTH*       | 2           | Depth of the streamer job queue.                                                                           |
 *   +------------------------+-------------+------------------------------------------------------------------------------------------------------------+
 *   | *JOB_FIFO_PASSTHROUGH* | 1           | If set to 1 (default), the streamer job queue is passthrough, otherwise it's a regular path-cutting FIFO.   |
 *   +------------------------+-------------+------------------------------------------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_core_source_v2_ctrl:
 * .. table:: **hci_core_source_v2** input control signals.
 *
 *   +-------------------+------------------------+-----------------------------------------------------------------------------+
 *   | **Name**          | **Type**               | **Description**                                                             |
 *   +-------------------+------------------------+-----------------------------------------------------------------------------+
 *   | *valid*           | `logic`                | When 1, the job described by `addressgen_ctrl` is enqueued if `ready` is 1.  |
 *   +-------------------+------------------------+-----------------------------------------------------------------------------+
 *   | *addressgen_ctrl* | `ctrl_addressgen_v4_t` | Configuration of the address generator (see **hwpe_stream_addressgen_v4**). |
 *   +-------------------+------------------------+-----------------------------------------------------------------------------+
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_core_source_v2_flags:
 * .. table:: **hci_core_source_v2** output flags.
 *
 *   +----------------------+-------------------------+-----------------------------------------------------------------------------------------------+
 *   | **Name**             | **Type**                | **Description**                                                                               |
 *   +----------------------+-------------------------+-----------------------------------------------------------------------------------------------+
 *   | *ready*              | `logic`                 | 1 when the job queue can accept a new job.                                                    |
 *   +----------------------+-------------------------+-----------------------------------------------------------------------------------------------+
 *   | *done*               | `logic`                 | 1 for one cycle when the streamer ends a job.                                                 |
 *   +----------------------+-------------------------+-----------------------------------------------------------------------------------------------+
 *   | *no_valid_transfers* | `logic`                 | Unused in the source streamer (see **hci_core_source**).                                      |
 *   +----------------------+-------------------------+-----------------------------------------------------------------------------------------------+
 *   | *addressgen_flags*   | `flags_addressgen_v4_t` | Address generator flags (see **hwpe_stream_addressgen_v4**).                                   |
 *   +----------------------+-------------------------+-----------------------------------------------------------------------------------------------+
 *
 */

`include "hci_helpers.svh"

module hci_core_source_v2
  import hwpe_stream_package::*;
  import hci_package::*;
#(
  // Stream interface params
  parameter int unsigned LATCH_FIFO           = 0,
  parameter int unsigned TRANS_CNT            = 16,
  parameter int unsigned ADDR_MIS_DEPTH       = 8, // Beware: this must be >= the maximum latency between TCDM gnt and TCDM r_valid!!!
  parameter int unsigned MISALIGNED_ACCESSES  = 1,
  parameter int unsigned JOB_FIFO_DEPTH       = 2,
  parameter int unsigned JOB_FIFO_PASSTHROUGH = 1,
  parameter int unsigned PASSTHROUGH_FIFO     = 0,
  parameter int unsigned RESP_FIFO_DEPTH      = 0,
  parameter int unsigned ELEMENT_WIDTH        = 8,  // e.g., 8 bits per element
  parameter int unsigned ELEMENTS_PER_BANK    = 4,  // number of elements in one memory bank
  parameter bit [3:0] DIM_ENABLE_1H           = 4'b0011, // Number of dimensions enabled in the address generator
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0
)
(
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,
  input logic clear_i,
  input logic enable_i,

  hci_core_intf.initiator        tcdm,
  hwpe_stream_intf_stream.source stream,

  // control plane
  input  hci_streamer_v2_ctrl_t   ctrl_i,
  output hci_streamer_v2_flags_t  flags_o
);

  flags_fifo_t job_fifo_flags;

  hci_streamer_ctrl_t  source_ctrl;
  hci_streamer_flags_t source_flags;

  logic job_pop_ready;
  logic req_start;

  /*
   * Job queue
   */
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( $bits(ctrl_addressgen_v4_t) )
  ) job_push (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( $bits(ctrl_addressgen_v4_t) )
  ) job_pop (
    .clk ( clk_i )
  );

  assign job_push.data  = ctrl_i.addressgen_ctrl;
  assign job_push.valid = ctrl_i.valid;
  assign job_push.strb  = '1;
  assign flags_o.ready  = job_push.ready;

  if (JOB_FIFO_PASSTHROUGH == 1) begin : job_fifo_passthrough_gen
    hwpe_stream_fifo_passthrough #(
      .DATA_WIDTH ( $bits(ctrl_addressgen_v4_t) ),
      .FIFO_DEPTH ( JOB_FIFO_DEPTH  )
    ) i_fifo_job (
      .clk_i   ( clk_i           ),
      .rst_ni  ( rst_ni          ),
      .clear_i ( clear_i         ),
      .flags_o ( job_fifo_flags  ),
      .push_i  ( job_push        ),
      .pop_o   ( job_pop         )
    );
  end
  else begin : job_fifo_nopassthrough_gen
    hwpe_stream_fifo #(
      .DATA_WIDTH ( $bits(ctrl_addressgen_v4_t) ),
      .FIFO_DEPTH ( JOB_FIFO_DEPTH  )
    ) i_fifo_job (
      .clk_i   ( clk_i           ),
      .rst_ni  ( rst_ni          ),
      .clear_i ( clear_i         ),
      .flags_o ( job_fifo_flags  ),
      .push_i  ( job_push        ),
      .pop_o   ( job_pop         )
    );
  end

  assign job_pop.ready = job_pop_ready;

  /*
   * Job dispatch FSM
   * The head of the job queue is presented to the underlying streamer for the whole duration of
   * the job, and popped only when the streamer reports it done; this keeps the running job's
   * tot_len (used by the streamer to detect completion) stable.
   */
  typedef enum logic { WRAP_IDLE, WRAP_RUNNING } wrap_state_t;
  wrap_state_t wrap_cs, wrap_ns;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin : wrap_fsm_seq
    if(rst_ni == 1'b0) begin
      wrap_cs <= WRAP_IDLE;
    end
    else if(clear_i == 1'b1) begin
      wrap_cs <= WRAP_IDLE;
    end
    else if(enable_i) begin
      wrap_cs <= wrap_ns;
    end
  end

  always_comb
  begin : wrap_fsm_comb
    wrap_ns       = wrap_cs;
    job_pop_ready = 1'b0;
    req_start     = 1'b0;
    case(wrap_cs)
      WRAP_IDLE : begin
        if(job_pop.valid & source_flags.ready_start) begin
          wrap_ns   = WRAP_RUNNING;
          req_start = 1'b1;
        end
      end
      WRAP_RUNNING : begin
        if(source_flags.done) begin
          wrap_ns       = WRAP_IDLE;
          job_pop_ready = 1'b1;
        end
      end
    endcase
  end

  assign source_ctrl = '{
    req_start       : req_start,
    addressgen_ctrl : job_pop.data
  };

  assign flags_o.done               = source_flags.done;
  assign flags_o.no_valid_transfers = source_flags.no_valid_transfers;
  assign flags_o.addressgen_flags   = source_flags.addressgen_flags;

  hci_core_source #(
    .LATCH_FIFO            ( LATCH_FIFO            ),
    .TRANS_CNT             ( TRANS_CNT             ),
    .ADDR_MIS_DEPTH        ( ADDR_MIS_DEPTH        ),
    .MISALIGNED_ACCESSES   ( MISALIGNED_ACCESSES   ),
    .PASSTHROUGH_FIFO      ( PASSTHROUGH_FIFO      ),
    .RESP_FIFO_DEPTH       ( RESP_FIFO_DEPTH       ),
    .ELEMENT_WIDTH         ( ELEMENT_WIDTH         ),
    .ELEMENTS_PER_BANK     ( ELEMENTS_PER_BANK     ),
    .DIM_ENABLE_1H         ( DIM_ENABLE_1H         ),
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
  ) i_hci_core_source (
    .clk_i       ( clk_i        ),
    .rst_ni      ( rst_ni       ),
    .test_mode_i ( test_mode_i  ),
    .clear_i     ( clear_i      ),
    .enable_i    ( enable_i     ),
    .tcdm        ( tcdm         ),
    .stream      ( stream       ),
    .ctrl_i      ( source_ctrl  ),
    .flags_o     ( source_flags )
  );

endmodule // hci_core_source_v2
