/*
 * hci_interconnect.sv
 * Francesco Conti <f.conti@unibo.it>
 * Tobias Riedener <tobiasri@student.ethz.ch>
 * Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
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
 */

/**
 * Convenience top-level for the PULP heterogeneous cluster interconnect. It
 * wraps both a logarithmic interconnect (LIC) and an (optional) HCI router meant 
 * to realize a LIC and a HWPE branch of the interconnect, respectively.
 * The two branches are (optionally) arbitrated via a HCI arbiter.
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_interconnect_params:
 * .. table:: **hci_interconnect** design-time parameters.
 *
 *   +---------------------+-----------------------------+----------------------------------------------------------------------------------+
 *   | **Name**            | **Default**                 | **Description**                                                                  |
 *   +---------------------+-----------------------------+----------------------------------------------------------------------------------+
 *   | *N_HWPE*            | 1                           | Number of HWPEs attached as initiator to the interconnect (LIC or HWPE branch).  |
 *   +---------------------+-----------------------------+----------------------------------------------------------------------------------+
 *   | *N_CORE*            | 8                           | Number of cores attached as initiator to the interconnect (LIC branch).          |
 *   +---------------------+-----------------------------+----------------------------------------------------------------------------------+
 *   | *N_DMA*             | 4                           | Number of DMA ports attached as initiator to the interconnect (LIC branch).      |
 *   +---------------------+-----------------------------+----------------------------------------------------------------------------------+
 *   | *N_EXT*             | 4                           | Number of external ports attached as initiator to the interconnect (LIC branch). |
 *   +---------------------+-----------------------------+----------------------------------------------------------------------------------+
 *   | *N_MEM*             | 16                          | Number of memory banks attached as target to the interconnect.                   |
 *   +---------------------+-----------------------------+----------------------------------------------------------------------------------+
 *   | *TS_BIT*            | 21                          | Bit passed to LIC to define test&set aliased memory region.                      |
 *   +---------------------+-----------------------------+----------------------------------------------------------------------------------+
 *   | *IW*                | `N_HWPE+N_CORE+N_DMA+N_EXT` | ID Width.                                                                        |
 *   +---------------------+-----------------------------+----------------------------------------------------------------------------------+
 *   | *EXPFIFO*           | 0                           | Depth of HCI router FIFO.                                                        |
 *   +---------------------+-----------------------------+----------------------------------------------------------------------------------+
 *   | *SEL_LIC*           | 0                           | Kind of LIC to instantiate (0=regular L1, 1=L2).                                 |
 *   +---------------------+-----------------------------+----------------------------------------------------------------------------------+
 */

`include "hci_helpers.svh"

module hci_interconnect
  import hci_package::*;
#(
  parameter int unsigned N_HWPE  = 1                        , // Number of HWPEs attached to the port
  parameter int unsigned N_CORE  = 8                        , // Number of Core ports
  parameter int unsigned N_DMA   = 4                        , // Number of DMA ports
  parameter int unsigned N_EXT   = 4                        , // Number of External ports
  parameter int unsigned N_MEM   = 16                       , // Number of Memory banks
  parameter int unsigned TS_BIT  = 21                       , // TEST_SET_BIT (for Log Interconnect)
  parameter int unsigned IW      = N_HWPE+N_CORE+N_DMA+N_EXT, // ID Width
  parameter int unsigned EXPFIFO = 0                        , // FIFO Depth for HWPE Interconnect
  parameter int unsigned SEL_LIC = 0                        , // Log interconnect type selector
  parameter int unsigned FILTER_WRITE_R_VALID[0:N_HWPE-1] = '{default: 0},
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(cores) = '0,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(mems)  = '0,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(hwpe)  = '0,
  parameter bit WAIVE_RQ3_ASSERT  = 1'b0,
  parameter bit WAIVE_RQ4_ASSERT  = 1'b0,
  parameter bit WAIVE_RSP3_ASSERT = 1'b0,
  parameter bit WAIVE_RSP5_ASSERT = 1'b0
) (
  input logic                   clk_i               ,
  input logic                   rst_ni              ,
  input logic                   clear_i             ,
  input hci_interconnect_ctrl_t ctrl_i              ,
  hci_core_intf.target           cores   [0:N_CORE-1],
  hci_core_intf.target           dma     [0:N_DMA-1] ,
  hci_core_intf.target           ext     [0:N_EXT-1] ,
  hci_core_intf.initiator        mems    [0:N_MEM-1] ,
  hci_core_intf.target           hwpe    [0:N_HWPE-1]
);

  localparam int unsigned AWC = `HCI_SIZE_GET_AW(cores);
  localparam int unsigned AWM = `HCI_SIZE_GET_AW(mems);
  localparam int unsigned EWC = `HCI_SIZE_GET_EW(cores);
  localparam int unsigned DW_LIC = `HCI_SIZE_GET_DW(cores);
  localparam int unsigned BW_LIC = `HCI_SIZE_GET_BW(cores);
  localparam int unsigned UW_LIC = `HCI_SIZE_GET_UW(cores);
  localparam int unsigned DWH = `HCI_SIZE_GET_DW(hwpe);
  localparam int unsigned AWH = `HCI_SIZE_GET_AW(hwpe);
  localparam int unsigned BWH = `HCI_SIZE_GET_BW(hwpe);
  localparam int unsigned UWH = `HCI_SIZE_GET_UW(hwpe);
  localparam int unsigned IWH = `HCI_SIZE_GET_IW(hwpe);

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(all_except_hwpe) = '{
    DW:  DEFAULT_DW,
    AW:  DEFAULT_AW,
    BW:  DEFAULT_BW,
    UW:  UW_LIC,
    IW:  DEFAULT_IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };
  hci_core_intf #(
    .DW  ( DEFAULT_DW  ),
    .AW  ( DEFAULT_AW  ),
    .BW  ( DEFAULT_BW  ),
    .UW  ( UW_LIC      ),
    .IW  ( DEFAULT_IW  ),
    .EW  ( DEFAULT_EW  ),
    .EHW ( DEFAULT_EHW )
`ifndef SYNTHESIS
    ,
    .WAIVE_RQ3_ASSERT  ( WAIVE_RQ3_ASSERT  ),
    .WAIVE_RQ4_ASSERT  ( WAIVE_RQ4_ASSERT  ),
    .WAIVE_RSP3_ASSERT ( WAIVE_RSP3_ASSERT ),
    .WAIVE_RSP5_ASSERT ( WAIVE_RSP5_ASSERT )
`endif
  ) all_except_hwpe[0:N_CORE+N_DMA+N_EXT-1] (
    .clk ( clk_i )
  );

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(all_except_hwpe_mem) = '{
    DW:  DEFAULT_DW,
    AW:  DEFAULT_AW,
    BW:  DEFAULT_BW,
    UW:  UW_LIC,
    IW:  IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };
  `HCI_INTF_ARRAY(all_except_hwpe_mem, clk_i, 0:N_MEM-1);

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(hwpe_mem_muxed) = '{
    DW:  DEFAULT_DW,
    AW:  AWM,
    BW:  DEFAULT_BW,
    UW:  UW_LIC,
    IW:  IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };
  `HCI_INTF_ARRAY(hwpe_mem_muxed, clk_i, 0:N_MEM-1);


  localparam hci_size_parameter_t `HCI_SIZE_PARAM(hwpe_mem) = '{
    DW:  DEFAULT_DW,
    AW:  AWM,
    BW:  DEFAULT_BW,
    UW:  UW_LIC,
    IW:  IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };
  `HCI_INTF_ARRAY(hwpe_mem, clk_i, 0:N_HWPE*N_MEM-1);


  localparam hci_size_parameter_t `HCI_SIZE_PARAM(hwpe_to_router) = `HCI_SIZE_PARAM(hwpe);
  hci_core_intf #(
    .DW(DWH),
    .AW(AWH),
    .BW(BWH),
    .UW(UWH),
    .IW(IWH),
    .EW(DEFAULT_EW),
    .EHW(DEFAULT_EHW)) hwpe_to_router (
      .clk(clk_i)
    );
  generate

    if(SEL_LIC==0) begin : l1_interconnect_gen
      hci_log_interconnect #(
        .N_CH0  ( N_CORE              ),
        .N_CH1  ( N_DMA + N_EXT       ),
        .N_MEM  ( N_MEM               ),
        .IW     ( IW                  ),
        .AWC    ( AWC                 ),
        .AWM    ( AWM-2               ),
        .DW     ( DW_LIC              ),
        .BW     ( BW_LIC              ),
        .UW     ( UW_LIC              ),
        .TS_BIT ( TS_BIT              ),
        .EW     ( EWC                 )
      ) i_log_interconnect (
        .clk_i  ( clk_i               ),
        .rst_ni ( rst_ni              ),
        .ctrl_i ( ctrl_i              ),
        .cores  ( all_except_hwpe     ),
        .mems   ( all_except_hwpe_mem )
      );
    end
    else if(SEL_LIC==1) begin : l2_interconnect_gen
      hci_log_interconnect_l2 #(
        .N_CH0  ( N_CORE              ),
        .N_CH1  ( N_DMA + N_EXT       ),
        .N_MEM  ( N_MEM               ),
        .IW     ( IW                  ),
        .AWC    ( AWC                 ),
        .AWM    ( AWM                 ),
        .DW     ( DW_LIC              ),
        .BW     ( BW_LIC              ),
        .UW     ( UW_LIC              )
      ) i_log_interconnect (
        .clk_i  ( clk_i               ),
        .rst_ni ( rst_ni              ),
        .ctrl_i ( '0                  ),
        .cores  ( all_except_hwpe     ),
        .mems   ( all_except_hwpe_mem )
      );
    end
    else begin : new_l1_interconnect_gen
      hci_new_log_interconnect #(
        .N_CH0  ( N_CORE              ),
        .N_CH1  ( N_DMA + N_EXT       ),
        .N_MEM  ( N_MEM               ),
        .IW     ( IW                  ),
        .AWC    ( AWC                 ),
        .AWM    ( AWM-2               ),
        .DW     ( DW_LIC              ),
        .BW     ( BW_LIC              ),
        .UW     ( UW_LIC              ),
        .TS_BIT ( TS_BIT              )
      ) i_log_interconnect (
        .clk_i  ( clk_i               ),
        .rst_ni ( rst_ni              ),
        .ctrl_i ( ctrl_i              ),
        .cores  ( all_except_hwpe     ),
        .mems   ( all_except_hwpe_mem )
      );
    end
  endgenerate

  generate
    if(N_HWPE > 0) begin: hwpe_branch_gen

      for(genvar ii=0; ii<N_HWPE; ii++) begin : hwpe_req2mem
    
        hci_router #(
          .FIFO_DEPTH           ( EXPFIFO                   ),
          .NB_OUT_CHAN          ( N_MEM                     ),
          .FILTER_WRITE_R_VALID ( FILTER_WRITE_R_VALID[ii]  ),
          .`HCI_SIZE_PARAM(in)  ( `HCI_SIZE_PARAM(hwpe)     ),
          .`HCI_SIZE_PARAM(out) ( `HCI_SIZE_PARAM(hwpe_mem) )
        ) i_router (
          .clk_i   ( clk_i                            ),
          .rst_ni  ( rst_ni                           ),
          .clear_i ( clear_i                          ),
          .in      ( hwpe[ii]                         ),
          .out     ( hwpe_mem[ii*N_MEM:(ii+1)*N_MEM-1])
        );
    
      end : hwpe_req2mem

      hci_arbiter_tree #(
        .NB_REQUESTS(N_HWPE),
        .NB_CHAN ( N_MEM ),
        .`HCI_SIZE_PARAM(out)(`HCI_SIZE_PARAM(hwpe_mem_muxed))
      ) i_wide_port_arbiter_tree (
        .clk_i   ( clk_i               ),
        .rst_ni  ( rst_ni              ),
        .clear_i ( clear_i             ),
        .ctrl_i  ( ctrl_i              ),
        .in      ( hwpe_mem            ),
        .out     ( hwpe_mem_muxed      )
      );

      hci_arbiter #(
        .NB_CHAN ( N_MEM )
      ) i_wide_vs_narrow_arbiter (
        .clk_i   ( clk_i               ),
        .rst_ni  ( rst_ni              ),
        .clear_i ( clear_i             ),
        .ctrl_i  ( ctrl_i              ),
        .in_high ( all_except_hwpe_mem ),
        .in_low  ( hwpe_mem_muxed      ),
        .out     ( mems                )
      );

    end
    else begin: no_hwpe_branch_gen

      for(genvar ii=0; ii<N_MEM; ii++) begin: no_hwpe_mem_binding
        hci_core_assign i_mem_assign (
          .tcdm_target    ( all_except_hwpe_mem [ii] ),
          .tcdm_initiator ( mems                [ii] )
        );
      end

    end
  endgenerate

  generate
    for(genvar ii=0; ii<N_CORE; ii++) begin: cores_binding
      hci_core_assign i_cores_assign (
        .tcdm_target    ( cores           [ii] ),
        .tcdm_initiator ( all_except_hwpe [ii] )
      );
    end : cores_binding
    for(genvar ii=0; ii<N_EXT; ii++) begin: ext_binding
      hci_core_assign i_ext_assign (
        .tcdm_target    ( ext             [ii]        ),
        .tcdm_initiator ( all_except_hwpe [N_CORE+ii] )
      );
    end : ext_binding
    for(genvar ii=0; ii<N_DMA; ii++) begin: dma_binding
      hci_core_assign i_dma_assign (
        .tcdm_target    ( dma             [ii]              ),
        .tcdm_initiator ( all_except_hwpe [N_CORE+N_EXT+ii] )
      );
    end : dma_binding
  endgenerate

/*
 * Asserts
 */
`ifndef SYNTHESIS
`ifndef VERILATOR
`ifndef VCS
  for (genvar i=0; i<N_HWPE; i++) begin : check_hwpe_size_asserts
    `HCI_SIZE_CHECK_ASSERTS_EXPLICIT_PARAM(`HCI_SIZE_PARAM(hwpe), hwpe[i]);
  end
  
  `HCI_SIZE_CHECK_ASSERTS_EXPLICIT_PARAM(`HCI_SIZE_PARAM(cores), cores[0]);
  `HCI_SIZE_CHECK_ASSERTS_EXPLICIT_PARAM(`HCI_SIZE_PARAM(mems) , mems[0] );

`endif
`endif
`endif;

endmodule : hci_interconnect
