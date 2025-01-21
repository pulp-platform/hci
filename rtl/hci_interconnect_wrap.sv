/*
 * hci_interconnect_wrap.sv
 *
 * Authors (hci_interconnect)
 * -Francesco Conti <f.conti@unibo.it>
 * -Tobias Riedener <tobiasri@student.ethz.ch>
 * -Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 *
 *
 * Authors (hci_interconnect_wrap)
 * -Luca Codeluppi <lcodelupp@student.ethz.ch>
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
`include "hci_helpers.svh"

module hci_interconnect_wrap
  import hci_package::*;
#(
  parameter int unsigned N_HWPE                           = 1                                              , // Number of HWPEs attached to the port
  parameter int unsigned N_CORE                           = 8                                              , // Number of Core ports
  parameter int unsigned N_DMA                            = 4                                              , // Number of DMA ports
  parameter int unsigned N_EXT                            = 4                                              , // Number of External ports
  parameter int unsigned N_MEM                            = 16                                             , // Number of Memory banks
  parameter int unsigned TS_BIT                           = 21                                             , // TEST_SET_BIT (for Log Interconnect)
  parameter int unsigned IW                               = N_HWPE+N_CORE+N_DMA+N_EXT                      , // ID Width
  parameter int unsigned EXPFIFO                          = 0                                              , // FIFO Depth for HWPE Interconnect
  parameter int unsigned SEL_LIC                          = 0                                              , // Log interconnect type selector
  parameter int unsigned ARBITER_MODE                     = 0                                              , // Chosen mode for the arbiter
  parameter int unsigned FILTER_WRITE_R_VALID[0:N_HWPE-1] = '{default: 0}                                  ,
  
  parameter int unsigned TOT_MEM_SIZE                     = 32                                             , // Total memory size (kB), this parameter is only used to define the default value for AW  
  parameter int unsigned HWPE_WIDTH                       = 4                                              , // Width of an HWPE wide-word (as a multiple of DW_cores), this parameter is only used to define the default value for DW_hwpe
  
  parameter int unsigned DW_cores                         = 32                                             ,
  parameter int unsigned AW_cores                         = $clog2(TOT_MEM_SIZE*1000)                      ,
  parameter int unsigned BW_cores                         = 8                                              ,
  parameter int unsigned UW_cores                         = 1                                              ,
  parameter int unsigned IW_cores                         = IW                                             ,
  parameter int unsigned EW_cores                         = 1                                              ,
  parameter int unsigned EHW_cores                        = 1                                              ,

  parameter int unsigned DW_mems                          = DW_cores                                             ,
  parameter int unsigned AW_mems                          = $clog2(TOT_MEM_SIZE*1000) - $clog2(N_MEM)      ,
  parameter int unsigned BW_mems                          = 8                                              ,
  parameter int unsigned UW_mems                          = 1                                              ,
  parameter int unsigned IW_mems                          = IW                                             ,
  parameter int unsigned EW_mems                          = 1                                              ,
  parameter int unsigned EHW_mems                         = 1                                              ,

  parameter int unsigned DW_hwpe                          = HWPE_WIDTH*DW_cores                            ,
  parameter int unsigned AW_hwpe                          = $clog2(TOT_MEM_SIZE*1000)                      ,
  parameter int unsigned BW_hwpe                          = 8                                              ,
  parameter int unsigned UW_hwpe                          = 1                                              ,
  parameter int unsigned IW_hwpe                          = IW                                             ,
  parameter int unsigned EW_hwpe                          = 1                                              ,
  parameter int unsigned EHW_hwpe                         = 1                                              ,

  parameter bit WAIVE_RQ3_ASSERT  = 1'b0,
  parameter bit WAIVE_RQ4_ASSERT  = 1'b0,
  parameter bit WAIVE_RSP3_ASSERT = 1'b0,
  parameter bit WAIVE_RSP5_ASSERT = 1'b0
) (
  input logic                clk_i,
  input logic                rst_ni,
  input logic                clear_i,

  input logic  [1:0]         arb_policy,
  input logic                invert_prio,
  input logic  [7:0]         low_prio_max_stall,

  input  logic [N_CORE-1:0]                         req_cores,
  output logic [N_CORE-1:0]                         gnt_cores,
  input  logic [N_CORE-1:0][AW_cores-1:0]           add_cores,
  input  logic [N_CORE-1:0]                         wen_cores,
  input  logic [N_CORE-1:0][DW_cores-1:0]           data_cores,
  input  logic [N_CORE-1:0][DW_cores/BW_cores-1:0]  be_cores,
  input  logic [N_CORE-1:0]                         r_ready_cores,
  input  logic [N_CORE-1:0][UW_cores-1:0]           user_cores,
  input  logic [N_CORE-1:0][IW_cores-1:0]           id_cores,
  output logic [N_CORE-1:0][DW_cores-1:0]           r_data_cores,
  output logic [N_CORE-1:0]                         r_valid_cores,
  output logic [N_CORE-1:0][UW_cores-1:0]           r_user_cores,
  output logic [N_CORE-1:0][IW_cores-1:0]           r_id_cores,
  output logic [N_CORE-1:0]                         r_opc_cores,
  input  logic [N_CORE-1:0][EW_cores-1:0]           ecc_cores,
  output logic [N_CORE-1:0][EW_cores-1:0]           r_ecc_cores,
  input  logic [N_CORE-1:0][EHW_cores-1:0]          ereq_cores,
  output logic [N_CORE-1:0][EHW_cores-1:0]          egnt_cores,
  output logic [N_CORE-1:0][EHW_cores-1:0]          r_evalid_cores,
  input  logic [N_CORE-1:0][EHW_cores-1:0]          r_eready_cores,

  input  logic [N_DMA-1:0]                          req_dma,
  output logic [N_DMA-1:0]                          gnt_dma,
  input  logic [N_DMA-1:0][AW_cores-1:0]            add_dma,
  input  logic [N_DMA-1:0]                          wen_dma,
  input  logic [N_DMA-1:0][DW_cores-1:0]            data_dma,
  input  logic [N_DMA-1:0][DW_cores/BW_cores-1:0]   be_dma,
  input  logic [N_DMA-1:0]                          r_ready_dma,
  input  logic [N_DMA-1:0][UW_cores-1:0]            user_dma,
  input  logic [N_DMA-1:0][IW_cores-1:0]            id_dma,
  output logic [N_DMA-1:0][DW_cores-1:0]            r_data_dma,
  output logic [N_DMA-1:0]                          r_valid_dma,
  output logic [N_DMA-1:0][UW_cores-1:0]            r_user_dma,
  output logic [N_DMA-1:0][IW_cores-1:0]            r_id_dma,
  output logic [N_DMA-1:0]                          r_opc_dma,
  input  logic [N_DMA-1:0][EW_cores-1:0]            ecc_dma,
  output logic [N_DMA-1:0][EW_cores-1:0]            r_ecc_dma,
  input  logic [N_DMA-1:0][EHW_cores-1:0]           ereq_dma,
  output logic [N_DMA-1:0][EHW_cores-1:0]           egnt_dma,
  output logic [N_DMA-1:0][EHW_cores-1:0]           r_evalid_dma,
  input  logic [N_DMA-1:0][EHW_cores-1:0]           r_eready_dma,

  input  logic [N_EXT-1:0]                          req_ext,
  output logic [N_EXT-1:0]                          gnt_ext,
  input  logic [N_EXT-1:0][AW_cores-1:0]            add_ext,
  input  logic [N_EXT-1:0]                          wen_ext,
  input  logic [N_EXT-1:0][DW_cores-1:0]            data_ext,
  input  logic [N_EXT-1:0][DW_cores/BW_cores-1:0]   be_ext,
  input  logic [N_EXT-1:0]                          r_ready_ext,
  input  logic [N_EXT-1:0][UW_cores-1:0]            user_ext,
  input  logic [N_EXT-1:0][IW_cores-1:0]            id_ext,
  output logic [N_EXT-1:0][DW_cores-1:0]            r_data_ext,
  output logic [N_EXT-1:0]                          r_valid_ext,
  output logic [N_EXT-1:0][UW_cores-1:0]            r_user_ext,
  output logic [N_EXT-1:0][IW_cores-1:0]            r_id_ext,
  output logic [N_EXT-1:0]                          r_opc_ext,
  input  logic [N_EXT-1:0][EW_cores-1:0]            ecc_ext,
  output logic [N_EXT-1:0][EW_cores-1:0]            r_ecc_ext,
  input  logic [N_EXT-1:0][EHW_cores-1:0]           ereq_ext,
  output logic [N_EXT-1:0][EHW_cores-1:0]           egnt_ext,
  output logic [N_EXT-1:0][EHW_cores-1:0]           r_evalid_ext,
  input  logic [N_EXT-1:0][EHW_cores-1:0]           r_eready_ext,

  input  logic [N_HWPE-1:0]                         req_hwpe,
  output logic [N_HWPE-1:0]                         gnt_hwpe,
  input  logic [N_HWPE-1:0][AW_hwpe-1:0]            add_hwpe,
  input  logic [N_HWPE-1:0]                         wen_hwpe,
  input  logic [N_HWPE-1:0][DW_hwpe-1:0]            data_hwpe,
  input  logic [N_HWPE-1:0][DW_hwpe/BW_hwpe-1:0]    be_hwpe,
  input  logic [N_HWPE-1:0]                         r_ready_hwpe,
  input  logic [N_HWPE-1:0][UW_hwpe-1:0]            user_hwpe,
  input  logic [N_HWPE-1:0][IW_hwpe-1:0]            id_hwpe,
  output logic [N_HWPE-1:0][DW_hwpe-1:0]            r_data_hwpe,
  output logic [N_HWPE-1:0]                         r_valid_hwpe,
  output logic [N_HWPE-1:0][UW_hwpe-1:0]            r_user_hwpe,
  output logic [N_HWPE-1:0][IW_hwpe-1:0]            r_id_hwpe,
  output logic [N_HWPE-1:0]                         r_opc_hwpe,
  input  logic [N_HWPE-1:0][EW_hwpe-1:0]            ecc_hwpe,
  output logic [N_HWPE-1:0][EW_hwpe-1:0]            r_ecc_hwpe,
  input  logic [N_HWPE-1:0][EHW_hwpe-1:0]           ereq_hwpe,
  output logic [N_HWPE-1:0][EHW_hwpe-1:0]           egnt_hwpe,
  output logic [N_HWPE-1:0][EHW_hwpe-1:0]           r_evalid_hwpe,
  input  logic [N_HWPE-1:0][EHW_hwpe-1:0]           r_eready_hwpe,

  output logic [N_MEM-1:0]                          req_mems,
  input  logic [N_MEM-1:0]                          gnt_mems,
  output logic [N_MEM-1:0][AW_mems-1:0]             add_mems,
  output logic [N_MEM-1:0]                          wen_mems,
  output logic [N_MEM-1:0][DW_mems-1:0]             data_mems,
  output logic [N_MEM-1:0][DW_mems/BW_mems-1:0]     be_mems,
  output logic [N_MEM-1:0]                          r_ready_mems,
  output logic [N_MEM-1:0][UW_mems-1:0]             user_mems,
  output logic [N_MEM-1:0][IW_mems-1:0]             id_mems,
  input  logic [N_MEM-1:0][DW_mems-1:0]             r_data_mems,
  input  logic [N_MEM-1:0]                          r_valid_mems,
  input  logic [N_MEM-1:0][UW_mems-1:0]             r_user_mems,
  input  logic [N_MEM-1:0][IW_mems-1:0]             r_id_mems,
  input  logic [N_MEM-1:0]                          r_opc_mems,
  output logic [N_MEM-1:0][EW_mems-1:0]             ecc_mems,
  input  logic [N_MEM-1:0][EW_mems-1:0]             r_ecc_mems,
  output logic [N_MEM-1:0][EHW_mems-1:0]            ereq_mems,
  input  logic [N_MEM-1:0][EHW_mems-1:0]            egnt_mems,
  input  logic [N_MEM-1:0][EHW_mems-1:0]            r_evalid_mems,
  output logic [N_MEM-1:0][EHW_mems-1:0]            r_eready_mems
);
  // local parameters
  localparam hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(cores) = '{    // CORE + DMA + EXT parameters
    DW  : DW_cores,
    AW  : AW_cores,
    BW  : BW_cores,
    UW  : UW_cores,
    IW  : IW_cores,
    EW  : EW_cores,
    EHW : EHW_cores
  };

  localparam hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(mems) = '{     // Bank parameters
    DW  : DW_mems,
    AW  : AW_mems,
    BW  : BW_mems,
    UW  : UW_mems,
    IW  : IW_mems,
    EW  : EW_mems,
    EHW : EHW_mems
  };

  localparam hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(hwpe) = '{     // HWPE parameters
    DW  : DW_hwpe,
    AW  : AW_hwpe,
    BW  : BW_hwpe,
    UW  : UW_hwpe,
    IW  : IW_hwpe,
    EW  : EW_hwpe,
    EHW : EHW_hwpe
  };

  // interfaces
  hci_core_intf #(
      .DW(HCI_SIZE_hwpe.DW),
      .AW(HCI_SIZE_hwpe.AW),
      .BW(HCI_SIZE_hwpe.BW),
      .UW(HCI_SIZE_hwpe.UW),
      .IW(HCI_SIZE_hwpe.IW),
      .EW(HCI_SIZE_hwpe.EW),
      .EHW(HCI_SIZE_hwpe.EHW)
    ) hwpe_intc [0:N_HWPE-1] (
      .clk(clk_i)
    );

  hci_core_intf #(
      .DW(HCI_SIZE_cores.DW),
      .AW(HCI_SIZE_cores.AW),
      .BW(HCI_SIZE_cores.BW),
      .UW(HCI_SIZE_cores.UW),
      .IW(HCI_SIZE_cores.IW),
      .EW(HCI_SIZE_cores.EW),
      .EHW(HCI_SIZE_cores.EHW)
    ) all_except_hwpe [0:N_CORE+N_DMA+N_EXT-1] (
      .clk(clk_i)
    );

  hci_core_intf #(
      .DW(HCI_SIZE_mems.DW),
      .AW(HCI_SIZE_mems.AW),
      .BW(HCI_SIZE_mems.BW),
      .UW(HCI_SIZE_mems.UW),
      .IW(HCI_SIZE_mems.IW),
      .EW(HCI_SIZE_mems.EW),
      .EHW(HCI_SIZE_mems.EHW)
    ) intc_mem_wiring [0:N_MEM-1] (
      .clk(clk_i)
    );

  // bindings
  generate
    for(genvar ii=0; ii<N_CORE; ii++) begin: cores_binding
      assign all_except_hwpe[ii].req      = req_cores[ii];
      assign gnt_cores      [ii]          = all_except_hwpe[ii].gnt;
      assign all_except_hwpe[ii].add      = add_cores[ii];
      assign all_except_hwpe[ii].wen      = wen_cores      [ii];
      assign all_except_hwpe[ii].data     = data_cores     [ii];
      assign all_except_hwpe[ii].be       = be_cores       [ii];
      assign all_except_hwpe[ii].r_ready  = r_ready_cores  [ii];  
      assign all_except_hwpe[ii].user     = user_cores     [ii]; 
      assign all_except_hwpe[ii].id       = id_cores       [ii]; 
      assign r_data_cores   [ii]          = all_except_hwpe[ii].r_data;
      assign r_valid_cores  [ii]          = all_except_hwpe[ii].r_valid;
      assign r_user_cores   [ii]          = all_except_hwpe[ii].r_user;
      assign r_id_cores     [ii]          = all_except_hwpe[ii].r_id;
      assign r_opc_cores    [ii]          = all_except_hwpe[ii].r_opc;
      assign all_except_hwpe[ii].ecc      = ecc_cores      [ii];
      assign r_ecc_cores    [ii]          = all_except_hwpe[ii].r_ecc;
      assign all_except_hwpe[ii].ereq     = ereq_cores     [ii];
      assign egnt_cores     [ii]          = all_except_hwpe[ii].egnt;
      assign r_evalid_cores [ii]          = all_except_hwpe[ii].r_evalid;
      assign all_except_hwpe[ii].r_eready = r_eready_cores [ii];
    end
  endgenerate

  generate
    for(genvar ii=N_CORE; ii<N_CORE+N_DMA; ii++) begin: dma_binding
      assign all_except_hwpe[ii].req      = req_dma        [ii];
      assign gnt_dma        [ii]          = all_except_hwpe[ii].gnt;
      assign all_except_hwpe[ii].add      = add_dma        [ii];
      assign all_except_hwpe[ii].wen      = wen_dma        [ii];
      assign all_except_hwpe[ii].data     = data_dma       [ii];
      assign all_except_hwpe[ii].be       = be_dma         [ii];
      assign all_except_hwpe[ii].r_ready  = r_ready_dma    [ii];  
      assign all_except_hwpe[ii].user     = user_dma       [ii]; 
      assign all_except_hwpe[ii].id       = id_dma         [ii]; 
      assign r_data_dma     [ii]          = all_except_hwpe[ii].r_data;
      assign r_valid_dma    [ii]          = all_except_hwpe[ii].r_valid;
      assign r_user_dma     [ii]          = all_except_hwpe[ii].r_user;
      assign r_id_dma       [ii]          = all_except_hwpe[ii].r_id;
      assign r_opc_dma      [ii]          = all_except_hwpe[ii].r_opc;
      assign all_except_hwpe[ii].ecc      = ecc_dma        [ii];
      assign r_ecc_dma      [ii]          = all_except_hwpe[ii].r_ecc;
      assign all_except_hwpe[ii].ereq     = ereq_dma       [ii];
      assign egnt_dma       [ii]          = all_except_hwpe[ii].egnt;
      assign r_evalid_dma   [ii]          = all_except_hwpe[ii].r_evalid;
      assign all_except_hwpe[ii].r_eready = r_eready_dma   [ii];
    end
  endgenerate


  generate
    for(genvar ii=N_CORE+N_DMA; ii<N_CORE+N_DMA+N_EXT; ii++) begin: ext_binding
      assign all_except_hwpe[ii].req      = req_ext        [ii];
      assign gnt_ext        [ii]          = all_except_hwpe[ii].gnt;
      assign all_except_hwpe[ii].add      = add_ext        [ii];
      assign all_except_hwpe[ii].wen      = wen_ext        [ii];
      assign all_except_hwpe[ii].data     = data_ext       [ii];
      assign all_except_hwpe[ii].be       = be_ext         [ii];
      assign all_except_hwpe[ii].r_ready  = r_ready_ext    [ii];  
      assign all_except_hwpe[ii].user     = user_ext       [ii]; 
      assign all_except_hwpe[ii].id       = id_ext         [ii]; 
      assign r_data_ext     [ii]          = all_except_hwpe[ii].r_data;
      assign r_valid_ext    [ii]          = all_except_hwpe[ii].r_valid;
      assign r_user_ext     [ii]          = all_except_hwpe[ii].r_user;
      assign r_id_ext       [ii]          = all_except_hwpe[ii].r_id;
      assign r_opc_ext      [ii]          = all_except_hwpe[ii].r_opc;
      assign all_except_hwpe[ii].ecc      = ecc_ext        [ii];
      assign r_ecc_ext      [ii]          = all_except_hwpe[ii].r_ecc;
      assign all_except_hwpe[ii].ereq     = ereq_ext       [ii];
      assign egnt_ext       [ii]          = all_except_hwpe[ii].egnt;
      assign r_evalid_ext   [ii]          = all_except_hwpe[ii].r_evalid;
      assign all_except_hwpe[ii].r_eready = r_eready_ext   [ii];
    end
  endgenerate

  generate
    for(genvar ii=0; ii<N_HWPE; ii++) begin: hwpe_binding
      assign hwpe_intc     [ii].req      = req_hwpe      [ii];
      assign gnt_hwpe      [ii]          = hwpe_intc     [ii].gnt;
      assign hwpe_intc     [ii].add      = add_hwpe      [ii];
      assign hwpe_intc     [ii].wen      = wen_hwpe      [ii];
      assign hwpe_intc     [ii].data     = data_hwpe     [ii];
      assign hwpe_intc     [ii].be       = be_hwpe       [ii];
      assign hwpe_intc     [ii].r_ready  = r_ready_hwpe  [ii];  
      assign hwpe_intc     [ii].user     = user_hwpe     [ii]; 
      assign hwpe_intc     [ii].id       = id_hwpe       [ii]; 
      assign r_data_hwpe   [ii]          = hwpe_intc     [ii].r_data;
      assign r_valid_hwpe  [ii]          = hwpe_intc     [ii].r_valid;
      assign r_user_hwpe   [ii]          = hwpe_intc     [ii].r_user;
      assign r_id_hwpe     [ii]          = hwpe_intc     [ii].r_id;
      assign r_opc_hwpe    [ii]          = hwpe_intc     [ii].r_opc;
      assign hwpe_intc     [ii].ecc      = ecc_hwpe      [ii];
      assign r_ecc_hwpe    [ii]          = hwpe_intc     [ii].r_ecc;
      assign hwpe_intc     [ii].ereq     = ereq_hwpe     [ii];
      assign egnt_hwpe     [ii]          = hwpe_intc     [ii].egnt;
      assign r_evalid_hwpe [ii]          = hwpe_intc     [ii].r_evalid;
      assign hwpe_intc     [ii].r_eready = r_eready_hwpe [ii];
    end
  endgenerate

  generate
    for(genvar ii=0; ii<N_MEM; ii++) begin: mems_binding
      assign req_mems       [ii]          = intc_mem_wiring  [ii].req;
      assign intc_mem_wiring[ii].gnt      = gnt_mems         [ii];
      assign add_mems       [ii]          = intc_mem_wiring  [ii].add;
      assign wen_mems       [ii]          = intc_mem_wiring  [ii].wen;
      assign data_mems      [ii]          = intc_mem_wiring  [ii].data;
      assign be_mems        [ii]          = intc_mem_wiring  [ii].be;
      assign r_ready_mems   [ii]          = intc_mem_wiring  [ii].r_ready;  
      assign user_mems      [ii]          = intc_mem_wiring  [ii].user; 
      assign id_mems        [ii]          = intc_mem_wiring  [ii].id; 
      assign intc_mem_wiring[ii].r_data   = r_data_mems      [ii];
      assign intc_mem_wiring[ii].r_valid  = r_valid_mems     [ii];
      assign intc_mem_wiring[ii].r_user   = r_user_mems      [ii];
      assign intc_mem_wiring[ii].r_id     = r_id_mems        [ii];
      assign intc_mem_wiring[ii].r_opc    = r_opc_mems       [ii];
      assign ecc_mems       [ii]          = intc_mem_wiring  [ii].ecc;
      assign intc_mem_wiring[ii].r_ecc    = r_ecc_mems       [ii];
      assign ereq_mems      [ii]          = intc_mem_wiring  [ii].ereq;
      assign intc_mem_wiring[ii].egnt     = egnt_mems        [ii];
      assign intc_mem_wiring[ii].r_evalid = r_evalid_mems    [ii];
      assign r_eready_mems  [ii]          = intc_mem_wiring  [ii].r_eready;
    end
  endgenerate
  
  hci_interconnect_ctrl_t ctrl_i;
  assign ctrl_i.arb_policy         = arb_policy;
  assign ctrl_i.invert_prio        = invert_prio;
  assign ctrl_i.low_prio_max_stall = low_prio_max_stall;
  
  // hci
  hci_interconnect #(
    .N_HWPE                             ( N_HWPE                           ), 
    .N_CORE                             ( N_CORE                           ), 
    .N_DMA                              ( N_DMA                            ), 
    .N_EXT                              ( N_EXT                            ), 
    .N_MEM                              ( N_MEM                            ), 
    .TS_BIT                             ( TS_BIT                           ), 
    .IW                                 ( IW                               ), 
    .EXPFIFO                            ( EXPFIFO                          ), 
    .SEL_LIC                            ( SEL_LIC                          ), 
    .ARBITER_MODE                       ( ARBITER_MODE                     ), 
    .FILTER_WRITE_R_VALID               ( FILTER_WRITE_R_VALID             ),
    .`HCI_SIZE_PARAM(cores)             ( `HCI_SIZE_PARAM(cores)           ),
    .`HCI_SIZE_PARAM(mems)              ( `HCI_SIZE_PARAM(mems)            ),
    .`HCI_SIZE_PARAM(hwpe)              ( `HCI_SIZE_PARAM(hwpe)            ),
    .WAIVE_RQ3_ASSERT                   ( WAIVE_RQ3_ASSERT                 ),
    .WAIVE_RQ4_ASSERT                   ( WAIVE_RQ4_ASSERT                 ),
    .WAIVE_RSP3_ASSERT                  ( WAIVE_RSP3_ASSERT                ),
    .WAIVE_RSP5_ASSERT                  ( WAIVE_RSP5_ASSERT                ) 
  ) i_hci_interconnect (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .clear_i(clear_i),
      .ctrl_i(ctrl_i),
      .cores(all_except_hwpe[0:N_CORE-1]),
      .dma(all_except_hwpe[N_CORE:N_CORE+N_DMA-1]),
      .ext(all_except_hwpe[N_CORE+N_DMA:N_CORE+N_DMA+N_EXT-1]),
      .mems(intc_mem_wiring),
      .hwpe(hwpe_intc)
  );

endmodule