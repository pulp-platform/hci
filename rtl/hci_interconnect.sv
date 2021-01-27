/*
 * hci_interconnect.sv
 * Francesco Conti <f.conti@unibo.it>
 * Tobias Riedener <tobiasri@student.ethz.ch>
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
 * Top level for the TCDM heterogeneous interconnect.
 */

import hci_package::*;

module hci_interconnect #(
  parameter int unsigned N_HWPE  = 4                        , // Number of HWPEs attached to the port
  parameter int unsigned N_CORE  = 8                        , // Number of Core ports
  parameter int unsigned N_DMA   = 4                        , // Number of DMA ports
  parameter int unsigned N_EXT   = 4                        , // Number of External ports
  parameter int unsigned N_MEM   = 16                       , // Number of Memory banks
  parameter int unsigned AWC     = hci_package::DEFAULT_AW  , // Address Width Core   (slave ports)
  parameter int unsigned AWM     = hci_package::DEFAULT_AW  , // Address width memory (master ports)
  parameter int unsigned DW_LIC  = hci_package::DEFAULT_DW  , // Data Width for Log Interconnect
  parameter int unsigned BW_LIC  = hci_package::DEFAULT_BW  , // Byte Width for Log Interconnect
  parameter int unsigned UW_LIC  = hci_package::DEFAULT_UW  , // User Width for Log Interconnect
  parameter int unsigned DW_SIC  = 128                      , // UNUSED!!!
  parameter int unsigned TS_BIT  = 21                       , // TEST_SET_BIT (for Log Interconnect)
  parameter int unsigned IW      = N_HWPE+N_CORE+N_DMA+N_EXT, // ID Width
  parameter int unsigned EXPFIFO = 0                        , // FIFO Depth for HWPE Interconnect
  parameter int unsigned DWH     = hci_package::DEFAULT_DW  , // Data Width for HWPE Interconnect
  parameter int unsigned AWH     = hci_package::DEFAULT_AW  , // Address Width for HWPE Interconnect
  parameter int unsigned BWH     = hci_package::DEFAULT_BW  , // Byte Width for HWPE Interconnect
  parameter int unsigned WWH     = hci_package::DEFAULT_WW  , // Word Width for HWPE Interconnect
  parameter int unsigned OWH     = AWH                      , // Offset Width for HWPE Interconnect
  parameter int unsigned UWH     = hci_package::DEFAULT_UW  , // User Width for HWPE Interconnect
  parameter int unsigned SEL_LIC = 0                          // Log interconnect type selector
) (
  input logic                   clk_i               ,
  input logic                   rst_ni              ,
  input logic                   clear_i             ,
  input hci_interconnect_ctrl_t ctrl_i              ,
  hci_core_intf.slave           cores   [N_CORE-1:0],
  hci_core_intf.slave           dma     [N_DMA-1:0] ,
  hci_core_intf.slave           ext     [N_EXT-1:0] ,
  hci_mem_intf.master           mems    [N_MEM-1:0] ,
  hci_core_intf.slave           hwpe
);

  hci_core_intf #(
    .UW ( UW_LIC )
  ) all_except_hwpe [N_CORE+N_DMA+N_EXT-1:0] (
    .clk ( clk_i )
  );

  hci_mem_intf #(
    .IW ( IW     ),
    .UW ( UW_LIC )
  ) all_except_hwpe_mem [N_MEM-1:0] (
    .clk ( clk_i )
  );

  hci_mem_intf #(
    .IW ( IW     ),
    .UW ( UW_LIC )
  ) hwpe_mem [N_MEM-1:0] (
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
    if(N_HWPE > 0) begin: hwpe_interconnect_gen

      hci_hwpe_interconnect #(
        .FIFO_DEPTH  ( EXPFIFO ),
        .NB_OUT_CHAN ( N_MEM   ),
        .AWM         ( AWM     ),
        .DWH         ( DWH     ),
        .AWH         ( AWH     ),
        .BWH         ( BWH     ),
        .WWH         ( WWH     ),
        .OWH         ( OWH     ),
        .UWH         ( UWH     )
      ) i_hwpe_interconnect (
        .clk_i   ( clk_i    ),
        .rst_ni  ( rst_ni   ),
        .clear_i ( clear_i  ),
        .in      ( hwpe     ),
        .out     ( hwpe_mem )
      );

      hci_shallow_interconnect #(
        .NB_CHAN ( N_MEM )
      ) i_shallow_interconnect (
        .clk_i   ( clk_i               ),
        .rst_ni  ( rst_ni              ),
        .clear_i ( clear_i             ),
        .ctrl_i  ( ctrl_i              ),
        .in_high ( all_except_hwpe_mem ),
        .in_low  ( hwpe_mem            ),
        .out     ( mems                )
      );

    end
    else begin: no_hwpe_interconnect_gen

      for(genvar ii=0; ii<N_MEM; ii++) begin: no_hwpe_mem_binding
        hci_mem_assign i_mem_assign (
          .tcdm_slave  ( all_except_hwpe_mem [ii] ),
          .tcdm_master ( mems                [ii] )
        );
      end

    end
  endgenerate

  generate
    for(genvar ii=0; ii<N_CORE; ii++) begin: cores_binding
      hci_core_assign i_cores_assign (
        .tcdm_slave  ( cores           [ii] ),
        .tcdm_master ( all_except_hwpe [ii] )
      );
    end // cores_binding
    for(genvar ii=0; ii<N_EXT; ii++) begin: ext_binding
      hci_core_assign i_ext_assign (
        .tcdm_slave  ( ext             [ii]        ),
        .tcdm_master ( all_except_hwpe [N_CORE+ii] )
      );
    end // ext_binding
    for(genvar ii=0; ii<N_DMA; ii++) begin: dma_binding
      hci_core_assign i_dma_assign (
        .tcdm_slave  ( dma             [ii]              ),
        .tcdm_master ( all_except_hwpe [N_CORE+N_EXT+ii] )
      );
    end // dma_binding
  endgenerate

endmodule // hci_interconnect
