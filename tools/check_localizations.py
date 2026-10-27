#!/usr/bin/env python3
"""画面文言(Localizable / InfoPlist)の多言語チェック。
- 全言語がすべてのキーを持つ
- 書式指定子(%@ %lld %d …)が英語と一致する
- 日本語以外の言語に、ひらがな・カタカナが混ざっていない(中国語は漢字OK、韓国語はハングルのみ、など)
使い方: python3 tools/check_localizations.py  (問題があれば終了コード1)"""
import json, re, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
kana = re.compile('[぀-ヿｦ-ﾟ]')
han = re.compile('[一-鿿]')
hangul = re.compile('[가-힯]')
cyr = re.compile('[Ѐ-ӿ]')
ph = re.compile(r'%(?:\d+\$)?(?:l+|)[@dsfx]|%%')
bad = 0
for name in ("Localizable", "InfoPlist"):
    d = json.loads((root / f"DanmakuApp/{name}.xcstrings").read_text())
    langs = {l for v in d["strings"].values() for l in v["localizations"]}
    print(name, sorted(langs))
    for key, v in d["strings"].items():
        loc = v["localizations"]
        en = loc["en"]["stringUnit"]["value"]
        for lang in langs:
            if lang not in loc:
                print(f"  MISSING {lang} {key}"); bad += 1; continue
            t = loc[lang]["stringUnit"]["value"]
            if lang == "ja":
                continue
            if sorted(ph.findall(t)) != sorted(ph.findall(en)):
                print(f"  PLACEHOLDER {lang} {key}: {t!r}"); bad += 1
            if kana.search(t):
                print(f"  KANA {lang} {key}: {t}"); bad += 1
            if lang not in ("zh-Hans", "zh-Hant") and han.search(t):
                print(f"  HAN {lang} {key}: {t}"); bad += 1
            if lang != "ko" and hangul.search(t):
                print(f"  HANGUL {lang} {key}: {t}"); bad += 1
            if lang != "ru" and cyr.search(t):
                print(f"  CYRILLIC {lang} {key}: {t}"); bad += 1
print("問題:", bad)
sys.exit(1 if bad else 0)
