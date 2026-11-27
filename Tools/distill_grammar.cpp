// Builds the R105 dual-section Mosto::GramV2 8-bit quantized compact CSR-Trie language model offline:
//   Section 1: Pure Wanxiang (CC-BY-4.0) 2..4-grams for Viterbi sentence decoding.
//   Section 2: Pure Wanxiang (CC-BY-4.0) 2-band context continuations appended in-file for natural predictions.
// Zero third-party headers: Rime::Grammar/ double-array trie reader is self-contained below.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <unordered_map>
#include <unordered_set>
#include <vector>


namespace {

constexpr size_t kMaxBundleGrammarBytes = 50855936ULL; // 48.50 MiB hard ceiling (stays safely < 50 MiB GitHub limit)
constexpr uint32_t kMaxVocab = 8192;
constexpr uint16_t kBmpMin = 0x3400;
constexpr uint16_t kBmpMax = 0x9FFF;
constexpr size_t kBmpRange = kBmpMax - kBmpMin + 1; // 27,648 entries

struct MMapGramV1 {
    int fd = -1;
    size_t fsize = 0;
    const uint8_t* base = nullptr;
    const uint32_t* array = nullptr;
    uint32_t size = 0;

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
        return true;
    }

    ~MMapGramV1() {
        if (base && base != MAP_FAILED) ::munmap(const_cast<uint8_t*>(base), fsize);
        if (fd >= 0) ::close(fd);
    }

    static inline uint32_t offset(uint32_t u) { return (u >> 10) << ((u & (1U << 9)) >> 6); }
    static inline uint32_t label(uint32_t u) { return u & ((1U << 31) | 0xFFU); }
    static inline bool has_leaf(uint32_t u) { return ((u >> 8) & 1U) != 0; }

    bool lookup(const uint8_t* key, size_t len, int32_t& out_val) const {
        uint32_t id = 0;
        uint32_t u = array[0];
        for (size_t i = 0; i < len; ++i) {
            uint32_t c = key[i];
            id ^= offset(u) ^ c;
            if (id >= size) return false;
            u = array[id];
            if (label(u) != c) return false;
        }
        if (!has_leaf(u)) return false;
        uint32_t lid = id ^ offset(u);
        if (lid >= size) return false;
        out_val = static_cast<int32_t>(array[lid] & 0x7FFFFFFFU);
        return true;
    }
};

template <typename Fn>
static void dfs_grammar(const MMapGramV1& g, Fn&& cb) {
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
        uint32_t base_xor = id ^ MMapGramV1::offset(u);
        while (f.next_c <= 255) {
            uint32_t c = f.next_c++;
            uint32_t nid = base_xor ^ c;
            if (nid < g.size && MMapGramV1::label(g.array[nid]) == c) {
                key.push_back(static_cast<uint8_t>(c));
                uint32_t nu = g.array[nid];
                if (MMapGramV1::has_leaf(nu)) {
                    uint32_t lid = nid ^ MMapGramV1::offset(nu);
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
        if (cp < kBmpMin || cp > kBmpMax || !is_lex_han[cp]) return false;
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
    std::vector<float> zi_log;
    void load_zi_log(const char* path) {
        zi_log.assign(0x10000, 0.0f);
        FILE* f = std::fopen(path, "r");
        if (!f) return;
        unsigned cp = 0; float v = 0.0f;
        while (std::fscanf(f, "%u\t%f", &cp, &v) == 2) {
            if (cp < 0x10000) zi_log[cp] = v;
        }
        std::fclose(f);
    }
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
                if (cp >= kBmpMin && cp <= kBmpMax) cps[n++] = static_cast<uint16_t>(cp);
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
        constexpr float word_pen = 22.0f;
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
    inline float word2_score(uint16_t a, uint16_t b) const {
        auto it = word2.find((static_cast<uint32_t>(a) << 16) | b);
        return it == word2.end() ? -1e9f : it->second;
    }
};

struct Cand {
    uint64_t packed;
    int32_t val;
    float rank;
};

struct alignas(8) GramV2Ovf {
    uint32_t idx;
    uint32_t deg;
};

static inline void pack_bits(std::vector<uint8_t>& buf, size_t index, int width, uint32_t val) {
    size_t bit = index * static_cast<size_t>(width);
    size_t boff = bit >> 3;
    uint32_t shift = static_cast<uint32_t>(bit & 7);
    uint64_t w = 0;
    std::memcpy(&w, buf.data() + boff, 8);
    w |= (static_cast<uint64_t>(val) << shift);
    std::memcpy(buf.data() + boff, &w, 8);
}

struct BuiltV2Section {
    std::vector<uint8_t> bytes;
    uint32_t vocab_size = 0;
    uint32_t n2 = 0;
    uint32_t n3 = 0;
    uint32_t n4 = 0;
    size_t by_char[5]{};
    // Sampled expected quantized values for self-verification
    struct Sample { uint16_t cps[4]; int len; float qval; };
    std::vector<Sample> samples;
};

static bool build_v2_section(const std::vector<std::pair<uint64_t, int32_t>>& raw_items, BuiltV2Section& sec) {
    struct Item { uint16_t c[4]; uint8_t len; float lc; };
    std::vector<Item> items;
    items.reserve(raw_items.size());

    // Canonical deduplication: sort by key ascending, max val first, keep unique.
    std::vector<std::pair<uint64_t, int32_t>> sorted = raw_items;
    std::sort(sorted.begin(), sorted.end(), [](const auto& a, const auto& b) {
        if (a.first != b.first) return a.first < b.first;
        return a.second > b.second;
    });

    std::vector<uint8_t> used_bmp(kBmpRange, 0);
    float min2 = 1e30f, max2 = -1e30f;
    float min3 = 1e30f, max3 = -1e30f;
    float min4 = 1e30f, max4 = -1e30f;

    uint64_t prev_k = 0;
    bool has_prev = false;
    for (const auto& kv : sorted) {
        if (has_prev && kv.first == prev_k) continue;
        prev_k = kv.first;
        has_prev = true;

        uint16_t cps[4]{};
        int len = unpack4(kv.first, cps);
        if (len < 2 || len > 4) continue;
        bool ok = true;
        for (int i = 0; i < len; ++i) {
            if (cps[i] < kBmpMin || cps[i] > kBmpMax) { ok = false; break; }
            used_bmp[cps[i] - kBmpMin] = 1;
        }
        if (!ok) continue;

        float lc = std::max(0, kv.second) / 10000.0f;
        items.push_back({{cps[0], cps[1], cps[2], cps[3]}, static_cast<uint8_t>(len), lc});
        sec.by_char[len]++;
        if (len == 2) { min2 = std::min(min2, lc); max2 = std::max(max2, lc); }
        else if (len == 3) { min3 = std::min(min3, lc); max3 = std::max(max3, lc); }
        else { min4 = std::min(min4, lc); max4 = std::max(max4, lc); }
    }
    std::vector<std::pair<uint64_t, int32_t>>().swap(sorted);

    if (items.empty()) return false;
    if (min2 > max2) { min2 = 0.0f; max2 = 0.0f; }
    if (min3 > max3) { min3 = 0.0f; max3 = 0.0f; }
    if (min4 > max4) { min4 = 0.0f; max4 = 0.0f; }

    float step2 = (max2 > min2) ? (max2 - min2) / 254.0f : 1.0f;
    float step3 = (max3 > min3) ? (max3 - min3) / 255.0f : 1.0f;
    float step4 = (max4 > min4) ? (max4 - min4) / 255.0f : 1.0f;

    std::vector<uint16_t> bmp_to_id(kBmpRange, 0xFFFFU);
    std::vector<uint16_t> id_to_bmp;
    id_to_bmp.reserve(8192);
    for (size_t i = 0; i < kBmpRange; ++i) {
        if (used_bmp[i]) {
            bmp_to_id[i] = static_cast<uint16_t>(id_to_bmp.size());
            id_to_bmp.push_back(static_cast<uint16_t>(kBmpMin + i));
        }
    }
    uint32_t V = static_cast<uint32_t>(id_to_bmp.size());
    if (V == 0 || V > kMaxVocab) {
        std::fprintf(stderr, "ERROR: vocabSize %u exceeds limit %u\n", V, kMaxVocab);
        return false;
    }
    sec.vocab_size = V;

    // Sort items lexically by (id0, id1, len, id2, id3) so every L1/L2 group is contiguous & sorted.
    struct EncItem {
        uint16_t id[4];
        uint8_t len;
        uint8_t q;
        float lc;
    };
    std::vector<EncItem> enc;
    enc.reserve(items.size());

    auto quant2 = [&](float v) -> uint8_t {
        if (max2 <= min2) return 1;
        long r = std::lround((static_cast<double>(v) - min2) / step2);
        return static_cast<uint8_t>(std::clamp<long>(1 + r, 1, 255));
    };
    auto quant34 = [&](float v, float mn, float mx, float st) -> uint8_t {
        if (mx <= mn) return 0;
        long r = std::lround((static_cast<double>(v) - mn) / st);
        return static_cast<uint8_t>(std::clamp<long>(r, 0, 255));
    };

    sec.samples.clear();
    size_t sample_step = std::max<size_t>(1, items.size() / 300);

    for (size_t i = 0; i < items.size(); ++i) {
        const auto& it = items[i];
        EncItem e{};
        for (int k = 0; k < it.len; ++k) e.id[k] = bmp_to_id[it.c[k] - kBmpMin];
        e.len = it.len;
        e.lc = it.lc;
        if (it.len == 2) e.q = quant2(it.lc);
        else if (it.len == 3) e.q = quant34(it.lc, min3, max3, step3);
        else e.q = quant34(it.lc, min4, max4, step4);
        enc.push_back(e);

        if (i % sample_step == 0 || i < 16) {
            float qval = (it.len == 2) ? (min2 + (e.q - 1) * step2)
                       : (it.len == 3) ? (min3 + e.q * step3)
                                       : (min4 + e.q * step4);
            sec.samples.push_back({{it.c[0], it.c[1], it.c[2], it.c[3]}, it.len, qval});
        }
    }
    std::vector<Item>().swap(items);

    std::sort(enc.begin(), enc.end(), [](const EncItem& a, const EncItem& b) {
        if (a.id[0] != b.id[0]) return a.id[0] < b.id[0];
        if (a.id[1] != b.id[1]) return a.id[1] < b.id[1];
        if (a.len != b.len) return a.len < b.len;
        if (a.id[2] != b.id[2]) return a.id[2] < b.id[2];
        return a.id[3] < b.id[3];
    });

    // Pass 1: count unique L2 nodes, n3, n4.
    uint32_t n2 = 0, n3 = 0, n4 = 0;
    for (size_t i = 0; i < enc.size();) {
        uint16_t a0 = enc[i].id[0], a1 = enc[i].id[1];
        size_t j = i;
        while (j < enc.size() && enc[j].id[0] == a0 && enc[j].id[1] == a1) {
            if (enc[j].len == 3) n3++;
            else if (enc[j].len == 4) n4++;
            j++;
        }
        n2++;
        i = j;
    }
    sec.n2 = n2;
    sec.n3 = n3;
    sec.n4 = n4;

    std::vector<uint32_t> l1_l2_start(V + 1, 0);
    std::vector<float> l1_log_mass(V, 0.0f);

    size_t l2_id13_bytes = ((static_cast<size_t>(n2) * 13ULL + 7ULL) / 8ULL) + 8ULL;
    size_t l3_id13_bytes = ((static_cast<size_t>(n3) * 13ULL + 7ULL) / 8ULL) + 8ULL;
    size_t l4_k26_bytes  = ((static_cast<size_t>(n4) * 26ULL + 7ULL) / 8ULL) + 8ULL;

    std::vector<uint8_t> l2_id13(l2_id13_bytes, 0);
    std::vector<uint8_t> l2_val(n2, 0);
    std::vector<uint8_t> l2_deg3(n2, 0);
    std::vector<uint8_t> l2_deg4(n2, 0);
    uint32_t blk_count = (n2 >> 5) + 1;
    std::vector<uint32_t> l2_blk3(blk_count, 0);
    std::vector<uint32_t> l2_blk4(blk_count, 0);
    std::vector<GramV2Ovf> l2_ovf3, l2_ovf4;

    std::vector<uint8_t> l3_id13(l3_id13_bytes, 0);
    std::vector<uint8_t> l3_val(n3, 0);
    std::vector<uint8_t> l4_k26(l4_k26_bytes, 0);
    std::vector<uint8_t> l4_val(n4, 0);

    uint32_t idx2 = 0, idx3 = 0, idx4 = 0;
    size_t p = 0;
    for (uint32_t id0 = 0; id0 < V; ++id0) {
        l1_l2_start[id0] = idx2;
        double max_l2 = -1e30;
        uint32_t row_start = idx2;
        while (p < enc.size() && enc[p].id[0] == id0) {
            uint16_t id1 = enc[p].id[1];
            if ((idx2 & 31U) == 0) {
                l2_blk3[idx2 >> 5] = idx3;
                l2_blk4[idx2 >> 5] = idx4;
            }
            pack_bits(l2_id13, idx2, 13, id1);

            uint8_t q2 = 0;
            uint32_t d3 = 0, d4 = 0;
            while (p < enc.size() && enc[p].id[0] == id0 && enc[p].id[1] == id1) {
                const auto& it = enc[p++];
                if (it.len == 2) {
                    q2 = it.q;
                    double dq = static_cast<double>(min2) + static_cast<double>(q2 - 1) * static_cast<double>(step2);
                    max_l2 = std::max(max_l2, dq);
                } else if (it.len == 3) {
                    pack_bits(l3_id13, idx3, 13, it.id[2]);
                    l3_val[idx3++] = it.q;
                    d3++;
                } else {
                    uint32_t key26 = (static_cast<uint32_t>(it.id[2]) << 13) | static_cast<uint32_t>(it.id[3]);
                    pack_bits(l4_k26, idx4, 26, key26);
                    l4_val[idx4++] = it.q;
                    d4++;
                }
            }
            l2_val[idx2] = q2;
            if (d3 < 255) l2_deg3[idx2] = static_cast<uint8_t>(d3);
            else { l2_deg3[idx2] = 255; l2_ovf3.push_back({idx2, d3}); }
            if (d4 < 255) l2_deg4[idx2] = static_cast<uint8_t>(d4);
            else { l2_deg4[idx2] = 255; l2_ovf4.push_back({idx2, d4}); }
            idx2++;
        }
        if (max_l2 > -1e29) {
            double sum = 0.0;
            for (uint32_t j = row_start; j < idx2; ++j) {
                uint8_t q = l2_val[j];
                if (q != 0) {
                    double dq = static_cast<double>(min2) + static_cast<double>(q - 1) * static_cast<double>(step2);
                    sum += std::exp(dq - max_l2);
                }
            }
            l1_log_mass[id0] = static_cast<float>(max_l2 + std::log(sum));
        }
    }
    l1_l2_start[V] = idx2;
    if ((n2 & 31U) == 0) {
        l2_blk3[n2 >> 5] = idx3;
        l2_blk4[n2 >> 5] = idx4;
    }
    std::vector<EncItem>().swap(enc);

    // Serialize all 16 sections with 8-byte alignment.
    sec.bytes.clear();
    sec.bytes.resize(144, 0);
    auto append_aligned = [&](const void* ptr, size_t len) -> uint32_t {
        while (sec.bytes.size() % 8 != 0) sec.bytes.push_back(0);
        uint32_t off = static_cast<uint32_t>(sec.bytes.size());
        if (len > 0) {
            const uint8_t* p8 = reinterpret_cast<const uint8_t*>(ptr);
            sec.bytes.insert(sec.bytes.end(), p8, p8 + len);
        }
        while (sec.bytes.size() % 8 != 0) sec.bytes.push_back(0);
        return off;
    };

    uint32_t offs[16]{};
    offs[0]  = append_aligned(bmp_to_id.data(), bmp_to_id.size() * 2);
    offs[1]  = append_aligned(id_to_bmp.data(), id_to_bmp.size() * 2);
    offs[2]  = append_aligned(l1_l2_start.data(), l1_l2_start.size() * 4);
    offs[3]  = append_aligned(l1_log_mass.data(), l1_log_mass.size() * 4);
    offs[4]  = append_aligned(l2_id13.data(), l2_id13.size());
    offs[5]  = append_aligned(l2_val.data(), l2_val.size());
    offs[6]  = append_aligned(l2_deg3.data(), l2_deg3.size());
    offs[7]  = append_aligned(l2_blk3.data(), l2_blk3.size() * 4);
    offs[8]  = append_aligned(l2_ovf3.data(), l2_ovf3.size() * sizeof(GramV2Ovf));
    offs[9]  = append_aligned(l2_deg4.data(), l2_deg4.size());
    offs[10] = append_aligned(l2_blk4.data(), l2_blk4.size() * 4);
    offs[11] = append_aligned(l2_ovf4.data(), l2_ovf4.size() * sizeof(GramV2Ovf));
    offs[12] = append_aligned(l3_id13.data(), l3_id13.size());
    offs[13] = append_aligned(l3_val.data(), l3_val.size());
    offs[14] = append_aligned(l4_k26.data(), l4_k26.size());
    offs[15] = append_aligned(l4_val.data(), l4_val.size());

    uint32_t total_bytes = static_cast<uint32_t>(sec.bytes.size());
    uint32_t version = 2;
    uint32_t ovf3_c = static_cast<uint32_t>(l2_ovf3.size());
    uint32_t ovf4_c = static_cast<uint32_t>(l2_ovf4.size());

    const char magic[16] = {'M','o','s','t','o',':',':','G','r','a','m','V','2','\0','\0','\0'};
    std::memcpy(sec.bytes.data() + 0,  magic, 16);
    std::memcpy(sec.bytes.data() + 16, &version, 4);
    std::memcpy(sec.bytes.data() + 20, &total_bytes, 4);
    std::memcpy(sec.bytes.data() + 24, &V, 4);
    std::memcpy(sec.bytes.data() + 28, &n2, 4);
    std::memcpy(sec.bytes.data() + 32, &n3, 4);
    std::memcpy(sec.bytes.data() + 36, &n4, 4);
    std::memcpy(sec.bytes.data() + 40, &ovf3_c, 4);
    std::memcpy(sec.bytes.data() + 44, &ovf4_c, 4);
    std::memcpy(sec.bytes.data() + 48, &min2, 4);
    std::memcpy(sec.bytes.data() + 52, &step2, 4);
    std::memcpy(sec.bytes.data() + 56, &min3, 4);
    std::memcpy(sec.bytes.data() + 60, &step3, 4);
    std::memcpy(sec.bytes.data() + 64, &min4, 4);
    std::memcpy(sec.bytes.data() + 68, &step4, 4);
    std::memcpy(sec.bytes.data() + 72, offs, 64);
    return true;
}

struct MMapV2Section {
    const uint8_t* p = nullptr;
    uint32_t section_bytes = 0, vocab = 0, n2 = 0, n3 = 0, n4 = 0, ovf3 = 0, ovf4 = 0;
    float min2 = 0, step2 = 1, min3 = 0, step3 = 1, min4 = 0, step4 = 1;
    const uint16_t* bmp_to_id = nullptr;
    const uint32_t* l1_l2_start = nullptr;
    const uint8_t* l2_id13 = nullptr;
    const uint8_t* l2_val = nullptr;
    const uint8_t* l2_deg3 = nullptr;
    const uint32_t* l2_blk3 = nullptr;
    const GramV2Ovf* l2_ovf3 = nullptr;
    const uint8_t* l2_deg4 = nullptr;
    const uint32_t* l2_blk4 = nullptr;
    const GramV2Ovf* l2_ovf4 = nullptr;
    const uint8_t* l3_id13 = nullptr;
    const uint8_t* l3_val = nullptr;
    const uint8_t* l4_k26 = nullptr;
    const uint8_t* l4_val = nullptr;

    bool parse(const uint8_t* base, size_t off, size_t fsize) {
        if (off + 144 > fsize) return false;
        const uint8_t* s = base + off;
        if (std::memcmp(s, "Mosto::GramV2\0", 14) != 0) return false;
        uint32_t ver = 0;
        std::memcpy(&ver, s + 16, 4);
        std::memcpy(&section_bytes, s + 20, 4);
        if (ver != 2 || section_bytes < 144 || (section_bytes % 8) != 0 || off + section_bytes > fsize) return false;
        std::memcpy(&vocab, s + 24, 4);
        std::memcpy(&n2, s + 28, 4);
        std::memcpy(&n3, s + 32, 4);
        std::memcpy(&n4, s + 36, 4);
        std::memcpy(&ovf3, s + 40, 4);
        std::memcpy(&ovf4, s + 44, 4);
        std::memcpy(&min2, s + 48, 4);
        std::memcpy(&step2, s + 52, 4);
        std::memcpy(&min3, s + 56, 4);
        std::memcpy(&step3, s + 60, 4);
        std::memcpy(&min4, s + 64, 4);
        std::memcpy(&step4, s + 68, 4);
        uint32_t o[16]{};
        std::memcpy(o, s + 72, 64);
        for (int i = 0; i < 16; ++i) {
            if (o[i] < 144 || o[i] > section_bytes || (o[i] % 8) != 0) return false;
        }
        p = s;
        bmp_to_id   = reinterpret_cast<const uint16_t*>(s + o[0]);
        l1_l2_start = reinterpret_cast<const uint32_t*>(s + o[2]);
        l2_id13     = s + o[4];
        l2_val      = s + o[5];
        l2_deg3     = s + o[6];
        l2_blk3     = reinterpret_cast<const uint32_t*>(s + o[7]);
        l2_ovf3     = reinterpret_cast<const GramV2Ovf*>(s + o[8]);
        l2_deg4     = s + o[9];
        l2_blk4     = reinterpret_cast<const uint32_t*>(s + o[10]);
        l2_ovf4     = reinterpret_cast<const GramV2Ovf*>(s + o[11]);
        l3_id13     = s + o[12];
        l3_val      = s + o[13];
        l4_k26      = s + o[14];
        l4_val      = s + o[15];
        return vocab > 0 && vocab <= kMaxVocab;
    }

    static inline uint16_t read13(const uint8_t* arr, uint32_t idx) {
        size_t bit = static_cast<size_t>(idx) * 13ULL;
        uint32_t w = 0;
        std::memcpy(&w, arr + (bit >> 3), 4);
        return static_cast<uint16_t>((w >> (bit & 7)) & 0x1FFFU);
    }

    static inline uint32_t read26(const uint8_t* arr, uint32_t idx) {
        size_t bit = static_cast<size_t>(idx) * 26ULL;
        uint64_t w = 0;
        std::memcpy(&w, arr + (bit >> 3), 8);
        return static_cast<uint32_t>((w >> (bit & 7)) & 0x03FFFFFFU);
    }

    static inline uint32_t deg_of(uint32_t idx, const uint8_t* deg, const GramV2Ovf* ovf, uint32_t ovf_n) {
        uint8_t d = deg[idx];
        if (d < 255) return d;
        uint32_t lo = 0, hi = ovf_n;
        while (lo < hi) {
            uint32_t mid = lo + (hi - lo) / 2;
            if (ovf[mid].idx < idx) lo = mid + 1;
            else hi = mid;
        }
        return (lo < ovf_n && ovf[lo].idx == idx) ? ovf[lo].deg : 0;
    }

    static inline void child_range(uint32_t l2_idx, const uint8_t* deg, const uint32_t* blk,
                                   const GramV2Ovf* ovf, uint32_t ovf_n, uint32_t& out_s, uint32_t& out_e) {
        uint32_t b = l2_idx >> 5;
        uint32_t s = blk[b];
        for (uint32_t k = b << 5; k < l2_idx; ++k) s += deg_of(k, deg, ovf, ovf_n);
        out_s = s;
        out_e = s + deg_of(l2_idx, deg, ovf, ovf_n);
    }

    bool lookup_cps(const uint16_t cps[4], int len, float& out_lc) const {
        uint16_t ids[4]{};
        for (int i = 0; i < len; ++i) {
            if (cps[i] < kBmpMin || cps[i] > kBmpMax) return false;
            uint16_t id = bmp_to_id[cps[i] - kBmpMin];
            if (id >= vocab) return false;
            ids[i] = id;
        }
        uint32_t lo2 = l1_l2_start[ids[0]], hi2 = l1_l2_start[ids[0] + 1];
        while (lo2 < hi2) {
            uint32_t mid = lo2 + (hi2 - lo2) / 2;
            uint16_t v = read13(l2_id13, mid);
            if (v < ids[1]) lo2 = mid + 1; else hi2 = mid;
        }
        if (lo2 >= l1_l2_start[ids[0] + 1] || read13(l2_id13, lo2) != ids[1]) return false;
        uint32_t idx2 = lo2;
        if (len == 2) {
            uint8_t q = l2_val[idx2];
            if (q == 0) return false;
            out_lc = min2 + (q - 1) * step2;
            return true;
        } else if (len == 3) {
            uint32_t orig_s = 0, orig_e = 0;
            child_range(idx2, l2_deg3, l2_blk3, l2_ovf3, ovf3, orig_s, orig_e);
            uint32_t s = orig_s, e = orig_e;
            while (s < e) {
                uint32_t mid = s + (e - s) / 2;
                uint16_t v = read13(l3_id13, mid);
                if (v < ids[2]) s = mid + 1; else e = mid;
            }
            if (s >= orig_e || read13(l3_id13, s) != ids[2]) return false;
            out_lc = min3 + l3_val[s] * step3;
            return true;
        } else {
            uint32_t key26 = (static_cast<uint32_t>(ids[2]) << 13) | static_cast<uint32_t>(ids[3]);
            uint32_t orig_s = 0, orig_e = 0;
            child_range(idx2, l2_deg4, l2_blk4, l2_ovf4, ovf4, orig_s, orig_e);
            uint32_t s = orig_s, e = orig_e;
            while (s < e) {
                uint32_t mid = s + (e - s) / 2;
                uint32_t v = read26(l4_k26, mid);
                if (v < key26) s = mid + 1; else e = mid;
            }
            if (s >= orig_e || read26(l4_k26, s) != key26) return false;
            out_lc = min4 + l4_val[s] * step4;
            return true;
        }
    }
};

struct PrefixItem { uint64_t packed; int32_t val; uint16_t rank; };

static inline void flush_topk(std::vector<PrefixItem>& cur, size_t max_k, std::vector<PrefixItem>& out) {
    if (cur.empty()) return;
    size_t k = std::min(max_k, cur.size());
    if (cur.size() > k) {
        std::partial_sort(cur.begin(), cur.begin() + k, cur.end(),
                          [](const PrefixItem& a, const PrefixItem& b) { return a.val > b.val; });
        cur.resize(k);
    } else {
        std::sort(cur.begin(), cur.end(),
                  [](const PrefixItem& a, const PrefixItem& b) { return a.val > b.val; });
    }
    for (size_t r = 0; r < cur.size(); ++r) {
        cur[r].rank = static_cast<uint16_t>(r);
        out.push_back(cur[r]);
    }
    cur.clear();
}

} // namespace

int main(int argc, char** argv) {
    const char* tea_path = "/tmp/wanxiang-lts-zh-hans.gram";
    const char* lex_path = "Keyboard/Resources/lexicon.bin";
    const char* out_path = nullptr;
    const char* zi_path = nullptr;

    size_t K2 = 100000;
    size_t K3 = 4300000;
    size_t K4 = 7320000;
    size_t pred_max3_1ch = 100000;
    size_t pred_max3_2ch = 420000;
    size_t pred_max4_1ch = 200000;
    size_t pred_max4_2ch = 100000;
    double pred_lambda = 1.0;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next_s = [&]() -> const char* { return (i + 1 < argc) ? argv[++i] : ""; };
        if (a == "--teacher" || a == "--tea" || a == "--source") tea_path = next_s();
        else if (a == "--lexicon" || a == "--lex") lex_path = next_s();
        else if (a == "--out") out_path = next_s();
        else if (a == "--zi") zi_path = next_s();
        else if (a == "--k2") K2 = std::stoull(next_s());
        else if (a == "--k3") K3 = std::stoull(next_s());
        else if (a == "--k4") K4 = std::stoull(next_s());
        else if (a == "--pred-max3-1ch") pred_max3_1ch = std::stoull(next_s());
        else if (a == "--pred-max3-2ch") pred_max3_2ch = std::stoull(next_s());
        else if (a == "--pred-max4-1ch") pred_max4_1ch = std::stoull(next_s());
        else if (a == "--pred-max4-2ch") pred_max4_2ch = std::stoull(next_s());
        else if (a == "--pred-lambda") pred_lambda = std::stod(next_s());
        else { std::fprintf(stderr, "Unknown flag: %s\n", a.c_str()); return 1; }
    }
    if (!out_path) return 1;

    LexTables lex;
    if (!lex.load(lex_path)) { std::fprintf(stderr, "Failed to load lexicon=%s\n", lex_path); return 1; }
    if (zi_path && zi_path[0]) lex.load_zi_log(zi_path);
    MMapGramV1 tea;
    if (!tea.open_file(tea_path)) { std::fprintf(stderr, "Failed to open source=%s\n", tea_path); return 1; }

    // Single-pass DFS over Wanxiang (CC-BY-4.0): collects Section 1 (decode) + streams Section 2 (predict) in O(1) scratch RAM.
    std::vector<Cand> c2, c3, c4;
    c2.reserve(80000);
    c3.reserve(4400000);
    c4.reserve(46000000);

    std::vector<PrefixItem> keep2, keep3_1ch, keep3_2ch, keep4_1ch, keep4_2ch;
    keep2.reserve(180000);
    keep3_1ch.reserve(200000);
    keep3_2ch.reserve(1500000);
    keep4_1ch.reserve(2500000);
    keep4_2ch.reserve(800000);

    // Streaming current-prefix buffers (DFS visits every trie prefix contiguously!)
    uint16_t cur_p1 = 0xFFFF;
    uint32_t cur_p2 = 0xFFFFFFFFU;
    uint64_t cur_p3 = 0xFFFFFFFFFFFFFFFFULL;
    std::vector<PrefixItem> buf2_p1, buf3_p1, buf3_p2, buf4_p2, buf4_p3;

    auto to_i32 = [](float v) -> int32_t {
        return static_cast<int32_t>(std::lround(std::max(0.01f, v) * 10000.0f));
    };

    dfs_grammar(tea, [&](const std::vector<uint8_t>& key, int32_t val) {
        uint16_t cps[4]{};
        int len = 0;
        if (!decode_rime_to_han4(key, cps, len, lex.is_lex_han)) return;
        uint64_t p = pack4(cps, len);
        float sf = val / 10000.0f;

        // Section 1: Wanxiang score capped at 2+2 tier (18.45) + lexicon seg_score so genuine 2+2 collocations beat rare 2+1+1 chains
        if (len == 2) c2.push_back({p, val, sf});
        else if (len == 3) c3.push_back({p, val, sf});
        else if (len == 4) {
            int sub3 = 0;
            if (key.size() == 8) {
                int32_t tmp = 0;
                if (tea.lookup(key.data(), 6, tmp)) sub3 += 1;
                if (tea.lookup(key.data() + 2, 6, tmp)) sub3 += 1;
            }
            float rank = std::min(sf, 18.50f) + (sub3 == 2 ? 0.68f : 0.0f);
            c4.push_back({p, val, rank});
        }

        // Section 2: streaming per-prefix top-k (since DFS visits p1 -> p2 -> p3 contiguously!)
        if (cps[0] != cur_p1) {
            flush_topk(buf4_p3, 8, keep4_1ch);
            flush_topk(buf4_p2, 10, keep4_2ch);
            flush_topk(buf3_p2, 12, keep3_2ch);
            flush_topk(buf3_p1, 16, keep3_1ch);
            flush_topk(buf2_p1, 24, keep2);
            cur_p1 = cps[0];
            cur_p2 = 0xFFFFFFFFU;
            cur_p3 = 0xFFFFFFFFFFFFFFFFULL;
        }
        uint32_t p2 = (static_cast<uint32_t>(cps[0]) << 16) | cps[1];
        if (p2 != cur_p2) {
            flush_topk(buf4_p3, 8, keep4_1ch);
            flush_topk(buf4_p2, 10, keep4_2ch);
            flush_topk(buf3_p2, 12, keep3_2ch);
            cur_p2 = p2;
            cur_p3 = 0xFFFFFFFFFFFFFFFFULL;
        }
        if (len == 4) {
            uint64_t p3 = pack4(cps, 3);
            if (p3 != cur_p3) {
                flush_topk(buf4_p3, 8, keep4_1ch);
                cur_p3 = p3;
            }
        }

        auto clamp_band = [](float x) -> float {
            return std::clamp(x, 0.5f, 6.5f);
        };
        auto zi_term = [&](uint16_t cp) -> float {
            float z = lex.zi_log[cp] > 0.0f ? lex.zi_log[cp] : std::max(0.0f, lex.char_score[cp] - 2.0f);
            return 0.25f * (std::min(16.0f, z) - 13.0f) + 0.45f * (std::min(17.5f, lex.char_score[cp]) - 15.0f);
        };
        if (len == 2) {
            if (lex.char_score[cps[1]] >= 13.5f) {
                float sc = clamp_band((sf - 8.0f) + zi_term(cps[1]));
                buf2_p1.push_back({p, to_i32(sc), 0});
            }
        } else if (len == 3) {
            if (lex.char_score[cps[2]] >= 13.5f) {
                float sc = clamp_band((sf - 12.6f) + zi_term(cps[2]));
                buf3_p2.push_back({p, to_i32(sc), 0});
            }
            float w2 = lex.word2_score(cps[1], cps[2]);
            uint16_t lastc = cps[2];
            bool func_tail = (lastc == 0x7684 || lastc == 0x4E86 || lastc == 0x7740 || lastc == 0x8FC7 || lastc == 0x5417 || lastc == 0x5462);
            if (w2 >= 10.5f && sf >= 13.5f && sf <= 16.20f && !func_tail) {
                float sc = clamp_band((sf - 13.6f) + 0.40f * (w2 - 11.5f));
                buf3_p1.push_back({p, to_i32(sc + 8.0f), 0});
            }
        } else if (len == 4) {
            if (lex.char_score[cps[3]] >= 13.5f && sf >= 16.0f) {
                float sc = clamp_band((std::min(sf, 18.45f) - 15.0f) + zi_term(cps[3]));
                buf4_p3.push_back({p, to_i32(sc), 0});
            }
            float w2 = lex.word2_score(cps[2], cps[3]);
            uint16_t lastc = cps[3];
            bool func_tail = (lastc == 0x7684 || lastc == 0x4E86 || lastc == 0x7740 || lastc == 0x8FC7 || lastc == 0x5417 || lastc == 0x5462);
            if (w2 >= 10.5f && sf >= 16.5f && sf <= 18.50f && !func_tail) {
                float sc = clamp_band((sf - 16.0f) + 0.40f * (w2 - 11.5f));
                buf4_p2.push_back({p, to_i32(sc + 8.0f), 0});
            }
        }
    });
    flush_topk(buf4_p3, 8, keep4_1ch);
    flush_topk(buf4_p2, 10, keep4_2ch);
    flush_topk(buf3_p2, 12, keep3_2ch);
    flush_topk(buf3_p1, 16, keep3_1ch);
    flush_topk(buf2_p1, 24, keep2);

    std::printf("DFS done: c2=%zu c3=%zu c4=%zu | pred raw: k2=%zu k3_1=%zu k3_2=%zu k4_1=%zu k4_2=%zu\n",
                c2.size(), c3.size(), c4.size(),
                keep2.size(), keep3_1ch.size(), keep3_2ch.size(), keep4_1ch.size(), keep4_2ch.size());
    std::fflush(stdout);

    // Build Section 1
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

    BuiltV2Section sec1;
    if (!build_v2_section(sec1_items, sec1)) { std::fprintf(stderr, "Section 1 V2 build failed\n"); return 1; }
    std::vector<std::pair<uint64_t, int32_t>>().swap(sec1_items);

    // Build Section 2
    auto cap_soft_ranked = [&](std::vector<PrefixItem>& v, size_t max_k) {
        if (v.size() > max_k) {
            auto pri = [&](const PrefixItem& x) -> double {
                double xv = x.val / 10000.0; if (xv >= 7.5) xv -= 8.0; return xv - pred_lambda * std::log2(1.0 + static_cast<double>(x.rank));
            };
            std::nth_element(v.begin(), v.begin() + max_k, v.end(),
                             [&](const PrefixItem& a, const PrefixItem& b) { return pri(a) > pri(b); });
            v.resize(max_k);
        }
    };
    cap_soft_ranked(keep3_1ch, pred_max3_1ch);
    cap_soft_ranked(keep3_2ch, pred_max3_2ch);
    cap_soft_ranked(keep4_1ch, pred_max4_1ch);
    cap_soft_ranked(keep4_2ch, pred_max4_2ch);

    std::vector<std::pair<uint64_t, int32_t>> sec2_items;
    sec2_items.reserve(keep2.size() + keep3_1ch.size() + keep3_2ch.size() + keep4_1ch.size() + keep4_2ch.size());
    for (const auto& x : keep2) sec2_items.push_back({x.packed, x.val});
    for (const auto& x : keep3_1ch) sec2_items.push_back({x.packed, x.val});
    for (const auto& x : keep3_2ch) sec2_items.push_back({x.packed, x.val});
    for (const auto& x : keep4_1ch) sec2_items.push_back({x.packed, x.val});
    for (const auto& x : keep4_2ch) sec2_items.push_back({x.packed, x.val});
    std::vector<PrefixItem>().swap(keep2);
    std::vector<PrefixItem>().swap(keep3_1ch);
    std::vector<PrefixItem>().swap(keep3_2ch);
    std::vector<PrefixItem>().swap(keep4_1ch);
    std::vector<PrefixItem>().swap(keep4_2ch);

    BuiltV2Section sec2;
    if (!build_v2_section(sec2_items, sec2)) { std::fprintf(stderr, "Section 2 V2 build failed\n"); return 1; }
    std::vector<std::pair<uint64_t, int32_t>>().swap(sec2_items);

    size_t sec1_bytes = sec1.bytes.size(), sec2_bytes = sec2.bytes.size(), total_bytes = sec1_bytes + sec2_bytes;
    if (total_bytes > kMaxBundleGrammarBytes) {
        std::fprintf(stderr, "ERROR: output %.2f MB = sec1 %.2f + sec2 %.2f exceeds 48.50 MiB\n",
                     total_bytes / 1048576.0, sec1_bytes / 1048576.0, sec2_bytes / 1048576.0);
        return 2;
    }
    FILE* f = std::fopen(out_path, "wb");
    if (!f) { std::perror("fopen"); return 1; }
    std::fwrite(sec1.bytes.data(), 1, sec1_bytes, f);
    std::fwrite(sec2.bytes.data(), 1, sec2_bytes, f);
    std::fclose(f);

    // Mmap self-verify both Mosto::GramV2 sections end-to-end.
    int vfd = ::open(out_path, O_RDONLY);
    struct stat vst{};
    if (vfd < 0 || ::fstat(vfd, &vst) != 0) { std::fprintf(stderr, "Self-verify stat failed\n"); return 1; }
    const uint8_t* vbase = reinterpret_cast<const uint8_t*>(::mmap(nullptr, vst.st_size, PROT_READ, MAP_PRIVATE, vfd, 0));
    MMapV2Section chk1, chk2;
    if (vbase == MAP_FAILED || !chk1.parse(vbase, 0, vst.st_size) || !chk2.parse(vbase, chk1.section_bytes, vst.st_size)) {
        std::fprintf(stderr, "Self-verify V2 parse failed!\n");
        return 1;
    }
    auto verify_samples = [&](const MMapV2Section& m, const BuiltV2Section& b, int sec_no) -> bool {
        for (const auto& s : b.samples) {
            float got = 0.0f;
            if (!m.lookup_cps(s.cps, s.len, got) || std::fabs(got - s.qval) > 1e-4f) {
                std::fprintf(stderr, "Self-verify mismatch sec=%d len=%d expected=%.5f got=%.5f\n",
                             sec_no, s.len, s.qval, got);
                return false;
            }
        }
        return true;
    };
    if (!verify_samples(chk1, sec1, 1) || !verify_samples(chk2, sec2, 2)) return 1;
    ::munmap(const_cast<uint8_t*>(vbase), vst.st_size);
    ::close(vfd);

    std::printf("DISTILLED_V2 %s: total=%.2f MB (%zu bytes)\n", out_path, total_bytes / 1048576.0, total_bytes);
    std::printf("  section1 (decode ): %.2f MB  V=%u n2=%u n3=%u n4=%u keys=%zu (len2=%zu len3=%zu len4=%zu)\n",
                sec1_bytes / 1048576.0, sec1.vocab_size, sec1.n2, sec1.n3, sec1.n4,
                sec1.by_char[2]+sec1.by_char[3]+sec1.by_char[4], sec1.by_char[2], sec1.by_char[3], sec1.by_char[4]);
    std::printf("  section2 (predict): %.2f MB  V=%u n2=%u n3=%u n4=%u keys=%zu (len2=%zu len3=%zu len4=%zu)\n",
                sec2_bytes / 1048576.0, sec2.vocab_size, sec2.n2, sec2.n3, sec2.n4,
                sec2.by_char[2]+sec2.by_char[3]+sec2.by_char[4], sec2.by_char[2], sec2.by_char[3], sec2.by_char[4]);
    return 0;
}
