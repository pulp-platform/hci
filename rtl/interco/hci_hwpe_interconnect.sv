/* 
 * hci_hwpe_interconnect.sv
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
 * The accelerator port expander has the purpose to "expand" the range of
 * the input accelerator ports (NB_IN_CHAN) to a set of output memory ports
 * (NB_OUT_CHAN >= NB_IN_CHAN).
 * It makes several assumptions:
 *  1. All input ports are synchronous. Therefore req, add, wen are taken
 *     only from in[0]. be, wdata are taken from all in ports.
 *     Similarly, all gnt and r_valid signals are propagated from the 
 *     first "internal virtual port" (see 3).
 *  2. Required ports on the output are decoded by a proper rotation of the
 *     input ports (virtually expanded with nil ports if NB_OUT_CHAN is 
 *     strictly greater than NB_IN_CHAN). This is performed using a 
 *     hwpe_stream_tcdm_reorder block.
 */

module hci_hwpe_interconnect
#(
  parameter int unsigned FIFO_DEPTH  = 0,
  parameter int unsigned NB_OUT_CHAN = 8,
  parameter int unsigned DWH = hci_package::DEFAULT_DW,
  parameter int unsigned AWH = hci_package::DEFAULT_AW,
  parameter int unsigned BWH = hci_package::DEFAULT_BW,
  parameter int unsigned WWH = hci_package::DEFAULT_WW,
  parameter int unsigned OWH = AWH,
  parameter int unsigned UWH = hci_package::DEFAULT_UW, // User Width not yet implemented
  parameter int unsigned AWM = 12
)
(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic clear_i,

  hci_core_intf.slave in,
  hci_mem_intf.master out [NB_OUT_CHAN-1:0]
);

  //There is only one input port, but with variable data width.
  //NB_IN_CHAN states, to how many standard (32-bit) ports the input port is equivalent
  localparam NB_IN_CHAN  = DWH / 32;
  //Word-interleaved scheme:
  // - First bits of requested address are shared
  // - Lowest 2 bits are byte offset within a DWORD -> ignored
  // - The bits inbetween designate the selected bank
  localparam LSB_COMMON_ADDR = $clog2(NB_OUT_CHAN) + 2;
  localparam AWC = AWM+$clog2(NB_OUT_CHAN);

`ifndef SYNTHESIS
  initial assert (NB_IN_CHAN <= NB_OUT_CHAN)  else  $fatal("NB_IN_CHAN > NB_OUT_CHAN!");
  initial assert (AWC+2 <= 32)                else  $fatal("AWM+$clog2(NB_OUT_CHAN)+2 > 32!");
`endif


  logic [$clog2(NB_OUT_CHAN)-1:0] bank_offset_s;
  logic [$clog2(NB_OUT_CHAN)-1:0] reorder_offset_s;
  logic [NB_IN_CHAN-1:0] virt_in_gnt;
  logic [NB_IN_CHAN-1:0] virt_in_rvalid;

  hci_core_intf #(
    .DW ( DWH ),
    .AW ( AWH ),
    .BW ( BWH ),
    .WW ( WWH ),
    .OW ( OWH ),
    .UW ( UWH )
  ) postfifo (
    .clk ( clk_i )
  );

  // using the interface from hwpe-stream here
  hwpe_stream_intf_tcdm virt_in  [NB_OUT_CHAN-1:0] (
    .clk ( clk_i )
  );
  hwpe_stream_intf_tcdm virt_out [NB_OUT_CHAN-1:0] (
    .clk ( clk_i )
  );

  // aux signal for r_valid generation
  logic [NB_OUT_CHAN-1:0] out_r_valid;

  // propagate handshake + address only from port 0
  generate

    // FIFOs for HWPE ports
    if(FIFO_DEPTH == 0) begin: no_fifo_gen
      hci_core_assign i_no_fifo (
        .tcdm_slave  ( in            ),
        .tcdm_master ( postfifo      )
      );
    end // no_fifo_gen
    else begin: fifo_gen
      hci_core_fifo #(
        .FIFO_DEPTH ( FIFO_DEPTH ),
        .DW         ( DWH        ),
        .BW         ( AWH        ),
        .AW         ( BWH        ),
        .WW         ( WWH        ),
        .OW         ( OWH        ),
        .UW         ( UWH        )
      ) i_fifo (
        .clk_i       ( clk_i         ),
        .rst_ni      ( rst_ni        ),
        .clear_i     ( clear_i       ),
        .flags_o     (               ),
        .tcdm_slave  ( in            ),
        .tcdm_master ( postfifo      )
      );
    end // fifo_gen

    // unimplemented user bits = 0
    assign postfifo.r_user = '0;
    
    assign bank_offset_s = postfifo.add[LSB_COMMON_ADDR-1:2];
    assign reorder_offset_s = NB_OUT_CHAN - bank_offset_s;

    for(genvar ii=0; ii<NB_IN_CHAN; ii++) begin : virt_in_bind

      assign virt_in[ii].req   = postfifo.req;
      assign virt_in[ii].wen   = postfifo.wen;
      assign virt_in[ii].be    = postfifo.be[ii*4+3:ii*4];
      assign virt_in[ii].data  = postfifo.data[ii*32+31:ii*32];
      assign postfifo.r_data[ii*32+31:ii*32]  = virt_in[ii].r_data;
      // in a word-interleaved scheme, the internal word-address is given
      // by the highest set of bits in postfifo[0].add, plus the bank-level offset
      always_comb
      begin : address_generation
        if(bank_offset_s + ii >= NB_OUT_CHAN)
          virt_in[ii].add = {postfifo.add[AWC-1:LSB_COMMON_ADDR] + 1, 2'b0};
        else
          virt_in[ii].add = {postfifo.add[AWC-1:LSB_COMMON_ADDR], 2'b0};
      end // address_generation
      
      assign virt_in_gnt[ii] = virt_in[ii].gnt;
      assign virt_in_rvalid[ii] = virt_in[ii].r_valid;

    end // virt_in_bind
    
    assign postfifo.gnt     = &virt_in_gnt;
    assign postfifo.r_valid = &virt_in_rvalid;

    for(genvar ii=NB_IN_CHAN; ii<NB_OUT_CHAN; ii++) begin : virt_nil_bind
      assign virt_in[ii].req  = '0;
      assign virt_in[ii].add  = '0;
      assign virt_in[ii].wen  = '0;
      assign virt_in[ii].be   = '0;
      assign virt_in[ii].data = '0;
    end // virt_nil_bind

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

      // generate out_r_valid
      always_ff @(posedge clk_i or negedge rst_ni)
      begin : resp_r_valid
        if(~rst_ni) begin
          out_r_valid[ii] <= 1'b0;
        end
        else begin
          out_r_valid[ii] <= out[ii].req & out[ii].gnt;
        end
      end  // resp_r_valid
    end // virt_out_bind

  endgenerate

  //Re-order the interfaces such that the port requesting the lowest bits of data
  //are located at the correct bank offset
  hwpe_stream_tcdm_reorder #(
    .NB_CHAN ( NB_OUT_CHAN )
  ) i_reorder (
    .clk_i   ( clk_i            ),
    .rst_ni  ( rst_ni           ),
    .clear_i ( clear_i          ),
    .order_i ( reorder_offset_s ), 
    .in      ( virt_in          ),
    .out     ( virt_out         )
  );

endmodule // hci_hwpe_interconnect
