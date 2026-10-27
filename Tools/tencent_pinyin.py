import sys
from pypinyin import lazy_pinyin, Style
src, out = sys.argv[1], sys.argv[2]
body = False
n = 0
with open(src, encoding='utf-8') as f, open(out, 'w', encoding='utf-8') as o:
    o.write('---\nname: tencent_py\n...\n')
    for line in f:
        line = line.rstrip('\n')
        if not body:
            body = line.strip() == '...'; continue
        p = line.split('\t')
        if len(p) < 2 or not p[0]: continue
        py = lazy_pinyin(p[0], style=Style.NORMAL, v_to_u=False, neutral_tone_with_five=False)
        if len(py) != len(p[0]) or not all(s.isalpha() and s.isascii() for s in py): continue
        py = [s.replace('ü', 'v') for s in py]
        o.write(f"{p[0]}\t{' '.join(py)}\t{p[1]}\n"); n += 1
print(n)
