/* 
 * hci_router.sv
 * Francesco Conti <f.conti@unibo.it>
 * Tobias Riedener <tobiasri@student.ethz.ch>
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
 * The `hci_router` is a specialized router used to build interconnects in a
 * heterogeneous PULP cluster.
 * It takes as input a single `in` HCI channel of width `DWH` (typically "wide",
 * i.e., greater than 32 bits) that gets routed *without arbitration* to `DWH/32`
 * adjacent `out` targets from a set of `NB_OUT_CHAN` `out` channels
 * (typically, one per memory bank).
 * Routing is performed by splitting the address of the `DWH`-bit wide word in an
 * *index* (bits `[$clog2(DWH)+2-1:2]`) and an *offset* part (bits `[AWH:$clog2(DWH)+2]`).
 * The index is used to select which `out` targets need to propagate the request,
 * while the offset is used to compute the target-level address for each `out` channel
 * -- since word interleaving is assumed, the same address is generally propagated
 * to all targeted `out` channels.
 * However, if `index > NB_OUT_CHAN-DWH/32`, then the set of selected targets
 * "wraps around": the first `NB_OUT_CHAN-DWH/32-index` `out` channels are 
 * activated, propagating as address the offset+4.
 * See https://ieeexplore.ieee.org/document/9903915 Sec. II-A (open-access) for details
 * (the router is called a *shallow* router).
 *
 * .. tabularcolumns:: |l|l|J|
 * .. _hci_router_params:
 * .. table:: **hci_router** design-time parameters.
 *
 *   +---------------------+-------------+-------------------------------------------------------------------+
 *   | **Name**            | **Default** | **Description**                                                   |
 *   +---------------------+-------------+-------------------------------------------------------------------+
 *   | *FIFO_DEPTH*        | 0           | If > 0, insert a HCI FIFO of this depth after the input channel.  |
 *   +---------------------+-------------+-------------------------------------------------------------------+
 *   | *NB_OUT_CHAN*       | 8           | Number of output HCI channel                                      |
 *   +---------------------+-------------+-------------------------------------------------------------------+
 */

`include "hci_helpers.svh"

module hci_router
#(
  parameter int unsigned FIFO_DEPTH  = 0,
  parameter int unsigned NB_OUT_CHAN = 8
)
(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic clear_i,

  hci_core_intf.target    in,
  hci_core_intf.initiator out [0:NB_OUT_CHAN-1]
);

  localparam int unsigned DWH = `HCI_SIZE_GET_DW(in);
  localparam int unsigned AWH = `HCI_SIZE_GET_AW(in);
  localparam int unsigned BWH = `HCI_SIZE_GET_BW(in);
  localparam int unsigned UWH = `HCI_SIZE_GET_UW(in);
  localparam int unsigned EHW = `HCI_SIZE_GET_EHW(in);
  localparam int unsigned AWM = `HCI_SIZE_GET_AW(out[0]);

  //There is only one input port, but with variable data width.
  //NB_IN_CHAN states, to how many standard (32-bit) ports the input port is equivalent
  localparam int unsigned NB_IN_CHAN  = DWH / 32;
  //Word-interleaved scheme:
  // - First bits of requested address are shared
  // - Lowest 2 bits are byte offset within a DWORD -> ignored
  // - The bits inbetween designate the selected bank
  localparam int unsigned LSB_COMMON_ADDR = $clog2(NB_OUT_CHAN) + 2;
  localparam int unsigned AWC = AWM+$clog2(NB_OUT_CHAN);

  logic [$clog2(NB_OUT_CHAN)-1:0] bank_offset_s;
  logic [NB_IN_CHAN-1:0] virt_in_gnt;
  logic [NB_IN_CHAN-1:0] virt_in_rvalid;
  logic                  virt_in_gnt_0_q;

  hci_core_intf #(
    .DW  ( DWH ),
    .AW  ( AWC ),
    .BW  ( BWH ),
    .UW  ( UWH ),
    .EHW ( EHW )
  ) postfifo (
    .clk ( clk_i )
  );

  // using the interface from hwpe-stream here
  hci_core_intf #(
    .DW  ( 32 ),
    .AW  ( 32 ),
    .BW  ( 4  ),
    .UW  ( 0  ),
    .IW  ( 0  ),
    .EW  ( 0  ),
    .EHW ( 0  )
`ifndef SYNTHESIS
    ,
    .WAIVE_RQ3_ASSERT ( 1'b1 ), // virt_in is grant-less by construction
    .WAIVE_RQ4_ASSERT ( 1'b1 )
`endif
  ) virt_in  [0:NB_IN_CHAN-1] (
    .clk ( clk_i )
  );
  hci_core_intf #(
    .DW  ( 32 ),
    .AW  ( 32 ),
    .BW  ( 4  ),
    .UW  ( 0  ),
    .IW  ( 0  ),
    .EW  ( 0  ),
    .EHW ( 0  )
  ) virt_out [0:NB_OUT_CHAN-1] (
    .clk ( clk_i )
  );

  // aux signal for r_valid generation
  logic [NB_OUT_CHAN-1:0] out_r_valid;

  // propagate handshake + address only from port 0
  generate

    // FIFOs for HWPE ports
    if(FIFO_DEPTH == 0) begin: no_fifo_gen
      hci_core_assign i_no_fifo (
        .tcdm_target    ( in            ),
        .tcdm_initiator ( postfifo      )
      );
    end // no_fifo_gen
    else begin: fifo_gen
      hci_core_fifo #(
        .FIFO_DEPTH ( FIFO_DEPTH ),
        .DW         ( DWH        ),
        .BW         ( AWH        ),
        .AW         ( BWH        ),
        .UW         ( UWH        )
      ) i_fifo (
        .clk_i          ( clk_i         ),
        .rst_ni         ( rst_ni        ),
        .clear_i        ( clear_i       ),
        .flags_o        (               ),
        .tcdm_target    ( in            ),
        .tcdm_initiator ( postfifo      )
      );
    end // fifo_gen

    // unimplemented user bits = 0
    assign postfifo.r_user = '0;

    // unimplemented id bits = 0
    assign postfifo.r_id = '0;

    // unimplemented ECC bits = 0
    assign postfifo.r_ecc = '0;

    // unimplemented operation code = 0
    assign postfifo.r_opc = '0;
    
    assign bank_offset_s = postfifo.add[LSB_COMMON_ADDR-1:2];

    for(genvar ii=0; ii<NB_IN_CHAN; ii++) begin : virt_in_bind

      assign virt_in[ii].req      = postfifo.req;
      assign virt_in[ii].wen      = postfifo.wen;
      assign virt_in[ii].be       = postfifo.be[ii*4+3:ii*4];
      assign virt_in[ii].data     = postfifo.data[ii*32+31:ii*32];
      assign postfifo.r_data[ii*32+31:ii*32]  = virt_in[ii].r_data;
      assign virt_in[ii].user     = postfifo.user;
      assign virt_in[ii].ecc      = postfifo.ecc;
      assign virt_in[ii].id       = postfifo.id;
      assign virt_in[ii].ereq     = postfifo.ereq;
      assign virt_in[ii].r_eready = postfifo.r_eready;
      // in a word-interleaved scheme, the internal word-address is given
      // by the highest set of bits in postfifo[0].add, plus the bank-level offset
      always_comb
      begin : address_generation
        if(bank_offset_s + ii >= NB_OUT_CHAN)
          virt_in[ii].add = {postfifo.add[AWC-1:LSB_COMMON_ADDR] + 1, 2'b0};
        else
          virt_in[ii].add = {postfifo.add[AWC-1:LSB_COMMON_ADDR], 2'b0};
      end // address_generation
      
      assign virt_in[ii].r_ready = postfifo.r_ready;
      assign virt_in_gnt[ii] = virt_in[ii].gnt;
      assign virt_in_rvalid[ii] = virt_in[ii].r_valid;

    end // virt_in_bind

    // register REQ&GNT --> TCDM protocol assumes that (post FIFO)
    // the GNT and R_VALID are exactly asserted in consecutive
    // cycles
    always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        virt_in_gnt_0_q <= '0;
      end
      else if(clear_i) begin
        virt_in_gnt_0_q <= '0;
      end
      else begin
        virt_in_gnt_0_q <= virt_in_gnt[0] & virt_in[0].req;
      end
    end
    
    // only propagate GNT for those initiators that have asserted REQ
    assign postfifo.gnt     = virt_in_gnt[0] & virt_in[0].req;
    // filter R_VALID with registered GNT
    assign postfifo.r_valid = virt_in_rvalid[0] & virt_in_gnt_0_q;

    for(genvar ii=0; ii<NB_OUT_CHAN; ii++) 
    begin : virt_out_bind
      assign out[ii].req  = virt_out[ii].req;
      assign out[ii].wen  = virt_out[ii].wen;
      assign out[ii].be   = virt_out[ii].be;
      assign out[ii].data = virt_out[ii].data;
      assign out[ii].add  = virt_out[ii].add;
      assign virt_out[ii].gnt     = out[ii].gnt;
      assign virt_out[ii].r_valid = out_r_valid[ii];
      assign virt_out[ii].r_data  = out[ii].r_data;

      // unimplemented user bits = 0
      assign out[ii].user = '0;

      // unimplemented id bits = 0
      assign out[ii].id = '0;

      // unimplemented ecc bits = 0
      assign out[ii].ecc = '0;
    end // virt_out_bind

  endgenerate

  //Re-order the interfaces such that the port requesting the lowest bits of data
  //are located at the correct bank offset
  hci_router_reorder #(
    .NB_IN_CHAN  ( NB_IN_CHAN  ),
    .NB_OUT_CHAN ( NB_OUT_CHAN )
  ) i_reorder (
    .clk_i   ( clk_i         ),
    .rst_ni  ( rst_ni        ),
    .clear_i ( clear_i       ),
    .order_i ( bank_offset_s ), 
    .in      ( virt_in       ),
    .out     ( virt_out      )
  );

/*
 * ECC Handshake signals
 */
  if(EHW > 0) begin : ecc_handshake_gen
    assign postfifo.egnt     = '{default: {postfifo.gnt}};
    assign postfifo.r_evalid = '{default: {postfifo.r_evalid}};
  end
  else begin : no_ecc_handshake_gen
    assign postfifo.egnt     = '1;
    assign postfifo.r_evalid = '0;
  end

/*
 * Asserts
 */
`ifndef SYNTHESIS
`ifndef VERILATOR

  initial
    assert (NB_IN_CHAN <= NB_OUT_CHAN)  else  $fatal("NB_IN_CHAN > NB_OUT_CHAN!");
  initial
    assert (AWC+2 <= 32)                else  $fatal("AWM+$clog2(NB_OUT_CHAN)+2 > 32!");

`endif
`endif;

endmodule // hci_router
