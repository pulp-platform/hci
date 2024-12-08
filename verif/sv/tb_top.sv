`include "hci_helpers.svh"

timeunit 1ns;
timeprecision 10ps;


module hci_tb 
  import hci_package::*;
  ();

  // Simulation parameters 
  localparam int unsigned     N_TEST             =          `N_TEST; 
  
  //--------------------------------------------
  //-             CLOCK AND RESET              -
  //--------------------------------------------

  // Timing parameters
  localparam time             CLK_PERIOD         =          `CLK_PERIOD;
  localparam time             APPL_DELAY         =          `APPL_DELAY;
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
  localparam int unsigned N_HWPE                  = `N_HWPE                                            ; // Number of HWPEs attached to the port
  localparam int unsigned N_CORE                  = `N_CORE                                            ; // Number of Core ports
  localparam int unsigned N_DMA                   = `N_DMA                                             ; // Number of DMA ports
  localparam int unsigned N_EXT                   = `N_EXT                                             ; // Number of External ports
  localparam int unsigned N_MASTER                = N_HWPE + N_CORE + N_DMA + N_EXT                    ; // Total number of masters
  localparam int unsigned TS_BIT                  = `TS_BIT                                            ; // TEST_SET_BIT (for Log Interconnect)
  localparam int unsigned IW                      = $clog2(N_TEST*N_MASTER)                            ; // ID Width
  localparam int unsigned EXPFIFO                 = `EXPFIFO                                           ; // FIFO Depth for HWPE Interconnect
  localparam int unsigned SEL_LIC                 = `SEL_LIC                                           ; // Log interconnect type selector

  localparam int unsigned DATA_WIDTH              = `DATA_WIDTH                                        ; // Width of DATA in bits
  localparam int unsigned TOT_MEM_SIZE            = `TOT_MEM_SIZE                                      ; // Memory size (kB)
  localparam int unsigned ADD_WIDTH               = $clog2(TOT_MEM_SIZE*1000)                          ; // Width of ADDRESS in bits
  localparam int unsigned N_BANKS                 = `N_BANKS                                           ; // Number of memory banks
  localparam int unsigned WIDTH_OF_MEMORY         = `WIDTH_OF_MEMORY                                   ; // Width of a memory bank (bits)
  localparam int unsigned WIDTH_OF_MEMORY_BYTE    = WIDTH_OF_MEMORY/8                                  ; // Width of a memory bank (bytes)
  localparam int unsigned BIT_BANK_INDEX          = $clog2(N_BANKS)                                    ; // Bits of the Bank index
  localparam int unsigned AddrMemWidth            = ADD_WIDTH - BIT_BANK_INDEX                         ; // Number of address bits per TCDM bank
  localparam int unsigned N_WORDS                 = (TOT_MEM_SIZE*1000/N_BANKS)/WIDTH_OF_MEMORY_BYTE   ; // Number of words in a bank                                                   ; // Number of tests to be executeds

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
    DW:  DATA_WIDTH,
    AW:  AddrMemWidth,
    BW:  hci_package::DEFAULT_BW,
    UW:  hci_package::DEFAULT_UW,
    IW:  IW,
    EW:  hci_package::DEFAULT_EW,
    EHW: hci_package::DEFAULT_EHW
  };
  localparam hci_package::hci_size_parameter_t `HCI_SIZE_PARAM(hwpe) = '{     // HWPE parameters
    DW:  4*DATA_WIDTH,
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
  assign                      ctrl_i.invert_prio = '0;
  assign                      ctrl_i.low_prio_max_stall = 8'd10;

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
  // CORES + DMA + EXT
  generate
    for(genvar ii=0; ii < N_MASTER - N_HWPE ; ii++) begin: app_driver
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
        .end_stimuli(END_STIMULI[ii])
      );
    end
  endgenerate

  // HWPE
  generate
    for(genvar ii=0; ii < N_HWPE ; ii++) begin: app_driver_hwpe
      application_driver#(
        .MASTER_NUMBER(ii),
        .IS_HWPE(1),
        .DATA_WIDTH(4*DATA_WIDTH),
        .ADD_WIDTH(ADD_WIDTH),
        .APPL_DELAY(APPL_DELAY), //delay on the input signals
        .IW(IW)
      ) app_driver_hwpe (
          .master(hwpe_intc[ii]),
          .rst_ni(rst_n),
          .clear_i(clear_i),
          .clk(clk),
          .end_stimuli(END_STIMULI[N_MASTER-N_HWPE+ii])
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
  logic [4*N_HWPE-1:0]            HIDE_HWPE = '0;
  logic [N_MASTER-N_HWPE-1:0]   HIDE_LOG = '0;

  // Declaration
  typedef struct packed {
    logic                           wen;
    logic [DATA_WIDTH - 1 : 0]      data;
    logic [ADD_WIDTH - 1 : 0]       add;
  } stimuli;

  typedef struct packed {
    logic [DATA_WIDTH - 1 : 0]      data;
    logic [AddrMemWidth - 1 : 0]    add;
  } out_intc_to_mem;


  stimuli                                         queue_stimuli_all_except_hwpe[N_MASTER-N_HWPE][$];
  stimuli                                         queue_stimuli_hwpe[N_HWPE*4][$];
  out_intc_to_mem                                 queue_out_intc_to_mem_write[N_BANKS][$];
  out_intc_to_mem                                 queue_out_intc_to_mem_read[N_BANKS][$];
  logic [DATA_WIDTH-1:0]                          queue_read[N_BANKS][$];
  logic [DATA_WIDTH-1:0]                          queue_read_master[N_MASTER-N_HWPE][$];
  logic [4*DATA_WIDTH-1:0]                        queue_read_master_hwpe[N_HWPE][$];
  logic [DATA_WIDTH-1:0]                          queue_read_hwpe[4*N_HWPE][$];
  logic                                           rolls_over_check[N_HWPE];
  logic                                           flag_read[N_BANKS];
  logic                                           flag_read_master[N_MASTER-N_HWPE];
  logic                                           flag_read_hwpe[N_HWPE];

  //------------ input queues -----------

  // Add CORES + DMA + EXT transactions to input queues
  generate
    for(genvar ii=0;ii<N_MASTER-N_HWPE;ii++) begin :  stimuli_queue_except_hwpe
      initial begin
        stimuli     in_except_hwpe;
        wait(rst_n);
        while(1) begin
          @(posedge clk);
          if(all_except_hwpe[ii].req) begin
            in_except_hwpe.wen  =   all_except_hwpe[ii].wen;
            in_except_hwpe.data =   all_except_hwpe[ii].data;
            in_except_hwpe.add  =   all_except_hwpe[ii].add;
            queue_stimuli_all_except_hwpe[ii].push_back(in_except_hwpe);
            $display("STIMULI wen = %0b data = %0b add = %0b, MASTER %0d",all_except_hwpe[ii].wen,all_except_hwpe[ii].data,all_except_hwpe[ii].add,ii);
            while(1) begin
              if(all_except_hwpe[ii].gnt) begin
                break;
              end
              @(posedge clk);
            end
          end
        end
      end
    end
  endgenerate

  // Add HWPE transactions to input queues
  generate
    for(genvar ii=0;ii<N_HWPE;ii++) begin :  stimuli_queue_hwpe
      initial begin
        stimuli     in_hwpe;
        wait(rst_n);
        while(1) begin
          @(posedge clk);
          if(hwpe_intc[ii].req) begin
            rolls_over_check[ii] = 0;
            for(int i=0;i<4;i++) begin
              in_hwpe.wen  =   hwpe_intc[ii].wen;
              create_address_and_data_hwpe(hwpe_intc[ii].add,hwpe_intc[ii].data,i,in_hwpe.add,in_hwpe.data,rolls_over_check[ii],rolls_over_check[ii]);
              $display("HWPE %0d, add to the queue %0d the address %b, time: %0t",ii,i+ii*4,in_hwpe.add,$time);
              queue_stimuli_hwpe[i+ii*4].push_back(in_hwpe);
            end
            while(1) begin
              if(hwpe_intc[ii].gnt) begin
                break;
              end
              @(posedge clk);
            end
          end
        end
      end
    end
  endgenerate
  // Read transactions: Add r_data to a queue (master side)

  generate 
    //LOG branch
    for(genvar ii=0;ii<N_MASTER-N_HWPE;ii++) begin
      always_ff @(posedge clk or negedge rst_n)
      begin
        if (~rst_n)
          flag_read_master[ii] <= 0;
        else if (all_except_hwpe[ii].req && all_except_hwpe[ii].wen && all_except_hwpe[ii].gnt)
          flag_read_master[ii] <= 1'b1;
        else
          flag_read_master[ii] <= 0;
      end

      initial begin: add_queue_read_master 
        int index_hwpe, index_master;
        wait (rst_n);
        while(1) begin
          @(posedge clk);
          if(all_except_hwpe[ii].r_valid && flag_read_master[ii]) begin
            $display("queue_read_master before: %b,master %0d,time %0t",queue_read_master[ii][0],ii,$time);
            queue_read_master[ii].push_back(all_except_hwpe[ii].r_data);
            $display("queue_read_master new element: %b,master %0d,time %0t",queue_read_master[ii][0],ii,$time);
          end
        end
      end
    end
    //HWPE branch
    for(genvar ii=0;ii<N_HWPE;ii++) begin
      always_ff @(posedge clk or negedge rst_n)
      begin
        if (~rst_n)
          flag_read_hwpe[ii] <= 0;
        else if (hwpe_intc[ii].req && hwpe_intc[ii].wen && hwpe_intc[ii].gnt)
          flag_read_hwpe[ii] <= 1'b1;
        else
          flag_read_hwpe[ii] <= 0;
      end
      initial begin: add_queue_read_hwpe_master
      int index_hwpe, index_master;
        wait (rst_n);
        while(1) begin
          @(posedge clk);
          if(hwpe_intc[ii].r_valid && flag_read_hwpe[ii]) begin
            queue_read_master_hwpe[ii].push_back(hwpe_intc[ii].r_data);
          end
        end
      end
    end
  endgenerate


  //------------------- output queues ------------------------------

  // Add transactions received by each BANK to different output queues
  generate
    for(genvar ii=0;ii<N_BANKS;ii++) begin: out_intc_write_queue
      initial begin: acquisition_out_intc
        out_intc_to_mem         out_intc_write;
        out_intc_to_mem         out_intc_read;
        wait (rst_n);
        while (1) begin
          @(posedge clk);
          if(intc_mem_wiring[ii].req && intc_mem_wiring[ii].gnt) begin
            if(!intc_mem_wiring[ii].wen) begin
              $display("acq time: %0t bank %0d", $time, ii);
              out_intc_write.data =   intc_mem_wiring[ii].data;
              out_intc_write.add  =   intc_mem_wiring[ii].add;
              $display("Element to add to the %0d WRITE output queue, data = %b, add = %b, simulation time : %t",ii,out_intc_write.data,out_intc_write.add, $time);
              queue_out_intc_to_mem_write[ii].push_back(out_intc_write);
              wait(queue_out_intc_to_mem_write[ii].size() == 0);
            end else begin
              out_intc_read.data =  intc_mem_wiring[ii].data;
              out_intc_read.add = intc_mem_wiring[ii].add;
              queue_out_intc_to_mem_read[ii].push_back(out_intc_read);
              $display("Element to add to the %0d READ output queue, data = %b, add = %b, simultaion time : %t",ii,intc_mem_wiring[ii].data,intc_mem_wiring[ii].add, $time);
              wait(queue_out_intc_to_mem_read[ii].size() == 0);
              end
            end
          end
        end
      end
  endgenerate

  // Read transactions: Add r_data to a queue (TCDM side)
  generate
    for(genvar ii=0;ii<N_BANKS;ii++) begin : flag
      /*initial begin
      wait(rst_n);
        while(1) begin
            if(intc_mem_wiring[ii].req && intc_mem_wiring[ii].gnt && intc_mem_wiring[ii].wen) begin
              flag_read[ii] = 1'b1;
            end
            else begin
              flag_read[ii] = '0;
            end
            @(posedge clk);
          end
        end*/

    always_ff @(posedge clk or negedge rst_n)
	  begin
      if (~rst_n)
        flag_read[ii] <= 0;
      else if (intc_mem_wiring[ii].req && intc_mem_wiring[ii].gnt && intc_mem_wiring[ii].wen)
        flag_read[ii] <= 1'b1;
      else
        flag_read[ii] <= 0;
	  end
  end
  endgenerate 

  generate 
    for(genvar ii=0;ii<N_BANKS;ii++) begin
      initial begin: add_queue_read_tcdm 
        int index_hwpe, index_master;
        wait (rst_n);
              while(1) begin
                //if(ii == 6)
                  //$display("intc_mem_wiring[6].r_valid = %b: time %0t",intc_mem_wiring[ii].r_valid,$time);
                  //$display("flag_read[%0d]=%b",ii,flag_read[ii]);
                @(posedge clk);
                if(intc_mem_wiring[ii].r_valid && flag_read[ii]) begin
                  $display("queue_read before: %b,bank %0d,time %0t",queue_read[ii][0],ii,$time);
                  queue_read[ii].push_back(intc_mem_wiring[ii].r_data);
                  $display("queue_read new element: %b,bank %0d,time %0t",queue_read[ii][0],ii,$time);
                  wait(queue_out_intc_to_mem_read[ii].size() == 0);
                end
              end
          
        end
      end
  endgenerate

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
        logic skip;
        int okay;
        wait (rst_n);
        while (1) begin
          okay = 0;
          wait(queue_out_intc_to_mem_write[ii].size() != 0);
          skip = 0;
          STOP_CHECK = 0;
          $display("BANK %0d: START CHECK WRITE, time:%0t",ii,$time);
          recreate_address(queue_out_intc_to_mem_write[ii][0].add,ii,recreated_queue.add);
          recreated_queue.data = queue_out_intc_to_mem_write[ii][0].data;
          recreated_queue.wen = 1'b0;
          for(int i=0;i<N_MASTER-N_HWPE;i++) begin
            if (queue_stimuli_all_except_hwpe[i].size() == 0) begin
              continue;
            end
            $display("BANK %0d: TO CHECK WRITE add = %0b, time:%0t",ii,recreated_queue.add,$time);
            $display("BANK %0d: OPTIONS wen = %0b add = %0b, MASTER %0d, time:%0t",ii,queue_stimuli_all_except_hwpe[i][0].wen,queue_stimuli_all_except_hwpe[i][0].add,i,$time);
            if (recreated_queue == queue_stimuli_all_except_hwpe[i][0]) begin
              okay = 1;
              $display("BANK %0d: FOUND CORRESPONDENCE, delete first element of queue_out_intc_to_mem_write = %b, time:%0t",ii,queue_out_intc_to_mem_write[ii][0],$time);
              queue_stimuli_all_except_hwpe[i].delete(0);
              $display("BANK %0d: AFTER DELETE queue_stimuli_all_except_hwpe = %b, time:%0t",ii,queue_stimuli_all_except_hwpe[i][0],$time);
              if(HIDE_LOG[i]) begin
                $display("-----------------------------------------");
                $display("Time %0t:    Test ***FAILED*** \n",$time);
                $display("The arbiter prioritized Master %0d, but it should have given priority to the HWPE", i);
                $finish();
              end
              $display("AFTER DELETE data = %0b add = %0b, MASTER %0d",queue_stimuli_all_except_hwpe[i][0].data,queue_stimuli_all_except_hwpe[i][0].add,i);
            end
          end
          //hwpe check branch
          if (!okay) begin
            for(int k=0;k<N_HWPE;k++) begin
              
                for(int i=0;i<4;i++)  begin
                  if (queue_stimuli_hwpe[i+k*4].size() == 0) begin
                    continue;
                  end
                  $display("BANK %0d: TO CHECK WRITE add = %0b, time:%0t",ii,recreated_queue.add,$time);
                  $display("BANK %0d: OPTIONS wen = %0b add = %0b, HWPE %0d, time:%0t",ii,queue_stimuli_hwpe[i+k*4][0].wen,queue_stimuli_hwpe[i+k*4][0].add,i+k*4,$time);
                  if (recreated_queue == queue_stimuli_hwpe[i+k*4][0])  begin
                    if(!already_checked[k]) begin
                      $display("BANK %0d: skip before %0d, time: %0t",ii,skip,$time);
                      check_hwpe(i,ii,okay,queue_stimuli_hwpe[4*k+:4],queue_out_intc_to_mem_write,skip);
                      $display("BANK %0d: skip after %0d, time: %0t",ii,skip,$time);
                      STOP_CHECK = 1;
                      //if(okay>0) begin
                      //  $display("BANK %0d: FOUND CORRESPONDENCE, delete first element of queue_out_intc_to_mem_write = %b, time:%0t",ii,queue_out_intc_to_mem_write[ii][0],$time);
                      //end
                      if(okay && HIDE_HWPE[i]) begin
                        $display("-----------------------------------------");
                        $display("Time %0t:    Test ***FAILED*** \n",$time);
                        $display("The arbiter prioritized the hwpe, but it should have given priority to the logarithmic branch", i);
                        $finish();
                      end
                      if(!skip) begin
                        hwpe_check[k]++;
                        already_checked[k] = 1;
                        $display("BANK %0d: new value for hwpe_check[%0d] = %0d, time: %0t",ii,k,hwpe_check[k],$time);
                        $display("BANK %0d: new value for already_checked[%0d] = %0d, time: %0t",ii,k,already_checked[k],$time);
                      end
                      break;
                    end else begin
                      hwpe_check[k]++;
                      okay = 1;
                      STOP_CHECK = 1;
                      $display("BANK %0d: ALREADY CHECKED new value for hwpe_check[%0d] = %0d, time: %0t",ii,k,hwpe_check[k],$time);
                    end
                  end
                end
                // while(1) begin
                //   @(posedge clk);
                //     if(hwpe_intc.gnt) begin
                //       break;
                //     end
                //   end
            
              //$display("BANK %0d: write hwpe_check = %0d time:%0t",ii,hwpe_check,$time);
              if(hwpe_check[k] == 4) begin
                hwpe_check[k] = 0;
                already_checked[k] = 0;
                  for(int i=0;i<4;i++) begin
                    $display("BANK %0d: DELETE queue_stimuli_hwpe[%0d][0] = %0b time:%0t",ii,i+k*4,queue_stimuli_hwpe[i+k*4][0],$time);
                    queue_stimuli_hwpe[i+k*4].delete(0);
                    $display("BANK %0d: AFTER DELETE queue_stimuli_hwpe[%0d][0] = %0b time:%0t",ii,i+k*4,queue_stimuli_hwpe[i+k*4][0],$time);
                  end
                end
                if(STOP_CHECK)
                  break;
            end
          end
          $display("END CHECK, eliminate data = %0b add = %0b, BANK %0d",queue_out_intc_to_mem_write[ii][0].data,queue_out_intc_to_mem_write[ii][0].add,ii);
          $display("AFTER ELIMINATE data = %0b add = %0b, BANK %0d",queue_out_intc_to_mem_write[ii][0].data,queue_out_intc_to_mem_write[ii][0].add,ii);
          $display("update n_correct, with okay = %0d, before n_correct = %0d",okay,n_correct);
          if(!okay && !skip) begin
              $display("-----------------------------------------");
              $display("Time %0t:    Test ***FAILED*** \n",$time);
              $display("Bank %0d: data = %b address = %b", ii,queue_out_intc_to_mem_write[ii][0].data,queue_out_intc_to_mem_write[ii][0].add);
              $display("This transaction does not happen in the correct order at a master level, or some values are wrong");
              $finish();
          end
          if(!skip) begin
            $display("before n_correct = %0d",n_correct);
            n_correct = n_correct + okay;
            $display("after n_correct = %0d",n_correct);
            $display("simulation time : %0t",$time);
            n_checks ++;
            $display("n_checks = %0d",n_checks);
          end
          queue_out_intc_to_mem_write[ii].delete(0);
        end
      end
    end
  endgenerate

  //------------- read transactions -------------

static logic           STOP_CHECK_READ = 0;
logic                  already_checked_read[N_HWPE] = '{default: 0};

  // Check address
  generate 
    for(genvar ii=0;ii<N_BANKS;ii++) begin
      initial begin: add_queue_read 
        logic [ADD_WIDTH - 1 : 0] recreated_address;
        logic skip;
        int okay;
        int NOT_FOUND;
        int DATA_MISMATCH;
        logic hwpe_read;
        logic [DATA_WIDTH*4-1 : 0] wide_word;
        int index_hwpe, index_master;
        wait (rst_n);
        while (1) begin
            wait(queue_out_intc_to_mem_read[ii].size() != 0);
            skip = 0;
            STOP_CHECK_READ = 0;
            $display("BANK %0d: START CHECK READ, time:%0t",ii,$time);
              NOT_FOUND = 1;
              DATA_MISMATCH = 1;
              okay = 0;
              hwpe_read = 1;
              // LOG branch
              recreate_address(queue_out_intc_to_mem_read[ii][0].add,ii,recreated_address);
              for(int i=0;i<N_MASTER-N_HWPE;i++) begin
                if (queue_stimuli_all_except_hwpe[i].size() == 0) begin
                  continue;
                end
                  $display("BANK %0d: TO CHECK READ add = %0b, time:%0t",ii,recreated_address,$time);
                  $display("BANK %0d: OPTIONS wen = %0b add = %0b, MASTER %0d, time:%0t",ii,queue_stimuli_all_except_hwpe[i][0].wen,queue_stimuli_all_except_hwpe[i][0].add,i,$time);
                  if (queue_stimuli_all_except_hwpe[i][0].wen && (recreated_address == queue_stimuli_all_except_hwpe[i][0].add)) begin
                    NOT_FOUND = 0;
                    $display("BANK %0d: FOUND CORRESPONDENCE, delete first element of queue_out_intc_to_mem_read add = %b, data = %b, time:%0t",ii,queue_out_intc_to_mem_read[ii][0].add,queue_out_intc_to_mem_read[ii][0].data,$time);
                    queue_out_intc_to_mem_read[ii].delete(0);
                    $display("BANK %0d: AFTER DELETE queue_out_intc_to_mem_read = %b, time:%0t",ii,queue_out_intc_to_mem_read[ii][0],$time);
                    $display("BANK %0d: BEFORE queue_stimuli_all_except_hwpe[i][0] add =%b, time:%0t",ii,queue_stimuli_all_except_hwpe[i][0].add,$time);
                    queue_stimuli_all_except_hwpe[i].delete(0);
                    $display("BANK %0d: AFTER DELETE queue_stimuli_all_except_hwpe[i][0] add =%b, time:%0t",ii,queue_stimuli_all_except_hwpe[i][0].add,$time);
                    hwpe_read = 0;
                    if(HIDE_LOG[i]) begin
                      $display("-----------------------------------------");
                      $display("Time %0t:    Test ***FAILED*** \n",$time);
                      $display("The arbiter prioritized Master %0d, but it should have given priority to the HWPE", i);
                      $finish();
                    end
                    wait(queue_read_master[i].size() != 0 && queue_read[ii].size() != 0);
                    $display("BANK %0d: size queue read master %0d !=0. queue_read_master = %b, queue_read = %b, time:%0t",ii,i,queue_read_master[i][0],queue_read[ii][0],$time);
                    if(queue_read_master[i][0] == queue_read[ii][0]) begin
                      $display("BANK %0d: the two first element of the queue are equal. delete the first element, time:%0t",ii,$time);
                      $display("BANK %0d: BEFORE queue_read[ii][0]=%b queue_read_master[i][0]=%b, time:%0t",ii,queue_read[ii][0],queue_read_master[i][0],$time);
                      queue_read[ii].delete(0);
                      queue_read_master[i].delete(0);
                      $display("BANK %0d: AFTER DELETE queue_read[ii][0]=%b queue_read_master[i][0]=%b, time:%0t",ii,queue_read[ii][0],queue_read_master[i][0],$time);
                      DATA_MISMATCH = 0;
                      okay = 1;
                    end
                    break;
                  end
              end
              // HWPE branch
              if(hwpe_read) begin
                for(int k=0;k<N_HWPE;k++) begin 
                  for(int i=0; i<4;i++) begin
                    if (queue_stimuli_hwpe[i+k*4].size() == 0) begin
                      continue;
                    end
                    $display("BANK %0d: TO CHECK READ add = %0b, time:%0t",ii,recreated_address,$time);
                    $display("BANK %0d: OPTIONS wen = %0b add = %0b, HWPE %0d, time:%0t",ii,queue_stimuli_hwpe[i+k*4][0].wen,queue_stimuli_hwpe[i+k*4][0].add,i+k*4,$time);
                    if(queue_stimuli_hwpe[i+k*4][0].wen && (recreated_address == queue_stimuli_hwpe[i+k*4][0].add)) begin
                        NOT_FOUND = 0;
                        STOP_CHECK_READ = 1;
                        if(!already_checked_read[k]) begin
                          check_hwpe_read_task(i,ii,queue_stimuli_hwpe[4*k+:4],queue_out_intc_to_mem_read,skip);
                          already_checked_read[k] = !skip;
                        end else begin
                          skip = 0;
                        end
                        if(!skip) begin
                          // while(1) begin
                          //   @(posedge clk);
                          //   if(hwpe_intc.gnt) begin
                          //     break;
                          //   end
                          // end
                          $display("BANK %0d: FOUND CORRESPONDENCE, time:%0t",ii,$time);
                          check_hwpe_read_add[k]++;
                          $display("BANK %0d: check_hwpe_read_add[%0d] = %0d, time:%0t",ii,k,check_hwpe_read_add[k],$time);
                          if(check_hwpe_read_add[k] == 4) begin
                            for(int j=0;j<4;j++) begin
                              $display("BANK %0d: DELETE queue_stimuli_hwpe[%0d] = %b, time:%0t",ii,4*k+j,queue_stimuli_hwpe[4*k+j][0].add,$time);
                                queue_stimuli_hwpe[4*k+j].delete(0);
                                check_hwpe_read_add[k] = 0;
                                $display("BANK %0d: AFTER queue_stimuli_hwpe[%0d] = %b, time:%0t",ii,4*k+j,queue_stimuli_hwpe[4*k+j][0].add,$time);
                              end
                              already_checked_read[k] = 0;
                          end
                          //$display("BANK %0d: check_hwpe_read_add = %0d",ii,check_hwpe_read_add);
                          //$display("BANK %0d: AFTER DELETE queue_out_intc_to_mem_read add = %b, queue_out_intc_to_mem_read data = %b, time:%0t",ii,queue_out_intc_to_mem_read[ii][0].add,queue_out_intc_to_mem_read[ii][0].data,$time);
                          if(HIDE_HWPE[i]) begin
                            $display("-----------------------------------------");
                            $display("Time %0t:    Test ***FAILED*** \n",$time);
                            $display("The arbiter prioritized the hwpe, but it should have given priority to the logarithmic branch");
                            $finish();
                          end
                          $display("BANK %0d: DELETE queue_out_intc_to_mem_read[%0d] = %b, time:%0t",ii,ii,queue_out_intc_to_mem_read[ii][0].add,$time);
                          queue_out_intc_to_mem_read[ii].delete(0);
                          $display("BANK %0d: AFTER queue_out_intc_to_mem_read[%0d] = %b, time:%0t",ii,ii,queue_out_intc_to_mem_read[ii][0].add,$time);
                          wait(queue_read_master_hwpe[k].size() != 0 && queue_read[ii].size() != 0);
                          $display("BANK %0d: size queue read master hwpe !=0. queue_read_master_hwpe = %b, queue_read = %b, time:%0t",ii,queue_read_master_hwpe[0][0],queue_read[ii][0],$time);
                          if(queue_read_master_hwpe[k][0][i*DATA_WIDTH +: DATA_WIDTH] == queue_read[ii][0]) begin
                            $display("BANK %0d: the two first element of the queue are equal. delete the first element, time:%0t",ii,$time);
                            $display("BANK %0d: BEFORE queue_read_master_hwpe[k][0]=%b queue_read[ii][0]=%b, time:%0t",ii,queue_read_master_hwpe[k][0],queue_read[ii][0],$time);
                            DATA_MISMATCH = 0;
                            okay = 1;
                            check_hwpe_read[k]++;
                            queue_read[ii].delete(0);
                            $display("BANK %0d: check_read_hwpe = %0d, time:%0t",ii,check_hwpe_read[k],$time);
                            if(check_hwpe_read[k] == 4) begin
                              $display("BANK %0d: check_read_hwpe = 4. delete the first element of queue_read_maser_hwpe, time:%0t",ii,check_hwpe_read[k],$time);
                              $display("BANK %0d: before queue_read_maser_hwpe = %0b, time:%0t",ii,queue_read_master_hwpe[k][0],$time);
                              queue_read_master_hwpe[k].delete(0);
                              check_hwpe_read[k] = 0;
                              $display("BANK %0d: after queue_read_maser_hwpe = %0b, time:%0t",ii,queue_read_master_hwpe[k][0],$time);
                            end
                            
                          end
                        end else begin
                          $display("BANK %0d: DELETE queue_out_intc_to_mem_read[%0d] = %b, time:%0t",ii,ii,queue_out_intc_to_mem_read[ii][0].add,$time);
                          queue_out_intc_to_mem_read[ii].delete(0);
                          $display("BANK %0d: AFTER queue_out_intc_to_mem_read[%0d] = %b, time:%0t",ii,ii,queue_out_intc_to_mem_read[ii][0].add,$time);
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
                $display("Bank %0d received a read req to address %b, but there's no correspondence among the one sent by the masters", ii,recreated_address);
                $display("The address may be wrong or the transaction does not arrive in the correct order");
                $display("first element of the 1 queue_stimuli_all_except_hwpe add:%b, data: %b, wen:%b",queue_stimuli_all_except_hwpe[1][0].add,queue_stimuli_all_except_hwpe[1][0].data,queue_stimuli_all_except_hwpe[1][0].wen);
                $finish();
              end
              if(DATA_MISMATCH && !skip)begin
                $display("-----------------------------------------");
                $display("Time %0t:    Test ***FAILED*** \n",$time);
                $display("The r_data is not propagated correctly through the interconnect");
                $display("r_data: %b, bank %0d",queue_read[ii][0],ii);
                $display("r_data: %b, master hwpe",queue_read_master_hwpe[0][0]);
                $finish();
              end
              if(!skip) begin
                $display("before n_correct = %0d",n_correct);
                n_correct = n_correct + okay;
                $display("after n_correct = %0d",n_correct);
                $display("simulation time : %0t",$time);
                n_checks ++;
                $display("n_checks = %0d",n_checks);
              end
            end
          end
      end
  endgenerate
  
  //--------------------------------------------
  //-             QoS: Arbiter                 -
  //--------------------------------------------

/*START COMMENT

  logic [7:0] stall_count = '0;
  logic invert_prio_for_one_cycle;
  //logic [N_MASTER-N_HWPE-1:0] PRIO;

  // Check at every cycle if there are any conflicts
  generate
    for(genvar ii=0;ii<N_MASTER-N_HWPE;ii++) begin
      initial begin
        logic [BIT_BANK_INDEX-1:0] bank_index_log;
        logic [BIT_BANK_INDEX-1:0] bank_index_hwpe;
        //PRIO[ii] = 1'b0;
        wait(rst_n);
        while(1) begin
          wait(all_except_hwpe[ii].req && hwpe_intc.req) begin
            calculate_bank_index(all_except_hwpe[ii].add,bank_index_log);
            calculate_bank_index(hwpe_intc.add,bank_index_hwpe);
            $display("Time: %0t, Start computing the priority check on master %0d, bank index log: %0d, bank index hwpe: %0d", $time,ii,bank_index_log,bank_index_hwpe);
            $display("Time: %0t, ctrl_i.invert_prio = %b, invert_prio_for_one_cycle = %b",$time,ctrl_i.invert_prio,invert_prio_for_one_cycle);
            for(int i=0;i<4;i++) begin
              if(bank_index_log == bank_index_hwpe) begin // If conflict
                if(!(ctrl_i.invert_prio ^ invert_prio_for_one_cycle)) begin // Control who has the priority
                $display("Time: %0t, hide hwpe[%0d]",$time,i);
                  HIDE_HWPE[i] = 1'b1;
                  //PRIO[ii] = 1'b1;
                  for(int j=0;j<ctrl_i.low_prio_max_stall;j++) begin
                      @(posedge clk);
                      if(all_except_hwpe[ii].gnt) begin
                        $display("Time: %0t, show hwpe[%0d]",$time,i);
                        #1ps;
                        break;
                      end
                  end
                  //PRIO[ii] = 1'b0;
                  HIDE_HWPE[i] = 1'b0;
                end else begin
                  $display("Time: %0t, hide master %0d",$time,ii);
                  HIDE_LOG[ii] = 1'b1;
                  for(int j=0;j<ctrl_i.low_prio_max_stall;j++) begin
                    @(posedge clk);
                    if(all_except_hwpe[ii].gnt) begin
                      #1ps;
                      break;
                    end
                  end
                  HIDE_LOG[ii] = 1'b0;
                end
                break;
              end
              bank_index_hwpe++;
              if(bank_index_hwpe >= N_BANKS ) begin
                bank_index_hwpe = bank_index_hwpe - N_BANKS;
              end
              if(i == 3) begin
                @(posedge clk);
              end
            end
          end
        end
      end
    end
  endgenerate

  // Count the number of stalls
  always_ff @(posedge clk or negedge rst_n)
	begin
		if (~rst_n)
			stall_count <= '0;
    else if (invert_prio_for_one_cycle)
      stall_count <= '0;
		else if ((|HIDE_HWPE) || (|HIDE_LOG)) begin
			stall_count <= stall_count + 1'b1;
      $display("STAL COUNT = %0d, time %0t",stall_count,$time);
    end else
			stall_count <= '0;
	end

  initial begin
    if (ctrl_i.low_prio_max_stall > 0)  begin : invert_prio_for_one_cycle_initial
      invert_prio_for_one_cycle = 1'b0;
      wait(rst_n);
      while(1) begin
        wait(stall_count > ctrl_i.low_prio_max_stall - 2);
        invert_prio_for_one_cycle = 1'b1;
        @(posedge clk);
        invert_prio_for_one_cycle = 1'b0;
        // $display("-----------------------------------------");
        // $display("Time %0t:    Test ***FAILED*** \n",$time);
        // $display("The channel with lower priority was stalled for %b (%0d), but the signal ctrl_i.low_prio_max_stall is %b (%0d), check = %b",stall_count,stall_count,ctrl_i.low_prio_max_stall,ctrl_i.low_prio_max_stall,stall_count > ctrl_i.low_prio_max_stall);
        // $finish();



    end
  end
  end



END COMMENT*/




  /*// Check low_prio_max_stall
  initial begin
    if (ctrl_i.low_prio_max_stall > 0)  begin
      wait(rst_n);
      wait(stall_count > ctrl_i.low_prio_max_stall);
      $display("-----------------------------------------");
      $display("Time %0t:    Test ***FAILED*** \n",$time);
      $display("The channel with lower priority was stalled for %b (%0d), but the signal ctrl_i.low_prio_max_stall is %b (%0d), check = %b",stall_count,stall_count,ctrl_i.low_prio_max_stall,ctrl_i.low_prio_max_stall,stall_count > ctrl_i.low_prio_max_stall);
      $finish();
    end
  end
*/
  //--------------------------------------------
  //-             REAL BANDWIDTH               -
  //--------------------------------------------
  static real                 band_real;
  initial begin
    time                 start_time, end_time;
    real                 tot_time,tot_data;
    band_real = -1;
    wait(rst_n);
    start_time = $time;
    $display("--------------------------START TIME : %0t",start_time);
    wait(&END_STIMULI);
    end_time = $time;
    $display("--------------------------STOP TIME : %0t",end_time);
    $display("START TIME: %f",start_time);
    tot_time = end_time - start_time; // ns
    $display("tot_time_real: %f",tot_time);
    tot_data = ((N_TEST * DATA_WIDTH) * (N_MASTER - N_HWPE) + (N_TEST * 4*DATA_WIDTH) * N_HWPE); // bit
    $display("tot_data_real: %f",tot_data);
    band_real = tot_data/tot_time; // Gbps
    $display("band_real: %f",band_real);

  end
  //--------------------------------------------
  //-             END OF SIMULATION            -
  //--------------------------------------------

 static real                   band_theo;
 logic                         WARNING = 1'b0;
  initial begin
    wait (n_checks >= N_TEST*(N_MASTER-N_HWPE)+N_HWPE*N_TEST*4);
    $display("n_checks final = %0d",n_checks);
    $display("------ Simulation End ------");
    if(n_correct == N_TEST*(N_MASTER-N_HWPE)+N_HWPE*N_TEST*4) begin
      $display("    Test ***PASSED*** \n");
    end else begin
      $display("    Test ***FAILED*** \n");
    end
    $display("n_correct = %0d out of n_check = %0d",n_correct,n_checks);
    $display("expected n_check = %0d",N_TEST*(N_MASTER-N_HWPE)+N_HWPE*N_TEST*4);
    $display("note: each hwpe transaction consists of 4 checks");
    calculate_theoretical_bandwidth(band_theo);
    wait(band_real>=0);
    $display("THEORETICAL BANDWIDTH: %f Gbps",band_theo);
    $display("REAL BANDWIDTH: %f Gbps",band_real);
    if(WARNING) begin
      $display("WARNING: the pieces of the HWPE wide word are written multiple times in the banks\n");
    end
    $finish();
  end

/*
  //--------------------------------------------
  //-       CHECK ERRORS IN APP DRIVERS        -
  //--------------------------------------------
  generate
    for(genvar i=0;i<N_MASTER-N_HWPE;i++) begin
      for(genvar j=i+1;j<N_MASTER-N_HWPE;j++) begin
        initial begin
          while(1) begin
            @(posedge clk);
            if(all_except_hwpe[i].req &&all_except_hwpe[j].req) begin
              assert (all_except_hwpe[i].add[ADD_WIDTH-1:2] != all_except_hwpe[j].add[ADD_WIDTH-1:2])
                else begin
                  $warning("Master %0d and Master %0d are attempting to make a request to the same address.",i,j);
                  //all_except_hwpe[i].add[ADD_WIDTH-1:2] = all_except_hwpe[j].add[ADD_WIDTH-1:2] + 1;
                end
            end
          end
        end
      end
      initial begin
        while(1) begin
          @(posedge clk);
          if(all_except_hwpe[i].req && hwpe_intc.req) begin
            assert (all_except_hwpe[i].add[ADD_WIDTH-1:2] != hwpe_intc.add[ADD_WIDTH-1:2])
              else begin
                $warning("Master %0d and HWPE are attempting to make a request to the same address. Added 1 to Master%0d's address",i,i);
                //all_except_hwpe[i].add[ADD_WIDTH-1:2] = all_except_hwpe[i].add[ADD_WIDTH-1:2] + 1;
              end
          end
        end
      end
    end
  endgenerate
*/
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

  task create_address_and_data_hwpe(input logic[ADD_WIDTH-1:0] address_before,input logic [4*DATA_WIDTH-1:0] data_before, input int index, output logic [ADD_WIDTH-1:0] address_after, output logic [DATA_WIDTH-1:0] data_after, input rolls_over_check_before, output rolls_over_check_after);
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
      //$display("queue hwpe before: data = %0b add = %0b rolls_before = %b rolls_after = %b",data_before,address_before,rolls_over_check_before,rolls_over_check_after);
      //$display("queue hwpe after: data = %0b add = %0b",data_after,address_after);
    end
  endtask

  task check_hwpe(input int unsigned index_hwpe_already_checked, input int unsigned index_bank_already_checked,output int okay,input stimuli queue_stimuli_hwpe[4][$], input out_intc_to_mem queue_out_intc_to_mem_write[N_BANKS][$], output logic skip);
  int signed index_hwpe_to_check;
  int signed index_bank_to_check;
  stimuli recreated_queue;
  $display("BANK %0d: start checking adjacent banks for hwpe write",index_bank_already_checked);
  $display("BANK %0d: this bank corresponde to the %0d kwpe index",index_bank_already_checked,index_hwpe_already_checked);
  //$display("index_hwpe_already_checked %0d", index_hwpe_already_checked);
  //$display("index_bank_already_checked %0d", index_bank_already_checked);
  skip = 0;
  okay = 1;
  for(int i=1; i<4; i++) begin
    index_hwpe_to_check = index_hwpe_already_checked + i;
    index_bank_to_check = index_bank_already_checked + i;
    if(index_hwpe_to_check > 3) begin
      //$display("before index_bank_to_check %0d",index_bank_to_check);
      index_hwpe_to_check = index_hwpe_to_check - 4;
      index_bank_to_check = index_bank_to_check -4;
      //$display("after index_bank_to_check %0d",index_bank_to_check);
    end
    if(index_bank_to_check >= int'(N_BANKS)) begin 
      index_bank_to_check = index_bank_to_check - N_BANKS;

    end
    if(index_bank_to_check < 0) begin
      //$display("before index_bank_to_check %0d",index_bank_to_check);
      index_bank_to_check = index_bank_to_check + N_BANKS;
      //$display("added N_BANKS %0d, now index_bank_to_check = %0d",N_BANKS,index_bank_to_check);
    end
    recreate_address(queue_out_intc_to_mem_write[index_bank_to_check][0].add,index_bank_to_check,recreated_queue.add);
    recreated_queue.data = queue_out_intc_to_mem_write[index_bank_to_check][0].data;
    //$display("Bank to check %0d: wen = %b data = %b address = %b", index_bank_to_check, queue_out_intc_to_mem_write[index_bank_to_check][0].wen,queue_out_intc_to_mem_write[index_bank_to_check][0].data,queue_out_intc_to_mem_write[index_bank_to_check][0].add);
    //$display("Bank to check %0d", index_bank_to_check);
    $display("BANK %0d: checking adjacent bank %0d, recreated_queue.add = %0b",index_bank_already_checked,index_bank_to_check,recreated_queue.add);
    $display("BANK %0d: checking %0d index hwpe, queue_stimuli_hwpe = %0b",index_bank_already_checked,index_hwpe_to_check,queue_stimuli_hwpe[index_hwpe_to_check][0].add);
    if(recreated_queue != queue_stimuli_hwpe[index_hwpe_to_check][0] || queue_out_intc_to_mem_write[index_bank_to_check].size()==0) begin
      //okay = 0;
      skip=1;
      WARNING = 1'b1;
      //$display("-----------------------------------------");
      //$display("Time %0t: ***WARNING*** \n",$time);
      //$display("the pieces of the HWPE wide word are not written in the same clock cycle\n",$time);
      //$display("Time %0t:    Test ***FAILED*** \n",$time);
      //$display("ERROR in hwpe branch during write-transaction check\n");
      //$display("Wide-word and address sent by hwpe: DATA %b%b%b%b ADD %b", queue_stimuli_hwpe[0][0].data,queue_stimuli_hwpe[1][0].data,queue_stimuli_hwpe[2][0].data,queue_stimuli_hwpe[3][0].data,queue_stimuli_hwpe[0][0].add);
      // $display("Wrong piece received by bank %0d: DATA %b ADD %b \n",index_bank_to_check,recreated_queue.data,recreated_queue.add);
      //$finish();
    end
  end
  endtask
/*
  task create_wide_word_read_hwpe(input logic [DATA_WIDTH-1:0] queue_read_hwpe[4*N_HWPE][$], output logic [4*DATA_WIDTH-1:0] wide_word_to_add);
    for(int i=0; i<4; i++) begin
      wide_word_to_add[i*DATA_WIDTH +: DATA_WIDTH] = queue_read_hwpe[i][0];
    end
  endtask
*/
  task calculate_bank_index(input logic [ADD_WIDTH-1:0] address, output logic [BIT_BANK_INDEX-1:0] index);
    index = address[BIT_BANK_INDEX-1+2:2];
  endtask

  task check_hwpe_read_task(input int unsigned index_hwpe_already_checked,input int unsigned index_bank_already_checked,input stimuli queue_stimuli_hwpe[4][$],input out_intc_to_mem queue_out_intc_to_mem_read[N_BANKS][$],output logic skip);
    int signed index_hwpe_to_check;
    int signed index_bank_to_check;
    stimuli recreated_queue;
    skip = 0;
    $display("BANK %0d: start checking adjacent banks for hwpe read",index_bank_already_checked);
    $display("BANK %0d: this bank corresponde to the %0d kwpe index",index_bank_already_checked,index_hwpe_already_checked);
    for(int i=1; i<4; i++) begin
      index_hwpe_to_check = index_hwpe_already_checked + i;
      index_bank_to_check = index_bank_already_checked + i;
      if(index_hwpe_to_check > 3) begin
        //$display("before index_bank_to_check %0d",index_bank_to_check);
        index_hwpe_to_check = index_hwpe_to_check - 4;
        index_bank_to_check = index_bank_to_check -4;
        //$display("after index_bank_to_check %0d",index_bank_to_check);
      end
      if(index_bank_to_check >= int'(N_BANKS)) begin 
        index_bank_to_check = index_bank_to_check - N_BANKS;

      end
      if(index_bank_to_check < 0) begin
        //$display("before index_bank_to_check %0d",index_bank_to_check);
        index_bank_to_check = index_bank_to_check + N_BANKS;
        //$display("added N_BANKS %0d, now index_bank_to_check = %0d",N_BANKS,index_bank_to_check);
      end
      recreate_address(queue_out_intc_to_mem_read[index_bank_to_check][0].add,index_bank_to_check,recreated_queue.add);
      recreated_queue.data = queue_out_intc_to_mem_read[index_bank_to_check][0].data;
      //$display("Bank to check %0d: wen = %b data = %b address = %b", index_bank_to_check, queue_out_intc_to_mem_write[index_bank_to_check][0].wen,queue_out_intc_to_mem_write[index_bank_to_check][0].data,queue_out_intc_to_mem_write[index_bank_to_check][0].add);
      //$display("Bank to check %0d", index_bank_to_check);
      $display("BANK %0d: checking adjacent bank %0d, recreated_queue add = %0b",index_bank_already_checked,index_bank_to_check,recreated_queue);
      $display("BANK %0d: checking %0d index hwpe, queue_stimuli_hwpe = %0b",index_bank_already_checked,index_hwpe_to_check,queue_stimuli_hwpe[index_hwpe_to_check][0].add);
      $display("BANK %0d: queue_out_intc_to_mem_read[index_bank_to_check].size() = %0d",index_bank_already_checked,queue_out_intc_to_mem_read[index_bank_to_check].size());
      if(recreated_queue != queue_stimuli_hwpe[index_hwpe_to_check][0] || queue_out_intc_to_mem_read[index_bank_to_check].size()==0) begin
        //okay = 0;
        skip = 1;
        WARNING = 1'b1;
        //$display("-----------------------------------------");
        //$display("Time %0t: ***WARNING*** \n",$time);
        //$display("the pieces of the HWPE wide word are not read in the same clock cycle\n",$time);
        //$display("Time %0t:    Test ***FAILED*** \n",$time);
        //$display("ERROR in hwpe branch during write-transaction check\n");
        //$display("Wide-word and address sent by hwpe: DATA %b%b%b%b ADD %b", queue_stimuli_hwpe[0][0].data,queue_stimuli_hwpe[1][0].data,queue_stimuli_hwpe[2][0].data,queue_stimuli_hwpe[3][0].data,queue_stimuli_hwpe[0][0].add);
        // $display("Wrong piece received by bank %0d: DATA %b ADD %b \n",index_bank_to_check,recreated_queue.data,recreated_queue.add);
        //$finish();
      end
    end
  endtask

  task calculate_theoretical_bandwidth(output real band_theo);
    
    int file, line_count, ret_code;
    real tot_time,tot_data;
    string line;

    file = $fopen("./verif/simvectors/stimuli_processed/master_log_0.txt","r");
    if (file == 0) begin
      $dispay("ERROR: cannot open file master_log_0.txt");
      $finish();
    end

    line_count = 0;

    while(!$feof(file)) begin
      ret_code = $fgets(line,file);
      line_count++;
    end
    $display("N_LINES: %f",line_count);
    $fclose(file);

    tot_time = line_count * CLK_PERIOD; // ns
    $display("tot_time: %f",tot_time);
    tot_data = ((N_TEST * DATA_WIDTH) * (N_MASTER - N_HWPE) + (N_TEST * 4*DATA_WIDTH) * N_HWPE); // bit
    $display("tot_data: %f",tot_data);
    band_theo = tot_data/tot_time; // Gbps
    $display("band_theo: %f",band_theo);
  endtask

endmodule
