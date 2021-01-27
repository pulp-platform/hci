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

  // response phase payload
  logic [DW-1:0] r_data;
  logic          r_valid;
  logic          r_opc;

  modport master (
    output req,
    input  gnt,
    output add,
    output wen,
    output data,
    output be,
    output boffs,
    output lrdy,
    input  r_data,
    input  r_valid,
    input  r_opc
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
    output r_data,
    output r_valid,
    output r_opc
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
    input r_data,
    input r_valid,
    input r_opc
  );

endinterface // hci_core_intf

interface hci_mem_intf (
  input logic clk
);

  parameter int unsigned AW = hci_package::DEFAULT_AW; /// Address Width
  parameter int unsigned DW = hci_package::DEFAULT_DW; /// Data Width (WW=DW for mem_intf)
  parameter int unsigned BW = hci_package::DEFAULT_BW; /// Width of a "byte" in bits (default 8)
  parameter int unsigned IW = 8; /// width of ID

  // handshake signals
  logic req;
  logic gnt;

  // request phase payload
  logic [AW-1:0]    add;
  logic             wen;   // wen=1'b1 for LOAD, wen=1'b0 for STORE
  logic [DW-1:0]    data;
  logic [DW/BW-1:0] be;
  logic [IW-1:0]    id;

  // response phase payload
  logic [DW-1:0] r_data;
  logic [IW-1:0] r_id;

  modport master (
    output req,
    input  gnt,
    output add,
    output wen,
    output data,
    output be,
    output id,
    input  r_data,
    input  r_id
  );

  modport slave (
    input  req,
    output gnt,
    input  add,
    input  wen,
    input  data,
    input  be,
    input  id,
    output r_data,
    output r_id
  );

  modport monitor (
    input req,
    input gnt,
    input add,
    input wen,
    input data,
    input be,
    input id,
    input r_data,
    input r_id
  );

endinterface // hci_mem_intf
