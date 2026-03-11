"""HTML report generation for memory lifetime visualization."""

from pathlib import Path
import html
import math


def build_memory_lifetime_html(
    *,
    pattern_nodes,
    driver_windows,
    regions_timeline,
    total_cycles,
    mux_serialization_applied,
    mux_phase_order,
    schedule_has_cycle,
    driver_name_fn,
    interco_type,
    n_core_cfg,
    n_dma_cfg,
    n_ext_cfg,
    n_hwpe_cfg,
    dw_narrow,
    dw_wide,
    n_narrow_hci_cfg,
    n_wide_hci_cfg,
    n_banks,
):
    palette = [
        "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#17becf",
        "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#9467bd",
        "#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e",
        "#e6ab02", "#a6761d", "#666666",
    ]

    def _color_for_driver(drv_idx):
        return palette[drv_idx % len(palette)]

    def _tick_step(total):
        if total <= 10:
            return 1
        raw = max(1, total // 10)
        mag = 10 ** int(math.log10(raw))
        return int(math.ceil(raw / mag) * mag)

    total_for_plot = max(1, total_cycles)
    chart_width = 1280
    x_left = 220
    x_right = 24
    plot_w = chart_width - x_left - x_right
    row_h = 80
    y_top = 36
    exec_rows = [driver_windows[d] for d in sorted(driver_windows.keys())]
    exec_h = y_top + row_h * len(exec_rows) + 72
    tick = _tick_step(total_for_plot)
    ticks = list(range(0, total_for_plot + 1, tick))
    if ticks[-1] != total_for_plot:
        ticks.append(total_for_plot)

    exec_svg = []
    exec_svg.append(f'<svg width="{chart_width}" height="{exec_h}" viewBox="0 0 {chart_width} {exec_h}" xmlns="http://www.w3.org/2000/svg">')
    exec_svg.append('<rect x="0" y="0" width="100%" height="100%" fill="#ffffff"/>')
    exec_svg.append(f'<text x="{x_left}" y="20" font-family="Arial, sans-serif" font-size="14" font-weight="700">Execution Timeline (transaction-count model)</text>')
    for t in ticks:
        x = x_left + (t / total_for_plot) * plot_w
        exec_svg.append(f'<line x1="{x:.2f}" y1="{y_top - 6}" x2="{x:.2f}" y2="{exec_h - 52}" stroke="#e0e0e0" stroke-width="1"/>')
        exec_svg.append(f'<text x="{x:.2f}" y="{exec_h - 36}" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#555">{t}</text>')
    exec_svg.append(
        f'<text x="{x_left + (plot_w / 2):.2f}" y="{exec_h - 18}" text-anchor="middle" '
        'font-family="Arial, sans-serif" font-size="12" fill="#333">Transaction number</text>'
    )
    exec_svg.append(
        f'<text x="{x_left + (plot_w / 2):.2f}" y="{exec_h - 2}" text-anchor="middle" '
        'font-family="Arial, sans-serif" font-size="11" fill="#555">'
        'Issued memory transactions (r/w) and computation cycles (i.e., req = 0) are both modeled here.'
        '</text>'
    )

    def _rw_mix_text(node):
        rpct = node.get('traffic_read_pct')
        if rpct is None:
            read_bytes = 0
            write_bytes = 0
            for reg in node.get('regions', []):
                label_l = str(reg.get('label', '')).lower()
                size_b = max(0, int(reg.get('size', 0)))
                if 'read' in label_l and 'write' not in label_l:
                    read_bytes += size_b
                elif 'write' in label_l and 'read' not in label_l:
                    write_bytes += size_b
            if (read_bytes + write_bytes) > 0:
                rpct = int(round(100.0 * read_bytes / (read_bytes + write_bytes)))
            else:
                rpct = 50
        rpct = max(0, min(100, int(rpct)))
        if rpct == 0:
            return "100% writes"
        if rpct == 100:
            return "100% reads"
        return f"{rpct}% reads / {100 - rpct}% writes"

    def _fmt_kib(bytes_v):
        return f"{(max(0, int(bytes_v)) / 1024.0):.1f} KiB"

    def _outside_detail_lines(node, base_addr, size_kib):
        regs = list(node.get('regions', []))
        label_map = {str(r.get('label', '')): r for r in regs}
        has_matmul_regs = any(k in label_map for k in ('A(read)', 'B(read)', 'C(write)'))
        is_matmul = node.get('mem_access_type') in {'matmul', 'matmul_phased', 'matmul_tiled_interleave'} or has_matmul_regs

        if is_matmul:
            mat_lines = []
            for lbl, short in [('A(read)', 'A'), ('B(read)', 'B'), ('C(write)', 'C')]:
                if lbl in label_map:
                    r = label_map[lbl]
                    mat_lines.append(f"{short}@0x{int(r['base']):08x} ({_fmt_kib(r['size'])})")
            if not mat_lines:
                return [f"@0x{base_addr:08x}", f"{size_kib:.1f} KiB"]
            return mat_lines

        if regs:
            r0 = regs[0]
            return [f"@0x{int(r0['base']):08x}", f"{_fmt_kib(r0['size'])}"]
        return [f"@0x{base_addr:08x}", f"{size_kib:.1f} KiB"]

    for row_idx, row in enumerate(exec_rows):
        y = y_top + row_idx * row_h
        name = html.escape(row['name'])
        label_color = "#111111" if row['is_hwpe'] else "#555555"
        exec_svg.append(f'<text x="{x_left - 10}" y="{y + 34}" text-anchor="end" font-family="Arial, sans-serif" font-size="12" fill="{label_color}">{name}</text>')
        exec_svg.append(f'<line x1="{x_left}" y1="{y + row_h - 1}" x2="{x_left + plot_w}" y2="{y + row_h - 1}" stroke="#f0f0f0" stroke-width="1"/>')
        nodes = [n for n in pattern_nodes if n['driver_idx'] == row['driver_idx']]
        for node in nodes:
            if node['end_cycle'] <= node['start_cycle']:
                continue
            x = x_left + (node['start_cycle'] / total_for_plot) * plot_w
            w = max(1.0, ((node['end_cycle'] - node['start_cycle']) / total_for_plot) * plot_w)
            color = _color_for_driver(node['driver_idx'])
            base_addr = min((int(r.get('base', 0)) for r in node.get('regions', [])), default=0)
            size_kib = (int(node['n_transactions']) * int(node.get('txn_bytes', 1))) / 1024.0
            rw_mix = _rw_mix_text(node)
            line1_full = f"{node['job']}"
            line2_full = f"{node['mem_access_type']}"
            line3_full = rw_mix
            outside_lines = _outside_detail_lines(node, base_addr, size_kib)
            title = (
                f"{node['driver_name']} p{node['pattern_idx']} job={node['job']} "
                f"[{node['start_cycle']}, {node['end_cycle']}) "
                f"{node['mem_access_type']} n={node['n_transactions']} "
                f"base=0x{base_addr:08x} {size_kib:.1f}KiB {rw_mix} "
                f"{' | '.join(outside_lines)}"
            )
            exec_svg.append('<g style="cursor:help;">')
            exec_svg.append(f'<title>{html.escape(title)}</title>')
            exec_svg.append(
                f'<rect x="{x:.2f}" y="{y + 4}" width="{w:.2f}" height="34" '
                f'rx="3" ry="3" fill="{color}" fill-opacity="0.82" stroke="#222" stroke-width="0.2"/>'
            )
            line1 = html.escape(line1_full)
            exec_svg.append(
                f'<text x="{x + 4:.2f}" y="{y + 15}" font-family="Arial, sans-serif" font-size="9" '
                f'fill="#ffffff" style="pointer-events:none;">{line1}</text>'
            )
            line2 = html.escape(line2_full)
            exec_svg.append(
                f'<text x="{x + 4:.2f}" y="{y + 25}" font-family="Arial, sans-serif" font-size="8" '
                f'fill="#ffffff" style="pointer-events:none;">{line2}</text>'
            )
            line3 = html.escape(line3_full)
            exec_svg.append(
                f'<text x="{x + 4:.2f}" y="{y + 34}" font-family="Arial, sans-serif" font-size="8" '
                f'fill="#ffffff" style="pointer-events:none;">{line3}</text>'
            )
            for ext_idx, ext in enumerate(outside_lines):
                y_ext = y + 49 + (ext_idx * 9)
                ext_txt = html.escape(ext)
                exec_svg.append(
                    f'<text x="{x + 2:.2f}" y="{y_ext:.2f}" font-family="Arial, sans-serif" font-size="8" '
                    f'fill="#333333" style="pointer-events:none;">{ext_txt}</text>'
                )
            exec_svg.append('</g>')
    exec_svg.append('</svg>')

    region_rows = [regions_timeline[k] for k in sorted(regions_timeline.keys(), key=lambda k: (k[0], k[1], k[2]))]
    overlap_rows = []
    overlaps_by_region = {i: [] for i in range(len(region_rows))}
    for i in range(len(region_rows)):
        a = region_rows[i]
        for j in range(i + 1, len(region_rows)):
            b = region_rows[j]
            ov_base = max(a['base'], b['base'])
            ov_end = min(a['end'], b['end'])
            if ov_base <= ov_end:
                ov_size = ov_end - ov_base + 1
                overlap_rows.append({
                    'a_idx': i,
                    'b_idx': j,
                    'ov_base': ov_base,
                    'ov_end': ov_end,
                    'ov_size': ov_size,
                })
                overlaps_by_region[i].append((j, ov_base, ov_end, ov_size))
                overlaps_by_region[j].append((i, ov_base, ov_end, ov_size))

    used_min = min((reg['base'] for reg in region_rows), default=0)
    used_max = max((reg['end'] for reg in region_rows), default=0)
    if used_max < used_min:
        used_max = used_min
    used_span = max(1, used_max - used_min + 1)

    map_left = 170
    map_right = 24
    map_plot_w = chart_width - map_left - map_right
    map_h = 124
    bar_y = 56
    bar_h = 24
    region_map_svg = []
    region_map_svg.append(f'<svg width="{chart_width}" height="{map_h}" viewBox="0 0 {chart_width} {map_h}" xmlns="http://www.w3.org/2000/svg">')
    region_map_svg.append('<rect x="0" y="0" width="100%" height="100%" fill="#ffffff"/>')
    region_map_svg.append(
        f'<text x="{map_left}" y="20" font-family="Arial, sans-serif" font-size="14" font-weight="700">'
        f"Memory Region Blocks (used range 0x{used_min:08x} - 0x{used_max:08x})"
        f"</text>"
    )
    region_map_svg.append(
        f'<rect x="{map_left}" y="{bar_y}" width="{map_plot_w}" height="{bar_h}" '
        f'fill="#f6f6f6" stroke="#cfcfcf" stroke-width="1"/>'
    )
    for pct in [0, 25, 50, 75, 100]:
        x = map_left + (pct / 100.0) * map_plot_w
        addr = used_min + int(((used_span - 1) * pct) / 100.0)
        region_map_svg.append(f'<line x1="{x:.2f}" y1="{bar_y - 8}" x2="{x:.2f}" y2="{bar_y + bar_h + 8}" stroke="#d7d7d7" stroke-width="1"/>')
        region_map_svg.append(
            f'<text x="{x:.2f}" y="{bar_y + bar_h + 22}" text-anchor="middle" '
            f'font-family="Arial, sans-serif" font-size="11" fill="#555">0x{addr:08x}</text>'
        )
    for reg in region_rows:
        x = map_left + ((reg['base'] - used_min) / used_span) * map_plot_w
        w = max(1.0, (reg['size'] / used_span) * map_plot_w)
        color = _color_for_driver(reg['accesses'][0]['driver_idx']) if reg['accesses'] else "#888888"
        title = (
            f"{reg['label']} 0x{reg['base']:08x}-0x{reg['end']:08x} "
            f"size={reg['size']}B accesses={len(reg['accesses'])}"
        )
        region_map_svg.append(
            f'<rect x="{x:.2f}" y="{bar_y + 2}" width="{w:.2f}" height="{bar_h - 4}" '
            f'rx="2" ry="2" fill="{color}" fill-opacity="0.62" stroke="#222" stroke-width="0.35">'
            f'<title>{html.escape(title)}</title></rect>'
        )
        if w >= 92:
            region_map_svg.append(
                f'<text x="{x + 4:.2f}" y="{bar_y + 16}" font-family="Arial, sans-serif" '
                f'font-size="10" fill="#111">{html.escape(reg["label"])}</text>'
            )
    region_map_svg.append('</svg>')

    legend_items = []
    for d in sorted(driver_windows.keys()):
        n = driver_name_fn(d)
        c = _color_for_driver(d)
        legend_items.append(
            f'<span style="display:inline-flex;align-items:center;margin-right:12px;margin-bottom:6px;">'
            f'<span style="display:inline-block;width:11px;height:11px;background:{c};margin-right:5px;border:1px solid #222;"></span>'
            f'<span>{html.escape(n)}</span></span>'
        )

    region_cards = []
    for idx, reg in enumerate(region_rows):
        access_rows = []
        accesses = sorted(reg['accesses'], key=lambda a: (a['driver_idx'], a['pattern_idx'], a['start']))
        for acc in accesses:
            desc = acc['description'] if acc['description'] else "-"
            access_rows.append(
                "<tr>"
                f"<td>{html.escape(acc['driver_name'])}</td>"
                f"<td>p{acc['pattern_idx']}</td>"
                f"<td>{html.escape(acc['job'])}</td>"
                f"<td>{html.escape(desc)}</td>"
                f"<td>[{acc['start']}, {acc['end']})</td>"
                "</tr>"
            )
        overlap_refs = overlaps_by_region.get(idx, [])
        if overlap_refs:
            ov_txt = ", ".join(
                [
                    f"{html.escape(region_rows[j]['label'])} "
                    f"(0x{ovb:08x}-0x{ove:08x}, {ovs} B)"
                    for (j, ovb, ove, ovs) in overlap_refs
                ]
            )
        else:
            ov_txt = "none"
        region_cards.append(
            "<div class='region-card'>"
            f"<div><b>{html.escape(reg['label'])}</b> | base=0x{reg['base']:08x} | end=0x{reg['end']:08x} | size={reg['size']} B</div>"
            f"<div class='meta' style='margin:4px 0 8px 0;'><b>Overlaps:</b> {ov_txt}</div>"
            "<table class='smalltbl'><thead><tr>"
            "<th>Driver/HWPE</th><th>Pattern</th><th>Job</th><th>Description</th><th>Modeled interval</th>"
            "</tr></thead><tbody>"
            f"{''.join(access_rows)}"
            "</tbody></table>"
            "</div>"
        )

    overlap_table_rows = []
    for ov in overlap_rows:
        a = region_rows[ov['a_idx']]
        b = region_rows[ov['b_idx']]
        overlap_table_rows.append(
            "<tr>"
            f"<td>{html.escape(a['label'])} (0x{a['base']:08x}-0x{a['end']:08x})</td>"
            f"<td>{html.escape(b['label'])} (0x{b['base']:08x}-0x{b['end']:08x})</td>"
            f"<td>0x{ov['ov_base']:08x}</td>"
            f"<td>0x{ov['ov_end']:08x}</td>"
            f"<td>{ov['ov_size']}</td>"
            "</tr>"
        )

    note = "Timeline follows declared wait_for_jobs dependencies from workload.json."
    note_2 = (
        "Time axis is transaction-count based only "
        "(no interconnect conflict/stall/arbitration modeling)."
    )
    note_2b = "Per-driver list order is still enforced by stimulus/fence sequencing."
    note_3 = ""
    if mux_serialization_applied:
        note_3 = (
            "MUX mode: HWPE execution is serialized by job order, "
            "with lower HWPE ID first inside each job (tb_hci-like)."
        )
        if mux_phase_order:
            note_3 += f" Job order: {', '.join(mux_phase_order)}."
    note_3_html = f"<div class='meta'>{html.escape(note_3)}</div>" if note_3 else ""
    cycle_warning_html = (
        "<p style='margin:8px 0;color:#b00020;font-weight:600;'>Warning: dependency cycle detected; fallback scheduling order used.</p>"
        if schedule_has_cycle else ""
    )
    overlap_html = (
        "<table><thead><tr><th>Region A</th><th>Region B</th><th>Overlap Base</th><th>Overlap End</th><th>Overlap Size (B)</th></tr></thead><tbody>"
        f"{''.join(overlap_table_rows)}"
        "</tbody></table>"
        if overlap_table_rows else
        "<div class='meta'>No overlaps detected among used regions.</div>"
    )

    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<title>Memory Access Region View (Transaction-Count Model)</title>"
        "<style>"
        "body{font-family:Arial,sans-serif;margin:18px;background:#fafafa;color:#111;}"
        "h1{font-size:20px;margin:0 0 6px 0;}h2{font-size:16px;margin:18px 0 8px 0;}"
        ".meta{font-size:13px;color:#333;margin-bottom:10px;}"
        ".panel{background:#fff;border:1px solid #ddd;border-radius:8px;padding:12px;margin-bottom:14px;overflow-x:auto;}"
        "table{border-collapse:collapse;width:100%;font-size:12px;background:#fff;}"
        "th,td{border:1px solid #ddd;padding:5px 7px;text-align:left;vertical-align:top;}"
        "th{background:#f3f3f3;}"
        ".region-card{border:1px solid #dcdcdc;border-radius:6px;padding:10px;margin-bottom:10px;background:#fff;}"
        ".smalltbl{border-collapse:collapse;width:100%;font-size:11px;background:#fff;}"
        ".smalltbl th,.smalltbl td{border:1px solid #ddd;padding:4px 6px;text-align:left;vertical-align:top;}"
        ".smalltbl th{background:#f7f7f7;}"
        "</style></head><body>"
        "<h1>Memory Access Region View</h1>"
        f"<div class='meta'><b>Drivers ({dw_narrow} bit):</b> "
        f"CORE={n_core_cfg}, DMA={n_dma_cfg}, EXT={n_ext_cfg}</div>"
        f"<div class='meta'><b>Drivers ({dw_wide} bit):</b> HWPE={n_hwpe_cfg}</div>"
        f"<div class='meta'><b>Interconnect type:</b> {html.escape(interco_type)} | "
        f"<b>Narrow master ports ({dw_narrow} bit):</b> {n_narrow_hci_cfg} | "
        f"<b>Wide master ports ({dw_wide} bit):</b> {n_wide_hci_cfg} | "
        f"<b>Slave ports (banks):</b> {n_banks} | "
        f"<b>Total modeled time:</b> {total_cycles} units</div>"
        f"<div class='meta'>{html.escape(note)}</div>"
        f"<div class='meta'>{html.escape(note_2)}</div>"
        f"<div class='meta'>{html.escape(note_2b)}</div>"
        f"{note_3_html}"
        f"{cycle_warning_html}"
        "<div class='panel'><h2 style='margin-top:0;'>Legend</h2>"
        f"{''.join(legend_items)}</div>"
        "<div class='panel'>"
        f"{''.join(exec_svg)}"
        "</div>"
        "<div class='panel'>"
        f"{''.join(region_map_svg)}"
        "</div>"
        "<h2>Region Usage Blocks</h2>"
        f"{''.join(region_cards)}"
        "<h2>Overlapping Regions</h2>"
        f"{overlap_html}"
        "</body></html>"
    )


def write_memory_lifetime_html(memory_lifetime_path: Path, **kwargs):
    html_doc = build_memory_lifetime_html(**kwargs)
    memory_lifetime_path.write_text(html_doc, encoding='utf-8')
