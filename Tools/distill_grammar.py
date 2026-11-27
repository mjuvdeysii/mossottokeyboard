#!/usr/bin/env python3
"""
Build the R105 dual-section Mosto::GramV2 8-bit quantized language model purely from CC-BY-4.0 Wanxiang data:
  - Section 1: Wanxiang 2..4-grams (Viterbi sentence decoding)
  - Section 2: Wanxiang 2-band context continuations (single-char & 2-char predictions)

Zero third-party C++ headers; enforces <= 48.50 MiB (50,855,936 B) raw ceiling and zero-dirty-RAM mmap layout.
"""
import argparse
import gzip
import os
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CPP_SRC = os.path.join(ROOT, "Tools", "distill_grammar.cpp")
FETCH_SCRIPT = os.path.join(ROOT, "Tools", "fetch_sentence_model.sh")


def main() -> None:
    ap = argparse.ArgumentParser(description="Distill CC-BY-4.0 Wanxiang into dual-section Mosto::GramV2 grammar.gram")
    ap.add_argument("--source", default="/tmp/wanxiang-lts-zh-hans.gram", help="Wanxiang source .gram path")
    ap.add_argument("--lexicon", default=os.path.join(ROOT, "Keyboard/Resources/lexicon.bin"), help="Path to lexicon.bin")
    ap.add_argument("--zi", default="/tmp/zi_standalone.tsv", help="Optional standalone char log-counts TSV")
    ap.add_argument("--out", default=os.path.join(ROOT, "Keyboard/Resources/grammar.gram"), help="Output dual-section .gram")
    ap.add_argument("--k2", type=int, default=100000)
    ap.add_argument("--k3", type=int, default=4300000)
    ap.add_argument("--k4", type=int, default=7710000)
    ap.add_argument("--pred-max3-1ch", type=int, default=70000)
    ap.add_argument("--pred-max3-2ch", type=int, default=180000)
    ap.add_argument("--pred-max4-1ch", type=int, default=90000)
    ap.add_argument("--pred-max4-2ch", type=int, default=55000)
    ap.add_argument("--pred-lambda", type=float, default=1.0)
    args = ap.parse_args()

    if not os.path.exists(args.source):
        print(f"Wanxiang source missing at {args.source}; fetching via fetch_sentence_model.sh...")
        subprocess.check_call(["bash", FETCH_SCRIPT, args.source])

    bin_path = "/tmp/distill-grammar"
    subprocess.check_call(["clang++", "-O3", "-std=c++17", CPP_SRC, "-o", bin_path])

    tmp_out = args.out + ".tmp"
    cmd = [
        bin_path,
        "--source", args.source,
        "--lexicon", args.lexicon,
        "--out", tmp_out,
        "--k2", str(args.k2),
        "--k3", str(args.k3),
        "--k4", str(args.k4),
        "--pred-max3-1ch", str(args.pred_max3_1ch),
        "--pred-max3-2ch", str(args.pred_max3_2ch),
        "--pred-max4-1ch", str(args.pred_max4_1ch),
        "--pred-max4-2ch", str(args.pred_max4_2ch),
        "--pred-lambda", str(args.pred_lambda),
    ]
    if args.zi and os.path.exists(args.zi):
        cmd += ["--zi", args.zi]
    subprocess.check_call(cmd)
    os.replace(tmp_out, args.out)

    raw_bytes = os.path.getsize(args.out)
    with open(args.out, "rb") as f_in:
        gz_bytes = len(gzip.compress(f_in.read(), compresslevel=6))
    print(f"Verified {args.out}: {raw_bytes / 1048576:.2f} MB raw, {gz_bytes / 1048576:.2f} MB gzipped")


if __name__ == "__main__":
    main()
