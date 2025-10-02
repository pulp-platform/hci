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

`define HCI_TYPEDEF_REQ_T(req_t, addr_t, data_t, be_t, user_t, id_t, ecc_t)\
  typedef struct packed {                                                  \
    logic  req;                                                            \
    addr_t add;                                                            \
    logic  wen;                                                            \
    data_t data;                                                           \
    be_t   be;                                                             \
    logic  r_ready;                                                        \
    user_t user;                                                           \
    id_t   id;                                                             \
    ecc_t  ecc;                                                            \
    logic  ereq;                                                           \
    logic  r_eready;                                                       \
  } req_t;

`define HCI_TYPEDEF_RSP_T(rsp_t, data_t, user_t, id_t, ecc_t)\
  typedef struct packed {                                    \
    logic  gnt;                                              \
    data_t r_data;                                           \
    logic  r_valid;                                          \
    user_t r_user;                                           \
    id_t   r_id;                                             \
    logic  r_opc;                                            \
    ecc_t  r_ecc;                                            \
    logic  egnt;                                             \
    logic  r_evalid;                                         \
  } rsp_t;
