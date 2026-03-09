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
    set N_NARROW_HCI [examine -radix dec /tb_hci_pkg/N_NARROW_HCI]
    set N_WIDE_HCI [examine -radix dec /tb_hci_pkg/N_WIDE_HCI]
    set HWPE_WIDTH_FACT [examine -radix dec /tb_hci_pkg/HWPE_WIDTH_FACT]
    set INTERCO_TYPE [examine /tb_hci_pkg/INTERCO_TYPE]

    add wave -noupdate /tb_hci/clk
    add wave -noupdate /tb_hci/rst_n

    # Application-driver interfaces
    add wave -noupdate -group application_drivers -divider log_masters
    for {set i 0} {$i < $N_LOG_MASTERS} {incr i} {
        add wave -noupdate -group application_drivers -group log_$i /tb_hci/hci_driver_log_if[$i]/*
    }

    add wave -noupdate -group application_drivers -divider hwpe_masters
    for {set i 0} {$i < $N_HWPE} {incr i} {
        add wave -noupdate -group application_drivers -group hwpe_$i /tb_hci/hci_driver_hwpe_if[$i]/*
    }

    # Interconnect-side interfaces
    add wave -noupdate -group hci_interfaces -divider narrow_cores
    for {set i 0} {$i < $N_CORE} {incr i} {
        add wave -noupdate -group hci_interfaces -group core_$i /tb_hci/hci_initiator_narrow[$i]/*
    }

    if {[string first "LOG" $INTERCO_TYPE] != -1} {
        add wave -noupdate -group hci_interfaces -divider narrow_hwpe_split
        for {set i 0} {$i < $N_HWPE} {incr i} {
            for {set f 0} {$f < $HWPE_WIDTH_FACT} {incr f} {
                set idx [expr {$N_CORE + $i * $HWPE_WIDTH_FACT + $f}]
                if {$idx < $N_NARROW_HCI} {
                    add wave -noupdate -group hci_interfaces -group hwpe_$i -group lane_$f /tb_hci/hci_initiator_narrow[$idx]/*
                }
            }
        }
    }

    if {$N_WIDE_HCI > 0} {
        add wave -noupdate -group hci_interfaces -divider wide_hwpe
        for {set i 0} {$i < $N_WIDE_HCI} {incr i} {
            add wave -noupdate -group hci_interfaces -group wide_$i /tb_hci/hci_initiator_wide[$i]/*
        }
    }

    add wave -noupdate -group hci_interfaces -divider dma
    for {set i 0} {$i < $N_DMA} {incr i} {
        add wave -noupdate -group hci_interfaces -group dma_$i /tb_hci/hci_initiator_dma[$i]/*
    }

    add wave -noupdate -group hci_interfaces -divider ext
    for {set i 0} {$i < $N_EXT} {incr i} {
        add wave -noupdate -group hci_interfaces -group ext_$i /tb_hci/hci_initiator_ext[$i]/*
    }

    # Memory slaves
    add wave -noupdate -group memory_slaves
    for {set i 0} {$i < $N_BANKS} {incr i} {
        add wave -noupdate -group memory_slaves -group bank_$i /tb_hci/hci_target_mems[$i]/*
    }

    # Metrics
    add wave -noupdate -group metrics /tb_hci/s_end_req
    add wave -noupdate -group metrics /tb_hci/s_end_resp
    add wave -noupdate -group metrics /tb_hci/s_issued_transactions
    add wave -noupdate -group metrics /tb_hci/s_issued_read_transactions
    add wave -noupdate -group metrics /tb_hci/stim_latency
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

    add wave -noupdate /tb_hci/s_clear
    add wave -noupdate /tb_hci/s_clear_drv
    add wave -noupdate /tb_hci/s_hci_ctrl

    configure wave -signalnamewidth 1
} else {
    run -a
}
