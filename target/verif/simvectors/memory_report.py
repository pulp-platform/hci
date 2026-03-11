"""Text memory map report generation."""

from pathlib import Path


def build_memory_map_text(
    *,
    total_mem_size_kib,
    n_banks,
    data_width,
    hwpe_data_width,
    n_core_cfg,
    n_dma_cfg,
    n_ext_cfg,
    n_log_cfg,
    n_hwpe_cfg,
    interco_type,
    dw_narrow,
    dw_wide,
    n_narrow_hci_cfg,
    n_wide_hci_cfg,
    memory_map_entries,
    job_to_drivers,
    driver_name_fn,
    n_drivers,
    fence_masks,
    total_cycles,
    mux_serialization_applied,
    mux_phase_order,
    schedule_has_cycle,
    driver_windows,
    pattern_nodes,
    regions_timeline,
):
    word_bytes = data_width // 8
    bank_stride_bytes = n_banks * word_bytes
    lines = []
    lines.append("=" * 72)
    lines.append("MEMORY MAP REPORT")
    lines.append(f"  Total memory : {total_mem_size_kib} KiB  ({total_mem_size_kib * 1024} B)")
    lines.append(f"  Banks        : {n_banks}  x  {word_bytes} B/word  (interleaved, stride {bank_stride_bytes} B)")
    lines.append(f"  Data width   : {data_width} b LOG  /  {hwpe_data_width} b HWPE")
    lines.append(
        f"  Drivers({dw_narrow} bit) : "
        f"CORE={n_core_cfg}, DMA={n_dma_cfg}, EXT={n_ext_cfg}  (LOG total={n_log_cfg})"
    )
    lines.append(
        f"  Drivers({dw_wide} bit) : "
        f"HWPE={n_hwpe_cfg}"
    )
    lines.append(
        f"  Interconnect type : {interco_type}  |  "
        f"Narrow master ports ({dw_narrow} bit)={n_narrow_hci_cfg}  |  "
        f"Wide master ports ({dw_wide} bit)={n_wide_hci_cfg}  |  "
        f"Slave ports (banks)={n_banks}"
    )
    lines.append("=" * 72)
    for entry in memory_map_entries:
        lines.append(f"\n  [{entry['label']}]  pattern={entry['pattern']}  n_transactions={entry['n']}")
        if 'info' in entry:
            lines.append(f"    {entry['info']}")
        for k, v in entry.get('detail', {}).items():
            lines.append(f"    {k:<14}: {v}")
    lines.append("")
    lines.append("  Job / dependency map:")
    for job, drivers in sorted(job_to_drivers.items()):
        driver_names = [driver_name_fn(d) for d in drivers]
        lines.append(f"    job '{job}': {', '.join(driver_names)}")
    for i in range(n_drivers):
        name = driver_name_fn(i)
        for f, mask in enumerate(fence_masks[i]):
            if mask:
                deps = [driver_name_fn(j) for j in range(n_drivers) if mask & (1 << j)]
                lines.append(f"    {name} after pattern[{f}] (fence {f}) waits for: {', '.join(deps)}")
    lines.append("")
    lines.append("  Temporal schedule (transaction-count model):")
    lines.append(f"    Total modeled time: {total_cycles} units (1 unit = 1 transaction)")
    lines.append("    Note: Declared wait_for_jobs dependencies are used for scheduling.")
    lines.append("    Note: Per-driver list order is also enforced (pattern p[i] -> p[i+1]).")
    lines.append("    Note: No interconnect contention/stall timing is modeled.")
    if mux_serialization_applied:
        lines.append("    Note: MUX mode serializes HWPE execution by job order, then HWPE ID (tb_hci-like).")
        lines.append(f"    MUX job order: {', '.join(mux_phase_order)}")
    if schedule_has_cycle:
        lines.append("    WARNING: dependency cycle detected while scheduling; using fallback order.")
    for d in range(n_drivers):
        if d not in driver_windows:
            continue
        w = driver_windows[d]
        lines.append(f"    {w['name']:<8}: [{w['start']:>6}, {w['end']:>6})  dur={w['end'] - w['start']:>6}")
        for node in [n for n in pattern_nodes if n['driver_idx'] == d]:
            reg_tokens = []
            for reg in node['regions']:
                reg_tokens.append(f"{reg['label']}@0x{reg['base']:08x}+{reg['size']}B")
            reg_text = ", ".join(reg_tokens) if reg_tokens else "no regions"
            lines.append(
                f"      p{node['pattern_idx']} job={node['job']} "
                f"[{node['start_cycle']},{node['end_cycle']}) "
                f"type={node['mem_access_type']} n={node['n_transactions']}  {reg_text}"
            )
    lines.append("")
    lines.append("  Memory region lifetimes:")
    for key in sorted(regions_timeline.keys(), key=lambda k: (k[0], k[1], k[2])):
        reg = regions_timeline[key]
        users = sorted({a['driver_name'] for a in reg['accesses']})
        lines.append(
            f"    {reg['label']:<8} 0x{reg['base']:08x}-0x{reg['end']:08x} "
            f"({reg['size']:>6} B)  lifetime=[{reg['lifetime_start']},{reg['lifetime_end']})  "
            f"users={', '.join(users)}"
        )
    lines.append("=" * 72)

    return "\n".join(lines) + "\n"


def write_memory_map_txt(memory_map_path: Path, **kwargs):
    report_text = build_memory_map_text(**kwargs)
    memory_map_path.write_text(report_text, encoding='utf-8')
    return report_text
