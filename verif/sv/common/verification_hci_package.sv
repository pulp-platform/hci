package verification_hci_package;

  ////////////////////////
  //PARAMETERS          //
  ////////////////////////
  
  // Timing parameters
  localparam time         CLK_PERIOD           = `ifdef CLK_PERIOD `CLK_PERIOD `else 6 `endif,;
  localparam time         APPL_DELAY           = 0;
  localparam unsigned     RST_CLK_CYCLES       = `ifdef RST_CLK_CYCLES `RST_CLK_CYCLES `else 10 `endif;

  // HCI parameters
  localparam int unsigned N_HWPE_REAL          = `ifdef N_HWPE `N_HWPE `else 1 `endif                                                    ; // Number of HWPEs attached to the port
  localparam int unsigned N_CORE_REAL          = `ifdef N_CORE `N_CORE `else 1 `endif                                                    ; // Number of Core ports
  localparam int unsigned N_DMA_REAL           = `ifdef N_DMA `N_DMA `else 1 `endif                                                      ; // Number of DMA ports
  localparam int unsigned N_EXT_REAL           = `ifdef N_EXT `N_EXT `else 1 `endif                                                      ; // Number of External ports
  localparam int unsigned N_HWPE               = (N_HWPE_REAL == 0) ? 1 : N_HWPE_REAL                                                    ; // Number of HWPEs attached to the port
  localparam int unsigned N_CORE               = (N_CORE_REAL == 0) ? 1 : N_CORE_REAL                                                    ; // Number of Core ports
  localparam int unsigned N_DMA                = (N_DMA_REAL == 0) ? 1 : N_DMA_REAL                                                      ; // Number of DMA ports
  localparam int unsigned N_EXT                = (N_EXT_REAL == 0) ? 1 : N_EXT_REAL                                                      ; // Number of External ports
  localparam int unsigned N_MASTER             = N_HWPE + N_CORE + N_DMA + N_EXT                                                         ; // Total number of masters
  localparam int unsigned N_MASTER_REAL        = N_HWPE_REAL + N_CORE_REAL + N_DMA_REAL + N_EXT_REAL                                     ; // Total number of masters
  localparam int unsigned TS_BIT               = `ifdef TS_BIT `TS_BIT `else 0 `endif                                                    ; // TEST_SET_BIT (for Log Interconnect)
  localparam int unsigned IW                   = $clog2(N_TRANSACTION_LOG*(N_MASTER_REAL-N_HWPE_REAL)+N_TRANSACTION_HWPE*N_HWPE_REAL)    ; // ID Width
  localparam int unsigned EXPFIFO              = `ifdef EXPFIFO `EXPFIFO `else 0 `endif                                                  ; // FIFO Depth for HWPE Interconnect
  localparam int unsigned SEL_LIC              = `ifdef SEL_LIC `SEL_LIC `else 0 `endif                                                  ; // Log interconnect type selector

  localparam int unsigned DATA_WIDTH           = `ifdef DATA_WIDTH `DATA_WIDTH `else 32 `endif                                           ; // Width of DATA in bits
  localparam int unsigned HWPE_WIDTH           = `ifdef HWPE_WIDTH `HWPE_WIDTH `else 4 `endif                                            ; // Widht of an HWPE wide-word (as a multiple of DATA_WIDTH)
  localparam int unsigned TOT_MEM_SIZE         = `ifdef TOT_MEM_SIZE `TOT_MEM_SIZE `else 32 `endif                                       ; // Memory size (kB)
  localparam int unsigned ADD_WIDTH            = $clog2(TOT_MEM_SIZE*1024)                                                               ; // Width of ADDRESS in bits
  localparam int unsigned N_BANKS              = `ifdef N_BANKS `N_BANKS `else 16 `endif                                                 ; // Number of memory banks
  localparam int unsigned WIDTH_OF_MEMORY      = DATA_WIDTH                                                                              ; // Width of a memory bank (bits)
  localparam int unsigned WIDTH_OF_MEMORY_BYTE = WIDTH_OF_MEMORY/8                                                                       ; // Width of a memory bank (bytes)
  localparam int unsigned BIT_BANK_INDEX       = $clog2(N_BANKS)                                                                         ; // Bits of the Bank index
  localparam int unsigned AddrMemWidth         = ADD_WIDTH - BIT_BANK_INDEX                                                              ; // Number of address bits per TCDM bank
  localparam int unsigned N_WORDS              = (TOT_MEM_SIZE*1024/N_BANKS)/WIDTH_OF_MEMORY_BYTE                                        ; // Number of words in a bank
  localparam int unsigned FILTER_WRITE_R_VALID = '0;

  localparam int unsigned ARBITER_MODE         = (`ifdef PRIORITY_CHECK_MODE_ONE `PRIORITY_CHECK_MODE_ONE `else 0 == 1) ? 1 : 0          ;// Choosen mode for the arbiter
  localparam int unsigned INVERT_PRIO          = `ifdef INVERT_PRIO `INVERT_PRIO `else 0 `endif
  localparam int unsigned LOW_PRIO_MAX_STALL   = `ifdef LOW_PRIO_MAX_STALL `LOW_PRIO_MAX_STALL `else 3 `endif
  // Simulation parameters
  localparam int unsigned N_TRANSACTION_LOG    = `ifdef N_TRANSACTION_LOG `N_TRANSACTION_LOG `else 10 `endif;
  localparam int unsigned TRANSACTION_RATIO    = `ifdef TRANSACTION_RATIO `TRANSACTION_RATIO `else 1 `endif;
  localparam int unsigned N_TRANSACTION_HWPE   = int'(N_TRANSACTION_LOG*TRANSACTION_RATIO);
  localparam int unsigned TOT_CHECK            = N_TRANSACTION_LOG*(N_CORE_REAL + N_DMA_REAL + N_EXT_REAL)+N_HWPE_REAL*N_TRANSACTION_HWPE*HWPE_WIDTH;

  ////////////////////////
  //STRUCT              //
  ////////////////////////
  typedef struct packed {
    logic                  wen;
    logic [DATA_WIDTH-1:0] data;
    logic [ADD_WIDTH-1:0]  add;
  } stimuli;

  typedef struct packed {
    logic [DATA_WIDTH - 1 : 0]   data;
    logic [AddrMemWidth - 1 : 0] add;
  } out_intc_to_mem;

  ////////////////////////
  //TASK                //
  ////////////////////////
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

//Functions
function int manipulate_add(input logic [ADD_WIDTH-1:0] add);
  logic [ADD_WIDTH-1:0] manipulated_add;
  logic [ADD_WIDTH-BIT_BANK_INDEX-1:0] bank_level_manipulated_add;
  logic [DATA_WIDTH-1:0] ret_1;
  logic ret_2;

  create_address_and_data_hwpe(add,'0,HWPE_WIDTH,manipulated_add,ret_1,'0,ret_2);
  bank_level_manipulated_add = {manipulated_add[ADD_WIDTH-1:BIT_BANK_INDEX + 2],manipulated_add[1:0]};
  return int'(bank_level_manipulated_add);
endfunction

endpackage