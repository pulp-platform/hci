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

`ifndef HCI_ASSERT_DELAY
`define HCI_ASSERT_DELAY #1ps
`endif

interface hci_core_intf (
  input logic clk
);
`ifndef SYNTHESIS
  parameter bit WAIVE_RQ3_ASSERT  = 1'b0;
  parameter bit WAIVE_RQ4_ASSERT  = 1'b0;
  parameter bit WAIVE_RSP3_ASSERT = 1'b0;
  parameter bit WAIVE_RSP5_ASSERT = 1'b0;
`endif

  parameter int unsigned DW  = hci_package::DEFAULT_DW;  /// Data Width
  parameter int unsigned AW  = hci_package::DEFAULT_AW;  /// Address Width
  parameter int unsigned BW  = hci_package::DEFAULT_BW;  /// Width of a "byte" in bits (default 8)
  parameter int unsigned UW  = hci_package::DEFAULT_UW;  /// User Width
  parameter int unsigned IW  = hci_package::DEFAULT_IW;  /// ID Width
  parameter int unsigned EW  = hci_package::DEFAULT_EW;  /// ECC Width
  parameter int unsigned EHW = hci_package::DEFAULT_EHW; /// Handshake ECC Width

  // handshake signals
  logic req;
  logic gnt;
  logic r_valid;
  logic r_ready;

  // request phase payload
  logic [AW-1:0]    add;
  logic             wen; // wen=1'b1 for LOAD, wen=1'b0 for STORE
  logic [DW-1:0]    data;
  logic [DW/BW-1:0] be;
  logic [UW-1:0]    user;
  logic [IW-1:0]    id;

  // response phase payload
  logic [DW-1:0] r_data;
  logic [UW-1:0] r_user;
  logic [IW-1:0] r_id;
  logic          r_opc;

  // data ECC signals
  logic [EW-1:0] ecc;
  logic [EW-1:0] r_ecc;

  // handshake ECC signals
  logic [EHW-1:0] ereq;
  logic [EHW-1:0] egnt;
  logic [EHW-1:0] r_evalid;
  logic [EHW-1:0] r_eready;

  modport initiator (
    output req,
    input  gnt,
    output add,
    output wen,
    output data,
    output be,
    output r_ready,
    output user,
    output id,
    input  r_data,
    input  r_valid,
    input  r_user,
    input  r_id,
    input  r_opc,
    output ecc,
    input  r_ecc,
    output ereq,
    input  egnt,
    input  r_evalid,
    output r_eready
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
    input  id,
    output r_data,
    output r_valid,
    output r_user,
    output r_id,
    output r_opc,
    input  ecc,
    output r_ecc,
    input  ereq,
    output egnt,
    output r_evalid,
    input  r_eready
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
    input id,
    input r_data,
    input r_valid,
    input r_user,
    input r_id,
    input r_opc,
    input ecc,
    input r_ecc,
    input ereq,
    input egnt,
    input r_evalid,
    input r_eready
  );

`ifndef SYNTHESIS
`ifndef VERILATOR
`ifndef VCS

  logic clk_assert;
  always @(clk)
  begin
    `HCI_ASSERT_DELAY clk_assert = clk;
  end

  // RQ-3 STABILITY
  property hci_rq3_stability_rule;
    @(posedge clk_assert)
    ($past(req) & ~($past(req) & $past(gnt))) |-> (
      (data == $past(data)) && 
      (add  == $past(add))  &&
      (wen  == $past(wen))  &&
      (be   == $past(be))   &&
      (user == $past(user)) &&
      (ecc  == $past(ecc))  &&
      (id   == $past(id))
    ) | WAIVE_RQ3_ASSERT;
  endproperty;

  // RQ-4 NORETIRE
  property hci_rq4_noretire_rule;
    @(posedge clk_assert)
    ($past(req) & ~req) |-> ($past(req) & $past(gnt)) | WAIVE_RQ4_ASSERT;
  endproperty;

  // RSP-3 STABILITY
  property hci_rsp3_stability_rule;
    @(posedge clk_assert)
    ($past(r_valid) & ~($past(r_valid) & $past(r_ready))) |-> (
      (r_data == $past(r_data)) && 
      (r_user == $past(r_user)) &&
      (r_ecc  == $past(r_ecc))  &&
      (r_id   == $past(r_id))
    ) | WAIVE_RSP3_ASSERT;
  endproperty;

  // RSP-5 NORETIRE
  property hci_rsp5_noretire_rule;
    @(posedge clk_assert)
    ($past(r_valid) & ~r_valid) |-> ($past(r_valid) & $past(r_ready)) | WAIVE_RSP5_ASSERT;
  endproperty;

  HCI_RQ3: assert property(hci_rq3_stability_rule)
    else `HCI_ASSERT_SEVERITY("HCI RQ-3 STABILITY protocol violation!", 1);

  HCI_RQ4: assert property(hci_rq4_noretire_rule)
    else `HCI_ASSERT_SEVERITY("HCI RQ-4 NORETIRE protocol violation!", 1);

  HCI_RSP3: assert property(hci_rsp3_stability_rule)
    else `HCI_ASSERT_SEVERITY("HCI RSP-3 STABILITY protocol violation!", 1);

  HCI_RSP5: assert property(hci_rsp5_noretire_rule)
    else `HCI_ASSERT_SEVERITY("HCI RSP-5 NORETIRE protocol violation!", 1);
`endif
`endif
`endif

endinterface // hci_core_intf

`ifdef BUILD_DEPRECATED
interface hci_mem_intf (
  input logic clk
);

  parameter int unsigned AW = hci_package::DEFAULT_AW; /// Address Width
  parameter int unsigned DW = hci_package::DEFAULT_DW; /// Data Width
  parameter int unsigned BW = hci_package::DEFAULT_BW; /// Width of a "byte" in bits (default 8)
  parameter int unsigned IW = hci_package::DEFAULT_IW; /// width of ID
  parameter int unsigned UW = hci_package::DEFAULT_UW;  /// User Width
  parameter int unsigned EW = hci_package::DEFAULT_EW; /// ECC Width
  parameter int unsigned EHW = hci_package::DEFAULT_EHW; /// ECC Handshake Width

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

  // data ECC signals
  logic [EW-1:0] ecc;
  logic [EW-1:0] r_ecc;

  // handshake ECC signals
  logic [EHW-1:0] ereq;
  logic [EHW-1:0] egnt;
  logic [EHW-1:0] r_evalid;
  logic [EHW-1:0] r_eready;

  modport initiator (
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
    input  r_user,
    output ecc,
    input  r_ecc,
    output ereq,
    input  egnt,
    input  r_evalid,
    output r_eready
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
    output r_data,
    output r_id,
    output r_user,
    output ecc,
    input  r_ecc,
    input  ereq,
    output egnt,
    output r_evalid,
    input  r_eready
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
    input r_user,
    input ecc,
    input r_ecc,
    input ereq,
    input egnt,
    input r_evalid,
    input r_eready
  );

endinterface // hci_mem_intf
`endif /* BUILD_DEPRECATED */
