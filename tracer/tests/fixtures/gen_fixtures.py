#!/usr/bin/env python3
#
# gen_fixtures.py
# Francesco Conti <f.conti@unibo.it>
#
# Regenerate the synthetic transaction logs used by the integration tests.
# They are written in exactly the format emitted by hci_transaction_tracer and
# hwpe_stream_transaction_tracer: fixed-width, `0x`-prefixed hexadecimal.
#
#   python3 tests/fixtures/gen_fixtures.py
#
# The generated files are committed, so this script only needs to be run when
# the fixtures themselves must change.

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# 8 write payloads shared by the HCI request logs and the HWPE-Stream logs, so
# that the cross-domain comparisons line up.
DATA = [0xDEAD0000 + i * 0x1111 for i in range(8)]
BASE_ADD = 0x1C010000


def hx(value, bits):
    return "0x%0*x" % ((bits + 3) // 4, value)


def write(name, obj):
    path = os.path.join(HERE, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)
        f.write("\n")
    return path


def hci_req_log(txs, dw=32, aw=32, bw=8, uw=0, iw=8, ew=0, path="tb.i_tracer_a"):
    return {
        "schema": "hci_transaction_request-v1",
        "interface": {"DW": dw, "AW": aw, "BW": bw, "UW": uw, "IW": iw, "EW": ew},
        "path": path,
        "transactions": txs,
    }


def hci_rsp_log(txs, dw=32, aw=32, bw=8, uw=0, iw=8, ew=0, path="tb.i_tracer_a"):
    return {
        "schema": "hci_transaction_response-v1",
        "interface": {"DW": dw, "AW": aw, "BW": bw, "UW": uw, "IW": iw, "EW": ew},
        "path": path,
        "transactions": txs,
    }


def stream_log(txs, dw=32, ew=8, path="tb.i_stream_tracer_a"):
    return {
        "schema": "hwpe_stream_transaction-v1",
        "interface": {"DATA_WIDTH": dw, "ELEMENT_WIDTH": ew, "STRB_WIDTH": dw // ew},
        "path": path,
        "transactions": txs,
    }


def req(seq, cycle, add, wen, data, be, dw=32, aw=32, sw=4, tid=None):
    tx = {
        "seq": seq,
        "cycle": cycle,
        "add": hx(add, aw),
        "wen": wen,
        "data": hx(data, dw),
        "be": hx(be, sw),
    }
    if tid is not None:
        tx["id"] = hx(tid, 8)
    return tx


def rsp(seq, cycle, data, opc=0, dw=32, tid=None):
    tx = {"seq": seq, "cycle": cycle, "r_data": hx(data, dw), "r_opc": opc}
    if tid is not None:
        tx["r_id"] = hx(tid, 8)
    return tx


def beat(seq, cycle, data, strb, dw=32, sw=4):
    return {"seq": seq, "cycle": cycle, "data": hx(data, dw), "strb": hx(strb, sw)}


def req_basic(cycle0, path):
    txs = [
        req(i, cycle0 + 2 * i, BASE_ADD + 4 * i, 0, DATA[i], 0xF, tid=i)
        for i in range(8)
    ]
    return hci_req_log(txs, path=path)


def rsp_basic(cycle0, path):
    txs = [rsp(i, cycle0 + 2 * i, DATA[i], 0, tid=i) for i in range(8)]
    return hci_rsp_log(txs, path=path)


def stream_basic(cycle0, path):
    return stream_log([beat(i, cycle0 + 3 * i, DATA[i], 0xF) for i in range(8)], path=path)


def main():
    generated = []

    # --- HCI requests: the reference pair -----------------------------------
    generated.append(write("hci/req_a_basic.json", req_basic(10, "tb.i_tracer_a")))
    generated.append(write("hci/req_b_basic.json", req_basic(37, "tb.i_tracer_b")))

    # One nibble of one transaction differs.
    log = req_basic(37, "tb.i_tracer_b")
    log["transactions"][4]["data"] = hx(DATA[4] & ~0x0400, 32)
    generated.append(write("hci/req_b_one_mismatch.json", log))

    # An extra transaction inserted in the middle of B.
    log = req_basic(37, "tb.i_tracer_b")
    log["transactions"].insert(
        4, req(99, 44, BASE_ADD + 0x100, 0, 0xCAFEBABE, 0xF, tid=99)
    )
    generated.append(write("hci/req_b_extra_tx.json", log))

    # ... and in the middle of A.
    log = req_basic(10, "tb.i_tracer_a")
    log["transactions"].insert(
        4, req(99, 21, BASE_ADD + 0x200, 0, 0x0BADF00D, 0xF, tid=99)
    )
    generated.append(write("hci/req_a_extra_tx.json", log))

    # Reads mixed in, to exercise the wen filter of hci-req-vs-stream.
    txs = []
    seq = 0
    for i in range(8):
        if i in (3, 7):
            txs.append(req(seq, 10 + 2 * seq, BASE_ADD + 0x400 + 4 * i, 1, 0, 0xF, tid=seq))
            seq += 1
        txs.append(req(seq, 10 + 2 * seq, BASE_ADD + 4 * i, 0, DATA[i], 0xF, tid=seq))
        seq += 1
    generated.append(write("hci/req_a_with_loads.json", hci_req_log(txs)))

    # Byte enables that make part of the data a genuine don't-care.
    a = hci_req_log(
        [req(i, 10 + i, BASE_ADD + 4 * i, 0, DATA[i], 0x3, tid=i) for i in range(4)]
    )
    b = hci_req_log(
        [
            req(i, 90 + i, BASE_ADD + 4 * i, 0, DATA[i] & 0x0000FFFF, 0x3, tid=i)
            for i in range(4)
        ],
        path="tb.i_tracer_b",
    )
    generated.append(write("hci/req_a_be_dontcare.json", a))
    generated.append(write("hci/req_b_be_dontcare.json", b))

    # x/z bits: one in an enabled byte (a real difference), one in a disabled
    # byte (a don't-care that must never be flagged).
    a = hci_req_log(
        [
            {
                "seq": 0,
                "cycle": 10,
                "add": hx(BASE_ADD, 32),
                "wen": 0,
                "data": "0xdead00x0",
                "be": "0xf",
                "id": "0x00",
            },
            {
                "seq": 1,
                "cycle": 12,
                "add": hx(BASE_ADD + 4, 32),
                "wen": 0,
                "data": "0xxxxx1111",
                "be": "0x3",
                "id": "0x01",
            },
        ]
    )
    b = hci_req_log(
        [
            req(0, 90, BASE_ADD, 0, 0xDEAD0000, 0xF, tid=0),
            req(1, 92, BASE_ADD + 4, 0, 0x00001111, 0x3, tid=1),
        ],
        path="tb.i_tracer_b",
    )
    generated.append(write("hci/req_a_xcase.json", a))
    generated.append(write("hci/req_b_xcase.json", b))

    # Bank-width interconnect: one enable bit per 32-bit word.
    wide = [0x1111111122222222333333334444444 + i for i in range(3)]
    a = hci_req_log(
        [req(i, 10 + i, BASE_ADD + 16 * i, 0, wide[i], 0x3, dw=128, sw=4, tid=i) for i in range(3)],
        dw=128,
        bw=32,
    )
    b = hci_req_log(
        [req(i, 90 + i, BASE_ADD + 16 * i, 0, wide[i], 0x3, dw=128, sw=4, tid=i) for i in range(3)],
        dw=128,
        bw=32,
        path="tb.i_tracer_b",
    )
    generated.append(write("hci/req_a_bw32.json", a))
    generated.append(write("hci/req_b_bw32.json", b))

    # 512-bit data, differing in a single byte at bits [95:88].
    big = [sum(((i * 16 + n) % 256) << (8 * n) for n in range(64)) for i in range(3)]
    a = hci_req_log(
        [
            req(i, 10 + i, BASE_ADD + 64 * i, 0, big[i], (1 << 64) - 1, dw=512, sw=64, tid=i)
            for i in range(3)
        ],
        dw=512,
    )
    b = hci_req_log(
        [
            req(
                i,
                90 + i,
                BASE_ADD + 64 * i,
                0,
                big[i] ^ (0x5A << 88 if i == 1 else 0),
                (1 << 64) - 1,
                dw=512,
                sw=64,
                tid=i,
            )
            for i in range(3)
        ],
        dw=512,
        path="tb.i_tracer_b",
    )
    generated.append(write("hci/req_a_wide512.json", a))
    generated.append(write("hci/req_b_wide512.json", b))

    # 64-bit requests, and the 32-bit stream they pack into.
    pairs = [(DATA[2 * i + 1] << 32) | DATA[2 * i] for i in range(4)]
    generated.append(
        write(
            "hci/req_a_dw64.json",
            hci_req_log(
                [
                    req(i, 10 + i, BASE_ADD + 8 * i, 0, pairs[i], 0xFF, dw=64, sw=8, tid=i)
                    for i in range(4)
                ],
                dw=64,
            ),
        )
    )

    # --- truncated logs -----------------------------------------------------
    full = json.dumps(req_basic(10, "tb.i_tracer_a"), indent=2)
    # Cut in the middle of the 6th transaction.
    marker = '"seq": 5'
    cut = full.index(marker) + len(marker) + 8
    with open(os.path.join(HERE, "hci/req_truncated_midobj.json"), "w") as f:
        f.write(full[:cut])
    generated.append("hci/req_truncated_midobj.json")

    # Cut right after the comma that follows the last transaction.
    end = full.rindex("}", 0, full.rindex("]"))
    with open(os.path.join(HERE, "hci/req_truncated_after_comma.json"), "w") as f:
        f.write(full[: end + 1] + ",")
    generated.append("hci/req_truncated_after_comma.json")

    # Cut before the interface object closes: nothing to salvage.
    with open(os.path.join(HERE, "hci/req_truncated_no_interface.json"), "w") as f:
        f.write('{\n  "schema": "hci_transaction_request-v1",\n  "interface": { "DW": 32, "AW"')
    generated.append("hci/req_truncated_no_interface.json")

    # --- HCI responses ------------------------------------------------------
    generated.append(write("hci/rsp_a_basic.json", rsp_basic(11, "tb.i_tracer_a")))
    generated.append(write("hci/rsp_b_basic.json", rsp_basic(38, "tb.i_tracer_b")))

    log = rsp_basic(38, "tb.i_tracer_b")
    log["transactions"][2]["r_opc"] = 1
    generated.append(write("hci/rsp_b_opc_mismatch.json", log))

    # Same payloads, every cycle shifted: must still compare equal.
    log = rsp_basic(11, "tb.i_tracer_a")
    for tx in log["transactions"]:
        tx["cycle"] += 100
    generated.append(write("hci/rsp_a_cycle_shift.json", log))

    # --- HWPE-Stream --------------------------------------------------------
    generated.append(write("stream/str_a_basic.json", stream_basic(20, "tb.i_stream_a")))
    generated.append(write("stream/str_b_basic.json", stream_basic(51, "tb.i_stream_b")))

    log = stream_basic(51, "tb.i_stream_b")
    log["transactions"][2]["strb"] = "0x7"
    log["transactions"][2]["data"] = hx(DATA[2] & 0x00FFFFFF, 32)
    generated.append(write("stream/str_b_strb_mismatch.json", log))

    log = stream_basic(51, "tb.i_stream_b")
    log["transactions"] = log["transactions"][:7]
    generated.append(write("stream/str_b_shorter.json", log))

    # Same enabled bits as be=0xf on a 32-bit bus, encoded with 4-bit elements.
    generated.append(
        write(
            "stream/str_ew4.json",
            stream_log(
                [beat(i, 20 + 3 * i, DATA[i], 0xFF, sw=8) for i in range(8)],
                ew=4,
                path="tb.i_stream_ew4",
            ),
        )
    )

    # The 32-bit stream matching hci/req_a_dw64.json under --split.
    generated.append(
        write(
            "stream/str_from_dw64.json",
            stream_log(
                [beat(i, 20 + 3 * i, DATA[i], 0xF) for i in range(8)],
                path="tb.i_stream_from_dw64",
            ),
        )
    )

    # --- malformed ----------------------------------------------------------
    log = req_basic(10, "tb.i_tracer_a")
    log["schema"] = "hci_transaction_bogus-v9"
    generated.append(write("malformed/bad_schema_tag.json", log))

    log = req_basic(10, "tb.i_tracer_a")
    del log["interface"]
    generated.append(write("malformed/missing_interface.json", log))

    log = req_basic(10, "tb.i_tracer_a")
    log["interface"]["BW"] = 5
    generated.append(write("malformed/dw_not_multiple_of_bw.json", log))

    with open(os.path.join(HERE, "malformed/empty.json"), "w") as f:
        f.write("")
    generated.append("malformed/empty.json")

    for name in generated:
        print(name if isinstance(name, str) else os.path.relpath(name, HERE))


if __name__ == "__main__":
    main()
