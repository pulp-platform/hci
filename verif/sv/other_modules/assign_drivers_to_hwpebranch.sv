module assign_drivers_to_hwpebranch
  import hci_package::*;
#(
    parameter int unsigned     DRIVER_ID = 1,
    parameter int unsigned     HWPE_WIDTH = 4,
    parameter int unsigned     DATA_WIDTH_CORE = 32
)(
    hci_core_intf.target       driver_target,
    hci_core_intf.initiator    hci_initiator
);

  localparam logic[DATA_WIDTH_CORE-1:0] DRIVER_ID_logic = DRIVER_ID[DATA_WIDTH_CORE-1:0];


  assign hci_initiator.data    = hci_initiator.wen ? { HWPE_WIDTH {DRIVER_ID_logic}} : driver_target.data;

  assign hci_initiator.req     = driver_target.req;
  assign driver_target.gnt     = hci_initiator.gnt;
  assign hci_initiator.add     = driver_target.add;
  assign hci_initiator.wen     = driver_target.wen;
  assign hci_initiator.be      = driver_target.be;
  assign hci_initiator.r_ready = driver_target.r_ready;
  assign hci_initiator.user    = driver_target.user;
  assign hci_initiator.id      = driver_target.id;
  assign driver_target.r_data  = hci_initiator.r_data;
  assign driver_target.r_valid = hci_initiator.r_valid;
  assign driver_target.r_user  = hci_initiator.r_user;
  assign driver_target.r_id    = hci_initiator.r_id;
  assign driver_target.r_opc   = hci_initiator.r_opc;

  // ECC signals
  assign hci_initiator.ereq     = driver_target.ereq;
  assign driver_target.egnt     = hci_initiator.egnt;
  assign driver_target.r_evalid = hci_initiator.r_evalid;
  assign hci_initiator.r_eready = driver_target.r_eready;
  assign hci_initiator.ecc      = driver_target.ecc;
  assign driver_target.r_ecc    = hci_initiator.r_ecc;

endmodule