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
  parameter int unsigned N_HWPE  = 4,
  parameter int unsigned N_CORE  = 8,
  parameter int unsigned N_DMA   = 4,
  parameter int unsigned N_EXT   = 4,
  parameter int unsigned N_MEM   = 16,
  parameter int unsigned AWC     = 32,
  parameter int unsigned AWM     = 32,
  parameter int unsigned DW_LIC  = 32,
  parameter int unsigned DW_SIC  = 128,
  parameter int unsigned TS_BIT  = 21,
  parameter int unsigned IW      = N_HWPE+N_CORE+N_DMA+N_EXT,
  parameter int unsigned EXPFIFO = 0,
  parameter int unsigned DWH = hci_package::DEFAULT_DW,
  parameter int unsigned AWH = hci_package::DEFAULT_AW,
  parameter int unsigned BWH = hci_package::DEFAULT_BW,
  parameter int unsigned WWH = hci_package::DEFAULT_WW,
  parameter int unsigned OWH = AWH,
  parameter int unsigned SEL_LIC = 0
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,
  input  hci_interconnect_ctrl_t ctrl_i,
  hci_core_intf.slave            cores   [N_CORE-1:0],
  hci_core_intf.slave            dma     [N_DMA-1:0],
  hci_core_intf.slave            ext     [N_EXT-1:0],
  hci_mem_intf.master            mems    [N_MEM-1:0],
  hci_core_intf.slave            hwpe
);

  hci_core_intf all_except_hwpe [N_CORE+N_DMA+N_EXT-1:0] (
    .clk ( clk_i )
  );

  hci_mem_intf #(
    .IW ( IW )
  ) all_except_hwpe_mem [N_MEM-1:0] (
    .clk ( clk_i )
  );

  hci_mem_intf #(
    .IW ( IW )
  ) hwpe_mem [N_MEM-1:0] (
    .clk ( clk_i )
  );

  generate;
    if(SEL_LIC==0) begin : l1_interconnect_gen
      hci_log_interconnect #(
        .N_CH0  ( N_CORE              ),
        .N_CH1  ( N_DMA + N_EXT       ),
        .N_MEM  ( N_MEM               ),
        .IW     ( IW                  ),
        .AWC    ( AWC                 ),
        .AWM    ( AWM-2               ),
        .DW     ( DW_LIC              ),
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
        .DW     ( DW_LIC              )
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

  hci_hwpe_interconnect #(
    .FIFO_DEPTH  ( EXPFIFO ),
    .NB_OUT_CHAN ( N_MEM   ),
    .AWM         ( AWM     ),
    .DWH         ( DWH     ),
    .AWH         ( AWH     ),
    .BWH         ( BWH     ),
    .WWH         ( WWH     ),
    .OWH         ( OWH     )
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
