// Builds the R100 dual-section Rime::Grammar/1.0 language model cleanly offline:
//   Section 1: Wanxiang teacher + Octagram corroborated 2..4-grams for Viterbi sentence decoding.
//   Section 2: Pruned Octagram sub-trie appended directly after Section 1 for natural continuations.
// Copyright notes: darts-clone header is BSD-2-Clause; Octagram is LGPL-3.0; Wanxiang is CC-BY-4.0.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <string>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "darts.h"

namespace {

constexpr size_t kMaxBundleGrammarBytes = 50855936ULL; // 48.50 MB hard ceiling

struct MMapGram {
    int fd = -1;
    size_t fsize = 0;
    const uint8_t* base = nullptr;
    const uint32_t* array = nullptr;
    uint32_t size = 0;
    const uint32_t* pred_array = nullptr;
    uint32_t pred_size = 0;

    bool open_file(const char* path) {
        fd = ::open(path, O_RDONLY);
        if (fd < 0) return false;
        struct stat st{};
        if (::fstat(fd, &st) != 0) return false;
        fsize = static_cast<size_t>(st.st_size);
        void* p = ::mmap(nullptr, fsize, PROT_READ, MAP_PRIVATE, fd, 0);
        if (p == MAP_FAILED) return false;
        base = reinterpret_cast<const uint8_t*>(p);
        if (fsize < 64) return false;
        int32_t off = 0;
        std::memcpy(&size, base + 36, 4);
        std::memcpy(&off, base + 40, 4);
        if (std::strncmp(reinterpret_cast<const char*>(base), "Rime::Grammar/", 14) != 0) return false;
        size_t sec1_end = 40ULL + static_cast<size_t>(off) + static_cast<size_t>(size) * 4ULL;
        if (sec1_end > fsize) return false;
        array = reinterpret_cast<const uint32_t*>(base + 40 + off);

        pred_array = array;
        pred_size = size;
        if (sec1_end + 44 <= fsize &&
            std::strncmp(reinterpret_cast<const char*>(base + sec1_end), "Rime::Grammar/", 14) == 0) {
            uint32_t psize = 0;
            int32_t poff = 0;
            std::memcpy(&psize, base + sec1_end + 36, 4);
            std::memcpy(&poff, base + sec1_end + 40, 4);
            size_t p_arr_off = sec1_end + 40ULL + static_cast<size_t>(poff);
            if (poff >= 4 && (p_arr_off % 4) == 0 && p_arr_off + static_cast<size_t>(psize) * 4ULL <= fsize) {
                pred_array = reinterpret_cast<const uint32_t*>(base + p_arr_off);
                pred_size = psize;
            }
        }
        return true;
    }

    ~MMapGram() {
        if (base && base != MAP_FAILED) ::munmap(const_cast<uint8_t*>(base), fsize);
        if (fd >= 0) ::close(fd);
    }

    static inline uint32_t offset(uint32_t u) { return (u >> 10) << ((u & (1U << 9)) >> 6); }
    static inline uint32_t label(uint32_t u) { return u & ((1U << 31) | 0xFFU); }
    static inline bool has_leaf(uint32_t u) { return ((u >> 8) & 1U) != 0; }

    static bool lookup_in(const uint32_t* arr, uint32_t sz, const uint8_t* key, size_t len, int32_t& out_val) {
        uint32_t id = 0;
        uint32_t u = arr[0];
        for (size_t i = 0; i < len; ++i) {
            uint32_t c = key[i];
            id ^= offset(u) ^ c;
            if (id >= sz) return false;
            u = arr[id];
            if (label(u) != c) return false;
        }
        if (!has_leaf(u)) return false;
        uint32_t lid = id ^ offset(u);
        if (lid >= sz) return false;
        out_val = static_cast<int32_t>(arr[lid] & 0x7FFFFFFFU);
        return true;
    }

    bool lookup(const uint8_t* key, size_t len, int32_t& out_val) const {
        return lookup_in(array, size, key, len, out_val);
    }

    bool lookup_pred(const uint8_t* key, size_t len, int32_t& out_val) const {
        return lookup_in(pred_array, pred_size, key, len, out_val);
    }
};

template <typename Fn>
static void dfs_grammar(const MMapGram& g, Fn&& cb) {
    struct Frame { uint32_t id; uint16_t next_c; uint8_t key_len; };
    std::vector<uint8_t> key;
    key.reserve(64);
    std::vector<Frame> st;
    st.reserve(64);
    st.push_back({0, 1, 0});
    while (!st.empty()) {
        Frame& f = st.back();
        if (f.next_c > 255) {
            st.pop_back();
            if (!st.empty()) key.resize(st.back().key_len);
            continue;
        }
        uint32_t id = f.id;
        uint32_t u = g.array[id];
        uint32_t base_xor = id ^ MMapGram::offset(u);
        while (f.next_c <= 255) {
            uint32_t c = f.next_c++;
            uint32_t nid = base_xor ^ c;
            if (nid < g.size && MMapGram::label(g.array[nid]) == c) {
                key.push_back(static_cast<uint8_t>(c));
                uint32_t nu = g.array[nid];
                if (MMapGram::has_leaf(nu)) {
                    uint32_t lid = nid ^ MMapGram::offset(nu);
                    if (lid < g.size) {
                        int32_t val = static_cast<int32_t>(g.array[lid] & 0x7FFFFFFFU);
                        cb(key, val);
                    }
                }
                if (key.size() < 32) {
                    st.push_back({nid, 1, static_cast<uint8_t>(key.size())});
                    break;
                } else {
                    key.pop_back();
                }
            }
        }
    }
}

static inline bool decode_rime_to_han4(const std::vector<uint8_t>& enc, uint16_t cps[4], int& out_len,
                                       const std::vector<uint8_t>& is_lex_han) {
    size_t i = 0;
    int len = 0;
    while (i < enc.size()) {
        if (len >= 4) return false;
        uint8_t b0 = enc[i];
        uint32_t cp = 0;
        if ((b0 & 0x80) == 0 || b0 == 0xE0) {
            return false;
        } else if (b0 == 0xE1) {
            if (i + 1 >= enc.size()) return false;
            cp = static_cast<uint32_t>(enc[i + 1] - 0x40) << 8;
            i += 2;
        } else if ((b0 & 0xF0) == 0xE0) {
            size_t n = b0 & 0x0F;
            if (i + n >= enc.size()) return false;
            for (size_t k = 1; k <= n; ++k) cp = (cp << 7) | (enc[i + k] & 0x7F);
            i += 1 + n;
        } else {
            if (i + 1 >= enc.size()) return false;
            cp = (static_cast<uint32_t>(b0 - 0x40) << 8) | enc[i + 1];
            i += 2;
        }
        if (cp < 0x3400 || cp > 0x9FFF || !is_lex_han[cp]) return false;
        cps[len++] = static_cast<uint16_t>(cp);
    }
    out_len = len;
    return len >= 2 && len <= 4;
}

static inline uint64_t pack4(const uint16_t cps[4], int len) {
    uint64_t p = 0;
    for (int i = 0; i < len; ++i) p |= static_cast<uint64_t>(cps[i]) << (16 * i);
    return p;
}

static inline int unpack4(uint64_t p, uint16_t cps[4]) {
    int len = 0;
    for (int i = 0; i < 4; ++i) {
        uint16_t c = static_cast<uint16_t>((p >> (16 * i)) & 0xFFFFU);
        if (c == 0) break;
        cps[len++] = c;
    }
    return len;
}

static inline void encode_rime_cp(uint32_t cp, std::vector<uint8_t>& out) {
    if (cp < 0x80) {
        out.push_back(cp == 0 ? 0xE0 : static_cast<uint8_t>(cp));
    } else if (cp >= 0x4000 && cp < 0xA000) {
        if ((cp & 0xFF) == 0) {
            out.push_back(0xE1);
            out.push_back(static_cast<uint8_t>((cp >> 8) + 0x40));
        } else {
            out.push_back(static_cast<uint8_t>((cp >> 8) + 0x40));
            out.push_back(static_cast<uint8_t>(cp & 0xFF));
        }
    } else {
        uint32_t u = cp;
        int bits = 32;
        while (bits > 0 && (u & 0xFE000000U) == 0) { bits -= 7; u <<= 7; }
        int n = (bits + 6) / 7;
        out.push_back(static_cast<uint8_t>(0xE0 | n));
        while (n > 0) {
            n -= 1;
            out.push_back(static_cast<uint8_t>(((u >> 25) & 0x7F) | 0x80));
            u <<= 7;
        }
    }
}

struct LexTables {
    std::vector<uint8_t> is_lex_han;
    std::vector<float> char_score;
    std::unordered_map<uint32_t, float> word2;
    std::unordered_map<uint64_t, float> word3;
    std::unordered_map<uint64_t, float> word4;

    bool load(const char* path) {
        is_lex_han.assign(0x10000, 0);
        char_score.assign(0x10000, 0.0f);
        int fd = ::open(path, O_RDONLY);
        if (fd < 0) return false;
        struct stat st{};
        if (::fstat(fd, &st) != 0) { ::close(fd); return false; }
        size_t sz = st.st_size;
        const uint8_t* b = reinterpret_cast<const uint8_t*>(::mmap(nullptr, sz, PROT_READ, MAP_PRIVATE, fd, 0));
        if (b == MAP_FAILED) { ::close(fd); return false; }

        uint32_t syl_count = 0, entry_count = 0, syl_blob = 0;
        std::memcpy(&syl_count, b + 8, 4);
        std::memcpy(&entry_count, b + 12, 4);
        std::memcpy(&syl_blob, b + 16, 4);
        size_t entries_off = 24 + syl_count * 16ULL;
        size_t syl_blob_off = entries_off + entry_count * 12ULL;
        size_t text_off = syl_blob_off + syl_blob * 2ULL;

        word2.reserve(131072);
        word3.reserve(163840);
        word4.reserve(200000);

        for (uint32_t i = 0; i < entry_count; ++i) {
            const uint8_t* e = b + entries_off + i * 12ULL;
            uint32_t toff = 0;
            int16_t raw_sc = 0;
            std::memcpy(&toff, e, 4);
            std::memcpy(&raw_sc, e + 8, 2);
            uint8_t tlen = e[10];
            float sc = raw_sc / 100.0f;

            const uint8_t* s = b + text_off + toff;
            uint16_t cps[8];
            int n = 0;
            bool ok = true;
            size_t p = 0;
            while (p < tlen) {
                if (n >= 8) { ok = false; break; }
                uint32_t cp = 0;
                uint8_t b0 = s[p];
                if (b0 < 0x80) { cp = b0; p += 1; }
                else if ((b0 & 0xE0) == 0xC0 && p + 1 < tlen) { cp = ((b0 & 0x1F) << 6) | (s[p+1] & 0x3F); p += 2; }
                else if ((b0 & 0xF0) == 0xE0 && p + 2 < tlen) { cp = ((b0 & 0x0F) << 12) | ((s[p+1] & 0x3F) << 6) | (s[p+2] & 0x3F); p += 3; }
                else { ok = false; break; }
                if (cp >= 0x3400 && cp <= 0x9FFF) cps[n++] = static_cast<uint16_t>(cp);
                else { ok = false; break; }
            }
            if (!ok || n == 0) continue;
            for (int k = 0; k < n; ++k) is_lex_han[cps[k]] = 1;
            if (n == 1) {
                if (sc > char_score[cps[0]]) char_score[cps[0]] = sc;
            } else if (n == 2) {
                uint32_t k2 = (static_cast<uint32_t>(cps[0]) << 16) | cps[1];
                auto it = word2.find(k2);
                if (it == word2.end() || sc > it->second) word2[k2] = sc;
            } else if (n == 3) {
                uint64_t k3 = pack4(cps, 3);
                auto it = word3.find(k3);
                if (it == word3.end() || sc > it->second) word3[k3] = sc;
            } else if (n == 4) {
                uint64_t k4 = pack4(cps, 4);
                auto it = word4.find(k4);
                if (it == word4.end() || sc > it->second) word4[k4] = sc;
            }
        }
        ::munmap(const_cast<uint8_t*>(b), sz);
        ::close(fd);
        return true;
    }

    inline float seg_score(const uint16_t* cps, int len) const {
        constexpr float word_pen = 6.0f;
        float dp[5] = {0.0f, -1e9f, -1e9f, -1e9f, -1e9f};
        for (int i = 1; i <= len; ++i) {
            float best = dp[i - 1] + char_score[cps[i - 1]] - word_pen;
            if (i >= 2) {
                uint32_t k2 = (static_cast<uint32_t>(cps[i - 2]) << 16) | cps[i - 1];
                auto it = word2.find(k2);
                if (it != word2.end()) best = std::max(best, dp[i - 2] + it->second - word_pen);
            }
            if (i >= 3) {
                uint64_t k3 = pack4(cps + (i - 3), 3);
                auto it = word3.find(k3);
                if (it != word3.end()) best = std::max(best, dp[i - 3] + it->second - word_pen);
            }
            if (i >= 4) {
                uint64_t k4 = pack4(cps + (i - 4), 4);
                auto it = word4.find(k4);
                if (it != word4.end()) best = std::max(best, dp[i - 4] + it->second - word_pen);
            }
            dp[i] = best;
        }
        return dp[len] / static_cast<float>(len);
    }

    inline bool has_word2(uint16_t a, uint16_t b) const {
        return word2.find((static_cast<uint32_t>(a) << 16) | b) != word2.end();
    }
};

struct Cand {
    uint64_t packed;
    int32_t val;
    float rank;
};

struct BuiltSection {
    std::vector<const char*> ptrs;
    std::vector<std::size_t> lens;
    std::vector<int> vals;
    std::vector<uint8_t> arena;
    size_t by_char[5]{};
    Darts::DoubleArray da;
};

static bool build_section(const std::vector<std::pair<uint64_t, int32_t>>& items, BuiltSection& sec) {
    sec.arena.clear();
    sec.arena.reserve(items.size() * 7ULL);
    struct Rec { uint32_t off; uint8_t len; uint8_t clen; int32_t val; };
    std::vector<Rec> recs;
    recs.reserve(items.size());

    std::vector<uint8_t> enc;
    enc.reserve(8);
    for (const auto& kv : items) {
        uint16_t cps[4]{};
        int clen = unpack4(kv.first, cps);
        enc.clear();
        for (int i = 0; i < clen; ++i) encode_rime_cp(cps[i], enc);
        uint32_t off = static_cast<uint32_t>(sec.arena.size());
        sec.arena.insert(sec.arena.end(), enc.begin(), enc.end());
        recs.push_back({off, static_cast<uint8_t>(enc.size()), static_cast<uint8_t>(clen), std::max(0, kv.second)});
    }

    std::sort(recs.begin(), recs.end(), [&](const Rec& a, const Rec& b) {
        size_t ml = std::min(a.len, b.len);
        int cmp = std::memcmp(sec.arena.data() + a.off, sec.arena.data() + b.off, ml);
        if (cmp != 0) return cmp < 0;
        if (a.len != b.len) return a.len < b.len;
        return a.val > b.val;
    });

    sec.ptrs.clear();
    sec.lens.clear();
    sec.vals.clear();
    sec.ptrs.reserve(recs.size());
    sec.lens.reserve(recs.size());
    sec.vals.reserve(recs.size());
    std::fill(std::begin(sec.by_char), std::end(sec.by_char), 0);

    const uint8_t* prev_ptr = nullptr;
    size_t prev_len = 0;
    for (const auto& r : recs) {
        const uint8_t* cur = sec.arena.data() + r.off;
        if (prev_ptr && r.len == prev_len && std::memcmp(cur, prev_ptr, r.len) == 0) continue;
        prev_ptr = cur;
        prev_len = r.len;
        sec.ptrs.push_back(reinterpret_cast<const char*>(cur));
        sec.lens.push_back(r.len);
        sec.vals.push_back(r.val);
        if (r.clen >= 2 && r.clen <= 4) sec.by_char[r.clen]++;
    }

    int rc = sec.da.build(sec.ptrs.size(), sec.ptrs.data(), sec.lens.data(), sec.vals.data());
    return rc == 0;
}

static void write_section(FILE* f, const BuiltSection& sec) {
    char fmt[32]{};
    std::snprintf(fmt, sizeof(fmt), "Rime::Grammar/1.0");
    uint32_t checksum = 0;
    uint32_t arr_sz = static_cast<uint32_t>(sec.da.size());
    int32_t off_val = 4;
    std::fwrite(fmt, 1, 32, f);
    std::fwrite(&checksum, 4, 1, f);
    std::fwrite(&arr_sz, 4, 1, f);
    std::fwrite(&off_val, 4, 1, f);
    std::fwrite(sec.da.array(), 4, arr_sz, f);
}

static std::vector<std::pair<uint64_t, int32_t>> build_prediction_items(
    const MMapGram& stu, const LexTables& lex,
    size_t pred_max3_1ch, size_t pred_max3_2ch, size_t pred_max4_1ch, size_t pred_max4_2ch,
    double pred_lambda) {

    // Soft rank-penalized selection balancing prefix breadth (rank 0..k) and strong multi-slot continuations.
    struct PrefixItem { uint64_t packed; int32_t val; uint16_t rank; };
    std::unordered_map<uint16_t, std::vector<PrefixItem>> len2_by_p1;
    std::unordered_map<uint16_t, std::vector<PrefixItem>> len3_by_p1;
    std::unordered_map<uint32_t, std::vector<PrefixItem>> len3_by_p2;
    std::unordered_map<uint32_t, std::vector<PrefixItem>> len4_by_p2;
    std::unordered_map<uint64_t, std::vector<PrefixItem>> len4_by_p3;

    len2_by_p1.reserve(8192);
    len3_by_p1.reserve(8192);
    len3_by_p2.reserve(250000);
    len4_by_p2.reserve(250000);
    len4_by_p3.reserve(600000);

    dfs_grammar(stu, [&](const std::vector<uint8_t>& key, int32_t sv) {
        uint16_t cps[4]{};
        int len = 0;
        if (!decode_rime_to_han4(key, cps, len, lex.is_lex_han)) return;
        uint64_t p = pack4(cps, len);
        if (len == 2) {
            if (lex.char_score[cps[1]] >= 13.5f) {
                len2_by_p1[cps[0]].push_back({p, sv, 0});
            }
        } else if (len == 3) {
            if (lex.char_score[cps[2]] >= 13.5f) {
                uint32_t p2 = (static_cast<uint32_t>(cps[0]) << 16) | cps[1];
                len3_by_p2[p2].push_back({p, sv, 0});
            }
            if (lex.has_word2(cps[1], cps[2])) {
                len3_by_p1[cps[0]].push_back({p, sv, 0});
            }
        } else if (len == 4) {
            if (lex.char_score[cps[3]] >= 13.5f) {
                uint64_t p3 = pack4(cps, 3);
                len4_by_p3[p3].push_back({p, sv, 0});
            }
            if (lex.has_word2(cps[2], cps[3])) {
                uint32_t p2 = (static_cast<uint32_t>(cps[0]) << 16) | cps[1];
                len4_by_p2[p2].push_back({p, sv, 0});
            }
        }
    });

    auto keep_top_ranked = [](auto& groups, size_t max_per_prefix, std::vector<PrefixItem>& out) {
        for (auto& kv : groups) {
            auto& v = kv.second;
            size_t k = std::min(max_per_prefix, v.size());
            if (v.size() > k) {
                std::partial_sort(v.begin(), v.begin() + k, v.end(),
                                  [](const PrefixItem& a, const PrefixItem& b) { return a.val > b.val; });
                v.resize(k);
            } else {
                std::sort(v.begin(), v.end(),
                          [](const PrefixItem& a, const PrefixItem& b) { return a.val > b.val; });
            }
            for (size_t r = 0; r < v.size(); ++r) {
                v[r].rank = static_cast<uint16_t>(r);
                out.push_back(v[r]);
            }
        }
    };

    auto cap_soft_ranked = [&](std::vector<PrefixItem>& v, size_t max_k) {
        if (v.size() > max_k) {
            auto pri = [&](const PrefixItem& x) -> double {
                return (x.val / 10000.0) - pred_lambda * std::log2(1.0 + static_cast<double>(x.rank));
            };
            std::nth_element(v.begin(), v.begin() + max_k, v.end(),
                             [&](const PrefixItem& a, const PrefixItem& b) { return pri(a) > pri(b); });
            v.resize(max_k);
        }
    };

    std::vector<PrefixItem> keep2, keep3_1ch, keep3_2ch, keep4_1ch, keep4_2ch_raw;
    keep_top_ranked(len2_by_p1, 24, keep2);
    keep_top_ranked(len3_by_p1, 16, keep3_1ch);
    keep_top_ranked(len3_by_p2, 12, keep3_2ch);
    cap_soft_ranked(keep3_1ch, pred_max3_1ch);
    cap_soft_ranked(keep3_2ch, pred_max3_2ch);

    // Track kept len=3 prefixes so 2-char len=4 continuations never expose orphan v1==nil internal nodes.
    std::unordered_set<uint64_t> kept_p3;
    kept_p3.reserve(keep3_1ch.size() + keep3_2ch.size());
    for (const auto& x : keep3_1ch) kept_p3.insert(x.packed);
    for (const auto& x : keep3_2ch) kept_p3.insert(x.packed);

    keep_top_ranked(len4_by_p3, 8, keep4_1ch);
    cap_soft_ranked(keep4_1ch, pred_max4_1ch);

    keep_top_ranked(len4_by_p2, 10, keep4_2ch_raw);
    std::vector<PrefixItem> keep4_2ch;
    keep4_2ch.reserve(keep4_2ch_raw.size());
    for (const auto& x : keep4_2ch_raw) {
        uint16_t cps[4]{};
        unpack4(x.packed, cps);
        if (kept_p3.count(pack4(cps, 3)) > 0) keep4_2ch.push_back(x);
    }
    cap_soft_ranked(keep4_2ch, pred_max4_2ch);

    // Preserve 2-char v1 scores for prefixes of kept 3-grams (c0, c1) so Grammar.continuations rank<24 holds accurately.
    std::unordered_set<uint64_t> needed_p2;
    needed_p2.reserve(keep3_1ch.size());
    std::vector<uint8_t> enc;
    enc.reserve(8);
    std::vector<std::pair<uint64_t, int32_t>> out;
    out.reserve(keep2.size() + keep3_1ch.size() + keep3_2ch.size() + keep4_1ch.size() + keep4_2ch.size() + 32768);

    for (const auto& x : keep2) out.push_back({x.packed, x.val});
    for (const auto& x : keep3_1ch) {
        uint16_t cps[4]{};
        unpack4(x.packed, cps);
        needed_p2.insert(pack4(cps, 2));
        out.push_back({x.packed, x.val});
    }
    for (uint64_t p2 : needed_p2) {
        uint16_t cps[4]{};
        unpack4(p2, cps);
        enc.clear();
        encode_rime_cp(cps[0], enc);
        encode_rime_cp(cps[1], enc);
        int32_t sv = 0;
        if (stu.lookup(enc.data(), enc.size(), sv)) out.push_back({p2, sv});
    }
    for (const auto& x : keep3_2ch) out.push_back({x.packed, x.val});
    for (const auto& x : keep4_1ch) out.push_back({x.packed, x.val});
    for (const auto& x : keep4_2ch) out.push_back({x.packed, x.val});
    return out;
}

} // namespace

int main(int argc, char** argv) {
    const char* stu_path = "/tmp/octagram-base.gram";
    const char* tea_path = "/tmp/wanxiang-lts-zh-hans.gram";
    const char* lex_path = "Keyboard/Resources/lexicon.bin";
    const char* out_path = nullptr;

    size_t K2 = 100000;
    size_t K3 = 2980000;
    size_t K4 = 2620000;
    double w_seg = 1.0;
    double w_tea = 1.5;
    double stu_boost = 3.0;
    size_t pred_max3_1ch = 80000;
    size_t pred_max3_2ch = 340000;
    size_t pred_max4_1ch = 160000;
    size_t pred_max4_2ch = 70000;
    double pred_lambda = 1.0;
    bool pred_only = false;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next_s = [&]() -> const char* { return (i + 1 < argc) ? argv[++i] : ""; };
        if (a == "--student" || a == "--stu") stu_path = next_s();
        else if (a == "--teacher" || a == "--tea") tea_path = next_s();
        else if (a == "--lexicon" || a == "--lex") lex_path = next_s();
        else if (a == "--out") out_path = next_s();
        else if (a == "--k2") K2 = std::stoull(next_s());
        else if (a == "--k3") K3 = std::stoull(next_s());
        else if (a == "--k4") K4 = std::stoull(next_s());
        else if (a == "--w-seg") w_seg = std::stod(next_s());
        else if (a == "--w-tea") w_tea = std::stod(next_s());
        else if (a == "--stu-boost") stu_boost = std::stod(next_s());
        else if (a == "--pred-max3-1ch") pred_max3_1ch = std::stoull(next_s());
        else if (a == "--pred-max3-2ch") pred_max3_2ch = std::stoull(next_s());
        else if (a == "--pred-max4-1ch") pred_max4_1ch = std::stoull(next_s());
        else if (a == "--pred-max4-2ch") pred_max4_2ch = std::stoull(next_s());
        else if (a == "--pred-lambda") pred_lambda = std::stod(next_s());
        else if (a == "--pred-only") pred_only = true;
        else {
            std::fprintf(stderr, "Unknown flag: %s\n", a.c_str());
            return 1;
        }
    }
    if (!out_path) {
        std::fprintf(stderr, "Usage: distill_grammar --out <output.gram> [--student ... --teacher ... --lexicon ...]\n");
        return 1;
    }

    MMapGram stu;
    if (!stu.open_file(stu_path)) {
        std::fprintf(stderr, "Failed to open student=%s\n", stu_path);
        return 1;
    }
    LexTables lex;
    if (!lex.load(lex_path)) {
        std::fprintf(stderr, "Failed to load lexicon=%s\n", lex_path);
        return 1;
    }

    if (pred_only) {
        auto sec2_items = build_prediction_items(stu, lex, pred_max3_1ch, pred_max3_2ch, pred_max4_1ch, pred_max4_2ch, pred_lambda);
        BuiltSection sec2;
        if (!build_section(sec2_items, sec2)) {
            std::fprintf(stderr, "Section 2 Darts build failed\n");
            return 1;
        }
        size_t sec2_bytes = 44ULL + sec2.da.size() * 4ULL;
        FILE* f = std::fopen(out_path, "wb");
        if (!f) { std::perror("fopen out"); return 1; }
        write_section(f, sec2);
        std::fclose(f);
        std::printf("PRED_ONLY %s: size=%.2f MB (%zu bytes) keys=%zu (len2=%zu len3=%zu len4=%zu)\n",
                    out_path, sec2_bytes / 1048576.0, sec2_bytes,
                    sec2.ptrs.size(), sec2.by_char[2], sec2.by_char[3], sec2.by_char[4]);
        return 0;
    }

    MMapGram tea;
    if (!tea.open_file(tea_path)) {
        std::fprintf(stderr, "Failed to open teacher=%s\n", tea_path);
        return 1;
    }

    // Section 1: Select distilled Wanxiang + Octagram-corroborated 2..4-grams for Viterbi decoding.
    constexpr double med_len[5] = {0.0, 0.0, 1.6168, 5.6655, 9.7806};
    std::vector<Cand> c2, c3, c4;
    c2.reserve(80000);
    c3.reserve(4300000);
    c4.reserve(48000000);

    dfs_grammar(tea, [&](const std::vector<uint8_t>& key, int32_t val) {
        uint16_t cps[4]{};
        int len = 0;
        if (!decode_rime_to_han4(key, cps, len, lex.is_lex_han)) return;
        int32_t sv = 0;
        bool in_stu = stu.lookup(key.data(), key.size(), sv);
        float tea_lc = val / 10000.0f;
        float seg = (w_seg != 0.0 && len >= 3) ? lex.seg_score(cps, len) : 0.0f;
        float rank = static_cast<float>(w_seg * seg + w_tea * (tea_lc - med_len[len]) + (in_stu ? stu_boost : 0.0));
        uint64_t p = pack4(cps, len);
        if (len == 2) c2.push_back({p, val, rank});
        else if (len == 3) c3.push_back({p, val, rank});
        else if (len == 4) c4.push_back({p, val, rank});
    });

    std::vector<std::pair<uint64_t, int32_t>> sec1_items;
    sec1_items.reserve(std::min(K2, c2.size()) + std::min(K3, c3.size()) + std::min(K4, c4.size()));
    auto pick_topk = [&](std::vector<Cand>& vec, size_t K) {
        if (K < vec.size()) {
            std::nth_element(vec.begin(), vec.begin() + K, vec.end(),
                             [](const Cand& a, const Cand& b) { return a.rank > b.rank; });
            vec.resize(K);
        }
        for (const auto& c : vec) sec1_items.push_back({c.packed, c.val});
        std::vector<Cand>().swap(vec);
    };
    pick_topk(c2, K2);
    pick_topk(c3, K3);
    pick_topk(c4, K4);

    BuiltSection sec1;
    if (!build_section(sec1_items, sec1)) {
        std::fprintf(stderr, "Section 1 Darts build failed\n");
        return 1;
    }
    std::vector<std::pair<uint64_t, int32_t>>().swap(sec1_items);

    // Section 2: Pruned Octagram sub-trie for context prediction (continuations).
    auto sec2_items = build_prediction_items(stu, lex, pred_max3_1ch, pred_max3_2ch, pred_max4_1ch, pred_max4_2ch, pred_lambda);
    BuiltSection sec2;
    if (!build_section(sec2_items, sec2)) {
        std::fprintf(stderr, "Section 2 Darts build failed\n");
        return 1;
    }
    std::vector<std::pair<uint64_t, int32_t>>().swap(sec2_items);

    size_t sec1_bytes = 44ULL + sec1.da.size() * 4ULL;
    size_t sec2_bytes = 44ULL + sec2.da.size() * 4ULL;
    size_t total_bytes = sec1_bytes + sec2_bytes;
    if (total_bytes > kMaxBundleGrammarBytes) {
        std::fprintf(stderr, "ERROR: output %.2f MB (%zu bytes) = sec1 %.2f MB + sec2 %.2f MB exceeds 48.50 MB hard cap (%zu bytes)!\n",
                     total_bytes / 1048576.0, total_bytes, sec1_bytes / 1048576.0, sec2_bytes / 1048576.0, kMaxBundleGrammarBytes);
        return 2;
    }

    FILE* f = std::fopen(out_path, "wb");
    if (!f) { std::perror("fopen out"); return 1; }
    write_section(f, sec1);
    write_section(f, sec2);
    std::fclose(f);

    // Self-verify both sections via MMapGram.
    MMapGram check;
    if (!check.open_file(out_path) || check.size != sec1.da.size() || check.pred_size != sec2.da.size()) {
        std::fprintf(stderr, "Self-verify open_file/section header failed!\n");
        return 1;
    }
    auto verify_sec = [&](const BuiltSection& s, bool is_pred) -> bool {
        size_t step = std::max<size_t>(1, s.ptrs.size() / 200);
        for (size_t i = 0; i < s.ptrs.size(); i += step) {
            int32_t got = -1;
            const uint8_t* ptr = reinterpret_cast<const uint8_t*>(s.ptrs[i]);
            bool ok = is_pred ? check.lookup_pred(ptr, s.lens[i], got) : check.lookup(ptr, s.lens[i], got);
            if (!ok || got != s.vals[i]) {
                std::fprintf(stderr, "Self-verify mismatch sec=%d idx=%zu expected=%d got=%d\n",
                             is_pred ? 2 : 1, i, s.vals[i], got);
                return false;
            }
        }
        return true;
    };
    if (!verify_sec(sec1, false) || !verify_sec(sec2, true)) return 1;

    std::printf("DISTILLED %s: total=%.2f MB (%zu bytes)\n",
                out_path, total_bytes / 1048576.0, total_bytes);
    std::printf("  section1 (decode ): %.2f MB  keys=%zu (len2=%zu len3=%zu len4=%zu)\n",
                sec1_bytes / 1048576.0, sec1.ptrs.size(), sec1.by_char[2], sec1.by_char[3], sec1.by_char[4]);
    std::printf("  section2 (predict): %.2f MB  keys=%zu (len2=%zu len3=%zu len4=%zu)\n",
                sec2_bytes / 1048576.0, sec2.ptrs.size(), sec2.by_char[2], sec2.by_char[3], sec2.by_char[4]);
    return 0;
}
