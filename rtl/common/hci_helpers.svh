/*
 * hci_helpers.svh
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2024 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

`ifndef __HCI_HELPERS__
`define __HCI_HELPERS__

// Manage the special case of FPGA targets
`ifdef TARGET_FPGA
  `define HCI_TARGET_FPGA
`elsif PULP_FPGA_EMUL
 `define HCI_TARGET_FPGA
`elsif FPGA_EMUL
 `define HCI_TARGET_FPGA
`elsif XILINX
 `define HCI_TARGET_FPGA
`endif

// Helper `defines to get internal sizes. Interestingly, the code for synthesis
// does not (consistently) work in simulation, and vice versa - although they
// have exactly the same purpose.

// Convenience defines to get conventional param name from interface name
// Example:
//   intf:  tcdm_initiator
//   param: HCI_SIZE_tcdm_initiator
`define HCI_SIZE_PREFIX_INTF(__prefix, __intf) __prefix``__intf
`define HCI_SIZE_PARAM(__intf) `HCI_SIZE_PREFIX_INTF(HCI_SIZE_, __intf)

`define HCI_SIZE_GET_DW(__x)  (`HCI_SIZE_PARAM(__x).DW)
`define HCI_SIZE_GET_AW(__x)  (`HCI_SIZE_PARAM(__x).AW)
`define HCI_SIZE_GET_BW(__x)  (`HCI_SIZE_PARAM(__x).BW)
`define HCI_SIZE_GET_UW(__x)  (`HCI_SIZE_PARAM(__x).UW)
`define HCI_SIZE_GET_IW(__x)  (`HCI_SIZE_PARAM(__x).IW)
`define HCI_SIZE_GET_EW(__x)  (`HCI_SIZE_PARAM(__x).EW)
`define HCI_SIZE_GET_EHW(__x) (`HCI_SIZE_PARAM(__x).EHW)

// Shorthand for defining a HCI interface compatible with a parameter
`define HCI_INTF_EXPLICIT_PARAM(__name, __clk, __param) \
  hci_core_intf #( \
    .DW  ( __param.DW  ), \
    .AW  ( __param.AW  ), \
    .BW  ( __param.BW  ), \
    .UW  ( __param.UW  ), \
    .IW  ( __param.IW  ), \
    .EW  ( __param.EW  ), \
    .EHW ( __param.EHW ) \
  ) __name ( \
    .clk ( __clk ) \
  )
`define HCI_INTF(__name, __clk)                `HCI_INTF_EXPLICIT_PARAM(__name, __clk,          `HCI_SIZE_PARAM(__name))
`define HCI_INTF_ARRAY(__name, __clk, __range) `HCI_INTF_EXPLICIT_PARAM(__name[__range], __clk, `HCI_SIZE_PARAM(__name))

`ifndef SYNTHESIS
  `define HCI_SIZE_GET_DW_CHECK(__x)  (__x.DW)
  `define HCI_SIZE_GET_AW_CHECK(__x)  (__x.AW)
  `define HCI_SIZE_GET_BW_CHECK(__x)  (__x.BW)
  `define HCI_SIZE_GET_UW_CHECK(__x)  (__x.UW)
  `define HCI_SIZE_GET_IW_CHECK(__x)  (__x.IW)
  `define HCI_SIZE_GET_EW_CHECK(__x)  (__x.EW)
  `define HCI_SIZE_GET_EHW_CHECK(__x) (__x.EHW)

  // Asserts (generic definition usable with any parameter name)
  `define HCI_SIZE_CHECK_ASSERTS_EXPLICIT_PARAM(__xparam, __xintf) \
  initial __xparam``_intf_size_check_dw  : assert(__xparam.DW  == `HCI_SIZE_GET_DW_CHECK(__xintf)); \
  initial __xparam``_intf_size_check_bw  : assert(__xparam.BW  == `HCI_SIZE_GET_BW_CHECK(__xintf)); \
  initial __xparam``_intf_size_check_aw  : assert(__xparam.AW  == `HCI_SIZE_GET_AW_CHECK(__xintf)); \
  initial __xparam``_intf_size_check_uw  : assert(__xparam.UW  == `HCI_SIZE_GET_UW_CHECK(__xintf)); \
  initial __xparam``_intf_size_check_iw  : assert(__xparam.IW  == `HCI_SIZE_GET_IW_CHECK(__xintf)); \
  initial __xparam``_intf_size_check_ew  : assert(__xparam.EW  == `HCI_SIZE_GET_EW_CHECK(__xintf)); \
  initial __xparam``_intf_size_check_ehw : assert(__xparam.EHW == `HCI_SIZE_GET_EHW_CHECK(__xintf))

  // Asserts (specialized definition for conventional param names
  `define HCI_SIZE_CHECK_ASSERTS(__intf) `HCI_SIZE_CHECK_ASSERTS_EXPLICIT_PARAM(`HCI_SIZE_PARAM(__intf), __intf)

`endif

`endif /* `ifndef __HCI_HELPERS__ */
