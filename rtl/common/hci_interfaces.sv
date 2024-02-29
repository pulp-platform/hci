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

`ifndef HCI_ASSERT_SEVERITY
`define HCI_ASSERT_SEVERITY $warning
`endif

interface hci_core_intf (
  input logic clk
);
`ifndef SYNTHESIS
  parameter bit BYPASS_RQ3_ASSERT  = 1'b0;
  parameter bit BYPASS_RQ4_ASSERT  = 1'b0;
  parameter bit BYPASS_RSP3_ASSERT = 1'b0;
  parameter bit BYPASS_RSP5_ASSERT = 1'b0;
`endif

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

`ifndef SYNTHESIS
`ifndef VERILATOR
  // RQ-3 STABILITY
  property hci_rq3_stability_rule;
    @(posedge clk)
    ($past(req) & ~($past(req) & $past(gnt))) |-> (
      (data == $past(data)) && 
      (add  == $past(add))  &&
      (wen  == $past(wen))  &&
      (be   == $past(be))   &&
      (user == $past(user)) &&
      (ecc  == $past(ecc))  &&
      (id   == $past(id))
    ) | BYPASS_RQ3_ASSERT;
  endproperty;

  // RQ-4 NORETIRE
  property hci_rq4_noretire_rule;
    @(posedge clk)
    ($past(req) & ~req) |-> ($past(req) & $past(gnt)) | BYPASS_RQ4_ASSERT;
  endproperty;

  // RSP-3 STABILITY
  property hci_rsp3_stability_rule;
    @(posedge clk)
    ($past(r_valid) & ~($past(r_valid) & $past(r_ready))) |-> (
      (r_data == $past(r_data)) && 
      (r_user == $past(r_user)) &&
      (r_ecc  == $past(r_ecc))  &&
      (r_id   == $past(r_id))   &&
      (r_opc  == $past(r_opc))
    ) | BYPASS_RSP3_ASSERT;
  endproperty;

  // RSP-5 NORETIRE
  property hci_rsp5_noretire_rule;
    @(posedge clk)
    ($past(r_valid) & ~r_valid) |-> ($past(r_valid) & $past(r_ready)) | BYPASS_RSP5_ASSERT;
  endproperty;

  HCI_RQ3: assert property(hci_rq3_stability_rule)
    else `HCI_ASSERT_SEVERITY("RQ-3 STABILITY failure", 1);

  HCI_RQ4: assert property(hci_rq4_noretire_rule)
    else `HCI_ASSERT_SEVERITY("RQ-4 NORETIRE failure", 1);

  HCI_RSP3: assert property(hci_rsp3_stability_rule)
    else `HCI_ASSERT_SEVERITY("RSP-3 STABILITY failure", 1);

  HCI_RSP5: assert property(hci_rsp5_noretire_rule)
    else `HCI_ASSERT_SEVERITY("RSP-5 NORETIRE failure", 1);
`endif
`endif

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
