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

  // Return either the argument minus 1 or 0 if 0; useful for IO vector width declaration
  function automatic integer unsigned iomsb(input integer unsigned width);
    return (width != 32'd0) ? unsigned'(width - 1) : 32'd0;
  endfunction

  parameter int unsigned DEFAULT_DW = 32;  // Default Data Width
  parameter int unsigned DEFAULT_AW = 32;  // Default Address Width
  parameter int unsigned DEFAULT_BW = 8;  // Default Byte Width
  parameter int unsigned DEFAULT_UW = 1;  // Default User Width
  parameter int unsigned DEFAULT_IW = 8;  // Default ID Width
  parameter int unsigned DEFAULT_EW = 1;  // Default ECC for Data Width
  parameter int unsigned DEFAULT_EHW = 1;  // Default ECC for Handhshake Width

  typedef struct packed {
    int unsigned DW;
    int unsigned AW;
    int unsigned BW;
    int unsigned UW;
    int unsigned IW;
    int unsigned EW;
    int unsigned EHW;
  } hci_size_parameter_t;

  parameter hci_size_parameter_t DEFAULT_HCI_SIZE = '{
    DW  : DEFAULT_DW,
    AW  : DEFAULT_AW,
    BW  : DEFAULT_BW,
    UW  : DEFAULT_UW,
    IW  : DEFAULT_IW,
    EW  : DEFAULT_EW,
    EHW : DEFAULT_EHW
  };

  typedef struct packed {
    logic [1:0] arb_policy; // used only in some systems
    logic       invert_prio;
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

  typedef struct packed {
    logic                                     valid;
    hwpe_stream_package::ctrl_addressgen_v3_t addressgen_ctrl;
  } hci_streamer_v2_ctrl_t;

  typedef struct packed {
    logic                                      ready;
    logic                                      done;
    hwpe_stream_package::flags_addressgen_v3_t addressgen_flags;
  } hci_streamer_v2_flags_t;

  typedef struct packed {
    logic                                     req_start;
    logic                                     ignore_bias;
    hwpe_stream_package::ctrl_addressgen_v3_t addressgen_ctrl;
  } hci_streamer_biased_ctrl_t;

  typedef enum {
    STREAMER_IDLE, STREAMER_PRESAMPLE ,STREAMER_WORKING, STREAMER_DONE
  } hci_streamer_state_t;

  typedef enum {
    COPY,        // Full copy and comparison of all signals
    NO_ECC,      // Do not assign and compare ecc signals
    NO_DATA,     // Do not assign and compare data signals
    CTRL_ONLY    // Do not assign either ecc nor data signals
  } hci_copy_t;

  typedef struct packed {
    logic [32-1:0] addr;
    logic          write;
    logic [32-1:0] wdata;
    logic [8-1:0]  wstrb;
    logic          valid;
  } hci_ecc_req_t;

  typedef struct packed {
    logic [32-1:0] rdata;
    logic          error;
    logic          ready;
  } hci_ecc_rsp_t;


endpackage // hci_package
