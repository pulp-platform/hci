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
  parameter int unsigned UW = hci_package::DEFAULT_UW; /// User Width
  parameter int unsigned IW = hci_package::DEFAULT_IW; /// ID Width
  parameter int unsigned EW = hci_package::DEFAULT_EW; /// ECC Width

  // handshake signals
  logic req;
  logic gnt;
  logic r_ready; // load ready signal

  // request phase payload
  logic        [AW-1:0]            add;
  logic                            wen; // wen=1'b1 for LOAD, wen=1'b0 for STORE
  logic        [DW-1:0]            data;
  logic        [DW/BW-1:0]         be;
  logic        [UW-1:0]            user;
  logic        [EW-1:0]            ecc;
  logic        [IW-1:0]            id;

  // response phase payload
  logic [DW-1:0] r_data;
  logic          r_valid;
  logic          r_opc;
  logic [UW-1:0] r_user;
  logic [EW-1:0] r_ecc;
  logic [IW-1:0] r_id;

  modport initiator (
    output req,
    input  gnt,
    output add,
    output wen,
    output data,
    output be,
    output r_ready,
    output user,
    output ecc,
    output id,
    input  r_data,
    input  r_valid,
    input  r_opc,
    input  r_user,
    input  r_ecc,
    input  r_id
  );

  modport target (
    input  req,
    output gnt,
    input  add,
    input  wen,
    input  data,
    input  be,
    input  r_ready,
    input  user,
    input  ecc,
    input  id,
    output r_data,
    output r_valid,
    output r_opc,
    output r_user,
    output r_ecc,
    output r_id
  );

  modport monitor (
    input req,
    input gnt,
    input add,
    input wen,
    input data,
    input be,
    input r_ready,
    input user,
    input ecc,
    input id,
    input r_data,
    input r_valid,
    input r_opc,
    input r_user,
    input r_ecc,
    input r_id
  );

endinterface // hci_core_intf

interface hci_mem_intf (
  input logic clk
);

  parameter int unsigned AW = hci_package::DEFAULT_AW; /// Address Width
  parameter int unsigned DW = hci_package::DEFAULT_DW; /// Data Width
  parameter int unsigned BW = hci_package::DEFAULT_BW; /// Width of a "byte" in bits (default 8)
  parameter int unsigned IW = hci_package::DEFAULT_IW; /// width of ID
  parameter int unsigned UW = hci_package::DEFAULT_UW;  /// User Width
  parameter int unsigned EW = hci_package::DEFAULT_EW; /// ECC Width

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
  logic [EW-1:0]    ecc;

  // response phase payload
  logic [DW-1:0] r_data;
  logic [IW-1:0] r_id;
  logic [UW-1:0] r_user;
  logic [EW-1:0] r_ecc;

  modport initiator (
    output req,
    input  gnt,
    output add,
    output wen,
    output data,
    output be,
    output id,
    output user,
    output ecc,
    input  r_data,
    input  r_id,
    input  r_user,
    input  r_ecc
  );

  modport target (
    input  req,
    output gnt,
    input  add,
    input  wen,
    input  data,
    input  be,
    input  id,
    input  user,
    input  ecc,
    output r_data,
    output r_id,
    output r_user,
    output r_ecc
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
    input ecc,
    input r_data,
    input r_id,
    input r_user,
    input r_ecc
  );

endinterface // hci_mem_intf
