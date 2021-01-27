/*
 * hci_interfaces.sv
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
 *
 * This file collects all HCI-related interfaces.
 */

interface hci_core_intf (
  input logic clk
);

  parameter int unsigned DW = hci_package::DEFAULT_DW; /// Data Width
  parameter int unsigned AW = hci_package::DEFAULT_AW; /// Address Width
  parameter int unsigned BW = hci_package::DEFAULT_BW; /// Width of a "byte" in bits (default 8)
  parameter int unsigned WW = hci_package::DEFAULT_WW; /// Width of a "word" in bits (default 32)
  parameter int unsigned OW = AW; /// intra-bank offset width, defaults to addr width
  parameter int unsigned UW = hci_package::DEFAULT_UW; /// User Width

  // handshake signals
  logic req;
  logic gnt;
  logic lrdy; // load ready signal

  // request phase payload
  logic        [AW-1:0]            add;
  logic                            wen; // wen=1'b1 for LOAD, wen=1'b0 for STORE
  logic        [DW-1:0]            data;
  logic        [DW/BW-1:0]         be;
  logic signed [DW/WW-1:0][OW-1:0] boffs; // intra-bank offset, used for bank-restricted scatter/gather
  logic        [UW-1:0]            user;

  // response phase payload
  logic [DW-1:0] r_data;
  logic          r_valid;
  logic          r_opc;
  logic [UW-1:0] r_user;

  modport master (
    output req,
    input  gnt,
    output add,
    output wen,
    output data,
    output be,
    output boffs,
    output lrdy,
    output user,
    input  r_data,
    input  r_valid,
    input  r_opc,
    input  r_user
  );

  modport slave (
    input  req,
    output gnt,
    input  add,
    input  wen,
    input  data,
    input  be,
    input  boffs,
    input  lrdy,
    input  user,
    output r_data,
    output r_valid,
    output r_opc,
    output r_user
  );

  modport monitor (
    input req,
    input gnt,
    input add,
    input wen,
    input data,
    input be,
    input boffs,
    input lrdy,
    input user,
    input r_data,
    input r_valid,
    input r_opc,
    input r_user
  );

endinterface // hci_core_intf

interface hci_mem_intf (
  input logic clk
);

  parameter int unsigned AW = hci_package::DEFAULT_AW; /// Address Width
  parameter int unsigned DW = hci_package::DEFAULT_DW; /// Data Width
  parameter int unsigned BW = hci_package::DEFAULT_BW; /// Width of a "byte" in bits (default 8)
  parameter int unsigned IW = 8; /// width of ID
  parameter int unsigned UW = hci_package::DEFAULT_UW;  /// User Width

  // handshake signals
  logic req;
  logic gnt;

  // request phase payload
  logic [AW-1:0]    add;
  logic             wen;   // wen=1'b1 for LOAD, wen=1'b0 for STORE
  logic [DW-1:0]    data;
  logic [DW/BW-1:0] be;
  logic [IW-1:0]    id;
  logic [UW-1:0]    user;

  // response phase payload
  logic [DW-1:0] r_data;
  logic [IW-1:0] r_id;
  logic [UW-1:0] r_user;

  modport master (
    output req,
    input  gnt,
    output add,
    output wen,
    output data,
    output be,
    output id,
    output user,
    input  r_data,
    input  r_id,
    input  r_user
  );

  modport slave (
    input  req,
    output gnt,
    input  add,
    input  wen,
    input  data,
    input  be,
    input  id,
    input  user,
    output r_data,
    output r_id,
    output r_user
  );

  modport monitor (
    input req,
    input gnt,
    input add,
    input wen,
    input data,
    input be,
    input id,
    input user,
    input r_data,
    input r_id,
    input r_user
  );

endinterface // hci_mem_intf
