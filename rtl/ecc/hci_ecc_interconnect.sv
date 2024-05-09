/*
 * hci_ecc_interconnect.sv
 * Francesco Conti <f.conti@unibo.it>
 * Tobias Riedener <tobiasri@student.ethz.ch>
 * Luigi Ghionda <luigi.ghionda@studio.unibo.it>
 *
 * Copyright (C) 2019-2024 ETH Zurich, University of Bologna
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
 * .. table:: **hci_ecc_interconnect** design-time parameters.
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

module hci_ecc_interconnect
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
  parameter int unsigned CHUNK_SIZE = 32                      // Chunk size of data to be encoded separately (HWPE branch)
) (
  input logic                   clk_i               ,
  input logic                   rst_ni              ,
  input logic                   clear_i             ,
  input hci_interconnect_ctrl_t ctrl_i              ,
  XBAR_PERIPH_BUS.Slave         periph_hci_ecc      ,
  hci_core_intf.target           cores   [0:N_CORE-1]    ,
  hci_core_intf.target           dma     [0:N_DMA-1]     ,
  hci_core_intf.target           ext     [0:N_EXT-1]     ,
  hci_core_intf.initiator        mems    [0:N_MEM-1]     ,
  hci_core_intf.target           hwpe
);

  localparam int unsigned AWC = `HCI_SIZE_GET_AW(cores[0]);
  localparam int unsigned AWM = `HCI_SIZE_GET_AW(mems[0]);
  localparam int unsigned DW_LIC = `HCI_SIZE_GET_DW(cores[0]);
  localparam int unsigned BW_LIC = `HCI_SIZE_GET_BW(cores[0]);
  localparam int unsigned UW_LIC = `HCI_SIZE_GET_UW(cores[0]);
  localparam int unsigned DWH = `HCI_SIZE_GET_DW(hwpe);
  localparam int unsigned AWH = `HCI_SIZE_GET_AW(hwpe);
  localparam int unsigned BWH = `HCI_SIZE_GET_BW(hwpe);
  localparam int unsigned UWH = `HCI_SIZE_GET_UW(hwpe);
  localparam int unsigned EWH = `HCI_SIZE_GET_EW(hwpe);
  localparam int unsigned N_CHUNK = DWH / CHUNK_SIZE;

  hci_core_intf #(
    .UW ( UW_LIC )
  ) all_except_hwpe [0:N_CORE+N_DMA+N_EXT-1] (
    .clk ( clk_i )
  );

  hci_core_intf #(
    .IW ( IW     ),
    .UW ( UW_LIC )
  ) all_except_hwpe_mem [0:N_MEM-1] (
    .clk ( clk_i )
  );

  hci_core_intf #(
    .IW ( IW     ),
    .UW ( UW_LIC ),
    .AW ( AWM    )
  ) hwpe_mem [0:N_MEM-1] (
    .clk ( clk_i )
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
        .TS_BIT ( TS_BIT              )
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

      logic [$clog2(N_CHUNK):0] data_single_err;
      logic [$clog2(N_CHUNK):0] data_multi_err;
      logic                     meta_single_err;
      logic                     meta_multi_err;

      hci_core_intf #(
        .DW ( DWH ),
        .AW ( AWH ),
        .BW ( BWH ),
        .UW ( UWH ),
        .EW ( EWH )
      ) hwpe_dec (
        .clk( clk_i )
      );

      hci_ecc_dec #(
        .DW         ( DWH ),
        .CHUNK_SIZE ( CHUNK_SIZE )
      ) i_ecc_dec (
        .data_single_err_o ( data_single_err ),
        .data_multi_err_o  ( data_multi_err  ),
        .meta_single_err_o ( meta_single_err ),
        .meta_multi_err_o  ( meta_multi_err  ),
        .tcdm_target       ( hwpe            ),
        .tcdm_initiator    ( hwpe_dec        )
      );

      hci_router #(
        .FIFO_DEPTH  ( EXPFIFO ),
        .NB_OUT_CHAN ( N_MEM   )
      ) i_router (
        .clk_i   ( clk_i    ),
        .rst_ni  ( rst_ni   ),
        .clear_i ( clear_i  ),
        .in      ( hwpe_dec ),
        .out     ( hwpe_mem )
      );

      hci_arbiter #(
        .NB_CHAN ( N_MEM )
      ) i_arbiter (
        .clk_i   ( clk_i               ),
        .rst_ni  ( rst_ni              ),
        .clear_i ( clear_i             ),
        .ctrl_i  ( ctrl_i              ),
        .in_high ( all_except_hwpe_mem ),
        .in_low  ( hwpe_mem            ),
        .out     ( mems                )
      );

      hci_ecc_manager #(
        .N_CHUNK       ( N_CHUNK                ),
        .AW            ( AWC                    ),
        .DW            ( DW_LIC                 ),
        .BW            ( BW_LIC                 ),
        .IW            ( N_CORE + 1             )
      ) i_hci_ecc_manager (
        .clk_i                        ( clk_i           ),
        .rst_ni                       ( rst_ni          ),
        .periph                       ( periph_hci_ecc  ),
        .data_correctable_err_num_i   ( data_single_err ),
        .data_uncorrectable_err_num_i ( data_multi_err  ),
        .meta_correctable_err_i       ( meta_single_err ),
        .meta_uncorrectable_err_i     ( meta_multi_err  )
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
    end // cores_binding
    for(genvar ii=0; ii<N_EXT; ii++) begin: ext_binding
      hci_core_assign i_ext_assign (
        .tcdm_target    ( ext             [ii]        ),
        .tcdm_initiator ( all_except_hwpe [N_CORE+ii] )
      );
    end // ext_binding
    for(genvar ii=0; ii<N_DMA; ii++) begin: dma_binding
      hci_core_assign i_dma_assign (
        .tcdm_target    ( dma             [ii]              ),
        .tcdm_initiator ( all_except_hwpe [N_CORE+N_EXT+ii] )
      );
    end // dma_binding
  endgenerate

endmodule // hci_ecc_interconnect
