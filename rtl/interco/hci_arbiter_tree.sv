/*
 * hci_arbiter_tree.sv
 * Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 * Francesco Conti <f.conti@unibo.it>
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
 * The `hci_arbiter_tree` is an arbitration tree designed using `hci_arbiter`
 * as the submodule. The hci_arbiter_tree is designed as a binary tree
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_arbiter_tree_params:
 * .. table:: **hci_arbiter_tree** design-time parameters.
 *
 *   +-----------------+-------------+-----------------------------+
 *   | **Name**        | **Default** | **Description**             |
 *   +-----------------+-------------+-----------------------------+
 *   | *NB_REQUESTS*   | 1           | Number of request ports     |
 *   +-----------------+-------------+-----------------------------+
 *   | *NB_CHAN*       | 16          | Number of ports per request |
 *   +-----------------+-------------+-----------------------------+
 *
 */

`include "hci_helpers.svh"

module hci_arbiter_tree
  import hci_package::*;
#(
  parameter int unsigned NB_REQUESTS = 1,
  parameter int unsigned NB_CHAN = 16,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(out)  = '0
)
(
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,
  input  hci_interconnect_ctrl_t ctrl_i,

  hci_core_intf.target    in    			   [0:NB_REQUESTS*NB_CHAN-1],
  hci_core_intf.initiator out                  [0:NB_CHAN-1]
);
  
  // number of levels in the arbitration tree
  localparam int unsigned NB_LEVELS = NB_REQUESTS > 1 ? $clog2(NB_REQUESTS) : 1;
  // maximum total number of arbiters in a single level
  localparam int unsigned MAX_ARBITERS_PER_LEVEL = (NB_REQUESTS + 1)/2;  
  
  localparam int unsigned DW = `HCI_SIZE_GET_DW(out);
  localparam int unsigned AW = `HCI_SIZE_GET_AW(out);
  localparam int unsigned BW = `HCI_SIZE_GET_BW(out);
  localparam int unsigned UW = `HCI_SIZE_GET_UW(out);
  localparam int unsigned IW = `HCI_SIZE_GET_IW(out);
  localparam int unsigned EW = `HCI_SIZE_GET_EW(out);
  localparam int unsigned EHW = `HCI_SIZE_GET_EHW(out);

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(arb_out) = '{
   DW:  `HCI_SIZE_GET_DW(out),
   AW:  `HCI_SIZE_GET_AW(out),
   BW:  `HCI_SIZE_GET_BW(out),
   UW:  `HCI_SIZE_GET_UW(out),
   IW:  `HCI_SIZE_GET_IW(out),
   EW:  `HCI_SIZE_GET_EW(out),
   EHW: `HCI_SIZE_GET_EHW(out)
  };
  
  `HCI_INTF_ARRAY(arb_out, clk_i, 0:NB_LEVELS*MAX_ARBITERS_PER_LEVEL*NB_CHAN-1);
  
  generate		
    for(genvar lvl=0; lvl<NB_LEVELS; lvl++) begin : arbiter_tree_levels
      localparam int unsigned quo = NB_REQUESTS / (1 << lvl);
      localparam int unsigned rem = (NB_REQUESTS % (1 << lvl)) ? 1 : 0;
      localparam int unsigned nb_arbiters = (quo + rem) / 2;
      
      for(genvar ii=0; ii< quo+rem; ii += 2) begin : arbiter_single_level
        // At the 0th level the primary inputs are used. in other levels intermediate input are used 
        if(lvl==0) begin : level_0
        // only arbiters are needed for atleast 2 requests together otherwise the remaining
        // requests could be bypassed as shown in the else statement
          localparam in_high_index = ii*NB_CHAN;
          localparam in_low_index  = in_high_index + NB_CHAN;
          localparam out_index  	 = lvl*MAX_ARBITERS_PER_LEVEL*NB_CHAN + (ii>>1)*NB_CHAN;
          if(ii < 2*nb_arbiters) begin : arbiter_path 
            hci_arbiter #(
              .NB_CHAN ( NB_CHAN )
            ) i_arbiter (
              .clk_i   ( clk_i                                          ),
              .rst_ni  ( rst_ni                                         ),
              .clear_i ( clear_i                                        ),
              .ctrl_i  ( ctrl_i                                         ),
              .in_high ( in[in_high_index : in_high_index + NB_CHAN-1]  ),
              .in_low  ( in[in_low_index  : in_low_index + NB_CHAN-1]   ),
              .out     ( arb_out[out_index: out_index + NB_CHAN-1]      )
            );
          end else begin : bypass
            for(genvar jj=0; jj<NB_CHAN; jj++) begin : assign_bankwise
              hci_core_assign i_no_arbiter_level_0 (
                .tcdm_target    ( in[ii*NB_CHAN+jj]       ),
                .tcdm_initiator ( arb_out[out_index + jj] )
              );
            end : assign_bankwise
          end : bypass
        end else begin : level_greater_than_0                
          localparam in_high_index = (lvl-1)*MAX_ARBITERS_PER_LEVEL*NB_CHAN + ii*NB_CHAN;
          localparam in_low_index  = in_high_index + NB_CHAN;
          localparam out_index  	 = lvl*MAX_ARBITERS_PER_LEVEL*NB_CHAN + (ii>>1)*NB_CHAN;
            
            if(ii < 2*nb_arbiters) begin : arbiter_path
              hci_arbiter #(
                .NB_CHAN ( NB_CHAN )
              ) i_arbiter (
                .clk_i   ( clk_i                                              ),
                .rst_ni  ( rst_ni                                             ),
                .clear_i ( clear_i                                            ),
                .ctrl_i  ( ctrl_i                                             ),
                .in_high ( arb_out[in_high_index: in_high_index + NB_CHAN -1] ),
                .in_low  ( arb_out[in_low_index : in_low_index + NB_CHAN - 1] ),
                .out     ( arb_out[out_index    : out_index + NB_CHAN-1]      )
              );
            end else begin : bypass
              for(genvar jj=0; jj<NB_CHAN; jj++) begin : assign_bankwise
                hci_core_assign i_no_arbiter (
                  .tcdm_target    ( arb_out[in_high_index + jj]),
                  .tcdm_initiator ( arb_out[out_index + jj]    )
                );
              end : assign_bankwise
            end : bypass 
        end : level_greater_than_0
      end : arbiter_single_level
    end : arbiter_tree_levels
    
    for(genvar jj=0; jj<NB_CHAN; jj++) begin: assign_output_bankwise
      hci_core_assign i_arbiter_output (
        .tcdm_target    ( arb_out[(NB_LEVELS-1)*MAX_ARBITERS_PER_LEVEL*NB_CHAN + jj] ),
        .tcdm_initiator ( out[jj]                                                    )
      ); 
    end
  endgenerate

endmodule // hci_arbiter_tree
