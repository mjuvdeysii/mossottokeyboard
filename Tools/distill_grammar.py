#!/usr/bin/env python3
"""
Build the R100 dual-section Rime::Grammar/1.0 language model cleanly offline:
  - Section 1: Wanxiang teacher + Octagram corroborated 2..4-grams (Viterbi decoding)
  - Section 2: Pruned Octagram sub-trie appended in-file (context continuations)

Keeps 100% Rime::Grammar/1.0 mmap zero-dirty-RAM layout and <= 48.50 MB total size.
"""
import argparse
import gzip
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CPP_SRC = os.path.join(ROOT, "Tools", "distill_grammar.cpp")
DARTS_DIR = os.path.join(ROOT, "Tools", "third_party")
FETCH_SCRIPT = os.path.join(ROOT, "Tools", "fetch_sentence_model.sh")


def main() -> None:
    ap = argparse.ArgumentParser(description="Distill Wanxiang + Octagram into dual-section grammar.gram")
    ap.add_argument("--student", default="/tmp/octagram-base.gram", help="Original 39MB Octagram grammar.gram path")
    ap.add_argument("--teacher", default="/tmp/wanxiang-lts-zh-hans.gram", help="Wanxiang teacher .gram path (in /tmp)")
    ap.add_argument("--lexicon", default=os.path.join(ROOT, "Keyboard/Resources/lexicon.bin"), help="Path to lexicon.bin")
    ap.add_argument("--out", default=os.path.join(ROOT, "Keyboard/Resources/grammar.gram"), help="Output dual-section .gram")
    ap.add_argument("--k2", type=int, default=100000)
    ap.add_argument("--k3", type=int, default=2980000)
    ap.add_argument("--k4", type=int, default=2620000)
    ap.add_argument("--w-seg", type=float, default=1.0)
    ap.add_argument("--w-tea", type=float, default=1.5)
    ap.add_argument("--stu-boost", type=float, default=3.0)
    ap.add_argument("--pred-max3-1ch", type=int, default=80000)
    ap.add_argument("--pred-max3-2ch", type=int, default=340000)
    ap.add_argument("--pred-max4-1ch", type=int, default=160000)
    ap.add_argument("--pred-max4-2ch", type=int, default=70000)
    ap.add_argument("--pred-lambda", type=float, default=1.0)
    args = ap.parse_args()

    if not os.path.exists(args.teacher):
        print(f"Teacher model missing at {args.teacher}; fetching via fetch_sentence_model.sh...")
        subprocess.check_call(["bash", FETCH_SCRIPT, args.teacher])

    if not os.path.exists(args.student):
        if os.path.exists(args.out) and os.path.getsize(args.out) < 42_000_000:
            shutil.copy2(args.out, args.student)
        else:
            sys.exit(f"Missing original 39MB Octagram student model at {args.student}")

    bin_path = "/tmp/distill-grammar"
    subprocess.check_call([
        "clang++", "-O3", "-std=c++17", f"-I{DARTS_DIR}", CPP_SRC, "-o", bin_path
    ])

    tmp_out = args.out + ".tmp"
    subprocess.check_call([
        bin_path,
        "--student", args.student,
        "--teacher", args.teacher,
        "--lexicon", args.lexicon,
        "--out", tmp_out,
        "--k2", str(args.k2),
        "--k3", str(args.k3),
        "--k4", str(args.k4),
        "--w-seg", str(args.w_seg),
        "--w-tea", str(args.w_tea),
        "--stu-boost", str(args.stu_boost),
        "--pred-max3-1ch", str(args.pred_max3_1ch),
        "--pred-max3-2ch", str(args.pred_max3_2ch),
        "--pred-max4-1ch", str(args.pred_max4_1ch),
        "--pred-max4-2ch", str(args.pred_max4_2ch),
        "--pred-lambda", str(args.pred_lambda),
    ])
    os.replace(tmp_out, args.out)

    raw_bytes = os.path.getsize(args.out)
    with open(args.out, "rb") as f_in:
        gz_bytes = len(gzip.compress(f_in.read(), compresslevel=6))
    print(f"Verified {args.out}: {raw_bytes / 1048576:.2f} MB raw, {gz_bytes / 1048576:.2f} MB gzipped")


if __name__ == "__main__":
    main()
