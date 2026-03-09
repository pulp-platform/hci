# If GUI is 1, spawn waveforms
if {$GUI == 1} {
    echo "GUI mode enabled"
    log -r /*

    set N_CORE [examine -radix dec /tb_hci_pkg/N_CORE]
    set N_DMA [examine -radix dec /tb_hci_pkg/N_DMA]
    set N_EXT [examine -radix dec /tb_hci_pkg/N_EXT]
    set N_HWPE [examine -radix dec /tb_hci_pkg/N_HWPE]
    set N_BANKS [examine -radix dec /tb_hci_pkg/N_BANKS]

    set N_LOG_MASTERS [examine -radix dec /tb_hci_pkg/N_LOG_MASTERS]
    set N_DRIVERS [examine -radix dec /tb_hci_pkg/N_DRIVERS]
    set N_NARROW_HCI [examine -radix dec /tb_hci_pkg/N_NARROW_HCI]
    set N_WIDE_HCI [examine -radix dec /tb_hci_pkg/N_WIDE_HCI]
    set HWPE_WIDTH_FACT [examine -radix dec /tb_hci_pkg/HWPE_WIDTH_FACT]
    set INTERCO_TYPE [examine /tb_hci_pkg/INTERCO_TYPE]
    set MAX_FENCES [examine -radix dec /tb_hci_pkg/MAX_FENCES]

    add wave -noupdate /tb_hci/clk
    add wave -noupdate /tb_hci/rst_n

    add wave -noupdate -divider Interfaces
    # -------------------------------------------------------------------------
    # Application-driver interfaces
    # -------------------------------------------------------------------------
    add wave -noupdate -group driver_side -divider narrow_masters
    for {set i 0} {$i < $N_LOG_MASTERS} {incr i} {
        add wave -noupdate -group driver_side -group log_$i /tb_hci/hci_driver_log_if[$i]/*
    }

    add wave -noupdate -group driver_side -divider hwpe_masters
    for {set i 0} {$i < $N_HWPE} {incr i} {
        add wave -noupdate -group driver_side -group hwpe_$i /tb_hci/hci_driver_hwpe_if[$i]/*
    }

    # -------------------------------------------------------------------------
    # Interconnect-side interfaces
    # -------------------------------------------------------------------------
    add wave -noupdate -group hci_initiator_side -divider narrow_cores
    for {set i 0} {$i < $N_CORE} {incr i} {
        add wave -noupdate -group hci_initiator_side -group core_$i /tb_hci/hci_initiator_narrow[$i]/*
    }

    if {[string first "LOG" $INTERCO_TYPE] != -1} {
        add wave -noupdate -group hci_initiator_side -divider narrow_hwpe_split
        for {set i 0} {$i < $N_HWPE} {incr i} {
            for {set f 0} {$f < $HWPE_WIDTH_FACT} {incr f} {
                set idx [expr {$N_CORE + $i * $HWPE_WIDTH_FACT + $f}]
                if {$idx < $N_NARROW_HCI} {
                    add wave -noupdate -group hci_initiator_side -group hwpe_$i -group lane_$f /tb_hci/hci_initiator_narrow[$idx]/*
                }
            }
        }
    }

    if {$N_WIDE_HCI > 0} {
        add wave -noupdate -group hci_initiator_side -divider wide_hwpe
        for {set i 0} {$i < $N_WIDE_HCI} {incr i} {
            add wave -noupdate -group hci_initiator_side -group wide_$i /tb_hci/hci_initiator_wide[$i]/*
        }
    }

    add wave -noupdate -group hci_initiator_side -divider dma
    for {set i 0} {$i < $N_DMA} {incr i} {
        add wave -noupdate -group hci_initiator_side -group dma_$i /tb_hci/hci_initiator_dma[$i]/*
    }

    add wave -noupdate -group hci_initiator_side -divider ext
    for {set i 0} {$i < $N_EXT} {incr i} {
        add wave -noupdate -group hci_initiator_side -group ext_$i /tb_hci/hci_initiator_ext[$i]/*
    }

    # -------------------------------------------------------------------------
    # Memory slaves
    # -------------------------------------------------------------------------
    add wave -noupdate -group memory_targets
    for {set i 0} {$i < $N_BANKS} {incr i} {
        add wave -noupdate -group memory_targets -group bank_$i /tb_hci/hci_target_mems[$i]/*
    }

    add wave -noupdate -divider "Application drivers"
    # -------------------------------------------------------------------------
    # Per-driver driver internals (req/resp FSM states, counters)
    # -------------------------------------------------------------------------
    add wave -noupdate -group driver_internals -divider log_masters
    for {set i 0} {$i < $N_LOG_MASTERS} {incr i} {
        add wave -noupdate -group driver_internals -group log_$i \
            /tb_hci/gen_app_driver_log[$i]/i_app_driver_log/req_state_q
        add wave -noupdate -group driver_internals -group log_$i \
            /tb_hci/gen_app_driver_log[$i]/i_app_driver_log/resp_state_q
        add wave -noupdate -group driver_internals -group log_$i \
            /tb_hci/gen_app_driver_log[$i]/i_app_driver_log/tr_idx_q
        add wave -noupdate -group driver_internals -group log_$i \
            /tb_hci/gen_app_driver_log[$i]/i_app_driver_log/n_req_issued_q
        add wave -noupdate -group driver_internals -group log_$i \
            /tb_hci/gen_app_driver_log[$i]/i_app_driver_log/n_rd_req_issued_q
        add wave -noupdate -group driver_internals -group log_$i \
            /tb_hci/gen_app_driver_log[$i]/i_app_driver_log/n_rd_resp_retired_q
        add wave -noupdate -group driver_internals -group log_$i \
            /tb_hci/gen_app_driver_log[$i]/i_app_driver_log/fence_reached_o
        add wave -noupdate -group driver_internals -group log_$i \
            /tb_hci/gen_app_driver_log[$i]/i_app_driver_log/end_resp_o
        add wave -noupdate -group driver_internals -group log_$i \
            /tb_hci/gen_app_driver_log[$i]/i_app_driver_log/resume_i
    }

    add wave -noupdate -group driver_internals -divider hwpe_masters
    for {set i 0} {$i < $N_HWPE} {incr i} {
        add wave -noupdate -group driver_internals -group hwpe_$i \
            /tb_hci/gen_app_driver_hwpe[$i]/i_app_driver_hwpe/req_state_q
        add wave -noupdate -group driver_internals -group hwpe_$i \
            /tb_hci/gen_app_driver_hwpe[$i]/i_app_driver_hwpe/resp_state_q
        add wave -noupdate -group driver_internals -group hwpe_$i \
            /tb_hci/gen_app_driver_hwpe[$i]/i_app_driver_hwpe/tr_idx_q
        add wave -noupdate -group driver_internals -group hwpe_$i \
            /tb_hci/gen_app_driver_hwpe[$i]/i_app_driver_hwpe/n_req_issued_q
        add wave -noupdate -group driver_internals -group hwpe_$i \
            /tb_hci/gen_app_driver_hwpe[$i]/i_app_driver_hwpe/n_rd_req_issued_q
        add wave -noupdate -group driver_internals -group hwpe_$i \
            /tb_hci/gen_app_driver_hwpe[$i]/i_app_driver_hwpe/n_rd_resp_retired_q
        add wave -noupdate -group driver_internals -group hwpe_$i \
            /tb_hci/gen_app_driver_hwpe[$i]/i_app_driver_hwpe/fence_reached_o
        add wave -noupdate -group driver_internals -group hwpe_$i \
            /tb_hci/gen_app_driver_hwpe[$i]/i_app_driver_hwpe/end_resp_o
        add wave -noupdate -group driver_internals -group hwpe_$i \
            /tb_hci/gen_app_driver_hwpe[$i]/i_app_driver_hwpe/resume_i
    }

    add wave -noupdate -divider Testbench
    # -------------------------------------------------------------------------
    # Fence / synchronization signals
    # -------------------------------------------------------------------------
    add wave -noupdate -group fence_sync /tb_hci/s_end_resp
    add wave -noupdate -group fence_sync /tb_hci/s_fence_reached
    add wave -noupdate -group fence_sync /tb_hci/s_resume

    for {set i 0} {$i < $N_DRIVERS} {incr i} {
        add wave -noupdate -group fence_sync -group fence_idx /tb_hci/fence_idx[$i]
    }

    # MUX sel (only present when INTERCO_TYPE == MUX)
    if {[string first "MUX" $INTERCO_TYPE] != -1} {
        add wave -noupdate -group fence_sync /tb_hci/gen_hwpe_mux/s_mux_sel
    }


    # -------------------------------------------------------------------------
    # Metrics
    # -------------------------------------------------------------------------
    add wave -noupdate -group metrics /tb_hci/s_issued_transactions
    add wave -noupdate -group metrics /tb_hci/s_issued_read_transactions
    add wave -noupdate -group metrics /tb_hci/tot_latency
    add wave -noupdate -group metrics /tb_hci/latency_per_master
    add wave -noupdate -group metrics /tb_hci/throughput_completed
    add wave -noupdate -group metrics /tb_hci/N_GNT_TRANSACTIONS_LOG
    add wave -noupdate -group metrics /tb_hci/N_GNT_TRANSACTIONS_HWPE
    add wave -noupdate -group metrics /tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG
    add wave -noupdate -group metrics /tb_hci/N_READ_GRANTED_TRANSACTIONS_HWPE
    add wave -noupdate -group metrics /tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG
    add wave -noupdate -group metrics /tb_hci/N_READ_COMPLETE_TRANSACTIONS_HWPE
    add wave -noupdate -group metrics /tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG
    add wave -noupdate -group metrics /tb_hci/N_WRITE_GRANTED_TRANSACTIONS_HWPE
    add wave -noupdate -group metrics /tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG
    add wave -noupdate -group metrics /tb_hci/SUM_REQ_TO_GNT_LATENCY_HWPE

    # -------------------------------------------------------------------------
    # HCI control
    # -------------------------------------------------------------------------
    add wave -noupdate /tb_hci/s_clear
    add wave -noupdate /tb_hci/s_hci_ctrl

    configure wave -signalnamewidth 1
} else {
    run -a
}
