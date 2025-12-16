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
`include "write_checker_tasks.svh"
`include "read_checker_tasks.svh"

timeunit 1ns;
timeprecision 10ps;

module tb_hci
  import hci_package::*;
  import tb_hci_pkg::*;
();

  /////////
  // HCI //
  /////////

  logic                   clk, rst_n;
  logic                   clear_i;
  hci_interconnect_ctrl_t ctrl_i;

  assign clear_i = 0;
  assign ctrl_i.invert_prio = INVERT_PRIO;
  assign ctrl_i.low_prio_max_stall = LOW_PRIO_MAX_STALL;

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
    ) hwpe_intc [0:N_HWPE-1] (
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
    ) all_except_hwpe [0:N_MASTER-N_HWPE-1] (
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
    ) intc_mem_wiring [0:N_BANKS-1] (
      .clk(clk)
    );

  /* HCI instance */
  hci_interconnect #(
      .N_HWPE(N_HWPE),                      // Number of HWPEs attached to the port
      .N_CORE(N_CORE),                      // Number of Core ports
      .N_DMA(N_DMA),                        // Number of DMA ports
      .N_EXT(N_EXT),                        // Number of External ports
      .N_MEM(N_BANKS),                      // Number of Memory banks
      .TS_BIT(TS_BIT),                      // TEST_SET_BIT (for Log Interconnect)
      .IW(IW),                              // ID Width
      .EXPFIFO(EXPFIFO),                    // FIFO Depth for HWPE Interconnect
      .SEL_LIC(SEL_LIC),                    // Log interconnect type selector
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
      .clear_i(clear_i),
      .ctrl_i(ctrl_i),
      .cores(all_except_hwpe[0:N_CORE-1]),
      .dma(all_except_hwpe[N_CORE:N_CORE+N_DMA-1]),
      .ext(all_except_hwpe[N_CORE+N_DMA:N_CORE+N_DMA+N_EXT-1]),
      .mems(intc_mem_wiring),
      .hwpe(hwpe_intc)
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
  ) memory (
    .clk_i(clk),
    .rst_ni(rst_n),
    .test_mode_i(/*unconnected*/),
    .tcdm_slave(intc_mem_wiring)
  );

  /////////////////////////
  // Application drivers //
  /////////////////////////

  logic [0:N_MASTER-1] END_STIMULI;
  logic [0:N_MASTER-1] END_LATENCY;

  /* Driver interfaces */
    hci_core_intf #(
      .DW(HCI_SIZE_hwpe.DW),
      .AW(HCI_SIZE_hwpe.AW),
      .BW(HCI_SIZE_hwpe.BW),
      .UW(HCI_SIZE_hwpe.UW),
      .IW(HCI_SIZE_hwpe.IW),
      .EW(HCI_SIZE_hwpe.EW),
      .EHW(HCI_SIZE_hwpe.EHW)
    ) drivers_hwpe [0:N_HWPE-1] (
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
  ) drivers_log [0:N_MASTER-N_HWPE-1] (
      .clk(clk)
    );

  /* CORE + DMA + EXT */
  generate
    for (genvar ii = 0; ii < N_MASTER - N_HWPE; ii++) begin : gen_app_driver_log
      application_driver#(
        .MASTER_NUMBER(ii),
        .IS_HWPE(0),
        .DATA_WIDTH(DATA_WIDTH),
        .ADD_WIDTH(ADD_WIDTH),
        .APPL_DELAY(APPL_DELAY), //delay on the input signals
        .IW(IW)
      ) app_driver (
        .master(drivers_log[ii]),
        .rst_ni(rst_n),
        .clear_i(clear_i),
        .clk(clk),
        .end_stimuli(END_STIMULI[ii]),
        .end_latency(END_LATENCY[ii])
      );
    end
  endgenerate

  /* HWPE */
  generate
    for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_app_driver_hwpe
      application_driver#(
        .MASTER_NUMBER(ii),
        .IS_HWPE(1),
        .DATA_WIDTH(HWPE_WIDTH*DATA_WIDTH),
        .ADD_WIDTH(ADD_WIDTH),
        .APPL_DELAY(APPL_DELAY), //delay on the input signals
        .IW(IW)
      ) app_driver_hwpe (
          .master(drivers_hwpe[ii]),
          .rst_ni(rst_n),
          .clear_i(clear_i),
          .clk(clk),
          .end_stimuli(END_STIMULI[N_MASTER-N_HWPE+ii]),
          .end_latency(END_LATENCY[N_MASTER-N_HWPE+ii])
      );
    end
  endgenerate

  /* Bindings drivers -> HCI interface */

  generate
    for (genvar ii = 0; ii < N_MASTER - N_HWPE; ii++) begin : gen_binding_log_hci
      assign_drivers #(
          .DRIVER_ID(ii),
          .IS_HWPE(0)
      ) i_assign_drivers_log (
          .driver_target(drivers_log[ii]),
          .hci_initiator(all_except_hwpe[ii])
      );
    end
  endgenerate

  generate
    for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_binding_hwpe_hci
      assign_drivers #(
          .DRIVER_ID(ii+N_MASTER-N_HWPE),
          .IS_HWPE(1),
          .HWPE_WIDTH(HWPE_WIDTH),
          .DATA_WIDTH_CORE(DATA_WIDTH)
      ) i_assign_drivers_hwpe (
          .driver_target(drivers_hwpe[ii]),
          .hci_initiator(hwpe_intc[ii])
      );
    end
  endgenerate

  ////////////
  // Queues //
  ////////////

  static int unsigned n_checks = 0;
  static int unsigned n_correct = 0;
  logic [N_BANKS-1:0] HIDE_HWPE;
  logic [N_BANKS-1:0] HIDE_LOG;

  real SUM_LATENCY_PER_TRANSACTION_LOG[N_MASTER-N_HWPE];
  real SUM_LATENCY_PER_TRANSACTION_HWPE[N_HWPE];

  /* STIMULI QUEUES */
  queues_stimuli #(
      .N_MASTER(N_MASTER),
      .N_HWPE(N_HWPE),
      .HWPE_WIDTH(HWPE_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .ADD_WIDTH(ADD_WIDTH)
  ) i_queues_stimuli (
      .all_except_hwpe(all_except_hwpe),
      .hwpe_intc(hwpe_intc),
      .rst_n(rst_n),
      .clk(clk)
  );

  logic EMPTY_queue_out_read [0:N_BANKS-1];
  always_comb begin
    for (int ii = 0; ii < N_BANKS; ii++) begin
      EMPTY_queue_out_read[ii] = (i_queues_out.queue_out_read[ii].size() == 0);
    end
  end

  /* R_DATA QUEUES */
  queues_rdata #(
      .N_MASTER(N_MASTER),
      .N_HWPE(N_HWPE),
      .N_BANKS(N_BANKS),
      .HWPE_WIDTH(HWPE_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .ADD_WIDTH(ADD_WIDTH)
  ) i_queues_rdata (
      .all_except_hwpe(all_except_hwpe),
      .hwpe_intc(hwpe_intc),
      .intc_mem_wiring(intc_mem_wiring),
      .EMPTY_queue_out_read(EMPTY_queue_out_read),
      .rst_n(rst_n),
      .clk(clk)
  );

  /* TCDM QUEUES */
  queues_out #(
      .N_MASTER(N_MASTER),
      .N_HWPE(N_HWPE),
      .N_BANKS(N_BANKS),
      .DATA_WIDTH(DATA_WIDTH),
      .AddrMemWidth(AddrMemWidth)
  ) i_queues_out (
      .all_except_hwpe(all_except_hwpe),
      .hwpe_intc(hwpe_intc),
      .intc_mem_wiring(intc_mem_wiring),
      .rst_n(rst_n),
      .clk(clk)
  );

  /////////////
  // Checker //
  /////////////

  // Checker state and statistics
  logic                  WARNING = 1'b0;
  static logic           hwpe_write_checked[N_HWPE] = '{default: 0};
  static logic           hwpe_read_checked[N_HWPE] = '{default: 0};
  static int unsigned    hwpe_write_port_count[N_HWPE] = '{default: 0};
  static int unsigned    hwpe_read_addr_count[N_HWPE] = '{default: 0};
  static int unsigned    hwpe_read_data_count[N_HWPE] = '{default: 0};

  /* CHECK WRITE TRANSACTIONS */
  generate
    for (genvar bank_id = 0; bank_id < N_BANKS; bank_id++) begin : checker_block_write
      initial begin
        stimuli_t recreated_trans;
        logic found_log, found_hwpe;
        logic hwpe_incomplete;
        int master_id, hwpe_id, port_id;

        wait (rst_n);
        while (1) begin
          // Wait for write transaction
          wait (i_queues_out.queue_out_write[bank_id].size() != 0);

          // Recreate address with bank index
          recreate_address(
            i_queues_out.queue_out_write[bank_id][0].add,
            bank_id,
            recreated_trans.add
          );
          recreated_trans.data = i_queues_out.queue_out_write[bank_id][0].data;
          recreated_trans.wen = WRITE_EN;

          // Check in log branch first
          check_write_in_log_branch(
            bank_id,
            recreated_trans,
            i_queues_stimuli.queue_all_except_hwpe,
            HIDE_LOG,
            found_log,
            master_id
          );

          // If not found, check in HWPE branch
          if (!found_log) begin
            check_write_in_hwpe_branch(
              bank_id,
              recreated_trans,
              i_queues_stimuli.queue_hwpe,
              i_queues_out.queue_out_write,
              HIDE_HWPE,
              hwpe_write_checked,
              hwpe_write_port_count,
              WARNING,
              found_hwpe,
              hwpe_id,
              port_id,
              hwpe_incomplete
            );

            // Clear HWPE queue if all ports checked
            if (found_hwpe && hwpe_id >= 0) begin
              clear_hwpe_write_queue(
                hwpe_id,
                i_queues_stimuli.queue_hwpe,
                hwpe_write_checked,
                hwpe_write_port_count
              );
            end
          end

          // Report error if no match found
          if (!found_log && !found_hwpe) begin
            report_transaction_mismatch(
              bank_id,
              "write",
              i_queues_out.queue_out_write[bank_id][0].data,
              recreated_trans.add
            );
          end

          // Update statistics
          if (found_log || (found_hwpe && !hwpe_incomplete)) begin
            n_correct++;
            n_checks++;
          end

          // Remove processed transaction
          i_queues_out.queue_out_write[bank_id].delete(0);
        end
      end
    end
  endgenerate


  /* CHECK READ TRANSACTIONS */
  generate
    for (genvar bank_id = 0; bank_id < N_BANKS; bank_id++) begin : checker_block_read
      initial begin
        stimuli_t recreated_trans;
        logic found_log, found_hwpe;
        logic data_match_log, data_match_hwpe;
        logic skip_hwpe_check;
        int master_id, hwpe_id, port_id;

        wait (rst_n);
        while (1) begin
          // Wait for read transaction
          wait (i_queues_out.queue_out_read[bank_id].size() != 0);

          // Recreate address with bank index
          recreate_address(
            i_queues_out.queue_out_read[bank_id][0].add,
            bank_id,
            recreated_trans.add
          );
          recreated_trans.data = i_queues_out.queue_out_read[bank_id][0].data;
          recreated_trans.wen = READ_EN;

          // Check in log branch first
          check_read_in_log_branch(
            bank_id,
            recreated_trans,
            i_queues_stimuli.queue_all_except_hwpe,
            i_queues_out.queue_out_read,
            i_queues_rdata.log_rdata,
            i_queues_rdata.mems_rdata,
            HIDE_LOG,
            found_log,
            data_match_log,
            master_id
          );

          // If not found, check in HWPE branch
          if (!found_log) begin
            check_read_in_hwpe_branch(
              bank_id,
              recreated_trans,
              i_queues_stimuli.queue_hwpe,
              i_queues_out.queue_out_read,
              i_queues_rdata.hwpe_rdata,
              i_queues_rdata.mems_rdata,
              HIDE_HWPE,
              hwpe_read_checked,
              hwpe_read_addr_count,
              hwpe_read_data_count,
              WARNING,
              found_hwpe,
              data_match_hwpe,
              skip_hwpe_check,
              hwpe_id,
              port_id
            );
          end

          // Report error if no match found
          if (!found_log && !found_hwpe) begin
            report_transaction_mismatch(
              bank_id,
              "read",
              recreated_trans.data,
              recreated_trans.add
            );
          end

          // Report error if data mismatch
          if (found_log && !data_match_log) begin
            report_test_failure("r_data is not propagated correctly through the interconnect (LOG branch)");
          end
          if (found_hwpe && !skip_hwpe_check && !data_match_hwpe) begin
            report_test_failure("r_data is not propagated correctly through the interconnect (HWPE branch)");
          end

          // Update statistics
          if (!skip_hwpe_check) begin
            logic check_ok;
            check_ok = (found_log && data_match_log) || (found_hwpe && data_match_hwpe);
            n_correct = n_correct + check_ok;
            n_checks++;
          end
        end
      end
    end
  endgenerate

  /////////
  // QoS //
  /////////

  /* ARBITER CHECKER (WIDE vs NARROW branch) */

  // generate
  //   if (PRIORITY_CHECK_MODE_ONE || PRIORITY_CHECK_MODE_ZERO) begin
      arbiter_checker #(
        .ARBITER_MODE(ARBITER_MODE),
        .N_MASTER(N_MASTER),
        .N_HWPE(N_HWPE),
        .N_BANKS(N_BANKS),
        .HWPE_WIDTH(HWPE_WIDTH),
        .BIT_BANK_INDEX(BIT_BANK_INDEX),
        .CLK_PERIOD(CLK_PERIOD)
      ) i_arbiter_checker (
        .HIDE_HWPE(HIDE_HWPE),
        .HIDE_LOG(HIDE_LOG),
        .ctrl_i(ctrl_i),
        .clk(clk),
        .rst_n(rst_n)
      );
  //   end else begin
  //     assign HIDE_HWPE = '0;
  //     assign HIDE_LOG = '0;
  //   end
  // endgenerate

  /* REAL THROUGHPUT AND SIMULATION TIME */

  real latency_per_master[N_MASTER];
  real throughput_real;
  real tot_latency;

  throughput_monitor #(
    .N_MASTER(N_MASTER),
    .N_TRANSACTION_LOG(N_TRANSACTION_LOG),
    .CLK_PERIOD(CLK_PERIOD),
    .DATA_WIDTH(DATA_WIDTH),
    .N_MASTER_REAL(N_MASTER_REAL),
    .N_HWPE_REAL(N_HWPE_REAL),
    .N_TRANSACTION_HWPE(N_TRANSACTION_HWPE),
    .HWPE_WIDTH(HWPE_WIDTH)
  ) i_throughput_monitor (
    .END_STIMULI(END_STIMULI),
    .END_LATENCY(END_LATENCY),
    .rst_n(rst_n),
    .clk(clk),
    .throughput_real(throughput_real),
    .tot_latency(tot_latency),
    .latency_per_master(latency_per_master)
  );

  /* LATENCY MONITOR */
  latency_monitor #(
      .N_MASTER(N_MASTER),
      .N_HWPE(N_HWPE)
  ) i_latency_monitor (
      .all_except_hwpe(all_except_hwpe),
      .hwpe_intc(hwpe_intc),
      .clk(clk),
      .rst_n(rst_n),
      .SUM_LATENCY_PER_TRANSACTION_HWPE(SUM_LATENCY_PER_TRANSACTION_HWPE),
      .SUM_LATENCY_PER_TRANSACTION_LOG(SUM_LATENCY_PER_TRANSACTION_LOG)
  );

  ///////////
  // Other //
  ///////////

  /* SIMULATION REPORT */
  sim_report #(
    .TOT_CHECK(TOT_CHECK),
    .N_CORE(N_CORE),
    .N_CORE_REAL(N_CORE_REAL),
    .N_DMA(N_DMA),
    .N_DMA_REAL(N_DMA_REAL),
    .N_EXT_REAL(N_EXT_REAL),
    .N_MASTER(N_MASTER),
    .N_MASTER_REAL(N_MASTER_REAL),
    .N_HWPE(N_HWPE),
    .N_HWPE_REAL(N_HWPE_REAL),
    .HWPE_WIDTH(HWPE_WIDTH)
  ) i_sim_report (
    .n_checks(n_checks),
    .n_correct(n_correct),
    .WARNING(WARNING),
    .throughput_real(throughput_real),
    .tot_latency(tot_latency),
    .latency_per_master(latency_per_master),
    .SUM_LATENCY_PER_TRANSACTION_LOG(SUM_LATENCY_PER_TRANSACTION_LOG),
    .SUM_LATENCY_PER_TRANSACTION_HWPE(SUM_LATENCY_PER_TRANSACTION_HWPE)
  );

  /* CLOCK AND RESET */
  clk_rst_gen #(
      .ClkPeriod   (CLK_PERIOD),
      .RstClkCycles(RST_CLK_CYCLES)
  ) i_clk_rst_gen (
      .clk_o (clk),
      .rst_no(rst_n)
  );

  /* ASSERTIONS */
  generate
    for (genvar ii = 0; ii < N_HWPE; ii++) begin : gen_assert_hwpe_address
      input_hwpe_add: assert property (@(posedge clk) (manipulate_add(hwpe_intc[ii].add) <= TOT_MEM_SIZE * 1024 / N_BANKS - WIDTH_OF_MEMORY_BYTE))
      else begin
        $display("-----------------------------------------");
        $display("Time %0t:    Test ***STOPPED*** \n",$time);
        $error("UNPREDICTABLE RESULT. One HWPE generated an out of boundary address.\nIf this message is shown, the test is not valid. Try a new workload");
        $finish();
      end
    end
  endgenerate

endmodule