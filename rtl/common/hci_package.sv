/*
 * hci_package.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2019-2020 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

package hci_package;

  parameter int unsigned DEFAULT_DW = 32; // Default Data Width
  parameter int unsigned DEFAULT_AW = 32; // Default Address Width
  parameter int unsigned DEFAULT_BW = 8;  // Default Byte Width
  parameter int unsigned DEFAULT_WW = 32; // Default Word Width
  parameter int unsigned DEFAULT_UW = 1;  // Default User Width

  typedef struct packed {
    logic [1:0] arb_policy;
    logic       hwpe_prio;
    logic [7:0] low_prio_max_stall;
  } hci_interconnect_ctrl_t;

  typedef struct packed {
    logic                                     req_start;
    hwpe_stream_package::ctrl_addressgen_v3_t addressgen_ctrl;
  } hci_streamer_ctrl_t;

  typedef struct packed {
    logic                                      ready_start;
    logic                                      done;
    hwpe_stream_package::flags_addressgen_v3_t addressgen_flags;
  } hci_streamer_flags_t;

  typedef enum {
    STREAMER_IDLE, STREAMER_WORKING, STREAMER_DONE
  } hci_streamer_state_t;

endpackage // hci_package
