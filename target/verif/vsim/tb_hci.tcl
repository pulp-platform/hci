# If GUI is 1, spawn waveforms
if {$GUI == 1} {
    echo "GUI mode enabled"
    log -r /*

    set N_CORE [examine -radix dec /tb_hci_pkg/N_CORE]
    set N_DMA [examine -radix dec /tb_hci_pkg/N_DMA]
    set N_EXT [examine -radix dec /tb_hci_pkg/N_EXT]
    set N_HWPE [examine -radix dec /tb_hci_pkg/N_HWPE]
    set N_BANKS [examine -radix dec /tb_hci_pkg/N_BANKS]

    set INTERCO_TYPE [examine /tb_hci_pkg/INTERCO_TYPE]
    set N_LOG_MASTERS [examine -radix dec /tb_hci_pkg/N_LOG_MASTERS]
    set N_HWPE_LOG_MASTERS [examine -radix dec /tb_hci_pkg/N_HWPE_LOG_MASTERS]
    set N_HWPE_MASTERS [examine -radix dec /tb_hci_pkg/N_HWPE_MASTERS]

    set HWPE_WIDTH_FACT [examine -radix dec /tb_hci_pkg/HWPE_WIDTH_FACT]

    add wave -noupdate /tb_hci/clk
    add wave -noupdate /tb_hci/rst_n

    # Application driver interfaces
    add wave -noupdate -group application_drivers -divider narrow_Cores
    for {set i 0} {$i < $N_CORE} {incr i} {
        add wave -noupdate -group application_drivers -group core_$i /tb_hci/hci_log_if[$i]/*
    }
    add wave -noupdate -group application_drivers -divider wide_HWPEs
    for {set i 0} {$i < $N_HWPE} {incr i} {
        add wave -noupdate -group application_drivers -group hwpe_$i /tb_hci/hci_hwpe_if[$i]/*
    }
    add wave -noupdate -group application_drivers -divider narrow_DMA
    for {set i 0} {$i < $N_DMA} {incr i} {
        set idx [expr {$i + $N_CORE}]
        add wave -noupdate -group application_drivers -group dma_$i /tb_hci/hci_log_if[$idx]/*
    }
    add wave -noupdate -group application_drivers -divider narrow_External
    for {set i 0} {$i < $N_EXT} {incr i} {
        set idx [expr {$i + $N_CORE + $N_DMA}]
        add wave -noupdate -group application_drivers -group ext_$i /tb_hci/hci_log_if[$idx]/*
    }
    # HCI-side interfaces
    add wave -noupdate -group hci_interfaces -divider narrow_Cores
    for {set i 0} {$i < $N_CORE} {incr i} {
        add wave -noupdate -group hci_interfaces -group core_$i /tb_hci/hci_core_if[$i]/*
    }
    if {$INTERCO_TYPE == {LOG}} {
        add wave -noupdate -group hci_interfaces -divider narrow_HWPEs_split
        for {set i 0} {$i < $N_HWPE} {incr i} {
            for {set f 0} {$f < $HWPE_WIDTH_FACT} {incr f} {
                set idx [expr {$N_CORE + $i*$HWPE_WIDTH_FACT + $f}]
                add wave -noupdate -group hci_interfaces -group hwpe_$i -group word_$f /tb_hci/hci_core_if[$idx]/*
            }
        }
    } elseif {$INTERCO_TYPE == {HCI} || $INTERCO_TYPE == {MUX}} {
        add wave -noupdate -group hci_interfaces -divider wide_HWPEs
        for {set i 0} {$i < $N_HWPE_MASTERS} {incr i} {
            add wave -noupdate -group hci_interfaces -group hwpe_$i /tb_hci/hci_hwpe_wide_if[$i]/*
        }
    } else {
        echo "WARNING: unsupported INTERCO_TYPE value: $INTERCO_TYPE_SYM ($INTERCO_TYPE)"
    }
    add wave -noupdate -group hci_interfaces -divider narrow_DMA
    for {set i 0} {$i < $N_DMA} {incr i} {
        add wave -noupdate -group hci_interfaces -group dma_$i /tb_hci/hci_dma_if[$i]/*
    }
    add wave -noupdate -group hci_interfaces -divider narrow_External
    for {set i 0} {$i < $N_EXT} {incr i} {
        add wave -noupdate -group hci_interfaces -group ext_$i /tb_hci/hci_ext_if[$i]/*
    }
    # Memory slaves
    add wave -noupdate -group memory_slaves
    for {set i 0} {$i < $N_BANKS} {incr i} {
        add wave -noupdate -group memory_slaves -group bank_$i /tb_hci/hci_mem_if[$i]/*
    }

    add wave -noupdate -group metrics /tb_hci/s_end_latency
    add wave -noupdate -group metrics /tb_hci/s_end_stimuli
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/s_issued_read_transactions[0]} {-format Analog-Step -height 84 -max 472.0} {/tb_hci/s_issued_read_transactions[1]} {-format Analog-Step -height 84 -max 493.0} {/tb_hci/s_issued_read_transactions[2]} {-format Analog-Step -height 84 -max 506.0} {/tb_hci/s_issued_read_transactions[3]} {-format Analog-Step -height 84 -max 481.0} {/tb_hci/s_issued_read_transactions[4]} {-format Analog-Step -height 84 -max 524.0} {/tb_hci/s_issued_read_transactions[5]} {-format Analog-Step -height 84 -max 512.0} {/tb_hci/s_issued_read_transactions[6]} {-format Analog-Step -height 84 -max 492.0} {/tb_hci/s_issued_read_transactions[7]} {-format Analog-Step -height 84 -max 518.0} {/tb_hci/s_issued_read_transactions[8]} {-format Analog-Step -height 84 -max 492.0} {/tb_hci/s_issued_read_transactions[9]} {-format Analog-Step -height 84 -max 503.0} {/tb_hci/s_issued_read_transactions[10]} {-format Analog-Step -height 84 -max 489.0} {/tb_hci/s_issued_read_transactions[11]} {-format Analog-Step -height 84 -max 493.0}} /tb_hci/s_issued_read_transactions
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/s_issued_transactions[0]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/s_issued_transactions[1]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/s_issued_transactions[2]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/s_issued_transactions[3]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/s_issued_transactions[4]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/s_issued_transactions[5]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/s_issued_transactions[6]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/s_issued_transactions[7]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/s_issued_transactions[8]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/s_issued_transactions[9]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/s_issued_transactions[10]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/s_issued_transactions[11]} {-format Analog-Step -height 84 -max 1000.0}} /tb_hci/s_issued_transactions
    add wave -noupdate -group metrics /tb_hci/stim_latency
    add wave -noupdate -group metrics /tb_hci/tot_latency
    add wave -noupdate -group metrics /tb_hci/latency_per_master
    add wave -noupdate -group metrics /tb_hci/throughput_completed
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/N_GNT_TRANSACTIONS_HWPE[0]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/N_GNT_TRANSACTIONS_HWPE[1]} {-format Analog-Step -height 84 -max 1000.0}} /tb_hci/N_GNT_TRANSACTIONS_HWPE
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/N_GNT_TRANSACTIONS_LOG[0]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/N_GNT_TRANSACTIONS_LOG[1]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/N_GNT_TRANSACTIONS_LOG[2]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/N_GNT_TRANSACTIONS_LOG[3]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/N_GNT_TRANSACTIONS_LOG[4]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/N_GNT_TRANSACTIONS_LOG[5]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/N_GNT_TRANSACTIONS_LOG[6]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/N_GNT_TRANSACTIONS_LOG[7]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/N_GNT_TRANSACTIONS_LOG[8]} {-format Analog-Step -height 84 -max 1000.0} {/tb_hci/N_GNT_TRANSACTIONS_LOG[9]} {-format Analog-Step -height 84 -max 1000.0}} /tb_hci/N_GNT_TRANSACTIONS_LOG
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/N_READ_COMPLETE_TRANSACTIONS_HWPE[0]} {-format Analog-Step -height 84 -max 489.0} {/tb_hci/N_READ_COMPLETE_TRANSACTIONS_HWPE[1]} {-format Analog-Step -height 84 -max 493.0}} /tb_hci/N_READ_COMPLETE_TRANSACTIONS_HWPE
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG[0]} {-format Analog-Step -height 84 -max 472.0} {/tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG[1]} {-format Analog-Step -height 84 -max 493.0} {/tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG[2]} {-format Analog-Step -height 84 -max 506.0} {/tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG[3]} {-format Analog-Step -height 84 -max 481.0} {/tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG[4]} {-format Analog-Step -height 84 -max 524.0} {/tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG[5]} {-format Analog-Step -height 84 -max 512.0} {/tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG[6]} {-format Analog-Step -height 84 -max 492.0} {/tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG[7]} {-format Analog-Step -height 84 -max 518.0} {/tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG[8]} {-format Analog-Step -height 84 -max 492.0} {/tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG[9]} {-format Analog-Step -height 84 -max 503.0}} /tb_hci/N_READ_COMPLETE_TRANSACTIONS_LOG
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/N_READ_GRANTED_TRANSACTIONS_HWPE[0]} {-format Analog-Step -height 84 -max 489.0} {/tb_hci/N_READ_GRANTED_TRANSACTIONS_HWPE[1]} {-format Analog-Step -height 84 -max 493.0}} /tb_hci/N_READ_GRANTED_TRANSACTIONS_HWPE
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG[0]} {-format Analog-Step -height 84 -max 472.0} {/tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG[1]} {-format Analog-Step -height 84 -max 493.0} {/tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG[2]} {-format Analog-Step -height 84 -max 506.0} {/tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG[3]} {-format Analog-Step -height 84 -max 481.0} {/tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG[4]} {-format Analog-Step -height 84 -max 524.0} {/tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG[5]} {-format Analog-Step -height 84 -max 512.0} {/tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG[6]} {-format Analog-Step -height 84 -max 492.0} {/tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG[7]} {-format Analog-Step -height 84 -max 518.0} {/tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG[8]} {-format Analog-Step -height 84 -max 492.0} {/tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG[9]} {-format Analog-Step -height 84 -max 503.0}} /tb_hci/N_READ_GRANTED_TRANSACTIONS_LOG
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_HWPE[0]} {-format Analog-Step -height 84 -max 511.0} {/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_HWPE[1]} {-format Analog-Step -height 84 -max 507.0}} /tb_hci/N_WRITE_GRANTED_TRANSACTIONS_HWPE
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG[0]} {-format Analog-Step -height 84 -max 528.0} {/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG[1]} {-format Analog-Step -height 84 -max 507.0} {/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG[2]} {-format Analog-Step -height 84 -max 494.0} {/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG[3]} {-format Analog-Step -height 84 -max 519.0} {/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG[4]} {-format Analog-Step -height 84 -max 475.99999999999994} {/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG[5]} {-format Analog-Step -height 84 -max 488.00000000000006} {/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG[6]} {-format Analog-Step -height 84 -max 508.0} {/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG[7]} {-format Analog-Step -height 84 -max 482.0} {/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG[8]} {-format Analog-Step -height 84 -max 508.0} {/tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG[9]} {-format Analog-Step -height 84 -max 497.0}} /tb_hci/N_WRITE_GRANTED_TRANSACTIONS_LOG
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/SUM_REQ_TO_GNT_LATENCY_HWPE[0]} {-format Analog-Step -height 84 -max 1327824.0} {/tb_hci/SUM_REQ_TO_GNT_LATENCY_HWPE[1]} {-format Analog-Step -height 84 -max 1336050.0}} /tb_hci/SUM_REQ_TO_GNT_LATENCY_HWPE
    add wave -noupdate -group metrics -subitemconfig {{/tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG[0]} {-format Analog-Step -height 84 -max 580398.0} {/tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG[1]} {-format Analog-Step -height 84 -max 580783.0} {/tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG[2]} {-format Analog-Step -height 84 -max 596101.00000000012} {/tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG[3]} {-format Analog-Step -height 84 -max 590598.0} {/tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG[4]} {-format Analog-Step -height 84 -max 603272.0} {/tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG[5]} {-format Analog-Step -height 84 -max 601733.0} {/tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG[6]} {-format Analog-Step -height 84 -max 596110.0} {/tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG[7]} {-format Analog-Step -height 84 -max 593715.0} {/tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG[8]} {-format Analog-Step -height 84 -max 602346.0} {/tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG[9]} {-format Analog-Step -height 84 -max 597075.0}} /tb_hci/SUM_REQ_TO_GNT_LATENCY_LOG
    add wave -noupdate /tb_hci/s_clear
    add wave -noupdate /tb_hci/s_hci_ctrl

    configure wave -signalnamewidth 1
} else {
    run -a
}
