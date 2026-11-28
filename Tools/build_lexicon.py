#!/usr/bin/env python3
"""
Build the compact binary lexicon (lexicon.bin) used by the keyboard engine.

Source data: 100% pure CC-BY-4.0 amzxyz/rime-wanxiang-data:
  zi.dict.yaml     single characters + standalone counts
  jichu.dict.yaml  base modern Chinese vocabulary + counts
  duoyin.dict.yaml polyphonic pronunciations + counts
  diming.dict.yaml place names + counts
  wanxiang-lts-zh-hans.gram  2-gram corroboration for low-count 2-char words

Usage:
  python3 Tools/build_lexicon.py [--wanxiang-dir /tmp/wanxiang-dicts] \
      [--gram /tmp/wanxiang-lts-zh-hans.gram] [--demote Tools/data/demote.txt] \
      [--zi-out /tmp/zi_standalone.tsv] -o Keyboard/Resources/lexicon.bin

Binary layout (little endian):
  magic 'XHLX' | version u32 | sylCount u32 | entryCount u32 | sylBlobCount u32 | textBlobLen u32
  syllable names: sylCount * 8 bytes (ASCII, NUL padded)
  first-syllable index: sylCount * (start u32, end u32)   -> entry index range
  entries: entryCount * 12 bytes (textOff u32, sylOff u32, score i16, textLen u8, sylLen u8)
           version 2: sorted by first syllable, then second syllable (single characters first), then two-syllable
           words before longer ones, then score desc — so the words that start with a given pair of syllables are
           one contiguous run
  version 3 trailer: follower table, read into memory: sylCount * (start u32, count u32), then
           pairCount * (second u16, pad u16, pairsStart u32, longerStart u32, end u32), then pairCount u32, 'PAIR'
  syllable blob: u16[sylBlobCount]
  text blob: UTF-8 bytes
"""
import argparse
import math
import mmap
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unicodedata
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------- Xiaohe scheme
INITIAL_KEY = {"zh": "v", "ch": "i", "sh": "u"}
FINAL_KEY = {
    "iu": "q", "ei": "w", "e": "e", "uan": "r", "van": "r", "ue": "t", "ve": "t",
    "un": "y", "vn": "y", "u": "u", "i": "i", "o": "o", "uo": "o", "ie": "p",
    "a": "a", "ong": "s", "iong": "s", "ai": "d", "en": "f", "eng": "g",
    "ang": "h", "an": "j", "ing": "k", "uai": "k", "iang": "l", "uang": "l",
    "ou": "z", "ia": "x", "ua": "x", "ao": "c", "ui": "v", "v": "v", "in": "b",
    "iao": "n", "ian": "m",
}
ZERO_INITIAL = {"a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "er", "o", "ou"}
CANONICAL_SYLLABLES = set((
    "a ai an ang ao ba bai ban bang bao bei ben beng bi bian biang biao bie bin bing bo bu "
    "ca cai can cang cao ce cei cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo "
    "da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo "
    "e ei en eng er fa fan fang fei fen feng fiao fo fou fu "
    "ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo "
    "ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo "
    "ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun "
    "ka kai kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang kui kun kuo "
    "la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lun luo lv lve "
    "ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu "
    "na nai nan nang nao ne nei nen neng ni nian niang niao nie nin ning niu nong nou nu nuan nuo nv nve "
    "o ou pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu "
    "qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun "
    "ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo "
    "sa sai san sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su suan sui sun suo "
    "ta tai tan tang tao te tei teng ti tian tiao tie ting tong tou tu tuan tui tun tuo "
    "wa wai wan wang wei wen weng wo wu xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun "
    "ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun "
    "za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo"
).split())


def code_for(py: str):
    """Xiaohe shuangpin 2-key code for a pinyin syllable, or None if not typeable."""
    if py in ZERO_INITIAL:
        if len(py) == 1:          # a -> aa, e -> ee, o -> oo
            return py + py
        if len(py) == 2:          # ai an ao ei en er ou -> as written
            return py
        return py[0] + FINAL_KEY[py]  # ang -> ah, eng -> eg
    for ini in ("zh", "ch", "sh"):
        if py.startswith(ini):
            fin = py[2:]
            return INITIAL_KEY[ini] + FINAL_KEY[fin] if fin in FINAL_KEY else None
    ini, fin = py[0], py[1:]
    if ini not in "bpmfdtnlgkhjqxrzcsyw":
        return None
    return ini + FINAL_KEY[fin] if fin in FINAL_KEY else None


# ---------------------------------------------------------------- parsing
def plain_pinyin(py: str):
    """Convert tone-marked pinyin (ā bà nǚ lüè) to plain ascii syllable tuple."""
    out = []
    for s in py.split(" "):
        s = (
            s.replace("ü", "v")
            .replace("ǖ", "v")
            .replace("ǘ", "v")
            .replace("ǚ", "v")
            .replace("ǜ", "v")
        )
        s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
        out.append(s.lower())
    return tuple(out)


def read_wanxiang_counts(paths):
    """Read (text, plain_syllables) -> max int weight across one or more Wanxiang .dict.yaml files."""
    counts = {}
    for p in paths:
        if not os.path.exists(p):
            sys.exit(f"Missing Wanxiang dictionary: {p}")
        body = False
        with open(p, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not body:
                    body = line.strip() == "..."
                    continue
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) < 3:
                    continue
                try:
                    c = int(parts[2])
                except ValueError:
                    continue
                key = (parts[0], plain_pinyin(parts[1]))
                if c > counts.get(key, -1):
                    counts[key] = c
    return counts


_DUMP_GRAM2_CPP = r"""
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
static inline uint32_t d_offset(uint32_t u) { return (u >> 10) << ((u & (1U << 9)) >> 6); }
static inline uint32_t d_label(uint32_t u) { return u & ((1U << 31) | 0xFFU); }
static inline bool d_has_leaf(uint32_t u) { return ((u >> 8) & 1U) != 0; }
int main(int argc, char** argv) {
    int fd = ::open(argv[1], O_RDONLY);
    if (fd < 0) return 1;
    struct stat st{}; if (::fstat(fd, &st) != 0) return 1;
    const uint8_t* base = (const uint8_t*)mmap(nullptr, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (base == MAP_FAILED) return 1;
    uint32_t sz = 0; int32_t off = 0;
    memcpy(&sz, base + 36, 4); memcpy(&off, base + 40, 4);
    const uint32_t* arr = (const uint32_t*)(base + 40 + off);
    struct F { uint32_t id; uint16_t nc; uint8_t kl; };
    std::vector<uint8_t> key; std::vector<F> stv; stv.push_back({0, 1, 0});
    FILE* out = fopen(argv[2], "w");
    if (!out) return 1;
    while (!stv.empty()) {
        auto& f = stv.back();
        if (f.nc > 255) { stv.pop_back(); if (!stv.empty()) key.resize(stv.back().kl); continue; }
        uint32_t id = f.id, u = arr[id], bx = id ^ d_offset(u);
        while (f.nc <= 255) {
            uint32_t c = f.nc++; uint32_t nid = bx ^ c;
            if (nid < sz && d_label(arr[nid]) == c) {
                key.push_back((uint8_t)c); uint32_t nu = arr[nid];
                if (key.size() == 4 && d_has_leaf(nu)) {
                    uint32_t cps[2]; bool ok = true;
                    for (int k = 0; k < 2; ++k) {
                        uint8_t b0 = key[2 * k], b1 = key[2 * k + 1];
                        if (b0 == 0xE1) cps[k] = (uint32_t)(b1 - 0x40) << 8;
                        else if ((b0 & 0x80) && (b0 & 0xF0) != 0xE0) cps[k] = ((uint32_t)(b0 - 0x40) << 8) | b1;
                        else { ok = false; break; }
                        if (cps[k] < 0x3400 || cps[k] > 0x9FFF) { ok = false; break; }
                    }
                    if (ok) {
                        float sf = (float)(arr[nid ^ d_offset(nu)] & 0x7FFFFFFFU) / 10000.0f;
                        fprintf(out, "%u\t%u\t%.4f\n", cps[0], cps[1], sf);
                    }
                }
                if (key.size() < 4) { stv.push_back({nid, 1, (uint8_t)key.size()}); break; }
                else key.pop_back();
            }
        }
    }
    fclose(out);
    munmap((void*)base, st.st_size);
    close(fd);
    return 0;
}
"""


def _read_gram2_python(gram_path: str):
    """Pure-Python fallback depth-4 DFS over a Rime::Grammar/ double-array trie."""
    gram2 = {}
    with open(gram_path, "rb") as f:
        mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        try:
            if mm[:14] != b"Rime::Grammar/":
                raise RuntimeError(f"Unsupported grammar header in {gram_path}")
            sz, off = struct.unpack_from("<Ii", mm, 36)
            arr_off = 40 + off
            arr = memoryview(mm)[arr_off : arr_off + sz * 4].cast("I")

            def walk(nid, step, cp0):
                u = arr[nid]
                bx = nid ^ ((u >> 10) << ((u & 512) >> 6))
                for b0 in range(0x80, 0xE2):
                    if b0 == 0xE0:
                        continue
                    id1 = bx ^ b0
                    if id1 >= sz:
                        continue
                    u1 = arr[id1]
                    if (u1 & 0x800000FF) != b0:
                        continue
                    bx1 = id1 ^ ((u1 >> 10) << ((u1 & 512) >> 6))
                    b1_range = range(0x80, 0xE0) if b0 == 0xE1 else range(256)
                    for b1 in b1_range:
                        id2 = bx1 ^ b1
                        if id2 >= sz:
                            continue
                        u2 = arr[id2]
                        if (u2 & 0x800000FF) != b1:
                            continue
                        cp = ((b1 - 0x40) << 8) if b0 == 0xE1 else (((b0 - 0x40) << 8) | b1)
                        if not (0x3400 <= cp <= 0x9FFF):
                            continue
                        if step == 0:
                            walk(id2, 1, cp)
                        elif (u2 >> 8) & 1:
                            lid = id2 ^ ((u2 >> 10) << ((u2 & 512) >> 6))
                            fv = (arr[lid] & 0x7FFFFFFF) / 10000.0
                            if fv <= 11.60:
                                gram2[chr(cp0) + chr(cp)] = fv

            walk(0, 0, 0)
        finally:
            mm.close()
    return gram2


def load_gram2(gram_path: str, gram2_tsv: str = None):
    """Load 2-gram log-counts (filtered fv <= 11.60 to exclude outlier noise like '的你 = 18.29')."""
    gram2 = {}
    tsv_path = gram2_tsv
    tmp_dir = None
    if tsv_path is None:
        if not gram_path or not os.path.exists(gram_path):
            sys.exit(f"Missing Wanxiang grammar at {gram_path}")
        clangxx = shutil.which("clang++") or shutil.which("c++")
        if clangxx:
            tmp_dir = tempfile.mkdtemp(prefix="mosto_gram2_")
            cpp = os.path.join(tmp_dir, "dump_gram2.cpp")
            exe = os.path.join(tmp_dir, "dump_gram2")
            tsv_path = os.path.join(tmp_dir, "wx_gram2.tsv")
            with open(cpp, "w", encoding="utf-8") as f:
                f.write(_DUMP_GRAM2_CPP)
            subprocess.check_call([clangxx, "-O3", "-std=c++17", cpp, "-o", exe])
            subprocess.check_call([exe, gram_path, tsv_path])
        else:
            return _read_gram2_python(gram_path)

    try:
        with open(tsv_path, encoding="utf-8") as f:
            for ln in f:
                a, b, v = ln.split("\t")
                fv = float(v)
                if fv <= 11.60:
                    gram2[chr(int(a)) + chr(int(b))] = fv
    finally:
        if tmp_dir:
            shutil.rmtree(tmp_dir, ignore_errors=True)
    return gram2


def build_wanxiang_scores(wanxiang_dir: str, gram_path: str, demote_path: str, gram2_tsv: str = None, zi_out: str = None):
    wx_zi = read_wanxiang_counts([os.path.join(wanxiang_dir, "zi.dict.yaml")])
    wx_jichu = read_wanxiang_counts([
        os.path.join(wanxiang_dir, "jichu.dict.yaml"),
        os.path.join(wanxiang_dir, "duoyin.dict.yaml"),
    ])
    wx_diming = read_wanxiang_counts([os.path.join(wanxiang_dir, "diming.dict.yaml")])
    wx_multi = dict(wx_jichu)
    for k, c in wx_diming.items():
        if k not in wx_multi or c > wx_multi[k]:
            wx_multi[k] = c

    if zi_out:
        max_zi = {}
        for (t, syls), c in wx_zi.items():
            if len(t) == 1 and 0x3400 <= ord(t) <= 0x9FFF and c > 0:
                max_zi[t] = max(max_zi.get(t, 0), c)
        os.makedirs(os.path.dirname(os.path.abspath(zi_out)), exist_ok=True)
        with open(zi_out, "w", encoding="utf-8") as fz:
            for ch, c in sorted(max_zi.items()):
                fz.write(f"{ord(ch)}\t{math.log(c + 1):.4f}\n")

    gram2 = load_gram2(gram_path, gram2_tsv)

    demote = set()
    if demote_path and os.path.exists(demote_path):
        with open(demote_path, encoding="utf-8") as f:
            for ln in f:
                if not ln.startswith("#"):
                    demote.update(ln.split())

    w2_counts = {}
    char_syl_in_words = defaultdict(int)
    for (t, syls), c in wx_jichu.items():
        if len(t) == 2 and len(syls) == 2 and c > 0:
            w2_counts[t] = max(w2_counts.get(t, 0), c)
        if len(t) >= 2 and len(t) == len(syls) and c > 0:
            for ch, sy in zip(t, syls):
                char_syl_in_words[(ch, sy)] += c

    by_len = defaultdict(list)
    skipped = 0
    for (t, syls), c in wx_multi.items():
        L = len(t)
        if L < 2 or L > 8 or L != len(syls) or c <= 0:
            skipped += 1
            continue
        if not all(0x3400 <= ord(ch) <= 0x9FFF for ch in t):
            skipped += 1
            continue
        if any(s not in CANONICAL_SYLLABLES or code_for(s) is None for s in syls):
            skipped += 1
            continue
        # Drop low-count colloquial zhei/nei variants so zhe/na lead reliably.
        if c < 2000 and ("zhei" in syls or "nei" in syls):
            continue
        by_len[L].append((c, t, syls))

    primary_syl2 = {}
    for c, t, syls in by_len[2]:
        if c > primary_syl2.get(t, (-1, None))[0]:
            primary_syl2[t] = (c, syls)

    FUNC_LEAD = set("的在了被把让给向从于对和与")
    PARTICLES = set("了的吗吧呢着过么啊呀地得来去上下")
    FUNC_TAIL4 = set("的了人你我他她")
    l3_clean = [
        x for x in by_len[3]
        if not (x[0] < 4000 and x[1][0] in FUNC_LEAD)
        and not (
            x[0] < 1800
            and x[1][2] not in PARTICLES
            and (w2_counts.get(x[1][:2], 0) >= 40000 or w2_counts.get(x[1][1:], 0) >= 40000)
        )
    ]
    l4_clean = [
        x for x in by_len[4]
        if not (x[0] < 2000 and (x[1][0] in FUNC_LEAD or x[1][3] in FUNC_TAIL4))
    ]

    kept_multi = {}
    used_han = set()
    for c, t, syls in by_len[2]:
        g2 = gram2.get(t, 0.0)
        is_pri = primary_syl2[t][1] == syls
        if c < 260 and not (is_pri and g2 >= 10.20):
            continue
        raw = 105.0 * math.log(c + 1) + 145.0
        if is_pri and g2 >= 10.90:
            raw = max(raw + 50.0, 95.0 * g2 - 95.0)
        elif is_pri and g2 >= 10.50:
            raw = max(raw + 25.0, 90.0 * g2 - 70.0)
        if raw < 900.0:
            raw = max(460.0, 900.0 - 2.00 * (900.0 - raw))
        else:
            raw = 900.0 + 1.25 * (raw - 900.0)
            if raw > 1120.0:
                dv = raw - 1120.0
                raw = 1120.0 + 195.0 * (1.0 - math.exp(-dv / 260.0)) + 0.02 * dv
        kept_multi[(t, syls)] = int(round(raw))
        for ch in t:
            used_han.add(ch)

    def assign_curve(items, limit, fn_hi, tail_mul):
        items = sorted(items, key=lambda x: -x[0])[:limit]
        i = 0
        n = len(items)
        while i < n:
            j = i + 1
            while j < n and items[j][0] == items[i][0]:
                j += 1
            v = fn_hi(0.5 * (i + j - 1))
            if v < 900.0:
                v = max(460.0, 900.0 - tail_mul * (900.0 - v))
            sc = int(round(v))
            for m in range(i, j):
                _, t, syls = items[m]
                kept_multi[(t, syls)] = sc
                for ch in t:
                    used_han.add(ch)
            i = j

    assign_curve(l3_clean, 130000, lambda r: 1255.0 - 94.0 * math.log(1.0 + r / 900.0) - 0.0019 * r, 1.55)
    assign_curve(l4_clean, 160000, lambda r: 1235.0 - 74.0 * math.log(1.0 + r / 480.0) - 0.0020 * r, 1.70)
    for L in (5, 6, 7, 8):
        for c, t, syls in by_len[L]:
            if c < 100:
                continue
            kept_multi[(t, syls)] = min(1180, int(round(80.0 * math.log(c + 1) + 350.0)))
            for ch in t:
                used_han.add(ch)

    single_by_char = defaultdict(list)
    for (t, syls), c in wx_zi.items():
        if len(t) != 1 or len(syls) != 1:
            continue
        if not (0x3400 <= ord(t) <= 0x9FFF) or syls[0] not in CANONICAL_SYLLABLES or code_for(syls[0]) is None:
            continue
        tot = c + 0.60 * char_syl_in_words.get((t, syls[0]), 0)
        single_by_char[t].append((syls, int(round(100.0 * math.log(tot + 1))), tot))
    for (ch, sy), wocc in char_syl_in_words.items():
        if not (0x3400 <= ord(ch) <= 0x9FFF) or sy not in CANONICAL_SYLLABLES or code_for(sy) is None:
            continue
        if not any(s == (sy,) for s, _, _ in single_by_char.get(ch, [])) and wocc >= 500:
            tot = 0.60 * wocc
            single_by_char[ch].append(((sy,), int(round(100.0 * math.log(tot + 1))), tot))

    char_rank = sorted(single_by_char.keys(), key=lambda ch: max(t for _, _, t in single_by_char[ch]), reverse=True)
    keep_chars = set(ch for ch in used_han if ch in single_by_char)
    for ch in char_rank:
        if len(keep_chars) >= 8080:
            break
        keep_chars.add(ch)
    if len(keep_chars) > 8080:
        top_chars = set(char_rank[:8080])
        kept_multi = {k: v for k, v in kept_multi.items() if all(ch in top_chars for ch in k[0])}
        keep_chars = top_chars

    scores = {}
    for ch in keep_chars:
        for syls, sc, _ in single_by_char[ch]:
            scores[(ch, syls)] = sc
    scores.update(kept_multi)

    # Guarantee 100% coverage of XiaoheScheme.allSyllables (e.g. cei/biang/rua outside BMP or top-8080).
    covered_syls = {s for (_, syls) in scores for s in syls}
    missing_syls = sorted(CANONICAL_SYLLABLES - covered_syls)
    if missing_syls:
        best_by_syl = {}
        for (t, syls), c in wx_zi.items():
            if len(t) == 1 and len(syls) == 1 and syls[0] in missing_syls:
                prev = best_by_syl.get(syls[0])
                if prev is None or c > prev[0]:
                    best_by_syl[syls[0]] = (c, t)
        for ms in missing_syls:
            if ms not in best_by_syl:
                raise RuntimeError(f"Canonical syllable missing from Wanxiang zi.dict.yaml: {ms}")
            c, t = best_by_syl[ms]
            scores[(t, (ms,))] = max(69, int(round(100.0 * math.log(c + 1))))

    for k in list(scores):
        if k[0] in demote or any(c in demote for c in k[0]):
            scores[k] = min(scores[k], -500)
    return scores, skipped


def write_lexicon(out_path, scores):
    """Write the XHLX v3 binary lexicon from (text, syllables) -> score (ln-frequency * 100)."""
    syllables = sorted({s for (_, syls) in scores for s in syls})
    assert set(syllables) == CANONICAL_SYLLABLES, (
        len(syllables),
        sorted(set(syllables) - CANONICAL_SYLLABLES),
        sorted(CANONICAL_SYLLABLES - set(syllables)),
    )
    sid = {s: i for i, s in enumerate(syllables)}

    for s in syllables:
        c = code_for(s)
        assert c and len(c) == 2 and c.isalpha(), (s, c)

    entries = []
    for (text, syls), score in scores.items():
        score = max(score, -32768)
        score = min(score, 32767)
        ids = [sid[s] for s in syls]
        second = ids[1] if len(ids) > 1 else -1
        entries.append((sid[syls[0]], (second, 0 if len(ids) <= 2 else 1, -score), text, ids, score))
    entries.sort(key=lambda e: (e[0], e[1]))

    syl_blob = []
    text_blob = bytearray()
    recs = bytearray()
    index = [[0, 0] for _ in syllables]
    for i, (first, _, text, ids, score) in enumerate(entries):
        if index[first][1] == 0 and (i == 0 or entries[i - 1][0] != first):
            index[first][0] = i
        index[first][1] = i + 1
        tb = text.encode("utf-8")
        if len(tb) > 255:
            continue
        recs += struct.pack("<IIhBB", len(text_blob), len(syl_blob), score, len(tb), len(ids))
        text_blob += tb
        syl_blob.extend(ids)

    with open(out_path, "wb") as f:
        f.write(b"XHLX")
        f.write(struct.pack("<IIIII", 3, len(syllables), len(entries), len(syl_blob), len(text_blob)))
        for s in syllables:
            f.write(s.encode("ascii").ljust(8, b"\0"))
        for a, b in index:
            f.write(struct.pack("<II", a, b))
        f.write(recs)
        f.write(struct.pack("<%dH" % len(syl_blob), *syl_blob))
        f.write(text_blob)
        table = []
        starts = []
        for first, (a, b) in enumerate(index):
            starts.append((len(table), 0))
            i = a
            while i < b and len(entries[i][3]) == 1:
                i += 1
            while i < b:
                second = entries[i][3][1]
                pairs_start = i
                while i < b and entries[i][3][1] == second and len(entries[i][3]) == 2:
                    i += 1
                longer_start = i
                while i < b and entries[i][3][1] == second:
                    i += 1
                table.append((second, pairs_start, longer_start, i))
            starts[-1] = (starts[-1][0], len(table) - starts[-1][0])
        for st, n in starts:
            f.write(struct.pack("<II", st, n))
        for second, a2, b2, c2 in table:
            f.write(struct.pack("<HHIII", second, 0, a2, b2, c2))
        f.write(struct.pack("<I", len(table)))
        f.write(b"PAIR")

    print(f"syllables={len(syllables)} entries={len(entries)} sylBlob={len(syl_blob)} textBlob={len(text_blob)}")
    with open(out_path + ".codes.txt", "w", encoding="utf-8") as f:
        for s in syllables:
            f.write(f"{s}\t{code_for(s)}\n")


def main():
    ap = argparse.ArgumentParser(description="Build pure CC-BY-4.0 Wanxiang XHLX v3 lexicon.bin")
    ap.add_argument("--wanxiang-dir", default="/tmp/wanxiang-dicts", help="Directory with zi/jichu/duoyin/diming.dict.yaml")
    ap.add_argument("--gram", default="/tmp/wanxiang-lts-zh-hans.gram", help="Wanxiang .gram path for 2-gram corroboration")
    ap.add_argument("--gram2-tsv", default=None, help="Optional pre-dumped 2-gram TSV (cp1\\tcp2\\tlog_val)")
    ap.add_argument("--demote", default=os.path.join(ROOT, "Tools/data/demote.txt"), help="Demoted characters/words list")
    ap.add_argument("--zi-out", default=None, help="Optional TSV path to export standalone char log-counts for distill_grammar.py")
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "Keyboard/Resources/lexicon.bin"), help="Output lexicon.bin path")
    args = ap.parse_args()

    scores, skipped = build_wanxiang_scores(
        args.wanxiang_dir, args.gram, args.demote, gram2_tsv=args.gram2_tsv, zi_out=args.zi_out
    )
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    tmp_out = args.out + ".tmp"
    write_lexicon(tmp_out, scores)
    os.replace(tmp_out, args.out)
    if os.path.exists(tmp_out + ".codes.txt"):
        os.replace(tmp_out + ".codes.txt", args.out + ".codes.txt")
    print(f"skipped={skipped}")


if __name__ == "__main__":
    main()
