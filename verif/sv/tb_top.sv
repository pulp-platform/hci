/*
 * tb_top.sv
 *
 * Luca Codeluppi <lcodelupp@student.ethz.ch>
 *
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

 /**
   Top-level module of a comprehensive and exhaustive HCI verification environment, including QoS measurement 
 **/

`include "hci_helpers.svh"

timeunit 1ns;
timeprecision 10ps;

module hci_tb 
  import hci_package::*;
  import verification_hci_package::*;
  ();

  //-------------------------------------------------------------------------------------------------------------------------------
  //-                                                          HCI                                                                -
  //-------------------------------------------------------------------------------------------------------------------------------

  logic                       clk, rst_n;
  logic                       clear_i;
  hci_interconnect_ctrl_t     ctrl_i;

  assign                      clear_i = 0;
  assign                      ctrl_i.invert_prio = INVERT_PRIO;
  assign                      ctrl_i.low_prio_max_stall = LOW_PRIO_MAX_STALL;
  
  ////////////////////
  // HCI interfaces //
  ////////////////////
  localparam hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(cores) = '{    // CORE + DMA + EXT parameters
    DW:  DEFAULT_DW,
    AW:  DEFAULT_AW,
    BW:  DEFAULT_BW,
    UW:  DEFAULT_UW,
    IW:  IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };
  localparam hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(mems) = '{     // Bank parameters
    DW:  DEFAULT_DW,
    AW:  AddrMemWidth,
    BW:  DEFAULT_BW,
    UW:  DEFAULT_UW,
    IW:  IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };
  localparam hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(hwpe) = '{     // HWPE parameters
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

  ////////////////// 
  // HCI instance //
  //////////////////
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
      .ARBITER_MODE(ARBITER_MODE),          // Chosen mode for the arbiter 
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

  //-------------------------------------------------------------------------------------------------------------------------------
  //-                                                         TCDM                                                                -
  //-------------------------------------------------------------------------------------------------------------------------------

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

  //-------------------------------------------------------------------------------------------------------------------------------
  //-                                                       APPLICATION DRIVERS                                                   -
  //-------------------------------------------------------------------------------------------------------------------------------
  logic [0:N_MASTER-1]         END_STIMULI = '0;
  logic [0:N_MASTER-1]         END_LATENCY = '0;
  
  ///////////////////////
  // Driver interfaces //
  ///////////////////////
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

  //////////////////////  
  // CORE + DMA + EXT //
  //////////////////////
  generate
    for(genvar ii=0; ii < N_MASTER - N_HWPE ; ii++) begin: app_driver_log
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
   
  //////////
  // HWPE //
  //////////
  generate
    for(genvar ii=0; ii < N_HWPE ; ii++) begin: app_driver_hwpe
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

  //-------------------------------------------------------------------------------------------------------------------------------
  //-                                                   INITIATORS-HCI BOUNDING                                                   -
  //-------------------------------------------------------------------------------------------------------------------------------

  generate
    for(genvar ii=0; ii < N_MASTER - N_HWPE ; ii++) begin: bounding_log_hci
      assign_drivers_to_logbranch #(
          .DRIVER_ID(ii)
      ) i_assign_drivers_to_logbranch (
          .driver_target(drivers_log[ii]),
          .hci_initiator(all_except_hwpe[ii])
      );
    end
  endgenerate

  generate
    for(genvar ii=0; ii < N_HWPE ; ii++) begin: bounding_hwpe_hci
      assign_drivers_to_hwpebranch #(
          .DRIVER_ID(ii+N_MASTER-N_HWPE),
          .HWPE_WIDTH(HWPE_WIDTH),
          .DATA_WIDTH_CORE(DATA_WIDTH)
      ) i_assign_drivers_to_hwpebranch (
          .driver_target(drivers_hwpe[ii]),
          .hci_initiator(hwpe_intc[ii])
      );
    end
  endgenerate

  //-------------------------------------------------------------------------------------------------------------------------------
  //-                                                           QUEUES                                                            -
  //-------------------------------------------------------------------------------------------------------------------------------

  static int unsigned           n_checks = 0;
  static int unsigned           n_correct = 0;
  static int unsigned           hwpe_check[N_HWPE] = '{default: 0};
  static int unsigned           check_hwpe_read[N_HWPE] = '{default: 0};
  static int unsigned           check_hwpe_read_add[N_HWPE] = '{default: 0};
  logic [N_BANKS-1:0]           HIDE_HWPE;
  logic [N_BANKS-1:0]           HIDE_LOG;

  real                          SUM_LATENCY_PER_TRANSACTION_LOG[N_MASTER-N_HWPE];
  real                          SUM_LATENCY_PER_TRANSACTION_HWPE[N_HWPE];

  ////////////////////
  // STIMULI QUEUES //
  ////////////////////
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
  generate  
    for(genvar ii=0;ii<N_BANKS;ii++) begin : assign_empty_queue_out_read
      assign EMPTY_queue_out_read[ii] = i_queues_out.queue_out_read[ii].size() == 0 ? 1 : 0;
    end
  endgenerate

  ///////////////////
  // R_DATA QUEUES //
  ///////////////////
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

  /////////////////
  // TCDM QUEUES //
  /////////////////
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

  //-------------------------------------------------------------------------------------------------------------------------------
  //-                                                           CHECKER                                                           -
  //-------------------------------------------------------------------------------------------------------------------------------

  //////////////////////////////
  // CHECK WRITE TRANSACTIONS //
  //////////////////////////////
  logic                  WARNING = 1'b0;
  static logic           already_checked[N_HWPE] = '{default: 0};
  static logic           STOP_CHECK = 0;

  generate 
    for(genvar ii=0;ii<N_BANKS;ii++) begin : checker_block_write
      initial begin 
        stimuli recreated_queue;
        logic NOT_ALL_WRITTEN_HWPE;
        int FOUND_IN_LOG, FOUND_IN_HWPE;
        wait (rst_n);
        while (1) begin
          //STEP 1: Wait for a write transaction (TCDM side)
          FOUND_IN_LOG = 0;
          NOT_ALL_WRITTEN_HWPE = 0;
          STOP_CHECK = 0;
          wait(i_queues_out.queue_out_write[ii].size() != 0);

          //STEP 2: Manipulate the address received by the bank by re-adding the bits of the bank index
          recreate_address(i_queues_out.queue_out_write[ii][0].add,ii,recreated_queue.add);
          recreated_queue.data = i_queues_out.queue_out_write[ii][0].data;
          recreated_queue.wen = 1'b0;

          //STEP 3: Look among the input queues to find a correspondence

            //STEP 3.1: Start looking in each master in the logarithmic branch
            for(int i=0;i<N_MASTER-N_HWPE;i++) begin
              //STEP 3.1.1: If the queue associated to a master is empty, go to the next master
              if (i_queues_stimuli.queue_all_except_hwpe[i].size() == 0) begin
                continue;
              end
              //STEP 3.1.2: Compare the manipulated address, the data and the wen signal with the ones stored in the input queue
              if (recreated_queue == i_queues_stimuli.queue_all_except_hwpe[i][0]) begin
                FOUND_IN_LOG = 1;
                //STEP 3.1.2.1: Delete the first element of the queue associated with the master where we found the correspondence
                i_queues_stimuli.queue_all_except_hwpe[i].delete(0);
                //STEP 3.1.2.2: Check priority
                if(HIDE_LOG[ii]) begin
                  $display("-----------------------------------------");
                  $display("Time %0t:    Test ***FAILED*** \n",$time);
                  $display("The arbiter prioritized master_log_%0d in LOG branch, but it should have given priority to the HWPE branch", i);
                  $finish();
                end
              end
            end
            //STEP 3.2: If no correspondence was found in the log branch, start looking in the hwpe branch
            if (!FOUND_IN_LOG) begin
              //STEP 3.2.1: Start looking in each hwpe
              for(int k=0;k<N_HWPE;k++) begin
                //STEP 3.2.1.2: Check each port
                for(int i=0;i<HWPE_WIDTH;i++)  begin
                  //STEP 3.2.1.2.1: If the queue is empty, skip and go to the next iteration
                  if (i_queues_stimuli.queue_hwpe[i+k*HWPE_WIDTH].size() == 0) begin
                    continue;
                  end
                  //STEP 3.2.1.2.2: Compare the manipulated address, the data and the wen signal with the ones stored in the input queue
                  if (recreated_queue == i_queues_stimuli.queue_hwpe[i+k*HWPE_WIDTH][0])  begin
                    FOUND_IN_HWPE = 1;
                    STOP_CHECK = 1;
                    //STEP 3.2.1.2.2.1: Start checking if all the ports of the HWPE are written at the same time.
                    //Since each involved bank would try to do this check, we avoid repeating the same verification multiple times by using the following if statement
                    if(!already_checked[k]) begin
                      //STEP 3.2.1.2.2.1.1: Check priority
                      if(HIDE_HWPE[ii]) begin
                        $display("-----------------------------------------");
                        $display("Time %0t:    Test ***FAILED*** \n",$time);
                        $display("The arbiter prioritized the HWPE branch, but it should have given priority to the LOG branch");
                        $finish();
                      end
                      //STEP 3.2.1.2.2.1.2: Check if all the ports of the hwpe are written at the same time in the banks
                      check_hwpe(i,ii,i_queues_stimuli.queue_hwpe[HWPE_WIDTH*k+:HWPE_WIDTH],i_queues_out.queue_out_write,NOT_ALL_WRITTEN_HWPE);
                      //STEP 3.2.1.2.2.1.3: If the condition 3.2.1.2.2.1.2 is met, then already_checked[k] is asserted to 1. In this way the adjacent banks will not repeat the same verification.
                      //hwpe_check[k] is also increased by one because one bank checked the k-th hwpe
                      if(!NOT_ALL_WRITTEN_HWPE) begin
                        hwpe_check[k]++;
                        already_checked[k] = 1;
                      end else begin
                        WARNING = 1'b1;
                      end
                      break;
                    //STEP 3.2.1.2.2.2: If already_checked[k] = 1, avoid 3.2.1.2.2.1.* and increment directly hwpe_check[k] 
                    end else begin
                      hwpe_check[k]++;
                      break;
                    end
                  end
                end
                //STEP 3.2.1.3: If the k-th HWPE reaches a number of HWPE_WIDTH checks, then the input queue associated to that HWPE is cleared
                if(hwpe_check[k] == HWPE_WIDTH) begin
                  hwpe_check[k] = 0;
                  already_checked[k] = 0;
                    for(int i=0;i<HWPE_WIDTH;i++) begin
                      i_queues_stimuli.queue_hwpe[i+k*HWPE_WIDTH].delete(0);
                    end
                end
                if(STOP_CHECK)
                  break;
              end
            end

          //STEP 4: Report an error if no correspondence was found
          if(!FOUND_IN_HWPE && !FOUND_IN_LOG) begin
              $display("-----------------------------------------");
              $display("Time %0t:    Test ***FAILED*** \n",$time);
              $display("Bank %0d received the following write transaction: data = %b address = %b", ii,i_queues_out.queue_out_write[ii][0].data,i_queues_out.queue_out_write[ii][0].add);
              $display("NO CORRESPONDENCE FOUND among the input queues");
              $display("POSSIBLE ERRORS:");
              $display("-Incorrect data or address");
              $display("-Incorrect order");
              $finish();
          end

          //STEP 5: Increment n_correct and n_checks accordingly to the check results
          if(FOUND_IN_LOG || (FOUND_IN_HWPE && !NOT_ALL_WRITTEN_HWPE)) begin
            n_correct ++;
            n_checks ++;
          end

          //STEP 6: Delete the first element of the output queue
          i_queues_out.queue_out_write[ii].delete(0);
        end
      end
    end 
  endgenerate

  /////////////////////////////
  // CHECK READ TRANSACTIONS //
  /////////////////////////////
  static logic           STOP_CHECK_READ = 0;
  logic                  already_checked_read[N_HWPE] = '{default: 0};

  // Check address
  generate 
    for(genvar ii=0;ii<N_BANKS;ii++) begin : checker_block_read
      initial begin: add_queue_read 
        stimuli recreated_queue;
        logic skip;
        int okay;
        int NOT_FOUND;
        int DATA_MISMATCH;
        logic hwpe_read;
        logic [DATA_WIDTH*HWPE_WIDTH-1 : 0] wide_word;
        int index_hwpe, index_master;
        wait (rst_n);
        while (1) begin
            wait(i_queues_out.queue_out_read[ii].size() != 0);
            skip = 0;
            STOP_CHECK_READ = 0;
              NOT_FOUND = 1;
              DATA_MISMATCH = 1;
              okay = 0;
              hwpe_read = 1;
              // LOG branch
              recreate_address(i_queues_out.queue_out_read[ii][0].add,ii,recreated_queue.add);
              recreated_queue.data = i_queues_out.queue_out_read[ii][0].data;
              recreated_queue.wen = 1'b1;
              for(int i=0;i<N_MASTER-N_HWPE;i++) begin
                if (i_queues_stimuli.queue_all_except_hwpe[i].size() == 0) begin
                  continue;
                end
                  if (i_queues_stimuli.queue_all_except_hwpe[i][0].wen && (recreated_queue == i_queues_stimuli.queue_all_except_hwpe[i][0])) begin
                    NOT_FOUND = 0;
                    i_queues_out.queue_out_read[ii].delete(0);
                    i_queues_stimuli.queue_all_except_hwpe[i].delete(0);
                    hwpe_read = 0;
                    if(HIDE_LOG[ii]) begin
                      $display("-----------------------------------------");
                      $display("Time %0t:    Test ***FAILED*** \n",$time);
                      $display("The arbiter prioritized master_log_%0d in LOG branch, but it should have given priority to the HWPE branch", i);
                      $finish();
                    end
                    wait(i_queues_rdata.log_rdata[i].size() != 0 && i_queues_rdata.mems_rdata[ii].size() != 0);               
                    if(i_queues_rdata.log_rdata[i][0] == i_queues_rdata.mems_rdata[ii][0]) begin
                      i_queues_rdata.mems_rdata[ii].delete(0);
                      i_queues_rdata.log_rdata[i].delete(0);
                      DATA_MISMATCH = 0;
                      okay = 1;
                    end
                    break;
                  end
              end
              // HWPE branch
              if(hwpe_read) begin
                for(int k=0;k<N_HWPE;k++) begin 
                  for(int i=0; i<HWPE_WIDTH;i++) begin
                    if (i_queues_stimuli.queue_hwpe[i+k*HWPE_WIDTH].size() == 0) begin
                      continue;
                    end
                    if(i_queues_stimuli.queue_hwpe[i+k*HWPE_WIDTH][0].wen && (recreated_queue == i_queues_stimuli.queue_hwpe[i+k*HWPE_WIDTH][0])) begin
                        NOT_FOUND = 0;
                        STOP_CHECK_READ = 1;
                        if(HIDE_HWPE[ii]) begin
                            $display("-----------------------------------------");
                            $display("Time %0t:    Test ***FAILED*** \n",$time);
                            $display("The arbiter prioritized the HWPE branch, but it should have given priority to the LOG branch");
                            $finish();
                          end
                        if(!already_checked_read[k]) begin
                          check_hwpe(i,ii,i_queues_stimuli.queue_hwpe[HWPE_WIDTH*k+:HWPE_WIDTH],i_queues_out.queue_out_read,skip);
                          already_checked_read[k] = !skip;
                        end else begin
                          skip = 0;
                        end
                        if(!skip) begin
                          check_hwpe_read_add[k]++;
                          if(check_hwpe_read_add[k] == HWPE_WIDTH) begin
                            for(int j=0;j<HWPE_WIDTH;j++) begin
                                i_queues_stimuli.queue_hwpe[HWPE_WIDTH*k+j].delete(0);
                                check_hwpe_read_add[k] = 0;
                              end
                              already_checked_read[k] = 0;
                          end
                          i_queues_out.queue_out_read[ii].delete(0);
                          wait(i_queues_rdata.hwpe_rdata[k].size() != 0 && i_queues_rdata.mems_rdata[ii].size() != 0);
                          if(i_queues_rdata.hwpe_rdata[k][0][i*DATA_WIDTH +: DATA_WIDTH] == i_queues_rdata.mems_rdata[ii][0]) begin
                            DATA_MISMATCH = 0;
                            okay = 1;
                            check_hwpe_read[k]++;
                            i_queues_rdata.mems_rdata[ii].delete(0);
                            if(check_hwpe_read[k] == HWPE_WIDTH) begin
                              i_queues_rdata.hwpe_rdata[k].delete(0);
                              check_hwpe_read[k] = 0;
                            end
                            
                          end
                        end else begin
                          i_queues_out.queue_out_read[ii].delete(0);
                          wait(i_queues_rdata.mems_rdata[ii].size() != 0);
                          i_queues_rdata.mems_rdata[ii].delete(0);
                          STOP_CHECK_READ = 1;
                          WARNING = 1;
                        end
                        break;
                      end
                    end
                    if(STOP_CHECK_READ)
                      break;
                  end
              end   
              if(NOT_FOUND) begin
                $display("-----------------------------------------");
                $display("Time %0t:    Test ***FAILED*** \n",$time);
                $display("Bank %0d received the following read transaction: address = %b", ii,recreated_queue.add);
                $display("NO CORRESPONDENCE FOUND among the input queues");
                $display("POSSIBLE ERRORS:");
                $display("-Incorrect data or address");
                $display("-Incorrect order");
                $finish();
              end
              if(DATA_MISMATCH && !skip)begin
                $display("-----------------------------------------");
                $display("Time %0t:    Test ***FAILED*** \n",$time);
                $display("r_data is not propagated correctly through the interconnect");
                $finish();
              end
              if(!skip) begin
                n_correct = n_correct + okay;
                n_checks ++;
              end
            end
          end
      end
  endgenerate
  
  //-------------------------------------------------------------------------------------------------------------------------------
  //-                                                           QoS                                                               -
  //-------------------------------------------------------------------------------------------------------------------------------
  
  /////////////////////////////////////////////
  // ARBITER CHECKER (WIDE vs NARROW branch) //
  /////////////////////////////////////////////
  generate
    if(`PRIORITY_CHECK_MODE_ONE || `PRIORITY_CHECK_MODE_ZERO) begin
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
    end else begin
      assign HIDE_HWPE = '0;
      assign HIDE_LOG = '0;
    end
  endgenerate
 
  ////////////////////////////////////////
  // REAL TROUGHPUT AND SIMULATION TIME //
  ////////////////////////////////////////
  real latency_per_master[N_MASTER];
  real troughput_real;
  real tot_latency;

  compute_througput_and_simtime #(
    .N_MASTER(N_MASTER),
    .N_TRANSACTION_LOG(N_TRANSACTION_LOG),
    .CLK_PERIOD(CLK_PERIOD),
    .DATA_WIDTH(DATA_WIDTH),
    .N_MASTER_REAL(N_MASTER_REAL),
    .N_HWPE_REAL(N_HWPE_REAL),
    .N_TRANSACTION_HWPE(N_TRANSACTION_HWPE),
    .HWPE_WIDTH(HWPE_WIDTH)
  ) i_compute_througput_and_simtime (
    .END_STIMULI(END_STIMULI),
    .END_LATENCY(END_LATENCY),
    .rst_n(rst_n),
    .clk(clk),
    .troughput_real(troughput_real),
    .tot_latency(tot_latency),
    .latency_per_master(latency_per_master)
  );  

  /////////////////////////////////////
  // COMPUTE LATENCY PER TRANSACTION //
  /////////////////////////////////////
  compute_latency_per_transaction #(
      .N_MASTER(N_MASTER),
      .N_HWPE(N_HWPE)
  ) i_compute_latency_per_transaction (
      .all_except_hwpe(all_except_hwpe),
      .hwpe_intc(hwpe_intc),
      .clk(clk),
      .rst_n(rst_n),
      .SUM_LATENCY_PER_TRANSACTION_HWPE(SUM_LATENCY_PER_TRANSACTION_HWPE),
      .SUM_LATENCY_PER_TRANSACTION_LOG(SUM_LATENCY_PER_TRANSACTION_LOG)
  );
  //-------------------------------------------------------------------------------------------------------------------------------
  //-                                                           Other                                                             -
  //-------------------------------------------------------------------------------------------------------------------------------

  ///////////////////////
  // END OF SIMULATION //
  ///////////////////////
  end_simulation_and_final_report #(
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
  ) i_end_simulation_and_final_report (
    .n_checks(n_checks),
    .n_correct(n_correct),
    .WARNING(WARNING),
    .troughput_real(troughput_real),
    .tot_latency(tot_latency),
    .latency_per_master(latency_per_master),
    .SUM_LATENCY_PER_TRANSACTION_LOG(SUM_LATENCY_PER_TRANSACTION_LOG),
    .SUM_LATENCY_PER_TRANSACTION_HWPE(SUM_LATENCY_PER_TRANSACTION_HWPE)
  );  

  /////////////////////////////////////////
  // PROGRESS BAR (10% 20% 30% ... 100%) //
  /////////////////////////////////////////
  progress_bar #(
    .TOT_CHECK(TOT_CHECK)
  ) i_progress_bar(
    .rst_n(rst_n),
    .n_checks(n_checks)
  );
  

  /////////////////////
  // CLOCK AND RESET //
  /////////////////////
  clk_rst_gen_prova #(
      .ClkPeriod   (CLK_PERIOD),
      .RstClkCycles(RST_CLK_CYCLES)
  ) i_clk_rst_gen (
      .clk_o (clk),
      .rst_no(rst_n)
  );

  ////////////////
  // ASSERTIONS //
  ////////////////
  generate
    for(genvar ii=0;ii<N_HWPE;ii++) begin : assert_hwpe_address
      input_hwpe_add: assert property (@(posedge clk) (manipulate_add(hwpe_intc[ii].add) <= TOT_MEM_SIZE*1024/N_BANKS-WIDTH_OF_MEMORY_BYTE))
      else begin
        $display("-----------------------------------------");
        $display("Time %0t:    Test ***STOPPED*** \n",$time);
        $error("UNPREDICTABLE RESULT. One HWPE generated an out of boundary address.\nIf this message is shown, the test is not valid. Try a new workload");
        $finish();
      end
    end
  endgenerate

endmodule