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

  logic [0:N_MASTER-1] s_end_stimuli;
  logic [0:N_MASTER-1] s_end_latency;
  int unsigned s_issued_transactions[0:N_MASTER-1];
  int unsigned s_issued_read_transactions[0:N_MASTER-1];

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
    AW:  AddrMemWidth,
    BW:  DEFAULT_BW,
    UW:  DEFAULT_UW,
    IW:  IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };
  localparam hci_size_parameter_t `HCI_SIZE_PARAM(hwpe) = '{     // HWPE parameters
    DW:  HWPE_WIDTH*DATA_WIDTH,
    AW:  DEFAULT_AW,
    BW:  DEFAULT_BW,
    UW:  DEFAULT_UW,
    IW:  IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };

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
  ) hci_log_if [0:N_MASTER-N_HWPE-1] (
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
  ) hci_mem_if [0:N_BANKS-1] (
    .clk(clk)
  );

  /* HCI instance */

  assign s_clear = 0;
  assign s_hci_ctrl.invert_prio = INVERT_PRIO;
  assign s_hci_ctrl.low_prio_max_stall = LOW_PRIO_MAX_STALL;

  hci_interconnect #(
    .N_HWPE(N_HWPE),   // Number of HWPEs attached to the port
    .N_CORE(N_CORE),   // Number of Core ports
    .N_DMA(N_DMA),     // Number of DMA ports
    .N_EXT(N_EXT),     // Number of External ports
    .N_MEM(N_BANKS),   // Number of Memory banks
    .TS_BIT(TS_BIT),   // TEST_SET_BIT (for Log Interconnect)
    .IW(IW),           // ID Width
    .EXPFIFO(EXPFIFO), // FIFO Depth for HWPE Interconnect
    .SEL_LIC(SEL_LIC), // Log interconnect type selector
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
    .cores(hci_log_if[0:N_CORE-1]),
    .dma(hci_log_if[N_CORE:N_CORE+N_DMA-1]),
    .ext(hci_log_if[N_CORE+N_DMA:N_CORE+N_DMA+N_EXT-1]),
    .mems(hci_mem_if),
    .hwpe(hci_hwpe_if)
  );

  //////////
  // TCDM //
  //////////

  tcdm_banks_wrap #(
    .BankSize(N_WORDS),
    .NbBanks(N_BANKS),
    .DataWidth(DATA_WIDTH),
    .AddrWidth(ADD_WIDTH),
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

  /* CORE + DMA + EXT */
  generate
    for (genvar ii = 0; ii < N_MASTER - N_HWPE; ii++) begin : gen_app_driver_log
      localparam string STIM_FILE_LOG =
          $sformatf("../simvectors/generated/stimuli_processed/master_log_%0d.txt", ii);
      application_driver #(
        .MASTER_NUMBER(ii),
        .IS_HWPE(0),
        .DATA_WIDTH(DATA_WIDTH),
        .ADD_WIDTH(ADD_WIDTH),
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
        .DATA_WIDTH(HWPE_WIDTH * DATA_WIDTH),
        .ADD_WIDTH(ADD_WIDTH),
        .APPL_DELAY(APPL_DELAY),  // Delay on the input signals
        .IW(IW),
        .STIM_FILE(STIM_FILE_HWPE)
      ) i_app_driver_hwpe (
        .hci_if(hci_hwpe_if[ii]),
        .rst_ni(rst_n),
        .clk_i(clk),
        .end_stimuli_o(s_end_stimuli[N_MASTER-N_HWPE+ii]),
        .end_latency_o(s_end_latency[N_MASTER-N_HWPE+ii]),
        .n_issued_transactions_o(s_issued_transactions[N_MASTER-N_HWPE+ii]),
        .n_issued_read_transactions_o(s_issued_read_transactions[N_MASTER-N_HWPE+ii])
      );
    end
  endgenerate

  /////////
  // QoS //
  /////////

  real SUM_REQ_TO_GNT_LATENCY_LOG[N_MASTER-N_HWPE];
  real SUM_REQ_TO_GNT_LATENCY_HWPE[N_HWPE];
  int unsigned N_GNT_TRANSACTIONS_LOG[N_MASTER-N_HWPE];
  int unsigned N_GNT_TRANSACTIONS_HWPE[N_HWPE];
  int unsigned N_READ_GRANTED_TRANSACTIONS_LOG[N_MASTER-N_HWPE];
  int unsigned N_READ_GRANTED_TRANSACTIONS_HWPE[N_HWPE];
  int unsigned N_WRITE_GRANTED_TRANSACTIONS_LOG[N_MASTER-N_HWPE];
  int unsigned N_WRITE_GRANTED_TRANSACTIONS_HWPE[N_HWPE];
  int unsigned N_READ_COMPLETE_TRANSACTIONS_LOG[N_MASTER-N_HWPE];
  int unsigned N_READ_COMPLETE_TRANSACTIONS_HWPE[N_HWPE];

  /* REAL THROUGHPUT AND SIMULATION TIME */

  real latency_per_master[N_MASTER];
  real throughput_completed;
  real stim_latency;
  real tot_latency;

  throughput_monitor #(
    .N_MASTER(N_MASTER),
    .N_HWPE(N_HWPE),
    .CLK_PERIOD(CLK_PERIOD),
    .DATA_WIDTH(DATA_WIDTH),
    .HWPE_WIDTH(HWPE_WIDTH)
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
    .N_MASTER(N_MASTER),
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
