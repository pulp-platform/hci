// Copyright (c) 2020 ETH Zurich, University of Bologna
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

`define HCI_ASSIGN_TO_INTF(intf, reqst, rspns)\
    assign intf.req       = reqst.req;        \
    assign intf.add       = reqst.add;        \
    assign intf.wen       = reqst.wen;        \
    assign intf.data      = reqst.data;       \
    assign intf.be        = reqst.be;         \
    assign intf.r_ready   = reqst.r_ready;    \
    assign intf.user      = reqst.user;       \
    assign intf.id        = reqst.id;         \
    assign intf.ecc       = reqst.ecc;        \
    assign intf.ereq      = reqst.ereq;       \
    assign intf.r_eready  = reqst.r_eready;   \
    assign rspns.gnt      = intf.gnt;         \
    assign rspns.r_data   = intf.r_data;      \
    assign rspns.r_valid  = intf.r_valid;     \
    assign rspns.r_user   = intf.r_user;      \
    assign rspns.r_id     = intf.r_id;        \
    assign rspns.r_opc    = intf.r_opc;       \
    assign rspns.r_ecc    = intf.r_ecc;       \
    assign rspns.egnt     = intf.egnt;        \
    assign rspns.r_evalid = intf.r_evalid;

`define HCI_ASSIGN_FROM_INTF(intf, reqst, rspns)\
    assign reqst.req      = intf.req;             \
    assign reqst.add      = intf.add;             \
    assign reqst.wen      = intf.wen;             \
    assign reqst.data     = intf.data;            \
    assign reqst.be       = intf.be;              \
    assign reqst.r_ready  = intf.r_ready;         \
    assign reqst.user     = intf.user;            \
    assign reqst.id       = intf.id;              \
    assign reqst.ecc      = intf.ecc;             \
    assign reqst.ereq     = intf.ereq;            \
    assign reqst.r_eready = intf.r_eready;        \
    assign intf.gnt       = rspns.gnt;            \
    assign intf.r_data    = rspns.r_data;         \
    assign intf.r_valid   = rspns.r_valid;        \
    assign intf.r_user    = rspns.r_user;         \
    assign intf.r_id      = rspns.r_id;           \
    assign intf.r_opc     = rspns.r_opc;          \
    assign intf.r_ecc     = rspns.r_ecc;          \
    assign intf.egnt      = rspns.egnt;           \
    assign intf.r_evalid  = rspns.r_evalid;
