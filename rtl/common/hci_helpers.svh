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
`ifndef SYNTHESIS
  `define HCI_SIZE_GET_DW(x)  (x.DW)
  `define HCI_SIZE_GET_AW(x)  (x.AW)
  `define HCI_SIZE_GET_BW(x)  (x.BW)
  `define HCI_SIZE_GET_UW(x)  (x.UW)
  `define HCI_SIZE_GET_IW(x)  (x.IW)
  `define HCI_SIZE_GET_EW(x)  (x.EW)
  `define HCI_SIZE_GET_EHW(x) (x.EHW)
`else /* SYNTHESIS */
  `ifdef HCI_TARGET_FPGA
    `define HCI_SIZE_GET_DW(x)  (x.DW)
    `define HCI_SIZE_GET_AW(x)  (x.AW)
    `define HCI_SIZE_GET_BW(x)  (x.BW)
    `define HCI_SIZE_GET_UW(x)  (x.UW)
    `define HCI_SIZE_GET_IW(x)  (x.IW)
    `define HCI_SIZE_GET_EW(x)  (x.EW)
    `define HCI_SIZE_GET_EHW(x) (x.EHW)
  `else /* not HCI_TARGET FPGA */
    `define HCI_SIZE_GET_DW(x)  ($bits(x.data))
    `define HCI_SIZE_GET_AW(x)  ($bits(x.add))
    `define HCI_SIZE_GET_BW(x)  ($bits(x.be))
    `define HCI_SIZE_GET_UW(x)  ($bits(x.user))
    `define HCI_SIZE_GET_IW(x)  ($bits(x.id))
    `define HCI_SIZE_GET_EW(x)  ($bits(x.ecc))
    `define HCI_SIZE_GET_EHW(x) ($bits(x.ereq))
  `endif
`endif

`endif /* `ifndef __HCI_HELPERS__ */
