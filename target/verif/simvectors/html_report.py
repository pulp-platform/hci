"""HTML report generation for memory lifetime visualization."""

from collections import deque
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
    tot_mem_size,
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
    exec_svg.append(f'<text x="{x_left}" y="20" font-family="Arial, sans-serif" font-size="14" font-weight="700">Execution Timeline</text>')
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

        if node.get('mem_access_type') == 'copy_linear':
            lines = []
            for lbl in ('src(read)', 'dst(write)'):
                if lbl in label_map:
                    r = label_map[lbl]
                    short = 'src' if lbl.startswith('src') else 'dst'
                    lines.append(f"{short}@0x{int(r['base']):08x} ({_fmt_kib(r['size'])})")
            return lines or [f"@0x{base_addr:08x}", f"{size_kib:.1f} KiB"]

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
        nodes = sorted(
            [n for n in pattern_nodes if n['driver_idx'] == row['driver_idx']],
            key=lambda n: n['start_cycle'],
        )
        for node_i, node in enumerate(nodes):
            if node['end_cycle'] <= node['start_cycle']:
                continue
            x = x_left + (node['start_cycle'] / total_for_plot) * plot_w
            w = max(1.0, ((node['end_cycle'] - node['start_cycle']) / total_for_plot) * plot_w)
            # clip width: extend to next box start (or plot edge) so text can use empty space
            next_nodes = [n for n in nodes[node_i + 1:] if n['end_cycle'] > n['start_cycle']]
            if next_nodes:
                next_x = x_left + (next_nodes[0]['start_cycle'] / total_for_plot) * plot_w
            else:
                next_x = x_left + plot_w
            clip_w = max(w, next_x - x)
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
            clip_id = f"c{node['node_idx']}"
            exec_svg.append(
                f'<defs><clipPath id="{clip_id}">'
                f'<rect x="{x:.2f}" y="{y}" width="{clip_w:.2f}" height="{row_h}"/>'
                f'</clipPath></defs>'
            )
            exec_svg.append('<g style="cursor:help;">')
            exec_svg.append(f'<title>{html.escape(title)}</title>')
            exec_svg.append(
                f'<rect x="{x:.2f}" y="{y + 4}" width="{w:.2f}" height="34" '
                f'rx="3" ry="3" fill="{color}" fill-opacity="0.82" stroke="#222" stroke-width="0.2"/>'
            )
            exec_svg.append(f'<g clip-path="url(#{clip_id})" style="pointer-events:none;">')
            line1 = html.escape(line1_full)
            exec_svg.append(
                f'<text x="{x + 4:.2f}" y="{y + 15}" font-family="Arial, sans-serif" font-size="9" '
                f'fill="#ffffff">{line1}</text>'
            )
            line2 = html.escape(line2_full)
            exec_svg.append(
                f'<text x="{x + 4:.2f}" y="{y + 25}" font-family="Arial, sans-serif" font-size="8" '
                f'fill="#ffffff">{line2}</text>'
            )
            line3 = html.escape(line3_full)
            exec_svg.append(
                f'<text x="{x + 4:.2f}" y="{y + 34}" font-family="Arial, sans-serif" font-size="8" '
                f'fill="#ffffff">{line3}</text>'
            )
            for ext_idx, ext in enumerate(outside_lines):
                y_ext = y + 49 + (ext_idx * 9)
                ext_txt = html.escape(ext)
                exec_svg.append(
                    f'<text x="{x + 2:.2f}" y="{y_ext:.2f}" font-family="Arial, sans-serif" font-size="8" '
                    f'fill="#333333">{ext_txt}</text>'
                )
            exec_svg.append('</g>')
            exec_svg.append('</g>')
    exec_svg.append('</svg>')

    region_rows = [regions_timeline[k] for k in sorted(regions_timeline.keys(), key=lambda k: (k[0], k[1], k[2]))]

    used_min = min((reg['base'] for reg in region_rows), default=0)
    used_max = max((reg['end'] for reg in region_rows), default=0)
    if used_max < used_min:
        used_max = used_min
    used_span = max(1, used_max - used_min + 1)

    # ---- Memory Address Timeline (2-D: address × time) ----
    _mat_addr_max = int(tot_mem_size) * 1024
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

    # ---- Non-linear Y axis ----
    # Each region interval gets a guaranteed minimum of _min_px display pixels
    # (tall enough to show its start-address label on the Y axis), plus a
    # proportional share of the remaining space.  This way _disp_scale == 1 and
    # small regions never collapse below _min_px regardless of how many there are.
    _min_px = 14.0   # px per region — enough for a 7.5px address label below the tick
    _sregs = sorted(region_rows, key=lambda r: r['base'])

    # Boundaries: region starts + 0 + addr_max  (end+1 skipped to reduce tick clutter)
    _boundaries = sorted({0, _mat_addr_max}
                         | {r['base'] for r in _sregs}
                         | {r['end'] + 1 for r in _sregs})

    # Count how many boundary intervals are "region" intervals
    def _interval_is_region(a0, a1):
        return any(r['base'] <= a0 and r['end'] >= a1 - 1 for r in _sregs)

    _n_reg_intervals = sum(
        1 for _bi in range(len(_boundaries) - 1)
        if _interval_is_region(_boundaries[_bi], _boundaries[_bi + 1])
    )
    # Reserve fixed pixel budget for regions; remainder distributed proportionally
    _reserved = _n_reg_intervals * _min_px
    _remaining = max(0.0, _mat_ph - _reserved)

    # Build intervals with guaranteed minimum pixel heights (disp_scale == 1.0)
    _intervals = []   # (addr_lo, addr_hi, disp_h_px)
    for _bi in range(len(_boundaries) - 1):
        _a0, _a1 = _boundaries[_bi], _boundaries[_bi + 1]
        _span = _a1 - _a0
        _prop_h = (_span / _mat_addr_span) * _remaining
        _is_r = _interval_is_region(_a0, _a1)
        _dh = (_min_px + _prop_h) if _is_r else _prop_h
        _intervals.append((_a0, _a1, _dh))
    # Total == _mat_ph by construction; no scaling needed
    _disp_scale = 1.0

    # Build cumulative lookup: addr -> y pixel
    _cum_addr = [_boundaries[0]]
    _cum_y = [float(_mat_yt)]
    for _a0, _a1, _dh in _intervals:
        _cum_addr.append(_a1)
        _cum_y.append(_cum_y[-1] + _dh)

    def _mat_ay(addr):
        _a = max(0, min(int(addr), _mat_addr_max))
        # Binary search in cumulative table
        _lo, _hi = 0, len(_cum_addr) - 1
        while _lo < _hi - 1:
            _mid = (_lo + _hi) // 2
            if _cum_addr[_mid] <= _a:
                _lo = _mid
            else:
                _hi = _mid
        # Interpolate within interval
        _ia0, _ia1 = _cum_addr[_lo], _cum_addr[_hi]
        _iy0, _iy1 = _cum_y[_lo], _cum_y[_hi]
        if _ia1 == _ia0:
            return _iy0
        return _iy0 + (_a - _ia0) / (_ia1 - _ia0) * (_iy1 - _iy0)

    def _mat_ah(addr_start, size):
        return max(1.5, _mat_ay(int(addr_start) + int(size)) - _mat_ay(int(addr_start)))

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

    # Background bands — each region uses the same non-linear mapping as everything else
    for _i, _reg in enumerate(_sregs):
        _ry = _mat_ay(_reg['base'])
        _rh = _mat_ah(_reg['base'], _reg['size'])
        _fill = "#f5f5f5" if _i % 2 == 0 else "#ebebeb"
        mat_svg.append(
            f'<rect x="{_mat_xl}" y="{_ry:.2f}" width="{_mat_pw}" height="{_rh:.2f}" '
            f'fill="{_fill}" stroke="#ddd" stroke-width="0.5"/>'
        )

    # Address-axis tick lines and hex labels.
    # Show region start addresses + 0 + addr_max.
    # With non-linear mapping each region start is >= _min_px apart — all labels fit.
    _tick_addrs = sorted({0, _mat_addr_max} | {r['base'] for r in _sregs})
    _prev_ty = -999.0
    for _addr in _tick_addrs:
        _ty = _mat_ay(_addr)
        if _ty < _mat_yt - 1 or _ty > _mat_ybot + 1:
            continue
        mat_svg.append(
            f'<line x1="{_mat_xl - 3}" y1="{_ty:.2f}" x2="{_mat_xl + _mat_pw}" y2="{_ty:.2f}" '
            f'stroke="#d0d0d0" stroke-width="0.5"/>'
        )
        if abs(_ty - _prev_ty) >= 8:
            mat_svg.append(
                f'<text x="{_mat_xl - 5}" y="{_ty + 7:.2f}" text-anchor="end" '
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
        f'<text x="{_mat_xl + _mat_pw / 2:.2f}" y="{_mat_h - 18}" text-anchor="middle" '
        f'font-family="Arial, sans-serif" font-size="12" fill="#333">Transaction number</text>'
    )
    mat_svg.append(
        f'<text x="{_mat_xl + _mat_pw / 2:.2f}" y="{_mat_h - 2}" text-anchor="middle" '
        f'font-family="Arial, sans-serif" font-size="11" fill="#555">'
        f'Issued memory transactions (r/w) and computation cycles (i.e., req = 0) are both modeled here.'
        f'</text>'
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
            _rh = _mat_ah(_base, _size)
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
            if _nw >= 8 and _rhc >= 9:
                _chars_per_line = max(1, int((_nw - 4) / 4))
                _job = _node["job"]
                _lines = [_job[i:i + _chars_per_line] for i in range(0, len(_job), _chars_per_line)]
                _clip_id = f"mc{_node['node_idx']}r{_base}"
                mat_svg.append(
                    f'<defs><clipPath id="{_clip_id}">'
                    f'<rect x="{_nx:.2f}" y="{_ry0:.2f}" width="{_nw:.2f}" height="{_rhc:.2f}"/>'
                    f'</clipPath></defs>'
                )
                mat_svg.append(f'<g clip-path="url(#{_clip_id})" style="pointer-events:none;">')
                for _li, _line in enumerate(_lines):
                    _ty = _ry0 + 8 + _li * 9
                    if _ty > _ry0 + _rhc:
                        break
                    mat_svg.append(
                        f'<text x="{_nx + 2:.2f}" y="{_ty:.2f}" '
                        f'font-family="Arial, sans-serif" font-size="7" fill="#111">'
                        f'{html.escape(_line)}</text>'
                    )
                mat_svg.append('</g>')
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

    # ---- Job Dependency DAG ----
    _dag_node_h = 28
    _dag_v_gap = 12
    _dag_h_gap = 70
    _dag_xl = 20
    _dag_yt = 50

    # Collect unique jobs (first occurrence wins for metadata)
    _dag_jobs = {}
    for _n in pattern_nodes:
        _jn = _n['job']
        if _jn not in _dag_jobs:
            _dag_jobs[_jn] = {
                'driver_idx': _n['driver_idx'],
                'driver_name': _n['driver_name'],
                'is_hwpe': _n['is_hwpe'],
                'wait_for': list(_n.get('wait_for_jobs_declared', [])),
            }

    # Filter wait_for to existing jobs only
    _all_dag_jobs = set(_dag_jobs)
    for _info in _dag_jobs.values():
        _info['wait_for'] = [d for d in _info['wait_for'] if d in _all_dag_jobs]

    # Build children map and in-degree for topological sort
    _dag_children = {j: [] for j in _dag_jobs}
    _dag_indeg = {j: 0 for j in _dag_jobs}
    for _jn, _info in _dag_jobs.items():
        for _dep in _info['wait_for']:
            _dag_children[_dep].append(_jn)
            _dag_indeg[_jn] += 1

    # Longest-path level assignment via topological BFS
    _dag_levels = {j: 0 for j in _dag_jobs}
    _tmp_indeg = dict(_dag_indeg)
    _q = deque(j for j in _dag_jobs if _tmp_indeg[j] == 0)
    while _q:
        _jn = _q.popleft()
        for _ch in _dag_children[_jn]:
            _dag_levels[_ch] = max(_dag_levels[_ch], _dag_levels[_jn] + 1)
            _tmp_indeg[_ch] -= 1
            if _tmp_indeg[_ch] == 0:
                _q.append(_ch)

    # Group by level; sort within level by (driver_idx, job_name)
    _dag_level_groups = {}
    for _jn, _lvl in _dag_levels.items():
        _dag_level_groups.setdefault(_lvl, []).append(_jn)
    for _lvl in _dag_level_groups:
        _dag_level_groups[_lvl].sort(key=lambda j: (_dag_jobs[j]['driver_idx'], j))

    # Node width: fit the longest job name (~5.8px per char at font-size 9 + padding)
    _dag_node_w = max(90, max((len(j) * 6 + 16) for j in _dag_jobs) if _dag_jobs else 90)

    # Assign (x, y) positions
    _dag_pos = {}
    _max_dag_lvl = max(_dag_levels.values()) if _dag_levels else 0
    for _lvl, _group in sorted(_dag_level_groups.items()):
        _nx = _dag_xl + _lvl * (_dag_node_w + _dag_h_gap)
        for _i, _jn in enumerate(_group):
            _dag_pos[_jn] = (_nx, _dag_yt + _i * (_dag_node_h + _dag_v_gap))

    _dag_svg_w = max(chart_width, _dag_xl + (_max_dag_lvl + 1) * (_dag_node_w + _dag_h_gap) + 20)
    _max_per_dag_lvl = max(len(g) for g in _dag_level_groups.values()) if _dag_level_groups else 1
    _dag_svg_h = _dag_yt + _max_per_dag_lvl * (_dag_node_h + _dag_v_gap) + 30

    dag_svg = []
    dag_svg.append(
        f'<svg width="{_dag_svg_w}" height="{_dag_svg_h}" '
        f'viewBox="0 0 {_dag_svg_w} {_dag_svg_h}" xmlns="http://www.w3.org/2000/svg">'
    )
    dag_svg.append('<rect x="0" y="0" width="100%" height="100%" fill="#ffffff"/>')
    dag_svg.append(
        f'<text x="{_dag_xl}" y="22" font-family="Arial, sans-serif" '
        f'font-size="14" font-weight="700">Job Dependency Graph</text>'
    )
    dag_svg.append(
        '<defs><marker id="dag_arr" markerWidth="8" markerHeight="7" refX="7" refY="3.5" orient="auto">'
        '<path d="M0,0 L0,7 L8,3.5 z" fill="#888"/>'
        '</marker></defs>'
    )

    # Edges (drawn before nodes so nodes appear on top)
    for _jn, _info in _dag_jobs.items():
        _tx, _ty = _dag_pos[_jn]
        _ty_mid = _ty + _dag_node_h / 2
        for _dep in _info['wait_for']:
            if _dep not in _dag_pos:
                continue
            _sx, _sy = _dag_pos[_dep]
            _sy_mid = _sy + _dag_node_h / 2
            _x1 = _sx + _dag_node_w
            _x2 = _tx
            _mx = (_x1 + _x2) / 2
            dag_svg.append(
                f'<path d="M{_x1:.1f},{_sy_mid:.1f} '
                f'C{_mx:.1f},{_sy_mid:.1f} {_mx:.1f},{_ty_mid:.1f} {_x2:.1f},{_ty_mid:.1f}" '
                f'fill="none" stroke="#aaa" stroke-width="1.2" marker-end="url(#dag_arr)"/>'
            )

    # Nodes
    for _jn, _info in _dag_jobs.items():
        _nx, _ny = _dag_pos[_jn]
        _nc = _color_for_driver(_info['driver_idx'])
        dag_svg.append(
            f'<rect x="{_nx}" y="{_ny}" width="{_dag_node_w}" height="{_dag_node_h}" '
            f'rx="4" fill="{_nc}" fill-opacity="0.88" stroke="#333" stroke-width="0.8"/>'
        )
        dag_svg.append(
            f'<text x="{_nx + 6}" y="{_ny + 18}" font-family="Arial, sans-serif" '
            f'font-size="9" fill="#ffffff" style="pointer-events:none;">'
            f'{html.escape(_jn)}</text>'
        )

    dag_svg.append('</svg>')

    legend_items = []
    for d in sorted(driver_windows.keys()):
        n = driver_name_fn(d)
        c = _color_for_driver(d)
        legend_items.append(
            f'<span style="display:inline-flex;align-items:center;margin-right:12px;margin-bottom:6px;">'
            f'<span style="display:inline-block;width:11px;height:11px;background:{c};margin-right:5px;border:1px solid #222;"></span>'
            f'<span>{html.escape(n)}</span></span>'
        )

    note ="Timeline follows declared wait_for_jobs dependencies from workload.json."
    note_2 = (
        "Time axis is transaction-count based only "
        "(no interconnect conflict/stall/arbitration modeling). "
        "Computation is modeled through idle cycles with no transaction issued."
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
        "<div class='panel'>"
        f"{''.join(dag_svg)}"
        "</div>"
        "</body></html>"
    )


def write_memory_lifetime_html(memory_lifetime_path: Path, **kwargs):
    html_doc = build_memory_lifetime_html(**kwargs)
    memory_lifetime_path.write_text(html_doc, encoding='utf-8')
