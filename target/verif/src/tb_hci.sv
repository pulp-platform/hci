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
  logic [N_DRIVERS-1:0]   s_end_resp;      // end_resp_o from all drivers
  logic [N_DRIVERS-1:0]   s_fence_reached; // fence_reached_o from all drivers (level, HIGH while PAUSED)
  logic [N_DRIVERS-1:0]   s_resume;        // resume_i to each driver (asserted when fence deps are met)
  int unsigned             fence_idx [N_DRIVERS]; // number of fences each driver has passed so far
  hci_interconnect_ctrl_t s_hci_ctrl;

  clk_rst_gen #(
    .ClkPeriod(CLK_PERIOD),
    .RstClkCycles(RST_CLK_CYCLES)
  ) i_clk_rst_gen (
    .clk_o(clk),
    .rst_no(rst_n)
  );

  ////////////////////
  // HCI interfaces //
  ////////////////////

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

  ///////////////////////////
  // Interface assignments //
  ///////////////////////////

  /* Assignments of narrow initiators to LOG branch of HCI */

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
  endgenerate

  /* Assignments of wide initiators to HCI (either LOG branch, HCI branch, or static MUX) */

  generate
    if (INTERCO_TYPE == HCI) begin : gen_hwpe_hci
      for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_hwpe_hci_assign
        hci_core_assign i_hwpe_hci_assign (
          .tcdm_target(hci_driver_hwpe_if[ii]),
          .tcdm_initiator(hci_initiator_wide[ii])
        );
      end
    end else if (INTERCO_TYPE == MUX) begin : gen_hwpe_mux
      // Phase-ordered MUX arbitration:
      //
      // The mux is held by whichever HWPE is currently running (not paused, not done).
      // In-flight reads are drained before any PAUSE (DRAIN_FOR_PAUSE state in the
      // driver FSM), so sel_i is safe to switch as soon as fence_reached_o goes high.
      //
      // When no HWPE is running (all are either paused or done), the mux is granted
      // to the lowest-indexed HWPE that is paused AND whose fence dependencies are
      // satisfied (s_resume high). This serializes same-phase jobs by master ID and
      // respects cross-phase data dependencies.
      logic [$clog2(N_HWPE > 1 ? N_HWPE-1 : 1):0] s_mux_sel;
      always_comb begin
        automatic logic any_running;
        any_running = 1'b0;
        for (int i = 0; i < N_HWPE; i++) begin
          if (!s_end_resp[N_LOG_MASTERS + i] && !s_fence_reached[N_LOG_MASTERS + i])
            any_running = 1'b1;
        end
        s_mux_sel = ($clog2(N_HWPE > 1 ? N_HWPE-1 : 1) + 1)'(N_HWPE - 1);
        for (int i = N_HWPE-1; i >= 0; i--) begin
          if (any_running) begin
            // Active HWPE holds the mux; lowest index wins (descending loop)
            if (!s_end_resp[N_LOG_MASTERS + i] && !s_fence_reached[N_LOG_MASTERS + i])
              s_mux_sel = ($clog2(N_HWPE > 1 ? N_HWPE-1 : 1) + 1)'(i);
          end else begin
            // No HWPE running: grant to lowest-indexed paused+ready HWPE
            if (!s_end_resp[N_LOG_MASTERS + i] && s_fence_reached[N_LOG_MASTERS + i]
                && s_resume[N_LOG_MASTERS + i])
              s_mux_sel = ($clog2(N_HWPE > 1 ? N_HWPE-1 : 1) + 1)'(i);
          end
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

  /////////////////
  // Fence logic //
  /////////////////

  logic s_clear;
  assign s_clear = 1'b0;

  assign s_hci_ctrl.arb_policy = ARBITER_MODE;
  assign s_hci_ctrl.invert_prio = INVERT_PRIO;
  assign s_hci_ctrl.priority_cnt_numerator = PRIORITY_CNT_NUMERATOR;
  assign s_hci_ctrl.priority_cnt_denominator = PRIORITY_CNT_DENOMINATOR;

  // fence_idx[i] = number of PAUSE tokens driver i has passed.
  // This counts all fences in file order, including synthetic blocking fences
  // and trailing completion fences.
  //
  // fence_idx increments when resume_i is asserted while fence_reached_o is high,
  // i.e. when the PAUSED-state handshake completes and the driver leaves that fence.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < N_DRIVERS; i++) fence_idx[i] <= '0;
    end else begin
      for (int i = 0; i < N_DRIVERS; i++) begin
        if (s_resume[i] && s_fence_reached[i])
          fence_idx[i] <= fence_idx[i] + 1;
      end
    end
  end

  // s_resume[i] is asserted only while driver i is paused at its current fence.
  // Driver i may pass that fence when, for every dependency bit j set in the
  // current FENCE_MASKS entry, fence_idx[j] is at least the required level
  // encoded in FENCE_REQ_LEVELS_PACKED.
  //
  // In other words: blocking fences wait for explicit dependency completion;
  // trailing zero-mask fences are free passes.
  always_comb begin
    for (int i = 0; i < N_DRIVERS; i++) begin
      automatic logic [N_DRIVERS-1:0] cur_mask;
      automatic logic                 all_satisfied;
      cur_mask = (fence_idx[i] < MAX_FENCES) ? FENCE_MASKS[i][fence_idx[i]] : '0;
      all_satisfied = 1'b1;
      for (int j = 0; j < N_DRIVERS; j++) begin
        if (cur_mask[j]) begin
          automatic logic [3:0] req;
          req = (fence_idx[i] < MAX_FENCES) ?
                FENCE_REQ_LEVELS_PACKED[i][fence_idx[i]][j*4+3 -: 4] : 4'h0;
          if (fence_idx[j] < req)
            all_satisfied = 1'b0;
        end
      end
      // Only assert resume_i while the driver is actually in PAUSED state.
      // Gating with fence_reached_o makes the signal a clean pulse.
      s_resume[i] = all_satisfied && s_fence_reached[i];
    end
  end

  /////////
  // HCI //
  /////////

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
        .resume_i(s_resume[ii]),
        .hci_if(hci_driver_log_if[ii]),
        .fence_reached_o(s_fence_reached[ii]),
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
        .resume_i(s_resume[N_LOG_MASTERS + ii]),
        .hci_if(hci_driver_hwpe_if[ii]),
        .fence_reached_o(s_fence_reached[N_LOG_MASTERS + ii]),
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

  ///////////////
  // Reporting //
  ///////////////

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

  ////////////////
  // Assertions //
  ////////////////

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

  // Advisory check only. The hard overflow guard is in Python generation
  // before packing FENCE_REQ_LEVELS into 4-bit fields.
  // In case of failure due to this asser, modify tb_hci_pkg.sv and generation of fence_masks.mk
  initial begin
    if (MAX_FENCES > 16) begin
      $warning(
        "MAX_FENCES=%0d exceeds the nominal 4-bit fence-level range; "
        "ensure no dependency requires a level > 15.",
        MAX_FENCES
      );
    end
  end

endmodule
