/*
 * hci_log_interconnect_l2.sv
 * Francesco Conti <f.conti@unibo.it>
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
 * Top level for the log interconnect, wrapped with HCI interfaces.
 */

import hci_package::*;

module hci_log_interconnect_l2 #(
  parameter int unsigned N_CH0  = 16,
  parameter int unsigned N_CH1  = 4,
  parameter int unsigned N_MEM  = 32,
  parameter int unsigned AWC    = hci_package::DEFAULT_AW,
  parameter int unsigned AWM    = hci_package::DEFAULT_AW,
  parameter int unsigned DW     = hci_package::DEFAULT_DW,
  parameter int unsigned BW     = hci_package::DEFAULT_BW,
  parameter int unsigned IW     = N_CH0+N_CH1,
  parameter int unsigned UW     = hci_package::DEFAULT_UW
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  hci_interconnect_ctrl_t ctrl_i,
  hci_core_intf.slave            cores [N_CH0+N_CH1-1:0],
  hci_mem_intf.master            mems  [N_MEM-1:0]
);

  // master side
  logic [N_CH0+N_CH1-1:0]             cores_req;
  logic [N_CH0+N_CH1-1:0] [AWC-3:0]   cores_add;
  logic [N_CH0+N_CH1-1:0]             cores_wen;
  logic [N_CH0+N_CH1-1:0] [UW+DW-1:0] cores_wdata;
  logic [N_CH0+N_CH1-1:0] [DW/BW-1:0] cores_be;
  logic [N_CH0+N_CH1-1:0]             cores_gnt;
  logic [N_CH0+N_CH1-1:0]             cores_r_valid;
  logic [N_CH0+N_CH1-1:0] [UW+DW-1:0] cores_r_rdata;
  // slave side
  logic [N_MEM-1:0]             mems_req;
  logic [N_MEM-1:0] [AWM-3:0]   mems_add;
  logic [N_MEM-1:0]             mems_wen;
  logic [N_MEM-1:0] [UW+DW-1:0] mems_wdata;
  logic [N_MEM-1:0] [DW/BW-1:0] mems_be;
  logic [N_MEM-1:0] [IW-1:0]    mems_ID;
  logic [N_MEM-1:0]             mems_gnt;
  logic [N_MEM-1:0] [UW+DW-1:0] mems_r_rdata;
  logic [N_MEM-1:0]             mems_r_valid;
  logic [N_MEM-1:0] [IW-1:0]    mems_r_ID;

  // interface unrolling
  generate
    for(genvar i=0; i<N_CH0+N_CH1; i++) begin : cores_unrolling
      assign cores_req   [i] = cores[i].req;
      assign cores_add   [i] = cores[i].add [AWC-1:2];
      assign cores_wen   [i] = cores[i].wen;
      assign cores_be    [i] = cores[i].be;
      if (UW > 0) begin
        assign cores_wdata [i] = {cores[i].user, cores[i].data};
        assign {cores[i].r_user, cores[i].r_data} = cores_r_rdata [i];
      end else begin
        assign cores_wdata [i] = cores[i].data;
        assign cores[i].r_data = cores_r_rdata [i];
        assign cores[i].r_user = '0;
      end
      assign cores[i].gnt     = cores_gnt     [i];
      assign cores[i].r_valid = cores_r_valid [i];
      assign cores[i].r_opc   = '0;
    end // cores_unrolling
    for(genvar i=0; i<N_MEM; i++) begin : mems_unrolling
      assign mems[i].req  = mems_req    [i];
      assign mems[i].add [AWC-3:2] = mems_add [i];
      assign mems[i].add [1:0]     = '0;
      assign mems[i].wen  = mems_wen    [i];
      assign mems[i].be   = mems_be     [i];
      assign mems[i].id   = mems_ID     [i];
      if (UW > 0) begin
        assign {mems[i].user, mems[i].data} = mems_wdata [i];
        assign mems_r_rdata [i] = {mems[i].r_user, mems[i].r_data};
      end else begin
        assign mems[i].data     = mems_wdata [i];
        assign mems[i].user     = '0;
        assign mems_r_rdata [i] = mems[i].r_data;
      end
      assign mems_gnt     [i] = mems[i].gnt;
      assign mems_r_ID    [i] = mems[i].r_id;

      always_ff @(posedge clk_i or negedge rst_ni)
      begin : resp_test_set
        if(~rst_ni) begin
          mems_r_valid[i] <= 1'b0;
        end
        else begin
          mems_r_valid[i] <= mems_req[i] & mems_gnt[i];
        end
      end

    end // mems_unrolling
  endgenerate

  // uses XBAR_TCDM from cluster_interconnect
  XBAR_L2 #(
    .N_CH0          ( N_CH0  ),
    .N_CH1          ( N_CH1  ),
    .N_SLAVE        ( N_MEM  ),
    .ID_WIDTH       ( IW     ),
    .ADDR_IN_WIDTH  ( AWC-2  ),
    .DATA_WIDTH     ( UW+DW  ),
    .BE_WIDTH       ( DW/BW  ),
    .ADDR_MEM_WIDTH ( AWM-2  )
  ) i_xbar_tcdm (
    .clk               ( clk_i             ),
    .rst_n             ( rst_ni            ),
    // .TCDM_arb_policy_i ( ctrl_i.arb_policy ),
    .data_req_i        ( cores_req         ),
    .data_add_i        ( cores_add         ),
    .data_wen_i        ( cores_wen         ),
    .data_wdata_i      ( cores_wdata       ),
    .data_be_i         ( cores_be          ),
    .data_gnt_o        ( cores_gnt         ),
    .data_r_valid_o    ( cores_r_valid     ),
    .data_r_rdata_o    ( cores_r_rdata     ),
    .data_req_o        ( mems_req          ),
    .data_add_o        ( mems_add          ),
    .data_wen_o        ( mems_wen          ),
    .data_wdata_o      ( mems_wdata        ),
    .data_be_o         ( mems_be           ),
    .data_ID_o         ( mems_ID           ),
    // .data_gnt_i        ( mems_gnt          ),
    .data_r_rdata_i    ( mems_r_rdata      ),
    .data_r_valid_i    ( mems_r_valid      ),
    .data_r_ID_i       ( mems_r_ID         )
  );

endmodule // hci_log_interconnect_l2
