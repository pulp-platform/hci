"""HTML report generation for memory lifetime visualization."""

from pathlib import Path
import html
import math


def build_schedule(pattern_nodes, node_idx_by_driver_pattern, job_to_nodes, interco_type):
    """Build the temporal model: dependency graph, topo-sort, timing assignment.

    Mutates pattern_nodes in-place (adds 'start_cycle' and 'end_cycle' to each node).
    Returns (driver_windows, regions_timeline, total_cycles,
             schedule_has_cycle, mux_serialization_applied, mux_phase_order).
    """
    n_nodes = len(pattern_nodes)
    preds = [set() for _ in range(n_nodes)]
    succs = [set() for _ in range(n_nodes)]
    mux_serialization_applied = False
    mux_phase_order = []

    def _add_edge(src, dst):
        if src == dst or src < 0 or dst < 0:
            return
        if src not in preds[dst]:
            preds[dst].add(src)
            succs[src].add(dst)

    for node in pattern_nodes:
        n_idx = node['node_idx']
        drv_idx = node['driver_idx']
        p_idx = node['pattern_idx']
        if p_idx > 0:
            prev_idx = node_idx_by_driver_pattern[(drv_idx, p_idx - 1)]
            if pattern_nodes[prev_idx]['job'] == node['job']:
                # Same-job consecutive patterns: add a hard dependency edge.
                # Different-job patterns on the same driver are serialized by
                # the timing model below (not as graph edges) to avoid creating
                # spurious cross-job cycles.
                _add_edge(prev_idx, n_idx)
        for dep_job in node['wait_for_jobs_effective']:
            for dep_idx in job_to_nodes.get(dep_job, []):
                _add_edge(dep_idx, n_idx)

    if interco_type == "MUX":
        # Match tb_hci MUX semantics in the temporal model:
        # serialize HWPE execution by job order, and by HWPE ID within a job.
        hwpe_nodes = [n for n in pattern_nodes if n['is_hwpe']]
        if hwpe_nodes:
            job_first_seen = {}
            for n in sorted(hwpe_nodes, key=lambda x: (x['pattern_idx'], x['local_idx'], x['node_idx'])):
                job_first_seen.setdefault(n['job'], len(job_first_seen))

            job_preds = {jb: set() for jb in job_first_seen}
            job_succs = {jb: set() for jb in job_first_seen}
            for n in hwpe_nodes:
                cur = n['job']
                for dep_job in n['wait_for_jobs_effective']:
                    dep = str(dep_job)
                    if dep in job_first_seen and dep != cur:
                        job_preds[cur].add(dep)
                        job_succs[dep].add(cur)

            phase_indeg = {jb: len(job_preds[jb]) for jb in job_first_seen}
            phase_ready = sorted([jb for jb, deg in phase_indeg.items() if deg == 0],
                                 key=lambda jb: job_first_seen[jb])
            mux_phase_order = []
            while phase_ready:
                cur = phase_ready.pop(0)
                mux_phase_order.append(cur)
                for nxt in sorted(job_succs[cur], key=lambda jb: job_first_seen[jb]):
                    phase_indeg[nxt] -= 1
                    if phase_indeg[nxt] == 0:
                        phase_ready.append(nxt)
                phase_ready.sort(key=lambda jb: job_first_seen[jb])
            if len(mux_phase_order) != len(job_first_seen):
                mux_phase_order = sorted(job_first_seen.keys(), key=lambda jb: job_first_seen[jb])

            phase_rank = {ph: i for i, ph in enumerate(mux_phase_order)}
            hwpe_sorted = sorted(
                hwpe_nodes,
                key=lambda n: (
                    phase_rank.get(n['job'], 10 ** 9),
                    n['local_idx'],
                    n['pattern_idx'],
                    n['node_idx'],
                ),
            )
            for i in range(1, len(hwpe_sorted)):
                _add_edge(hwpe_sorted[i - 1]['node_idx'], hwpe_sorted[i]['node_idx'])
            mux_serialization_applied = True

    indeg = [len(preds[i]) for i in range(n_nodes)]
    ready = [i for i, d in enumerate(indeg) if d == 0]
    ready.sort(key=lambda i: (pattern_nodes[i]['driver_idx'], pattern_nodes[i]['pattern_idx']))
    topo_order = []
    while ready:
        cur = ready.pop(0)
        topo_order.append(cur)
        for nxt in sorted(succs[cur]):
            indeg[nxt] -= 1
            if indeg[nxt] == 0:
                ready.append(nxt)
        ready.sort(key=lambda i: (pattern_nodes[i]['driver_idx'], pattern_nodes[i]['pattern_idx']))

    schedule_has_cycle = len(topo_order) != n_nodes
    if schedule_has_cycle:
        topo_order = list(range(n_nodes))

    node_start = [0 for _ in range(n_nodes)]
    node_end = [0 for _ in range(n_nodes)]
    for _ in range(max(1, n_nodes + 1)):
        changed = False
        for n_idx in topo_order:
            node = pattern_nodes[n_idx]
            dep_end = max((node_end[p] for p in preds[n_idx]), default=0)
            # Driver serialization: a pattern can only start after the previous
            # pattern on the same driver finishes, regardless of job name.
            # Enforced here (not as a graph edge) to avoid cross-job cycle risk.
            # Skip HWPE patterns in MUX mode: their ordering is already fully
            # encoded by the explicit MUX graph edges above.
            if node['pattern_idx'] > 0 and not (mux_serialization_applied and node['is_hwpe']):
                prev_drv_idx = node_idx_by_driver_pattern[
                    (node['driver_idx'], node['pattern_idx'] - 1)]
                dep_end = max(dep_end, node_end[prev_drv_idx])
            start_time = max(int(node['start_delay']), dep_end)
            end_time = start_time + max(0, int(node['cycles']))
            if start_time != node_start[n_idx] or end_time != node_end[n_idx]:
                node_start[n_idx] = start_time
                node_end[n_idx] = end_time
                changed = True
        if not changed:
            break

    for n_idx, node in enumerate(pattern_nodes):
        node['start_cycle'] = int(node_start[n_idx])
        node['end_cycle'] = int(node_end[n_idx])

    total_cycles = max((n['end_cycle'] for n in pattern_nodes), default=0)

    driver_windows = {}
    for node in pattern_nodes:
        w = driver_windows.setdefault(node['driver_idx'], {
            'driver_idx': node['driver_idx'],
            'name': node['driver_name'],
            'is_hwpe': node['is_hwpe'],
            'start': node['start_cycle'],
            'end': node['end_cycle'],
        })
        w['start'] = min(w['start'], node['start_cycle'])
        w['end'] = max(w['end'], node['end_cycle'])

    regions_timeline = {}
    for node in pattern_nodes:
        for reg in node['regions']:
            reg_key = (reg['base'], reg['size'], reg['label'])
            entry = regions_timeline.setdefault(reg_key, {
                'base': reg['base'],
                'size': reg['size'],
                'end': reg['end'],
                'label': reg['label'],
                'accesses': [],
            })
            entry['accesses'].append({
                'driver_idx': node['driver_idx'],
                'driver_name': node['driver_name'],
                'job': node['job'],
                'start': node['start_cycle'],
                'end': node['end_cycle'],
                'pattern_idx': node['pattern_idx'],
                'description': node['description'],
            })
    for reg in regions_timeline.values():
        reg['lifetime_start'] = min((a['start'] for a in reg['accesses']), default=0)
        reg['lifetime_end'] = max((a['end'] for a in reg['accesses']), default=0)

    return (driver_windows, regions_timeline, total_cycles,
            schedule_has_cycle, mux_serialization_applied, mux_phase_order)


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

    # ---- Memory Address Timeline (2-D: address × time) ----
    _mat_addr_max = (((used_max + 1) + 4095) // 4096) * 4096
    _mat_addr_span = max(1, _mat_addr_max)
    _mat_xl = 110
    _mat_xr = 24
    _mat_pw = chart_width - _mat_xl - _mat_xr
    _mat_h = 560
    _mat_yt = 36
    _mat_yb_mg = 52
    _mat_ph = _mat_h - _mat_yt - _mat_yb_mg
    _mat_ybot = _mat_yt + _mat_ph
    _RC = "#2980b9"   # read  → blue
    _WC = "#c0392b"   # write → red
    _MC = "#8e44ad"   # mixed → purple

    def _mat_ay(addr):
        return _mat_yt + (int(addr) / _mat_addr_span) * _mat_ph

    def _mat_ah(size):
        return max(1.5, (int(size) / _mat_addr_span) * _mat_ph)

    mat_svg = []
    mat_svg.append(
        f'<svg width="{chart_width}" height="{_mat_h}" viewBox="0 0 {chart_width} {_mat_h}" '
        f'xmlns="http://www.w3.org/2000/svg">'
    )
    mat_svg.append('<rect x="0" y="0" width="100%" height="100%" fill="#ffffff"/>')
    mat_svg.append(
        f'<text x="{_mat_xl}" y="22" font-family="Arial, sans-serif" font-size="14" font-weight="700">'
        f'Memory Address Timeline</text>'
    )

    # Background bands for each named region (alternating shades)
    _sregs = sorted(region_rows, key=lambda r: r['base'])
    for _i, _reg in enumerate(_sregs):
        _ry = _mat_ay(_reg['base'])
        _rh = _mat_ah(_reg['size'])
        mat_svg.append(
            f'<rect x="{_mat_xl}" y="{_ry:.2f}" width="{_mat_pw}" height="{_rh:.2f}" '
            f'fill="{"#f5f5f5" if _i % 2 == 0 else "#ebebeb"}" stroke="#ddd" stroke-width="0.5"/>'
        )
        _lcy = max(_mat_yt + 5.0, min(_mat_ybot - 2.0, _ry + _rh / 2))
        mat_svg.append(
            f'<text x="{_mat_xl - 4}" y="{_lcy:.2f}" text-anchor="end" '
            f'font-family="Arial, sans-serif" font-size="8" fill="#444">'
            f'{html.escape(_reg["label"])}</text>'
        )

    # Address-axis tick lines and hex labels at every region boundary
    _tick_addrs = {0, _mat_addr_max}
    for _reg in _sregs:
        _tick_addrs.add(_reg['base'])
        _tick_addrs.add(_reg['end'] + 1)
    _prev_ty = -999.0
    for _addr in sorted(_tick_addrs):
        _ty = _mat_ay(_addr)
        if _ty < _mat_yt - 1 or _ty > _mat_ybot + 1:
            continue
        mat_svg.append(
            f'<line x1="{_mat_xl - 3}" y1="{_ty:.2f}" x2="{_mat_xl + _mat_pw}" y2="{_ty:.2f}" '
            f'stroke="#d0d0d0" stroke-width="0.5"/>'
        )
        if abs(_ty - _prev_ty) >= 9:
            mat_svg.append(
                f'<text x="{_mat_xl - 5}" y="{_ty - 1:.2f}" text-anchor="end" '
                f'font-family="monospace" font-size="7.5" fill="#777">0x{_addr:05X}</text>'
            )
            _prev_ty = _ty

    # Time-axis grid (same tick positions as Gantt chart)
    for _t in ticks:
        _tx = _mat_xl + (_t / total_for_plot) * _mat_pw
        mat_svg.append(
            f'<line x1="{_tx:.2f}" y1="{_mat_yt}" x2="{_tx:.2f}" y2="{_mat_ybot}" '
            f'stroke="#e8e8e8" stroke-width="1"/>'
        )
        mat_svg.append(
            f'<text x="{_tx:.2f}" y="{_mat_ybot + 13}" text-anchor="middle" '
            f'font-family="Arial, sans-serif" font-size="10" fill="#555">{_t}</text>'
        )

    mat_svg.append(
        f'<rect x="{_mat_xl}" y="{_mat_yt}" width="{_mat_pw}" height="{_mat_ph}" '
        f'fill="none" stroke="#999" stroke-width="1"/>'
    )
    mat_svg.append(
        f'<text x="{_mat_xl + _mat_pw / 2:.2f}" y="{_mat_h - 4}" text-anchor="middle" '
        f'font-family="Arial, sans-serif" font-size="11" fill="#333">'
        f'Transaction number (same axis as Execution Timeline)</text>'
    )

    # One colored rectangle per (pattern_node, memory region)
    for _node in pattern_nodes:
        if _node['end_cycle'] <= _node['start_cycle']:
            continue
        _nx = _mat_xl + (_node['start_cycle'] / total_for_plot) * _mat_pw
        _nw = max(1.5, ((_node['end_cycle'] - _node['start_cycle']) / total_for_plot) * _mat_pw)
        for _reg in _node.get('regions', []):
            _base = int(_reg.get('base', 0))
            _size = int(_reg.get('size', 0))
            if _size <= 0 or _base >= _mat_addr_max:
                continue
            _lbl = str(_reg.get('label', '')).lower()
            if 'write' in _lbl and 'read' not in _lbl:
                _color = _WC; _rws = "W"
            elif 'read' in _lbl and 'write' not in _lbl:
                _color = _RC; _rws = "R"
            else:
                _rpct = _node.get('traffic_read_pct')
                if _rpct is not None:
                    _rpi = int(_rpct)
                    _color, _rws = (_RC, "R") if _rpi >= 70 else ((_WC, "W") if _rpi <= 30 else (_MC, "R/W"))
                else:
                    _color = _MC; _rws = "R/W"
            _ry = _mat_ay(_base)
            _rh = _mat_ah(_size)
            _ry0 = max(float(_mat_yt), _ry)
            _ry1 = min(float(_mat_ybot), _ry + _rh)
            _rhc = _ry1 - _ry0
            if _rhc <= 0:
                continue
            _ttl = (
                f"{_node['job']} [{_node['start_cycle']}, {_node['end_cycle']}) "
                f"0x{_base:05X}+{_size}B {_rws}"
            )
            mat_svg.append('<g style="cursor:help;">')
            mat_svg.append(f'<title>{html.escape(_ttl)}</title>')
            mat_svg.append(
                f'<rect x="{_nx:.2f}" y="{_ry0:.2f}" width="{_nw:.2f}" height="{_rhc:.2f}" '
                f'fill="{_color}" fill-opacity="0.45" stroke="{_color}" stroke-width="0.7" rx="1.5"/>'
            )
            if _nw >= 28 and _rhc >= 9:
                mat_svg.append(
                    f'<text x="{_nx + 2:.2f}" y="{_ry0 + min(_rhc - 1, 8):.2f}" '
                    f'font-family="Arial, sans-serif" font-size="7" fill="#111" '
                    f'style="pointer-events:none;">{html.escape(_node["job"])}</text>'
                )
            mat_svg.append('</g>')

    # Legend
    for _li, (_lc, _ll) in enumerate([(_RC, "Read from TCDM"), (_WC, "Write to TCDM"), (_MC, "Read + Write")]):
        _lx = _mat_xl + _li * 200
        _ly = _mat_ybot + 26
        mat_svg.append(
            f'<rect x="{_lx:.2f}" y="{_ly}" width="10" height="10" '
            f'fill="{_lc}" fill-opacity="0.6" stroke="{_lc}" rx="1"/>'
        )
        mat_svg.append(
            f'<text x="{_lx + 14:.2f}" y="{_ly + 9}" '
            f'font-family="Arial, sans-serif" font-size="10" fill="#333">'
            f'{html.escape(_ll)}</text>'
        )
    mat_svg.append('</svg>')

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
        f"{''.join(mat_svg)}"
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
