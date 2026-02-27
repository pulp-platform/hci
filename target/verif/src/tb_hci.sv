/*
 * tb_hci.sv
 *
 * Sergio Mazzola <smazzola@iis.ee.ethz.ch>
 * Luca Codeluppi <lcodelupp@student.ethz.ch>
 *
 *
 * Copyright (C) 2019-2025 ETH Zurich, University of Bologna
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
  logic                   s_clear;
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

  /* HCI interfaces */
  localparam hci_size_parameter_t `HCI_SIZE_PARAM(cores) = '{    // CORE + DMA + EXT parameters
    DW:  DEFAULT_DW,
    AW:  DEFAULT_AW,
    BW:  DEFAULT_BW,
    UW:  DEFAULT_UW,
    IW:  IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };
  localparam hci_size_parameter_t `HCI_SIZE_PARAM(mems) = '{     // Bank parameters
    DW:  DEFAULT_DW,
    AW:  ADDR_WIDTH_BANK,
    BW:  DEFAULT_BW,
    UW:  DEFAULT_UW,
    IW:  IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };
  localparam hci_size_parameter_t `HCI_SIZE_PARAM(hwpe) = '{     // HWPE parameters
    DW:  HWPE_WIDTH_FACT*DATA_WIDTH,
    AW:  DEFAULT_AW,
    BW:  DEFAULT_BW,
    UW:  DEFAULT_UW,
    IW:  IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };

  /* Application-driver-side interfaces */

  hci_core_intf #(
    .DW(HCI_SIZE_hwpe.DW),
    .AW(HCI_SIZE_hwpe.AW),
    .BW(HCI_SIZE_hwpe.BW),
    .UW(HCI_SIZE_hwpe.UW),
    .IW(HCI_SIZE_hwpe.IW),
    .EW(HCI_SIZE_hwpe.EW),
    .EHW(HCI_SIZE_hwpe.EHW)
  ) hci_hwpe_if [0:N_HWPE-1] (
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
  ) hci_log_if [0:N_LOG_MASTERS-1] (
    .clk(clk)
  );

  /* Interconnect-side master interfaces */

  hci_core_intf #(
    .DW(HCI_SIZE_hwpe.DW),
    .AW(HCI_SIZE_hwpe.AW),
    .BW(HCI_SIZE_hwpe.BW),
    .UW(HCI_SIZE_hwpe.UW),
    .IW(HCI_SIZE_hwpe.IW),
    .EW(HCI_SIZE_hwpe.EW),
    .EHW(HCI_SIZE_hwpe.EHW)
  ) hci_hwpe_wide_if [0:N_HWPE_MASTERS-1] (
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
  ) hci_core_if [0:N_CORE+N_HWPE_LOG_MASTERS-1] (
    .clk(clk)
  );

  // LOG-only intermediate interfaces for HWPE split lanes.
  hci_core_intf #(
    .DW(HCI_SIZE_cores.DW),
    .AW(HCI_SIZE_cores.AW),
    .BW(HCI_SIZE_cores.BW),
    .UW(HCI_SIZE_cores.UW),
    .IW(HCI_SIZE_cores.IW),
    .EW(HCI_SIZE_cores.EW),
    .EHW(HCI_SIZE_cores.EHW)
  ) hci_hwpe_log_if [0:N_HWPE_LOG_MASTERS-1] (
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
  ) hci_dma_if [0:N_DMA-1] (
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
  ) hci_ext_if [0:N_EXT-1] (
    .clk(clk)
  );

  /* Memory interface */

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
  ) hci_mem_if [0:N_BANKS-1] (
    .clk(clk)
  );

  /* HCI instance */

  generate
    for (genvar ii = 0; ii < N_CORE; ii++) begin : gen_core_to_log
      hci_core_assign i_core_to_hci_assign (
        .tcdm_target (hci_log_if[ii]),
        .tcdm_initiator (hci_core_if[ii])
      );
    end
    for (genvar ii = 0; ii < N_DMA; ii++) begin : gen_dma_to_log
      hci_core_assign i_dma_to_hci_assign (
        .tcdm_target (hci_log_if[N_CORE + ii]),
        .tcdm_initiator (hci_dma_if[ii])
      );
    end
    for (genvar ii = 0; ii < N_EXT; ii++) begin : gen_ext_to_log
      hci_core_assign i_ext_to_hci_assign (
        .tcdm_target (hci_log_if[N_CORE + N_DMA + ii]),
        .tcdm_initiator (hci_ext_if[ii])
      );
    end

    if (INTERCO_TYPE == HCI) begin : gen_hwpe_to_hci
      for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_hwpe_to_hci
        hci_core_assign i_hwpe_to_hci_assign (
          .tcdm_target (hci_hwpe_if[ii]),
          .tcdm_initiator (hci_hwpe_wide_if[ii])
        );
      end
    end else if (INTERCO_TYPE == LOG) begin : gen_hwpe_to_log
      for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_hwpe_to_log
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
          .tcdm_target(hci_hwpe_if[ii]),
          .tcdm_initiator(hci_hwpe_log_if[ii * HWPE_WIDTH_FACT : (ii + 1) * HWPE_WIDTH_FACT - 1])
        );

        for (genvar f = 0; f < HWPE_WIDTH_FACT; f++) begin : gen_hwpe_log_rvalid_filter
          localparam int unsigned IDX_LOG = ii * HWPE_WIDTH_FACT + f;
          localparam int unsigned IDX_CORE = N_CORE + IDX_LOG;
          hci_core_r_valid_filter #(
            .`HCI_SIZE_PARAM(tcdm_target)(HCI_SIZE_cores)
          ) i_hwpe_log_rvalid_filter (
            .clk_i(clk),
            .rst_ni(rst_n),
            .clear_i(s_clear),
            .enable_i(1'b1),
            .tcdm_target(hci_hwpe_log_if[IDX_LOG]),
            .tcdm_initiator(hci_core_if[IDX_CORE])
          );
        end
      end
    end else begin
      // Error: unsupported for now
      $error("Unsupported INTERCO_TYPE");
    end
  endgenerate

  assign s_clear = 0;
  assign s_hci_ctrl.arb_policy = ARBITER_MODE;
  assign s_hci_ctrl.invert_prio = INVERT_PRIO;
  assign s_hci_ctrl.low_prio_max_stall = LOW_PRIO_MAX_STALL;

  hci_interconnect #(
    .N_HWPE(N_HWPE_MASTERS), // Number of HWPE ports
    .N_CORE(N_CORE + N_HWPE_LOG_MASTERS), // Number of CORE ports
    .N_DMA(N_DMA),           // Number of DMA ports
    .N_EXT(N_EXT),           // Number of External ports
    .N_MEM(N_BANKS),         // Number of Memory banks
    .TS_BIT(TS_BIT),         // TEST_SET_BIT (for Log Interconnect)
    .IW(IW),                 // ID Width
    .EXPFIFO(EXPFIFO),       // FIFO Depth for HWPE Interconnect
    .SEL_LIC(SEL_LIC),       // Log interconnect type selector
    .FILTER_WRITE_R_VALID ( FILTER_WRITE_R_VALID ),
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
    .cores(hci_core_if),
    .dma(hci_dma_if),
    .ext(hci_ext_if),
    .mems(hci_mem_if),
    .hwpe(hci_hwpe_wide_if)
  );

  //////////
  // TCDM //
  //////////

  tcdm_banks_wrap #(
    .BankSize(N_WORDS),
    .NbBanks(N_BANKS),
    .DataWidth(DATA_WIDTH),
    .AddrWidth(ADDR_WIDTH),
    .BeWidth(DATA_WIDTH/8),
    .IdWidth(IW)
  ) i_tb_mem (
    .clk_i(clk),
    .rst_ni(rst_n),
    .test_mode_i(1'b0),
    .tcdm_slave(hci_mem_if)
  );

  /////////////////////////
  // Application drivers //
  /////////////////////////

  logic [0:N_DRIVERS-1] s_end_stimuli;
  logic [0:N_DRIVERS-1] s_end_latency;
  int unsigned s_issued_transactions[0:N_DRIVERS-1];
  int unsigned s_issued_read_transactions[0:N_DRIVERS-1];

  /* CORE + DMA + EXT */
  generate
    for (genvar ii = 0; ii < N_CORE + N_DMA + N_EXT; ii++) begin : gen_app_driver_log
      localparam string STIM_FILE_LOG =
          $sformatf("../simvectors/generated/stimuli_processed/master_log_%0d.txt", ii);
      application_driver #(
        .MASTER_NUMBER(ii),
        .IS_HWPE(0),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .APPL_DELAY(APPL_DELAY),  // Delay on the input signals
        .IW(IW),
        .STIM_FILE(STIM_FILE_LOG)
      ) i_app_driver_log (
        .hci_if(hci_log_if[ii]),
        .rst_ni(rst_n),
        .clk_i(clk),
        .end_stimuli_o(s_end_stimuli[ii]),
        .end_latency_o(s_end_latency[ii]),
        .n_issued_transactions_o(s_issued_transactions[ii]),
        .n_issued_read_transactions_o(s_issued_read_transactions[ii])
      );
    end
  endgenerate

  /* HWPE */
  generate
    for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_app_driver_hwpe
      localparam string STIM_FILE_HWPE =
          $sformatf("../simvectors/generated/stimuli_processed/master_hwpe_%0d.txt", ii);
      application_driver #(
        .MASTER_NUMBER(ii),
        .IS_HWPE(1),
        .DATA_WIDTH(HWPE_WIDTH_FACT * DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .APPL_DELAY(APPL_DELAY),  // Delay on the input signals
        .IW(IW),
        .STIM_FILE(STIM_FILE_HWPE)
      ) i_app_driver_hwpe (
        .clk_i(clk),
        .rst_ni(rst_n),
        .hci_if(hci_hwpe_if[ii]),
        .end_stimuli_o(s_end_stimuli[N_CORE+N_DMA+N_EXT + ii]),
        .end_latency_o(s_end_latency[N_CORE+N_DMA+N_EXT + ii]),
        .n_issued_transactions_o(s_issued_transactions[N_CORE+N_DMA+N_EXT + ii]),
        .n_issued_read_transactions_o(s_issued_read_transactions[N_CORE+N_DMA+N_EXT + ii])
      );
    end
  endgenerate

  /////////
  // QoS //
  /////////

  real SUM_REQ_TO_GNT_LATENCY_LOG[N_CORE+N_DMA+N_EXT];
  real SUM_REQ_TO_GNT_LATENCY_HWPE[N_HWPE];
  int unsigned N_GNT_TRANSACTIONS_LOG[N_CORE+N_DMA+N_EXT];
  int unsigned N_GNT_TRANSACTIONS_HWPE[N_HWPE];
  int unsigned N_READ_GRANTED_TRANSACTIONS_LOG[N_CORE+N_DMA+N_EXT];
  int unsigned N_READ_GRANTED_TRANSACTIONS_HWPE[N_HWPE];
  int unsigned N_WRITE_GRANTED_TRANSACTIONS_LOG[N_CORE+N_DMA+N_EXT];
  int unsigned N_WRITE_GRANTED_TRANSACTIONS_HWPE[N_HWPE];
  int unsigned N_READ_COMPLETE_TRANSACTIONS_LOG[N_CORE+N_DMA+N_EXT];
  int unsigned N_READ_COMPLETE_TRANSACTIONS_HWPE[N_HWPE];

  /* REAL THROUGHPUT AND SIMULATION TIME */

  real latency_per_master[N_DRIVERS];
  real throughput_completed;
  real stim_latency;
  real tot_latency;

  throughput_monitor #(
    .N_MASTER(N_DRIVERS),
    .N_HWPE(N_HWPE),
    .CLK_PERIOD(CLK_PERIOD),
    .DATA_WIDTH(DATA_WIDTH),
    .HWPE_WIDTH_FACT(HWPE_WIDTH_FACT)
  ) i_throughput_monitor (
    .clk_i(clk),
    .rst_ni(rst_n),
    .end_stimuli_i(s_end_stimuli),
    .end_latency_i(s_end_latency),
    .n_read_complete_log_i(N_READ_COMPLETE_TRANSACTIONS_LOG),
    .n_read_complete_hwpe_i(N_READ_COMPLETE_TRANSACTIONS_HWPE),
    .n_write_granted_log_i(N_WRITE_GRANTED_TRANSACTIONS_LOG),
    .n_write_granted_hwpe_i(N_WRITE_GRANTED_TRANSACTIONS_HWPE),
    .throughput_complete_o(throughput_completed),
    .stim_latency_o(stim_latency),
    .tot_latency_o(tot_latency),
    .latency_per_master_o(latency_per_master)
  );

  /* LATENCY MONITOR */
  latency_monitor #(
    .N_MASTER(N_DRIVERS),
    .N_HWPE(N_HWPE)
  ) i_latency_monitor (
    .clk_i(clk),
    .rst_ni(rst_n),
    .hci_log_if(hci_log_if),
    .hci_hwpe_if(hci_hwpe_if),
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

  ///////////
  // Other //
  ///////////

  /* SIMULATION REPORT */
  simulation_report i_simulation_report (
    .end_stimuli_i(s_end_stimuli),
    .end_latency_i(s_end_latency),
    .throughput_complete_i(throughput_completed),
    .stim_latency_i(stim_latency),
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

  /* ASSERTIONS */
  localparam int unsigned MAX_BANK_LOCAL_ADDR =
      TOT_MEM_SIZE * 1024 / N_BANKS - WIDTH_OF_MEMORY_BYTE;

  generate
    for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_assert_hwpe_address
      a_hwpe_addr_in_bounds: assert property (
        @(posedge clk)
          get_bank_local_address(hci_hwpe_if[ii].add) <= MAX_BANK_LOCAL_ADDR
      ) else begin
        $display("--------------------------------------------");
        $display("Time %0t: Test stopped", $time);
        $error(
          "HWPE%0d generated an out-of-bounds address (raw=0x%0h, bank_local=0x%0h, max=0x%0h).",
          ii,
          hci_hwpe_if[ii].add,
          get_bank_local_address(hci_hwpe_if[ii].add),
          MAX_BANK_LOCAL_ADDR
        );
        $display("This workload is invalid; rerun with a different workload configuration.");
        $finish();
      end
    end
  endgenerate

endmodule
