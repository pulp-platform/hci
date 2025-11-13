/*
 * hci_helpers.svh
 * Francesco Conti <f.conti@unibo.it>
 * Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
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

/*
 * HCI helpers are used to provide a "standard" way to propagate parameters
 * along with hci_core_intf in a synthesizable way.
 * Their usage is optional and they can always be replaced by (slightly more
 * boilerplate-y) SystemVerilog code.
 * Basically, this is a big "workaround" for some tools not allowing one
 * to "extract" constant parameters out of interfaces. Shame on you, non-compliant 
 * EDA tools!
 * 
 * Defining a new HCI interface
 * ############################
 *
 * To define a new interface, one would normally have to define the
 * size parameters (DW, AW, BW, UW, IW, EW, EHW) and pass them to the interface;
 * moreover the same parameters can be passed to other modules. The process is
 * error-prone, so the helpers provide a structured solution: a macro to 1. declare the 
 * size parameters with a standard name referred to the interface name (e.g.,
 * `HCI_SIZE_tcdm_init` for the `tcdm_init` interface); 2. declare the interface
 * itself, using the parameters just defined.
 * This is done by the following code:
 *
 *   localparam hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(tcdm_init) = '{
 *     DW:  32,
 *     AW:  32,
 *     BW:  hci_package::DEFAULT_BW,
 *     UW:  hci_package::DEFAULT_UW,
 *     IW:  2,
 *     EW:  hci_package::DEFAULT_EW,
 *     EHW: hci_package::DEFAULT_EHW
 *   };
 *   `HCI_INTF(tcdm_init, clk_i);
 *
 * This code gets transformed by the SystemVerilog preprocessor into
 *
 *   localparam hci_package::hci_size_parameter_t HCI_SIZE_tcdm_init = '{
 *     DW:  32,
 *     AW:  32,
 *     BW:  hci_package::DEFAULT_BW,
 *     UW:  hci_package::DEFAULT_UW,
 *     IW:  2,
 *     EW:  hci_package::DEFAULT_EW,
 *     EHW: hci_package::DEFAULT_EHW
 *   };
 *   hci_core_intf #(
 *     .DW  ( HCI_SIZE_tcdm_init.DW  ),
 *     .AW  ( HCI_SIZE_tcdm_init.AW  ),
 *     .BW  ( HCI_SIZE_tcdm_init.BW  ),
 *     .UW  ( HCI_SIZE_tcdm_init.UW  ),
 *     .IW  ( HCI_SIZE_tcdm_init.IW  ),
 *     .EW  ( HCI_SIZE_tcdm_init.EW  ),
 *     .EHW ( HCI_SIZE_tcdm_init.EHW )
 *   ) tcdm_init (
 *     .clk ( clk_i )
 *   ); 
 *
 * In case we have an array of interfaces, e.g., `tcdm_init[0:N-1]`, we can use the
 * following macro instead of `HCI_INTF:
 * 
 *   `HCI_INTF_ARRAY(tcdm_init, clk_i, 0:N-1);
 *
 * Apart from removing a bit of boilerplate, the idea behind this macro is that
 * we reduce clutter by hiding the fact that the `tcdm_init` interface and parameters
 * are carried by two different SystemVerilog entities (an interface and a localparam
 * struct).
 * 
 * Parametrizing an interface at a module's boundary
 * #################################################
 *
 * Parametrizing an HCI interface at a module's boundary requires adding the parameter
 * to the list, with a macro to derive the name from the interface's one.
 *
 *   module example
 *   #(
 *     // [other params...]
 *     parameter hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = hci_package::DEFAULT_HCI_SIZE
 *   )
 *   (
 *     input logic clk_i,
 *     input logic rst_ni,
 *     // [other interfaces and signals...]
 *     hci_core_intf.initiator        tcdm
 *   );
 *
 * This gets "untrolled" to the following (almost identical) code:
 *
 *   module example
 *   #(
 *     // [other params...]
 *     parameter hci_package::hci_size_parameter_t HCI_SIZE_tcdm = hci_package::DEFAULT_HCI_SIZE
 *   )
 *   (
 *     input logic clk_i,
 *     input logic rst_ni,
 *     // [other interfaces and signals...]
 *     hci_core_intf.initiator        tcdm
 *   );
 *
 * Basically the main advantage of using the macro here is better consistency and readability.
 * 
 * Propagating interface parametrization through hierarchy
 * #######################################################
 *
 * Following the previous parametrization allows propagating params through hierarchy
 * in a way that is concurrent with interfaces. Assum for example that `tcdm` is connected
 * to `ext_tcdm` in the module instantiating `example`. Then, to instatiate `example` the
 * following code can be used:
 *
 *   example #(
 *     // [other params...]
 *     .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(ext_tcdm) )
 *   ) i_example (
 *     .clk_i       ( clk_i    ),
 *     .rst_ni      ( rst_ni   ),
 *     // [other interfaces and signals...]
 *     .tcdm        ( ext_tcdm )
 *   );
 *
 * which in turn gets "unrolled" in this way:
 *
 *   example #(
 *     // [other params...]
 *     .HCI_SIZE_tcdm ( HCI_SIZE_ext_tcdm )
 *   ) i_example (
 *     .clk_i       ( clk_i    ),
 *     .rst_ni      ( rst_ni   ),
 *     // [other interfaces and signals...]
 *     .tcdm        ( ext_tcdm )
 *   );
 * 
 * Consistency assertions
 * ######################
 *
 * The helpers can also be used to define convenient consistency assertions on the interface
 * sizes. This is done with the following macro (considering the `tcdm` interface):
 *
 *   `HCI_INTF_ARRAY(tcdm_vec, clk_i, 0:N-1);
 *   `ifndef SYNTHESIS
 *   `HCI_SIZE_CHECK_ASSERTS(tcdm);
 *   `endif
 *
 * In case of an array of interfaces (or of a non-standard parameter name), the syntax is slightly
 * different (a bit more verbose, indicating explicitly the parameter name:
 *
 *   `HCI_INTF_ARRAY(tcdm_vec, clk_i, 0:N-1);
 *   `ifndef SYNTHESIS
 *   `HCI_SIZE_CHECK_ASSERTS_EXPLICIT_PARAM(tcdm, `HCI_SIZE_PARAM(tcdm));
 *   `endif
 *
 * Size getter macros
 * ##################
 *
 * To keep consistency with HCI v2.0, which attempted pure interface-based parameter propagation
 * (unsuccessfully), getter helpers are available for all standard parameters. E.g.,
 *
 *   localparam AW_INT = `HCI_SIZE_GET_AW(tcdm);
 *
 * will get translated into
 *
 *   localparam AW_INT = HCI_SIZE_tcdm.AW;
 *
 * Again, the main advantage is simpler and more readable code, but the two syntaxes are equally
 * valid.
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
  `define HCI_SIZE_CHECK_ASSERTS_EXPLICIT_PARAM(__xparam, __xintf) 

  // Asserts (specialized definition for conventional param names
  `define HCI_SIZE_CHECK_ASSERTS(__intf) 

`endif

`endif /* `ifndef __HCI_HELPERS__ */
