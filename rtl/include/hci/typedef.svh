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

`define HCI_TYPEDEF_REQ_T(req_t, addr_t, data_t, strb_t, boffs_t, user_t)\
  typedef struct packed {                                                \
    logic   req;                                                         \
    logic   wen;                                                         \
    strb_t  be;                                                          \
    boffs_t boffs;                                                       \
    addr_t  add;                                                         \
    data_t  data;                                                        \
    logic   lrdy;                                                        \
    user_t  user;                                                        \
  } req_t;

`define HCI_TYPEDEF_RSP_T(rsp_t, data_t, user_t)\
  typedef struct packed {                       \
    logic  gnt;                                 \
    logic  r_valid;                             \
    data_t r_data;                              \
    logic  r_opc;                               \
    user_t r_user;                              \
  } rsp_t;
