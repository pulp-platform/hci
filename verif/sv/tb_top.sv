`include "hci_helpers.svh"

timeunit 1ns;
timeprecision 10ps;


module hci_tb 
  import hci_package::*;
  import verification_hci_package::*;
  ();

  // Simulation parameters
  localparam int unsigned     N_TRANSACTION_LOG         =          `N_TRANSACTION_LOG;
  localparam int unsigned     TRANSACTION_RATIO         =          `TRANSACTION_RATIO;
  localparam int unsigned     N_TRANSACTION_HWPE        =          int'(N_TRANSACTION_LOG*`TRANSACTION_RATIO);
  localparam int unsigned     TOT_CHECK                 =          N_TRANSACTION_LOG*(`N_CORE + `N_DMA + `N_EXT)+`N_HWPE*N_TRANSACTION_HWPE*`HWPE_WIDTH;
  


  //--------------------------------------------
  //-             CLOCK AND RESET              -
  //--------------------------------------------

  // Timing parameters
  localparam time             CLK_PERIOD         =          `CLK_PERIOD;
  localparam time             APPL_DELAY         =          0;
  localparam unsigned         RST_CLK_CYCLES     =          `RST_CLK_CYCLES;

  // Clk and rst generation
  logic                       clk, rst_n;
  
  clk_rst_gen_prova #(
      .ClkPeriod   (CLK_PERIOD),
      .RstClkCycles(RST_CLK_CYCLES)
  ) i_clk_rst_gen (
      .clk_o (clk),
      .rst_no(rst_n)
  );



  //---------------------------------------------
  //-                   HCI                     -
  //---------------------------------------------

  // HCI parameters
  localparam int unsigned N_HWPE_REAL             = `N_HWPE                                                                                   ; // Number of HWPEs attached to the port
  localparam int unsigned N_CORE_REAL             = `N_CORE                                                                                   ; // Number of Core ports
  localparam int unsigned N_DMA_REAL              = `N_DMA                                                                                    ; // Number of DMA ports
  localparam int unsigned N_EXT_REAL              = `N_EXT                                                                                    ; // Number of External ports
  localparam int unsigned N_HWPE                  = (`N_HWPE == 0) ? 1 : `N_HWPE                                                              ; // Number of HWPEs attached to the port
  localparam int unsigned N_CORE                  = (`N_CORE == 0) ? 1 : `N_CORE                                                              ; // Number of Core ports
  localparam int unsigned N_DMA                   = (`N_DMA == 0) ? 1 : `N_DMA                                                                ; // Number of DMA ports
  localparam int unsigned N_EXT                   = (`N_EXT == 0) ? 1 : `N_EXT                                                                ; // Number of External ports
  localparam int unsigned N_MASTER                = N_HWPE + N_CORE + N_DMA + N_EXT                                                           ; // Total number of masters
  localparam int unsigned N_MASTER_REAL           = N_HWPE_REAL + N_CORE_REAL + N_DMA_REAL + N_EXT_REAL                                       ; // Total number of masters
  localparam int unsigned TS_BIT                  = `TS_BIT                                                                                   ; // TEST_SET_BIT (for Log Interconnect)
  localparam int unsigned IW                      = $clog2(N_TRANSACTION_LOG*(N_MASTER_REAL-N_HWPE_REAL)+N_TRANSACTION_HWPE*N_HWPE_REAL)      ; // ID Width
  localparam int unsigned EXPFIFO                 = `EXPFIFO                                                                                  ; // FIFO Depth for HWPE Interconnect
  localparam int unsigned SEL_LIC                 = `SEL_LIC                                                                                  ; // Log interconnect type selector

  localparam int unsigned DATA_WIDTH              = `DATA_WIDTH                                                                               ; // Width of DATA in bits
  localparam int unsigned HWPE_WIDTH              = `HWPE_WIDTH                                                                               ; // Widht of an HWPE wide-word (as a multiple of DATA_WIDTH)
  localparam int unsigned TOT_MEM_SIZE            = `TOT_MEM_SIZE                                                                             ; // Memory size (kB)
  localparam int unsigned ADD_WIDTH               = $clog2(TOT_MEM_SIZE*1000)                                                                 ; // Width of ADDRESS in bits
  localparam int unsigned N_BANKS                 = `N_BANKS                                                                                  ; // Number of memory banks
  localparam int unsigned WIDTH_OF_MEMORY         = `DATA_WIDTH                                                                               ; // Width of a memory bank (bits)
  localparam int unsigned WIDTH_OF_MEMORY_BYTE    = WIDTH_OF_MEMORY/8                                                                         ; // Width of a memory bank (bytes)
  localparam int unsigned BIT_BANK_INDEX          = $clog2(N_BANKS)                                                                           ; // Bits of the Bank index
  localparam int unsigned AddrMemWidth            = ADD_WIDTH - BIT_BANK_INDEX                                                                ; // Number of address bits per TCDM bank
  localparam int unsigned N_WORDS                 = (TOT_MEM_SIZE*1000/N_BANKS)/WIDTH_OF_MEMORY_BYTE                                          ; // Number of words in a bank

  localparam int unsigned ARBITER_MODE            = (`PRIORITY_CHECK_MODE_ONE == 1) ? 1 : 0                                                   ; // Choosen mode for the arbiter

  localparam hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(cores) = '{    // CORE + DMA + EXT parameters
    DW:  DATA_WIDTH,
    AW:  ADD_WIDTH,
    BW:  hci_package::DEFAULT_BW,
    UW:  hci_package::DEFAULT_UW,
    IW:  IW,
    EW:  hci_package::DEFAULT_EW,
    EHW: hci_package::DEFAULT_EHW
  };
  localparam hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(mems) = '{     // Bank parameters
    DW:  WIDTH_OF_MEMORY,
    AW:  AddrMemWidth,
    BW:  hci_package::DEFAULT_BW,
    UW:  hci_package::DEFAULT_UW,
    IW:  IW,
    EW:  hci_package::DEFAULT_EW,
    EHW: hci_package::DEFAULT_EHW
  };
  localparam hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(hwpe) = '{     // HWPE parameters
    DW:  HWPE_WIDTH*DATA_WIDTH,
    AW:  ADD_WIDTH,
    BW:  hci_package::DEFAULT_BW,
    UW:  hci_package::DEFAULT_UW,
    IW:  IW,
    EW:  hci_package::DEFAULT_EW,
    EHW: hci_package::DEFAULT_EHW
  };

  // Control signals
  logic                       clear_i;
  hci_interconnect_ctrl_t     ctrl_i;

  assign                      clear_i = 0;
  assign                      ctrl_i.invert_prio = `INVERT_PRIO;
  assign                      ctrl_i.low_prio_max_stall = `LOW_PRIO_MAX_STALL;

  // HCI connections
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
      .EHW(HCI_SIZE_mems.EHW)
    ) intc_mem_wiring [0:N_BANKS-1] (
      .clk(clk)
    );

  // HCI instance
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
      .HCI_SIZE_hwpe(HCI_SIZE_hwpe)
  ) i_hci_interconnect (
      .clk_i(clk),
      .rst_ni(rst_n),
      .clear_i(clear_i),
      .ctrl_i(ctrl_i),
      .cores(all_except_hwpe[0 : N_CORE - 1]),
      .dma(all_except_hwpe[N_CORE : N_CORE + N_DMA-1]),
      .ext(all_except_hwpe[N_CORE + N_DMA : N_CORE + N_DMA + N_EXT-1]),
      .mems(intc_mem_wiring),
      .hwpe(hwpe_intc)
  );



  //------------------------------------------------
  //-                     TCDM                     -
  //------------------------------------------------

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
    .test_mode_i(),        // not used inside tcdm
    .tcdm_slave(intc_mem_wiring)
  );



  //-------------------------------------------------
  //-              APPLICATION DRIVERS              -
  //-------------------------------------------------

  static logic [0:N_MASTER-1]         END_STIMULI = '0;
  static logic [0:N_MASTER-1]         END_LATENCY = '0;
  // CORES + DMA + EXT
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
        .master(all_except_hwpe[ii]),
        .rst_ni(rst_n),
        .clear_i(clear_i),
        .clk(clk),
        .end_stimuli(END_STIMULI[ii]),
        .end_latency(END_LATENCY[ii])
      );
    end
  endgenerate

  // HWPE
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
          .master(hwpe_intc[ii]),
          .rst_ni(rst_n),
          .clear_i(clear_i),
          .clk(clk),
          .end_stimuli(END_STIMULI[N_MASTER-N_HWPE+ii]),
          .end_latency(END_LATENCY[N_MASTER-N_HWPE+ii])
      );
    end
  endgenerate



  //-------------------------------------------------
  //-                   QUEUES                      -
  //-------------------------------------------------

  // Global variables
  static int unsigned           n_checks = 0;
  static int unsigned           n_correct = 0;
  static int unsigned           hwpe_check[N_HWPE] = '{default: 0};
  static int unsigned           check_hwpe_read[N_HWPE] = '{default: 0};
  static int unsigned           check_hwpe_read_add[N_HWPE] = '{default: 0};
  logic                         HIDE_HWPE[N_BANKS] = '{default: 0};
  logic                         HIDE_LOG[N_BANKS] = '{default: 0};

  static real               SUM_LATENCY_PER_TRANSACTION_LOG[N_MASTER-N_HWPE]= '{default: 0};
  static real               SUM_LATENCY_PER_TRANSACTION_HWPE[N_HWPE]= '{default: 0};

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
  for(genvar ii=0;ii<N_BANKS;ii++) begin
    assign EMPTY_queue_out_read[ii] = i_queues_out.queue_out_read[ii].size() == 0 ? 1 : 0;
  end
endgenerate

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


  //-----------------------------------------------
  //-                CHECKER                      -
  //-----------------------------------------------

  //------------- write transactions --------------

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
                  show_warning();
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
                        show_warning();
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
              show_warning();
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

  //------------- read transactions -------------

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
                      show_warning();
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
                            show_warning();
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
                show_warning();
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
                show_warning();
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
  
  //--------------------------------------------
  //-             QoS: Arbiter                 -
  //--------------------------------------------
/*
    static logic [N_BANKS-1:0]   LOG_REQ;
    static logic [N_BANKS-1:0]   HWPE_REQ;
    static logic [N_BANKS-1:0][N_MASTER-N_HWPE-1:0]   LOG_REQ_EACH_MASTER = '{default: '0};
    static logic [N_BANKS-1:0][N_HWPE-1:0]   HWPE_REQ_EACH_MASTER = '{default: '0};

    generate
    if(`PRIORITY_CHECK_MODE_ONE == 1 || `PRIORITY_CHECK_MODE_ZERO == 1) begin
      // Compute the requests for each bank
      for(genvar ii=0;ii<N_MASTER-N_HWPE;ii++) begin: req_per_bank_per_log_master
        logic [BIT_BANK_INDEX-1:0] bank_index_log;
        int unsigned bank_index_log_int;
        initial begin
          wait(rst_n);
          while(1) begin
            wait(all_except_hwpe[ii].req)
              calculate_bank_index(all_except_hwpe[ii].add,bank_index_log);
              bank_index_log_int = int'(bank_index_log);
              LOG_REQ_EACH_MASTER[bank_index_log_int][ii] = 1'b1;
              #(CLK_PERIOD/100)
              while(1) begin
                @(posedge clk);
                if(all_except_hwpe[ii].gnt) begin
                  #(CLK_PERIOD/100)
                  LOG_REQ_EACH_MASTER[bank_index_log_int][ii] = 1'b0;
                  break;
                end
              end
          end
        end
      end

      for(genvar ii=0;ii<N_BANKS;ii++) begin
        assign LOG_REQ[ii] = |LOG_REQ_EACH_MASTER[ii];
      end

      for(genvar ii=0;ii<N_HWPE;ii++) begin: req_per_bank_per_hwpe_master
        logic [BIT_BANK_INDEX-1:0] bank_index_hwpe;
        int unsigned bank_index_hwpe_int;
        initial begin
          wait(rst_n);
          while(1) begin
            wait(hwpe_intc[ii].req);
              calculate_bank_index(hwpe_intc[ii].add,bank_index_hwpe);
              bank_index_hwpe_int = int'(bank_index_hwpe);
              $display("hwpe%0d, bank index hwpe %0d, time : %0t",ii,bank_index_hwpe_int,$time);
              for(int i=0;i<HWPE_WIDTH;i++) begin
                if(bank_index_hwpe_int + i >= N_BANKS) begin
                  HWPE_REQ_EACH_MASTER[bank_index_hwpe_int + i - N_BANKS][ii] = 1'b1; //rolls over
                end else begin 
                  HWPE_REQ_EACH_MASTER[bank_index_hwpe_int + i][ii] = 1'b1;
                end
              end
              #(CLK_PERIOD/100);
              while(1) begin
                @(posedge clk);
                if(hwpe_intc[ii].gnt) begin
                  #(CLK_PERIOD/100);
                  for(int i=0;i<HWPE_WIDTH;i++) begin
                    if(bank_index_hwpe_int + i >= N_BANKS) begin
                      HWPE_REQ_EACH_MASTER[bank_index_hwpe_int + i - N_BANKS][ii] = 1'b0; //rolls over
                    end else begin 
                      HWPE_REQ_EACH_MASTER[bank_index_hwpe_int + i][ii] = 1'b0;
                    end
                  end
                  break;
                end
              end
          end
        end
      end
      for(genvar ii=0;ii<N_BANKS;ii++) begin
        assign HWPE_REQ[ii] = |HWPE_REQ_EACH_MASTER[ii];
      end
    end
    endgenerate

    static logic [N_BANKS-1:0] CONFLICTS = '0;
    static logic prior;

    generate 
    if(`PRIORITY_CHECK_MODE_ONE == 1) begin
      // Check conflicts and the number of stalls
      initial begin : check_conflicts
        int stall;
        stall = 0;
        prior = ctrl_i.invert_prio;
        wait(rst_n);
        while(1) begin
          @(negedge clk);
          for(int i=0;i<N_BANKS;i++) begin
            CONFLICTS[i] = LOG_REQ[i] && HWPE_REQ[i];
            $display("BANK %0d: conflict %0d, time %0t",i,CONFLICTS[i],$time);
            $display("BANK %0d: HWPE_REQ_EACH_MASTER %0d, time %0t",i,HWPE_REQ_EACH_MASTER[i][1],$time);
          end
          stall = stall*|CONFLICTS + |CONFLICTS;
          $display("stall: %0d, time %0t",stall,$time);
          if(prior == ctrl_i.invert_prio) begin
            if(stall == ctrl_i.low_prio_max_stall+1) begin
              prior = !prior;
              stall = 0;
            end
          end else begin
            prior = !prior;
            //stall = 0;
          end
        end
      end
    end
    if(`PRIORITY_CHECK_MODE_ZERO == 1) begin
      initial begin : check_conflicts
        int stall;
        stall = 0;
        prior = ctrl_i.invert_prio;
        wait(rst_n);
        while(1) begin
          @(negedge clk);
          for(int i=0;i<N_BANKS;i++) begin
            CONFLICTS[i] = LOG_REQ[i] && HWPE_REQ[i];
            $display("BANK %0d: conflict %0d, time %0t",i,CONFLICTS[i],$time);
            $display("BANK %0d: HWPE_REQ_EACH_MASTER %0d, time %0t",i,HWPE_REQ_EACH_MASTER[i][1],$time);
          end
          stall = stall*(|LOG_REQ && |HWPE_REQ) + (|LOG_REQ && |HWPE_REQ); // we improperly consider a stall when there is at least 1 req in both the high and low priority channel
          $display("stall: %0d, time %0t",stall,$time);
          if(prior == ctrl_i.invert_prio) begin
            if(stall == ctrl_i.low_prio_max_stall+1) begin
              prior = !prior;
              stall = 0;
            end
          end else begin
            prior = !prior;
          end
        end
      end
    end

    //Hide low priority branch in case of conflicts
    if(`PRIORITY_CHECK_MODE_ZERO == 1 || `PRIORITY_CHECK_MODE_ONE == 1) begin
      always_comb begin : HIDE
        for(int i=0;i<N_BANKS;i++) begin
          if(!prior) begin
            HIDE_HWPE[i] = CONFLICTS[i];
            HIDE_LOG[i] = 0;
          end else begin
            HIDE_HWPE[i] = 0;
            HIDE_LOG[i] = CONFLICTS[i];
          end
        end
      end
    end
    endgenerate
*/    
  //-----------------------------------------
  //-         REAL TROUGHPUT                -
  //-----------------------------------------
  static real                 troughput_real;
  static real                 tot_latency;
  initial begin
    time                 start_time, end_time;
    real                 tot_time,tot_data;
    troughput_real = -1;
    wait(rst_n);
    #(CLK_PERIOD/100);
    @(posedge clk);
    start_time = $time;
    wait(&END_STIMULI);
    end_time = $time;
    tot_time = (end_time - start_time)/CLK_PERIOD; // ns
    tot_data = ((N_TRANSACTION_LOG * DATA_WIDTH) * (N_MASTER_REAL - N_HWPE_REAL) + (N_TRANSACTION_HWPE * HWPE_WIDTH * DATA_WIDTH) * N_HWPE_REAL); // bit
    troughput_real = tot_data/tot_time; // Gbps
  end

  //--------------------------------------------
  //-               LATENCY                    -
  //--------------------------------------------
  real                 latency_per_master[N_MASTER];
  generate
    for(genvar ii=0;ii<N_MASTER;ii++) begin
      initial begin
        time                 start_time, end_time;
        wait(rst_n);
        #(CLK_PERIOD/100);
        @(posedge clk);
        start_time = $time;
        wait(END_LATENCY[ii]);
        end_time = $time;
        latency_per_master[ii] = (end_time - start_time)/CLK_PERIOD;
      end
    end
  endgenerate

  initial begin
      time                 start_time, end_time;
      wait(rst_n);
      #(CLK_PERIOD/100);
      @(posedge clk);
      start_time = $time;
      wait(&END_LATENCY);
      end_time = $time;
      tot_latency = (end_time - start_time)/CLK_PERIOD;

  end

  //-----------------------------------------------------------
  //-               LATENCY PER TRANSACTION                   -
  //-----------------------------------------------------------

  localparam int unsigned MAX_CYCLES_BETWEEN_GNT_RVALID             = `MAX_CYCLES_BETWEEN_GNT_RVALID + 2            ; // Maximum expected number of cycles between the gnt signal and the r_valid signal
  static logic [N_MASTER-1:0][MAX_CYCLES_BETWEEN_GNT_RVALID-1:0]     START_COMPUTE_LATENCY;
  static logic [N_MASTER-1:0][MAX_CYCLES_BETWEEN_GNT_RVALID-1:0]     FINISH_COMPUTE_LATENCY;
  generate
    for(genvar test=0;test<MAX_CYCLES_BETWEEN_GNT_RVALID-1;test++) begin
      for(genvar ii=0;ii<N_MASTER-N_HWPE;ii++) begin
        initial begin
          int unsigned latency;
          logic STOP;
          START_COMPUTE_LATENCY[ii][0] = 1'b1;
          wait(rst_n);
          while(1) begin
            STOP=0;
            wait(START_COMPUTE_LATENCY[ii][test]);
            FINISH_COMPUTE_LATENCY[ii][test]=0;
            latency = 1;
            @(posedge clk);
            if(all_except_hwpe[ii].req && START_COMPUTE_LATENCY[ii][test]) begin
              while(1) begin
                if(all_except_hwpe[ii].gnt) begin
                  if(all_except_hwpe[ii].wen) begin
                    if(test==0) begin
                      START_COMPUTE_LATENCY[ii][test+1] = 1;
                    end else if (test==1) begin
                      START_COMPUTE_LATENCY[ii][test+1] = |FINISH_COMPUTE_LATENCY[ii][0];
                    end else begin
                      START_COMPUTE_LATENCY[ii][test+1] = |FINISH_COMPUTE_LATENCY[ii][test-1:0];
                    end
                    while(1) begin
                      latency++;
                      @(posedge clk);
                      if(all_except_hwpe[ii].r_valid) begin
                        START_COMPUTE_LATENCY[ii][test+1] = 1'b0;
                        STOP=1;
                        break;
                      end
                    end
                  end else begin
                    break;
                  end
                  if(STOP)
                    break;
                end
                @(posedge clk);
                latency++;
              end
              FINISH_COMPUTE_LATENCY[ii][test]=1;
              SUM_LATENCY_PER_TRANSACTION_LOG[ii] = SUM_LATENCY_PER_TRANSACTION_LOG[ii] + latency;
          end
        end
      end
      end
    end
    for(genvar test=0;test<MAX_CYCLES_BETWEEN_GNT_RVALID-1;test++) begin
      for(genvar ii=0;ii<N_HWPE;ii++) begin
        initial begin
          int unsigned latency;
          logic STOP;
          START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][0] = 1'b1;
          wait(rst_n);
          while(1) begin
            STOP=0;
            wait(START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test]);
            FINISH_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test]=0;
            latency = 1;
            @(posedge clk);
            if(hwpe_intc[ii].req && START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test]) begin
              while(1) begin
                if(hwpe_intc[ii].gnt) begin
                  if(hwpe_intc[ii].wen) begin
                    if(test==0) begin
                      START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test+1] = 1;
                    end else if (test==1) begin
                      START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test+1] = |FINISH_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][0];
                    end else begin
                      START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test+1] = |FINISH_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test-1:0];
                    end
                    while(1) begin
                      latency++;
                      @(posedge clk);
                      if(hwpe_intc[ii].r_valid) begin
                        START_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test+1] = 1'b0;
                        STOP=1;
                        break;
                      end
                    end
                  end else begin
                    break;
                  end
                  if(STOP)
                    break;
                end
                @(posedge clk);
                latency++;
              end
              FINISH_COMPUTE_LATENCY[ii+N_MASTER-N_HWPE][test]=1;
              SUM_LATENCY_PER_TRANSACTION_HWPE[ii] = SUM_LATENCY_PER_TRANSACTION_HWPE[ii] + latency;
          end
        end
      end
    end
    end
  endgenerate

  //--------------------------------------------
  //-             END OF SIMULATION            -
  //--------------------------------------------

 logic                         WARNING = 1'b0;
  initial begin
    real troughput_theo;
    real average_latency;
    average_latency = 0;
    wait (n_checks >= TOT_CHECK);
    $display("n_checks final = %0d",n_checks);
    $display("------ Simulation End ------");
    if(n_correct == TOT_CHECK) begin
      $display("    Test ***PASSED*** \n");
      show_warning();
    end else begin
      $display("    Test ***FAILED*** \n");
      show_warning();
    end
    $display("\\\\CHECKS\\\\");
    $display("n_correct = %0d out of n_check = %0d",n_correct,n_checks);
    $display("expected n_check = %0d",TOT_CHECK);
    $display("note: each hwpe transaction consists of HWPE_WIDTH=%0d checks \n",HWPE_WIDTH);
    if(WARNING) begin
      $display("WARNING: Unnecessary spourious writes are occuring when the HWPE's wide word is written to the banks.\n");
      $display("The interconnect still works correctly, but this could be an unintended behaviour.\n");
    end

    calculate_theoretical_throughput(troughput_theo);
    wait(troughput_real>=0);
    $display("\\\\THROUGHPUT\\\\");
    $display("THEORETICAL THROUGHPUT: %f bit per cycle",troughput_theo);
    $display("REAL THROUGHPUT: %f bit per cycle",troughput_real);
    $display("PERFORMANCE RATING %f%%\n", troughput_real/troughput_theo*100);

    wait(tot_latency>=0);
    $display("\\\\SIMULATION TIME\\\\");
    $display("TOTAL SIMULATION TIME: %0d cycles", tot_latency);
    for(int i=0; i<N_CORE_REAL; i++) begin
      $display("TOTAL SIMULATION TIME for CORE%0d (stimuli file: master_log_%0d.txt): %f",i,i,latency_per_master[i]);
    end
    for(int i=N_CORE; i<N_CORE+N_DMA_REAL; i++) begin
      $display("TOTAL SIMULATION TIME for DMA%0d (stimuli file: master_log_%0d.txt): %f",i-N_CORE,i,latency_per_master[i]);
    end
    for(int i=N_CORE+N_DMA; i<N_CORE+N_DMA+N_EXT_REAL; i++) begin
      $display("TOTAL SIMULATION TIME for EXT%0d (stimuli file: master_log_%0d.txt): %f",i-(N_CORE+N_DMA),i,latency_per_master[i]);
    end
    for(int i=N_MASTER-N_HWPE; i<N_MASTER-N_HWPE+N_HWPE_REAL; i++) begin
      $display("TOTAL SIMULATION TIME for HWPE%0d (stimuli file: master_hwpe_%0d.txt): %f",i-N_MASTER-N_HWPE,i,latency_per_master[i]);
    end

    calculate_average_latency(SUM_LATENCY_PER_TRANSACTION_LOG,SUM_LATENCY_PER_TRANSACTION_HWPE);
    $display("\n\\\\LATENCY PER TRANSACTION\\\\");
    for(int i=0; i<N_MASTER_REAL-N_HWPE_REAL; i++) begin
      $display("Average latency for each transaction in master_log_%0d: %f",i,SUM_LATENCY_PER_TRANSACTION_LOG[i]);
      average_latency += SUM_LATENCY_PER_TRANSACTION_LOG[i];
    end
    for(int i=0; i<N_HWPE_REAL; i++) begin
      $display("Average latency for each transaction in master_hwpe_%0d: %f",i,SUM_LATENCY_PER_TRANSACTION_HWPE[i]);
      average_latency += SUM_LATENCY_PER_TRANSACTION_HWPE[i];
    end
    average_latency = average_latency/N_MASTER_REAL;
    $display("Average latency for each transaction (all masters): %f",average_latency);
    $finish();
  end

  //--------------------------------------------------------------------------------------------------------------------------------------------------------------
  //--------------------------------------------------------------------------------------------------------------------------------------------------------------


  //-----------------------------------
  //-             TASKS               -
  //-----------------------------------

  task recreate_address(input logic [AddrMemWidth-1:0] address_before, input int bank, output logic [ADD_WIDTH-1:0] address_after);
    begin
      logic [BIT_BANK_INDEX-1:0] bank_index;
      bank_index = bank;
      address_after = {address_before[AddrMemWidth-1:2],bank_index,address_before[1:0]}; //[$clog2(N_BANKS)-1:0]
    end
  endtask

  task create_address_and_data_hwpe(input logic[ADD_WIDTH-1:0] address_before,input logic [HWPE_WIDTH*DATA_WIDTH-1:0] data_before, input int index, output logic [ADD_WIDTH-1:0] address_after, output logic [DATA_WIDTH-1:0] data_after, input rolls_over_check_before, output rolls_over_check_after);
    begin
      logic [BIT_BANK_INDEX-1:0] bank_index_before, bank_index_after;
      bank_index_before = address_before[BIT_BANK_INDEX-1 + 2 : 2];
      bank_index_after = index + bank_index_before;
      rolls_over_check_after = rolls_over_check_before;
      if(bank_index_before > bank_index_after) begin //rolls over check
        rolls_over_check_after = 1'b1;
      end
      address_after = {address_before[ADD_WIDTH-1:BIT_BANK_INDEX + 2]+rolls_over_check_after,bank_index_after,address_before[1:0]};

      data_after = data_before[index*DATA_WIDTH +: DATA_WIDTH];
    end
  endtask

  task calculate_bank_index(input logic [ADD_WIDTH-1:0] address, output logic [BIT_BANK_INDEX-1:0] index);
    index = address[BIT_BANK_INDEX-1+2:2];
  endtask

  task check_hwpe(input int unsigned index_hwpe_already_checked,input int unsigned index_bank_already_checked,input stimuli queue_stimuli_hwpe[HWPE_WIDTH][$],input out_intc_to_mem queue_out_intc_to_mem_read[N_BANKS][$],output logic skip);
    int signed index_hwpe_to_check;
    int signed index_bank_to_check;
    stimuli recreated_queue;
    skip = 0;
    for(int i=1; i<HWPE_WIDTH; i++) begin
      index_hwpe_to_check = index_hwpe_already_checked + i;
      index_bank_to_check = index_bank_already_checked + i;
      if(index_hwpe_to_check > HWPE_WIDTH-1) begin
        index_hwpe_to_check = index_hwpe_to_check - HWPE_WIDTH;
        index_bank_to_check = index_bank_to_check -HWPE_WIDTH;
      end
      if(index_bank_to_check >= int'(N_BANKS)) begin 
        index_bank_to_check = index_bank_to_check - N_BANKS;

      end
      if(index_bank_to_check < 0) begin
        index_bank_to_check = index_bank_to_check + N_BANKS;
      end
      recreate_address(queue_out_intc_to_mem_read[index_bank_to_check][0].add,index_bank_to_check,recreated_queue.add);
      recreated_queue.data = queue_out_intc_to_mem_read[index_bank_to_check][0].data;
      if(recreated_queue != queue_stimuli_hwpe[index_hwpe_to_check][0] || queue_out_intc_to_mem_read[index_bank_to_check].size()==0) begin
        skip = 1;
        WARNING = 1'b1;
      end
    end
  endtask

  task calculate_theoretical_throughput(output real troughput_theo);
    
    real tot_data,band_memory_limit,tot_time;
    string line;
    if(TRANSACTION_RATIO>=1) begin
      tot_time = N_TRANSACTION_HWPE;
    end else begin
      tot_time = N_TRANSACTION_LOG;
    end

    tot_data = ((N_TRANSACTION_LOG * DATA_WIDTH) * (N_MASTER_REAL - N_HWPE_REAL) + (N_TRANSACTION_HWPE * HWPE_WIDTH * DATA_WIDTH) * N_HWPE_REAL); // bit
    troughput_theo = tot_data/tot_time; // bit per cycle
    band_memory_limit = real'(N_BANKS * DATA_WIDTH);
    if (troughput_theo >= band_memory_limit) begin
      troughput_theo = band_memory_limit;
    end
  endtask

  task automatic calculate_average_latency (ref real SUM_LATENCY_PER_TRANSACTION_LOG[N_MASTER-N_HWPE], ref real SUM_LATENCY_PER_TRANSACTION_HWPE[N_HWPE]);
    for(int i=0;i<N_MASTER-N_HWPE;i++) begin
      SUM_LATENCY_PER_TRANSACTION_LOG[i] = SUM_LATENCY_PER_TRANSACTION_LOG[i] / N_TRANSACTION_LOG;
    end
    for(int i=0;i<N_HWPE;i++) begin
      SUM_LATENCY_PER_TRANSACTION_HWPE[i] = SUM_LATENCY_PER_TRANSACTION_HWPE[i] / N_TRANSACTION_LOG;
    end
  endtask


  //-----------------------------------
  //-        ASSERTIONS               -
  //-----------------------------------
function int manipulate_add(input logic [ADD_WIDTH-1:0] add);
  logic [ADD_WIDTH-1:0] manipulated_add;
  logic [ADD_WIDTH-BIT_BANK_INDEX-1:0] bank_level_manipulated_add;
  logic [DATA_WIDTH-1:0] ret_1;
  logic ret_2;

  create_address_and_data_hwpe(add,'0,HWPE_WIDTH,manipulated_add,ret_1,'0,ret_2);
  bank_level_manipulated_add = {manipulated_add[ADD_WIDTH-1:BIT_BANK_INDEX + 2],manipulated_add[1:0]};
  return int'(bank_level_manipulated_add);
endfunction

logic  WARNING_HWPE_ADD = 0;
generate
  for(genvar ii=0;ii<N_HWPE;ii++) begin
    input_hwpe_add: assert property (@(posedge clk) (manipulate_add(hwpe_intc[ii].add) <= TOT_MEM_SIZE*1000/N_BANKS-WIDTH_OF_MEMORY_BYTE))
    else begin
      WARNING_HWPE_ADD = 1'b1;
    end
  end
endgenerate

task show_warning();
  if(WARNING_HWPE_ADD) begin
    $display("!!!WARNING!!!: UNPREDICTABLE RESULT. One HWPE generated an out of boundary address.");
    $display("If this message is shown, the test is not valid. Try a new workload\n");
    $finish();
  end
endtask
endmodule