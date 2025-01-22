package verification_hci_package;
  
  parameter int unsigned DATA_WIDTH = `DATA_WIDTH;
  parameter int unsigned ADD_WIDTH = $clog2(`TOT_MEM_SIZE*1000);
  parameter int unsigned AddrMemWidth = ADD_WIDTH-$clog2(`N_BANKS);

  typedef struct packed {
    logic                       wen;
    logic [DATA_WIDTH-1:0]      data;
    logic [ADD_WIDTH-1:0]       add;
  } stimuli;

  typedef struct packed {
    logic [DATA_WIDTH - 1 : 0]      data;
    logic [AddrMemWidth - 1 : 0]    add;
  } out_intc_to_mem;


endpackage