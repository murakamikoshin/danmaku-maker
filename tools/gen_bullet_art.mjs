// art/bosses/patterns/engine.js の専用弾のドット絵(MAPS と PALS)を、DanmakuApp/Game/BulletArtData.swift に書き出す。
// 使い方: node tools/gen_bullet_art.mjs [engine.js のパス]   (絵を直したときだけ。並びは BulletLook.Kind と同じ)
// 竜王の弾は、竜王の作業場所(../danmaku-dragon、ブランチ swipe-mode-spec)の engine.js にある。色は姿ごとに4つ(通常・蒼炎・紫電・白金)
import fs from "node:fs";
const src = fs.readFileSync(process.argv[2] || new URL("../art/bosses/patterns/engine.js", import.meta.url), "utf8");
const grab = (name) => {
  const i = src.indexOf(`const ${name} = {`); const j = src.indexOf("\n};", i);
  return new Function(`return ${src.slice(src.indexOf("{", i), j + 2)}`)();
};
const MAPS = grab("MAPS"), PALS = grab("PALS");
const order = ["fox","ofuda","plankton","bubble","ink","missile","hex","shell","flake","icicle","shard","soul","blade","chain","jelly","eye","tooth","goo","kingyo","yoyo","spark","awa","flame","slash","gust","sun","rock","spine","tornado","ember","pshot"];
let o = "// 自動生成: tools/gen_bullet_art.mjs(手で直さない)\n// ボス専用の弾のドット絵。BulletLook.Kind の並び。1文字 = 1論理px、上向きの絵\nenum BulletArtData {\n";
o += "    static let maps: [[String]] = [\n" + order.map(k => "        [" + MAPS[k].map(r => JSON.stringify(r)).join(", ") + "],").join("\n") + "\n    ]\n";
o += "    /// [種類][0=通常 1=覚醒(竜王の弾は 0〜3 = 姿)] → 文字 → 色(#rrggbb)\n    static let palettes: [[[Character: String]]] = [\n";
o += order.map(k => "        [" + PALS[k].map(p => "[" + Object.entries(p).map(([c, v]) => `${JSON.stringify(c)}: ${JSON.stringify(v)}`).join(", ") + "]").join(", ") + "],").join("\n") + "\n    ]\n}\n";
fs.writeFileSync(new URL("../DanmakuApp/Game/BulletArtData.swift", import.meta.url), o);
console.log("ok", order.length);
