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

  parameter int unsigned DEFAULT_DW = 32;
  parameter int unsigned DEFAULT_AW = 32;
  parameter int unsigned DEFAULT_BW = 8;
  parameter int unsigned DEFAULT_WW = 10;

  typedef struct packed {
    logic [1:0] arb_policy;
    logic       hwpe_prio;
    logic [7:0] low_prio_max_stall;
  } hci_interconnect_ctrl_t;

  typedef struct packed {
    logic [31:0] base_addr;
    logic [31:0] trans_size;
    logic [15:0] line_length;
    logic [7:0]  line_length_remainder; // in bytes
  } hci_core_addressgen_ctrl_t;

endpackage // hci_package
