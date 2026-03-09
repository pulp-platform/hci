/*
 * tb_hci.sv
 *
 * Sergio Mazzola <smazzola@iis.ee.ethz.ch>
 * Luca Codeluppi <lcodelupp@student.ethz.ch>
 *
 * Copyright (C) 2019-2026 ETH Zurich, University of Bologna
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

timeunit 1ns;
timeprecision 10ps;

module tb_hci
  import hci_package::*;
  import tb_hci_pkg::*;
();

  logic                   clk, rst_n;
  logic [N_DRIVERS-1:0]   s_end_resp;  // end_resp_o from all drivers, [N_DRIVERS-1:0] ordering
  logic [N_DRIVERS-1:0]   s_clear_drv; // per-driver clear_i (held 1 until dependencies done)
  hci_interconnect_ctrl_t s_hci_ctrl;

  clk_rst_gen #(
    .ClkPeriod(CLK_PERIOD),
    .RstClkCycles(RST_CLK_CYCLES)
  ) i_clk_rst_gen (
    .clk_o(clk),
    .rst_no(rst_n)
  );

  /////////
  // HCI //
  /////////

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(cores) = '{
    DW:  DW_cores,
    AW:  AW_cores,
    BW:  BW_cores,
    UW:  UW_cores,
    IW:  IW_cores,
    EW:  EW_cores,
    EHW: EHW_cores
  };

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(hwpe) = '{
    DW:  DW_hwpe,
    AW:  AW_hwpe,
    BW:  BW_hwpe,
    UW:  UW_hwpe,
    IW:  IW_hwpe,
    EW:  EW_hwpe,
    EHW: EHW_hwpe
  };

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(mems) = '{
    DW:  DW_mems,
    AW:  AW_mems,
    BW:  BW_mems,
    UW:  UW_mems,
    IW:  IW_mems,
    EW:  EW_mems,
    EHW: EHW_mems
  };

  /* Application-driver-side interfaces */

  hci_core_intf #(
    .DW(HCI_SIZE_cores.DW),
    .AW(HCI_SIZE_cores.AW),
    .BW(HCI_SIZE_cores.BW),
    .UW(HCI_SIZE_cores.UW),
    .IW(HCI_SIZE_cores.IW),
    .EW(HCI_SIZE_cores.EW),
    .EHW(HCI_SIZE_cores.EHW)
  ) hci_driver_log_if [0:N_LOG_MASTERS-1] (
    .clk(clk)
  );

  hci_core_intf #(
    .DW(HCI_SIZE_hwpe.DW),
    .AW(HCI_SIZE_hwpe.AW),
    .BW(HCI_SIZE_hwpe.BW),
    .UW(HCI_SIZE_hwpe.UW),
    .IW(HCI_SIZE_hwpe.IW),
    .EW(HCI_SIZE_hwpe.EW),
    .EHW(HCI_SIZE_hwpe.EHW)
  ) hci_driver_hwpe_if [0:N_HWPE-1] (
    .clk(clk)
  );

  /* Interconnect-side interfaces (hci_system-style organization) */

  hci_core_intf #(
    .DW(HCI_SIZE_cores.DW),
    .AW(HCI_SIZE_cores.AW),
    .BW(HCI_SIZE_cores.BW),
    .UW(HCI_SIZE_cores.UW),
    .IW(HCI_SIZE_cores.IW),
    .EW(HCI_SIZE_cores.EW),
    .EHW(HCI_SIZE_cores.EHW)
  ) hci_initiator_narrow [0:N_NARROW_HCI-1] (
    .clk(clk)
  );

  hci_core_intf #(
    .DW(HCI_SIZE_hwpe.DW),
    .AW(HCI_SIZE_hwpe.AW),
    .BW(HCI_SIZE_hwpe.BW),
    .UW(HCI_SIZE_hwpe.UW),
    .IW(HCI_SIZE_hwpe.IW),
    .EW(HCI_SIZE_hwpe.EW),
    .EHW(HCI_SIZE_hwpe.EHW)
  ) hci_initiator_wide [0:N_WIDE_HCI-1] (
    .clk(clk)
  );

  hci_core_intf #(
    .DW(HCI_SIZE_cores.DW),
    .AW(HCI_SIZE_cores.AW),
    .BW(HCI_SIZE_cores.BW),
    .UW(HCI_SIZE_cores.UW),
    .IW(HCI_SIZE_cores.IW),
    .EW(HCI_SIZE_cores.EW),
    .EHW(HCI_SIZE_cores.EHW)
  ) hci_initiator_dma [0:N_DMA-1] (
    .clk(clk)
  );

  hci_core_intf #(
    .DW(HCI_SIZE_cores.DW),
    .AW(HCI_SIZE_cores.AW),
    .BW(HCI_SIZE_cores.BW),
    .UW(HCI_SIZE_cores.UW),
    .IW(HCI_SIZE_cores.IW),
    .EW(HCI_SIZE_cores.EW),
    .EHW(HCI_SIZE_cores.EHW)
  ) hci_initiator_ext [0:N_EXT-1] (
    .clk(clk)
  );

  hci_core_intf #(
    .DW(HCI_SIZE_mems.DW),
    .AW(HCI_SIZE_mems.AW),
    .BW(HCI_SIZE_mems.BW),
    .UW(HCI_SIZE_mems.UW),
    .IW(HCI_SIZE_mems.IW),
    .EW(HCI_SIZE_mems.EW),
    .EHW(HCI_SIZE_mems.EHW),
    .WAIVE_RQ3_ASSERT(1'b1),
    .WAIVE_RQ4_ASSERT(1'b1),
    .WAIVE_RSP3_ASSERT(1'b1),
    .WAIVE_RSP5_ASSERT(1'b1)
  ) hci_target_mems [0:N_BANKS-1] (
    .clk(clk)
  );

  generate
    for (genvar ii = 0; ii < N_CORE; ii++) begin : gen_core_to_narrow
      hci_core_assign i_core_to_narrow_assign (
        .tcdm_target(hci_driver_log_if[ii]),
        .tcdm_initiator(hci_initiator_narrow[ii])
      );
    end

    for (genvar ii = 0; ii < N_DMA; ii++) begin : gen_dma_to_hci
      hci_core_assign i_dma_to_hci_assign (
        .tcdm_target(hci_driver_log_if[N_CORE + ii]),
        .tcdm_initiator(hci_initiator_dma[ii])
      );
    end

    for (genvar ii = 0; ii < N_EXT; ii++) begin : gen_ext_to_hci
      hci_core_assign i_ext_to_hci_assign (
        .tcdm_target(hci_driver_log_if[N_CORE + N_DMA + ii]),
        .tcdm_initiator(hci_initiator_ext[ii])
      );
    end

    if (INTERCO_TYPE == HCI) begin : gen_hwpe_hci
      for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_hwpe_hci_assign
        hci_core_assign i_hwpe_hci_assign (
          .tcdm_target(hci_driver_hwpe_if[ii]),
          .tcdm_initiator(hci_initiator_wide[ii])
        );
      end
    end else if (INTERCO_TYPE == MUX) begin : gen_hwpe_mux
      // In MUX mode, sel_i points at the lowest-indexed HWPE that has not yet finished
      // (i.e. whose end_resp_o has not fired). Once HWPE k asserts end_resp_o, sel_i
      // advances to k+1. We cannot use s_clear_drv here because HWPE 0 always has
      // eff_mask='0 so its clear_drv is permanently 0 even after it finishes.
      logic [$clog2(N_HWPE > 1 ? N_HWPE-1 : 1):0] s_mux_sel;
      always_comb begin
        s_mux_sel = ($clog2(N_HWPE > 1 ? N_HWPE-1 : 1) + 1)'(N_HWPE - 1);
        for (int i = N_HWPE-1; i >= 0; i--) begin
          if (!s_end_resp[N_LOG_MASTERS + i])
            s_mux_sel = ($clog2(N_HWPE > 1 ? N_HWPE-1 : 1) + 1)'(i);
        end
      end
      hci_core_mux_static #(
        .NB_CHAN(N_HWPE),
        .`HCI_SIZE_PARAM(in)(HCI_SIZE_hwpe)
      ) i_hwpe_mux (
        .clk_i(clk),
        .rst_ni(rst_n),
        .clear_i(s_clear),
        .sel_i(s_mux_sel),
        .in(hci_driver_hwpe_if),
        .out(hci_initiator_wide[0])
      );
    end else if (INTERCO_TYPE == LOG) begin : gen_hwpe_split
      for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_hwpe_split_per_master
        hci_core_split #(
          .DW(HWPE_WIDTH_FACT * DATA_WIDTH),
          .BW(DATA_WIDTH / 8),
          .UW(1),
          .NB_OUT_CHAN(HWPE_WIDTH_FACT),
          .FIFO_DEPTH(2),
          .`HCI_SIZE_PARAM(tcdm_target)(HCI_SIZE_hwpe)
        ) i_hwpe_to_log_split (
          .clk_i(clk),
          .rst_ni(rst_n),
          .clear_i(s_clear),
          .tcdm_target(hci_driver_hwpe_if[ii]),
          .tcdm_initiator(hci_initiator_narrow[N_CORE + ii * HWPE_WIDTH_FACT : N_CORE + (ii + 1) * HWPE_WIDTH_FACT - 1])
        );
      end
    end else begin : gen_unsupported_mode
      initial $error("Unsupported INTERCO_TYPE");
    end
  endgenerate

  logic s_clear;
  assign s_clear = 1'b0;

  assign s_hci_ctrl.arb_policy = ARBITER_MODE;
  assign s_hci_ctrl.invert_prio = INVERT_PRIO;
  assign s_hci_ctrl.priority_cnt_numerator = PRIORITY_CNT_NUMERATOR;
  assign s_hci_ctrl.priority_cnt_denominator = PRIORITY_CNT_DENOMINATOR;

  // Driver clear logic: driver i is held in reset until all drivers j in its effective wait
  // mask have asserted end_resp_o. If the effective mask is zero, the driver starts immediately.
  //
  // In MUX mode the user-defined WAIT_MASKS are ignored for HWPE drivers: instead a strict
  // sequential chain is enforced (HWPE i waits for HWPE i-1), because hci_core_mux_static
  // only forwards one HWPE at a time. HWPE ordering follows the index = position in
  // hwpe_masters[] in workload.json. LOG master masks are always taken from WAIT_MASKS.
  //
  // All drivers use end_resp_o (s_end_resp) as the handoff condition, guaranteeing that all
  // in-flight reads from the predecessor have been fully retired before the successor starts.
  // This is required for correctness in MUX mode (hci_core_mux_static gates r_valid to the
  // non-selected channel), and is conservatively safe for all other modes.
  generate
    for (genvar ii = 0; ii < N_DRIVERS; ii++) begin : gen_driver_clear
      logic [N_DRIVERS-1:0] eff_mask;
      if (INTERCO_TYPE == MUX && ii >= N_LOG_MASTERS) begin : gen_mux_mask
        // HWPE 0 (ii == N_LOG_MASTERS): no wait; HWPE k waits for HWPE k-1's end_resp_o
        assign eff_mask = (ii == N_LOG_MASTERS) ? '0 : (N_DRIVERS'(1) << (ii - 1));
      end else begin : gen_default_mask
        assign eff_mask = WAIT_MASKS[ii];
      end
      assign s_clear_drv[ii] = (eff_mask != '0) &&
                                ((s_end_resp & eff_mask) != eff_mask);
    end
  endgenerate

  hci_interconnect #(
    .N_HWPE(N_WIDE_HCI),
    .N_CORE(N_NARROW_HCI),
    .N_DMA(N_DMA),
    .N_EXT(N_EXT),
    .N_MEM(N_BANKS),
    .TS_BIT(TS_BIT),
    .IW(IW),
    .EXPFIFO(EXPFIFO),
    .SEL_LIC(SEL_LIC),
    .FILTER_WRITE_R_VALID(FILTER_WRITE_R_VALID),
    .HCI_SIZE_cores(HCI_SIZE_cores),
    .HCI_SIZE_mems(HCI_SIZE_mems),
    .HCI_SIZE_hwpe(HCI_SIZE_hwpe),
    .WAIVE_RQ3_ASSERT(1'b1),
    .WAIVE_RQ4_ASSERT(1'b1),
    .WAIVE_RSP3_ASSERT(1'b1),
    .WAIVE_RSP5_ASSERT(1'b1)
  ) i_hci_interconnect (
    .clk_i(clk),
    .rst_ni(rst_n),
    .clear_i(s_clear),
    .ctrl_i(s_hci_ctrl),
    .cores(hci_initiator_narrow),
    .dma(hci_initiator_dma),
    .ext(hci_initiator_ext),
    .mems(hci_target_mems),
    .hwpe(hci_initiator_wide)
  );

  //////////
  // TCDM //
  //////////

  tcdm_banks_wrap #(
    .BankSize(N_WORDS),
    .NbBanks(N_BANKS),
    .DataWidth(DATA_WIDTH),
    .AddrWidth(ADDR_WIDTH),
    .BeWidth(DATA_WIDTH / 8),
    .IdWidth(IW)
  ) i_tb_mem (
    .clk_i(clk),
    .rst_ni(rst_n),
    .test_mode_i(1'b0),
    .tcdm_slave(hci_target_mems)
  );

  /////////////////////////
  // Application drivers //
  /////////////////////////

  int unsigned s_issued_transactions[0:N_DRIVERS-1];
  int unsigned s_issued_read_transactions[0:N_DRIVERS-1];

  generate
    for (genvar ii = 0; ii < N_LOG_MASTERS; ii++) begin : gen_app_driver_log
      localparam string STIM_FILE_LOG =
          $sformatf("../simvectors/generated/stimuli/master_log_%0d.txt", ii);
      application_driver #(
        .MASTER_NUMBER(ii),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .IW(IW_cores),
        .STIM_FILE(STIM_FILE_LOG)
      ) i_app_driver_log (
        .clk_i(clk),
        .rst_ni(rst_n),
        .clear_i(s_clear_drv[ii]),
        .hci_if(hci_driver_log_if[ii]),
        .end_resp_o(s_end_resp[ii]),
        .n_issued_tr_o(s_issued_transactions[ii]),
        .n_issued_rd_tr_o(s_issued_read_transactions[ii]),
        .n_retired_rd_tr_o()
      );
    end
  endgenerate

  generate
    for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_app_driver_hwpe
      localparam string STIM_FILE_HWPE =
          $sformatf("../simvectors/generated/stimuli/master_hwpe_%0d.txt", ii);
      application_driver #(
        .MASTER_NUMBER(ii),
        .DATA_WIDTH(HWPE_WIDTH_FACT * DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .IW(IW_hwpe),
        .STIM_FILE(STIM_FILE_HWPE)
      ) i_app_driver_hwpe (
        .clk_i(clk),
        .rst_ni(rst_n),
        .clear_i(s_clear_drv[N_LOG_MASTERS + ii]),
        .hci_if(hci_driver_hwpe_if[ii]),
        .end_resp_o(s_end_resp[N_LOG_MASTERS + ii]),
        .n_issued_tr_o(s_issued_transactions[N_LOG_MASTERS + ii]),
        .n_issued_rd_tr_o(s_issued_read_transactions[N_LOG_MASTERS + ii]),
        .n_retired_rd_tr_o()
      );
    end
  endgenerate

  /////////
  // QoS //
  /////////

  real SUM_REQ_TO_GNT_LATENCY_LOG[N_LOG_MASTERS];
  real SUM_REQ_TO_GNT_LATENCY_HWPE[N_HWPE];
  int unsigned N_GNT_TRANSACTIONS_LOG[N_LOG_MASTERS];
  int unsigned N_GNT_TRANSACTIONS_HWPE[N_HWPE];
  int unsigned N_READ_GRANTED_TRANSACTIONS_LOG[N_LOG_MASTERS];
  int unsigned N_READ_GRANTED_TRANSACTIONS_HWPE[N_HWPE];
  int unsigned N_WRITE_GRANTED_TRANSACTIONS_LOG[N_LOG_MASTERS];
  int unsigned N_WRITE_GRANTED_TRANSACTIONS_HWPE[N_HWPE];
  int unsigned N_READ_COMPLETE_TRANSACTIONS_LOG[N_LOG_MASTERS];
  int unsigned N_READ_COMPLETE_TRANSACTIONS_HWPE[N_HWPE];

  real latency_per_master[N_DRIVERS];
  real throughput_completed;
  real tot_latency;

  bandwidth_monitor #(
    .N_MASTER(N_DRIVERS),
    .N_HWPE(N_HWPE),
    .CLK_PERIOD(CLK_PERIOD),
    .DATA_WIDTH(DATA_WIDTH),
    .HWPE_WIDTH_FACT(HWPE_WIDTH_FACT)
  ) i_bandwidth_monitor (
    .clk_i(clk),
    .rst_ni(rst_n),
    .end_resp_i(s_end_resp),
    .n_read_complete_log_i(N_READ_COMPLETE_TRANSACTIONS_LOG),
    .n_read_complete_hwpe_i(N_READ_COMPLETE_TRANSACTIONS_HWPE),
    .n_write_granted_log_i(N_WRITE_GRANTED_TRANSACTIONS_LOG),
    .n_write_granted_hwpe_i(N_WRITE_GRANTED_TRANSACTIONS_HWPE),
    .throughput_complete_o(throughput_completed),
    .tot_latency_o(tot_latency),
    .latency_per_master_o(latency_per_master)
  );

  req_gnt_monitor #(
    .N_MASTER(N_DRIVERS),
    .N_HWPE(N_HWPE)
  ) i_req_gnt_monitor (
    .clk_i(clk),
    .rst_ni(rst_n),
    .hci_driver_log_if(hci_driver_log_if),
    .hci_driver_hwpe_if(hci_driver_hwpe_if),
    .sum_req_to_gnt_latency_log_o(SUM_REQ_TO_GNT_LATENCY_LOG),
    .sum_req_to_gnt_latency_hwpe_o(SUM_REQ_TO_GNT_LATENCY_HWPE),
    .n_gnt_transactions_log_o(N_GNT_TRANSACTIONS_LOG),
    .n_gnt_transactions_hwpe_o(N_GNT_TRANSACTIONS_HWPE),
    .n_read_granted_log_o(N_READ_GRANTED_TRANSACTIONS_LOG),
    .n_read_granted_hwpe_o(N_READ_GRANTED_TRANSACTIONS_HWPE),
    .n_write_granted_log_o(N_WRITE_GRANTED_TRANSACTIONS_LOG),
    .n_write_granted_hwpe_o(N_WRITE_GRANTED_TRANSACTIONS_HWPE),
    .n_read_complete_log_o(N_READ_COMPLETE_TRANSACTIONS_LOG),
    .n_read_complete_hwpe_o(N_READ_COMPLETE_TRANSACTIONS_HWPE)
  );

  simulation_report i_simulation_report (
    .end_resp_i(s_end_resp),
    .throughput_complete_i(throughput_completed),
    .tot_latency_i(tot_latency),
    .latency_per_master_i(latency_per_master),
    .sum_req_to_gnt_latency_log_i(SUM_REQ_TO_GNT_LATENCY_LOG),
    .sum_req_to_gnt_latency_hwpe_i(SUM_REQ_TO_GNT_LATENCY_HWPE),
    .n_gnt_transactions_log_i(N_GNT_TRANSACTIONS_LOG),
    .n_gnt_transactions_hwpe_i(N_GNT_TRANSACTIONS_HWPE),
    .n_read_granted_transactions_log_i(N_READ_GRANTED_TRANSACTIONS_LOG),
    .n_read_granted_transactions_hwpe_i(N_READ_GRANTED_TRANSACTIONS_HWPE),
    .n_write_granted_transactions_log_i(N_WRITE_GRANTED_TRANSACTIONS_LOG),
    .n_write_granted_transactions_hwpe_i(N_WRITE_GRANTED_TRANSACTIONS_HWPE),
    .n_read_complete_transactions_log_i(N_READ_COMPLETE_TRANSACTIONS_LOG),
    .n_read_complete_transactions_hwpe_i(N_READ_COMPLETE_TRANSACTIONS_HWPE)
  );

  localparam int unsigned MAX_BANK_LOCAL_ADDR =
      TOT_MEM_SIZE * 1024 / N_BANKS - WIDTH_OF_MEMORY_BYTE;

  generate
    for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_assert_hwpe_address
      a_hwpe_addr_in_bounds: assert property (
        @(posedge clk)
          get_bank_local_address(hci_driver_hwpe_if[ii].add) <= MAX_BANK_LOCAL_ADDR
      ) else begin
        $display("--------------------------------------------");
        $display("Time %0t: Test stopped", $time);
        $error(
          "HWPE%0d generated an out-of-bounds address (raw=0x%0h, bank_local=0x%0h, max=0x%0h).",
          ii,
          hci_driver_hwpe_if[ii].add,
          get_bank_local_address(hci_driver_hwpe_if[ii].add),
          MAX_BANK_LOCAL_ADDR
        );
        $display("This workload is invalid; rerun with a different workload configuration.");
        $finish();
      end
    end
  endgenerate

endmodule
