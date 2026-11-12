// 静的ページ（トップ・利用規約・プライバシーポリシー・サポート・404・apple-app-site-association）を生成する。
// 使い方: node hosting/build.mjs   （site.config.json の値を差し替えてから実行）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, 'public');
const cfg = JSON.parse(fs.readFileSync(path.join(here, 'site.config.json'), 'utf8'));
const write = (rel, body) => { const f = path.join(out, rel); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, body); };
const mail = `<a href="mailto:${cfg.supportEmail}">${cfg.supportEmail}</a>`;

const CSS = `:root{color-scheme:dark;--ink:#110e26;--panel:#1c1740;--line:#332b62;--fg:#efeaff;--dim:#a39bd0;--pink:#ff6b9d;--gold:#ffd166}
*{box-sizing:border-box}body{margin:0;background:var(--ink);color:var(--fg);font-family:"Hiragino Sans","Noto Sans JP",system-ui,sans-serif;line-height:1.75}
main{max-width:720px;margin:0 auto;padding:28px 16px 64px}nav{display:flex;gap:14px;flex-wrap:wrap;font-size:14px;margin-bottom:24px}
a{color:#5ce1e6}h1{font-size:28px;line-height:1.3;margin:0 0 6px}h2{font-size:19px;margin:32px 0 6px;color:var(--gold)}p,li{color:#d9d3f2}.dim{color:var(--dim);font-size:13px}
ul{padding-left:1.3em}.btn{display:inline-block;background:var(--pink);color:#1a0b14;padding:12px 18px;border-radius:12px;font-weight:700;text-decoration:none}
.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:16px}footer{margin-top:40px;font-size:13px;color:var(--dim)}`;

const T = {
  ja: {
    name: '弾幕メーカー', home: 'トップ', terms: '利用規約', privacy: 'プライバシーポリシー', support: 'サポート', other: 'English', otherLang: 'en',
    tagline: '弾幕ステージを作って、投稿して、世界中で遊ぼう。',
    intro: '弾幕メーカーは、自分で作った弾幕ステージを投稿し、世界中の人と遊び合える iOS ゲームです。',
    store: 'App Store でダウンロード',
    notFoundTitle: 'ページが見つかりません', notFoundBody: 'URL が間違っているか、ページが移動した可能性があります。',
    updated: '最終更新日',
  },
  en: {
    name: 'Danmaku Maker', home: 'Home', terms: 'Terms of Use', privacy: 'Privacy Policy', support: 'Support', other: '日本語', otherLang: 'ja',
    tagline: 'Build bullet-hell stages, share them, and dodge the world.',
    intro: 'Danmaku Maker is an iOS game where you build your own bullet-hell stages, publish them, and play stages made by people around the world.',
    store: 'Download on the App Store',
    notFoundTitle: 'Page not found', notFoundBody: 'The link may be wrong, or the page has moved.',
    updated: 'Last updated',
  },
};

const BODY = {
  ja: {
    terms: [
      ['1. 適用', `この利用規約（以下「本規約」）は、${cfg.operator}（以下「運営者」）が提供する iOS アプリ「弾幕メーカー」（以下「本アプリ」）の利用条件を定めるものです。本アプリを利用した時点で、本規約に同意したものとみなします。`],
      ['2. アカウント', '本アプリは、ゲストとして（匿名のまま）遊べます。ステージの投稿・いいね・通報には、Sign in with Apple によるサインインが必要です。アカウントの管理は利用者の責任で行ってください。'],
      ['3. 投稿されたステージ', '投稿されたステージの権利は投稿者に残ります。投稿者は運営者に対し、本アプリの運営・表示・配信・宣伝（共有ページや共有画像を含む）に必要な範囲で、投稿内容を世界中で無償かつ非独占的に利用する権利を許諾します。投稿したステージは他の利用者が遊べるようになり、アプリ内でステージ名・作者名・成績などが表示されます。作者名やステージ名に個人情報を含めないでください。'],
      ['3の2. コメントとランキング', 'ステージの詳細画面では、Sign in with Apple でサインインした利用者がコメント（80文字まで）を書けます。コメントは他の利用者に公開されます。リンク・個人情報・誹謗中傷などは禁止で、運営者は不適切なコメントを予告なく削除できます。コメントは、書いた本人とステージの作者が削除でき、他の利用者は通報・ブロックができます。複数の通報があったコメントは、自動的に非表示になります。世界ランキングには、サーバーで確認できたクリア記録だけが載ります。ランキングに出る名前は、アプリが用意した言葉から選びます（自由入力はできません）。復活を使ったクリアは、ランキングとクリア数に数えません。'],
      ['4. 禁止事項', '次の行為を禁止します。<ul><li>法令または公序良俗に反する内容の投稿（ステージ、ステージ名、作者名、コメント、ランキングの名前を含む）</li><li>他者の権利（著作権・商標・プライバシーなど）の侵害</li><li>差別・誹謗中傷・脅迫・過度に性的または暴力的な表現（ステージ名・作者名を含む）</li><li>個人情報や連絡先、外部サイトへの誘導の掲載</li><li>クリア記録・ランキング記録・リプレイの改ざん、不正なプログラムの使用、サーバーへの過度な負荷</li><li>他者へのなりすまし、スパム行為</li><li>本アプリの解析・改変・リバースエンジニアリング</li></ul>'],
      ['5. 通報と対応', '不適切なステージは、各ステージの詳細画面から通報できます。また、作者をブロックすると、その作者のステージが一覧に表示されなくなります。運営者は通報を確認し、必要に応じてステージの非公開・削除を行います。複数の通報が集まったステージは、確認のため自動的に非公開になることがあります。'],
      ['6. アカウントの停止', '運営者は、本規約に違反した利用者に対し、事前の通知なく、ステージの削除・投稿機能の制限・アカウントの停止を行うことがあります。'],
      ['7. 広告と課金', '本アプリには広告（リワード広告）が表示されます。「広告削除」を購入すると、広告が表示されなくなり、復活が無料・無制限になります。購入は Apple のアプリ内課金を通じて行われ、返金などのお問い合わせは Apple の手続きに従います。購入の復元は、本アプリの設定画面または購入画面から行えます。'],
      ['8. 免責', '運営者は、本アプリの動作・内容・投稿されたステージについて、法令で認められる範囲で、明示・黙示を問わず保証しません。本アプリの利用により生じた損害について、運営者に故意または重過失がある場合を除き、責任を負いません。'],
      ['9. 規約の変更', '運営者は、必要に応じて本規約を変更できます。重要な変更はアプリ内またはこのページでお知らせします。'],
      ['10. 準拠法と裁判管轄', '本規約は日本法に準拠します。本アプリに関する紛争は、日本の裁判所を専属的合意管轄とします。'],
      ['11. お問い合わせ', `ご質問・通報・削除のご依頼は ${mail} までご連絡ください。`],
    ],
    privacy: [
      ['1. 運営者', `${cfg.operator}（個人）。お問い合わせ先: ${mail}`],
      ['2. 取得する情報', '<ul><li><b>匿名の利用者ID</b>：アプリを開くと、Firebase Authentication が匿名の ID を発行します。</li><li><b>Sign in with Apple</b>：投稿・いいね・通報のためにサインインした場合、Apple が発行する利用者 ID を取得します。メールアドレスや氏名は取得しません。</li><li><b>投稿内容</b>：ステージの内容（発射台の設定など）、ステージ名、作者名、クリア時の操作記録（リプレイ）、投稿日時、端末の言語。</li><li><b>利用状況</b>：挑戦回数・クリア数・いいね・通報（誰がどのステージを通報したかを含む）。</li><li><b>コメントとランキング</b>：書いたコメント（文章・日時・ランキング名）、ランキングに送ったクリア記録（クリアまでの時間やダメージと、確認のための操作記録）。ランキング名は、アプリが用意した言葉と、利用者ごとに自動で決まる4桁の数字だけでできており、氏名などは含みません。</li><li><b>広告</b>：広告の表示・操作に関する情報。許可した場合は広告識別子（IDFA）。</li><li><b>購入情報</b>：購入状態（広告削除・きせかえ・撃ち方・じぶんの画像の購入有無）。決済情報（カード番号など）は取得しません。</li><li><b>じぶんの画像</b>：「じぶんの画像」機能で選んだ画像は、お使いの端末の中にだけ保存します。当方のサーバーへの送信や収集は一切行いません。写真ライブラリ全体へのアクセスも行いません（選んだ1枚だけを受け取ります）。</li><li><b>通信ログ</b>：サーバー運用のため、IP アドレスなどが一時的に記録されます。</li></ul>'],
      ['3. 利用目的', 'ステージの投稿・表示・共有、不正や不適切な投稿への対応、集計（挑戦数・クリア率）、広告の配信、購入状態の管理、アプリの改善とサポート対応のために利用します。'],
      ['4. 外部サービス（委託先・提供先）', '<ul><li>Google（Firebase：認証・データベース・ストレージ・関数・ホスティング）</li><li>Apple（Sign in with Apple、App Store、アプリ内課金）</li><li>Google AdMob（広告配信）</li><li>RevenueCat（購入状態の管理）</li></ul>これらの事業者は、各社のプライバシーポリシーに従って情報を取り扱います。データは日本および米国などのサーバーで処理されることがあります。'],
      ['5. 広告とトラッキング', '広告を表示する前に、お住まいの地域の法令に応じて同意の確認（Google の User Messaging Platform）を行います。iOS の「トラッキングの許可」で許可しない場合、広告識別子は使用されず、広告は個人に合わせない形で表示されます。許可の設定は、iOS の設定からいつでも変更できます。'],
      ['6. 公開される情報', '投稿したステージ、ステージ名、作者名、挑戦数・クリア数・いいね数、コメント、ランキングの名前と記録は、他の利用者に公開されます。それ以外の情報（利用者 ID、通報、ブロックリストなど）は公開されません。ブロックした作者のリストは、お使いの端末に保存されます。'],
      ['7. 保存期間と削除', 'アプリの設定画面から、いつでもアカウントを削除できます。削除すると、ご自身が投稿したステージ、コメント、ランキングの記録と関連データを削除（または非公開に）します。通報の記録など、安全のために必要なものは、個人を特定しない形で残すことがあります。'],
      ['8. 子どもの利用', '本アプリは、特に子どもを対象としていません。保護者の方は、お子さまの投稿内容にご注意ください。'],
      ['9. 方針の変更', '本ポリシーを変更する場合は、このページで告知します。'],
      ['10. お問い合わせ', `個人情報の開示・削除などのご請求は ${mail} までご連絡ください。`],
    ],
    support: [
      ['お問い合わせ', `不具合・ご質問・不適切なステージの報告・データ削除のご依頼は、${mail} までご連絡ください。ステージの ID（5文字）をお知らせいただくと、確認がスムーズです。`],
      ['よくある質問', '<ul><li><b>購入を復元したい</b>：アプリの購入画面にある「購入を復元」を押してください。購入時と同じ Apple ID が必要です。</li><li><b>不適切なステージを見つけた</b>：ステージの詳細画面の「通報する」から報告してください。「作者をブロック」で一覧から非表示にもできます。</li><li><b>アカウントを削除したい</b>：アプリの「設定」→「アカウントを削除」から行えます。</li><li><b>投稿するにはサインインが必要？</b>：はい。遊ぶだけならサインイン不要です。投稿・いいね・通報には Sign in with Apple が必要です。</li><li><b>ステージがクリアできない</b>：投稿には、作者本人がテストプレイでクリアすることが必要です。</li></ul>'],
    ],
  },
  en: {
    terms: [
      ['1. Scope', `These Terms of Use ("Terms") govern your use of the iOS app "Danmaku Maker" (the "App") provided by ${cfg.operator} (the "Operator"). By using the App you agree to these Terms.`],
      ['2. Accounts', 'You can play as a guest (anonymously). Publishing, liking, and reporting stages require signing in with Apple. You are responsible for your account.'],
      ['3. Published stages', 'You keep the rights to the stages you publish. You grant the Operator a worldwide, royalty-free, non-exclusive license to use, display, distribute, and promote your content (including share pages and share images) as needed to run the App. Published stages can be played by other users, and the stage name, author name, and play statistics are shown in the App. Do not put personal information in stage or author names.'],
      ['3b. Comments and rankings', 'On a stage\'s detail screen, users signed in with Apple can write comments (up to 80 characters). Comments are public. Links, personal information and abuse are prohibited, and the operator may remove inappropriate comments without notice. A comment can be deleted by its writer and by the stage\'s author; other users can report or block. Comments with several reports are hidden automatically. The world ranking only lists clears verified by our server. Ranking names are picked from words provided by the App (free text is not possible). Clears that used a revive do not count toward rankings or clear stats.'],
      ['4. Prohibited conduct', 'You must not:<ul><li>publish unlawful content (including stages, stage names, author names, comments, and ranking names);</li><li>infringe others\' rights (copyright, trademark, privacy, etc.);</li><li>post discriminatory, defamatory, threatening, or excessively sexual or violent content, including in stage and author names;</li><li>post personal information, contact details, or links to other sites;</li><li>tamper with clear records, ranking records or replays, use cheats, or overload the servers;</li><li>impersonate others or spam;</li><li>analyze, modify, or reverse engineer the App.</li></ul>'],
      ['5. Reporting and moderation', 'You can report inappropriate stages from the stage detail screen, and block an author to hide their stages from your lists. The Operator reviews reports and may hide or delete stages. Stages that receive multiple reports may be hidden automatically pending review.'],
      ['6. Suspension', 'The Operator may delete stages, restrict publishing, or suspend accounts that violate these Terms, without prior notice.'],
      ['7. Ads and purchases', 'The App shows ads (rewarded ads). Buying "Remove Ads" removes ads and makes revives free and unlimited. Purchases are processed by Apple in-app purchase; refund requests follow Apple\'s process. You can restore purchases from the Settings or purchase screen.'],
      ['8. Disclaimer', 'To the extent permitted by law, the Operator makes no warranties about the App or user-published stages, and is not liable for damages arising from your use of the App except in cases of intent or gross negligence.'],
      ['9. Changes', 'The Operator may update these Terms. Important changes will be announced in the App or on this page.'],
      ['10. Governing law', 'These Terms are governed by the laws of Japan, and the Japanese courts have exclusive jurisdiction.'],
      ['11. Contact', `For questions, reports, or removal requests, contact ${mail}.`],
    ],
    privacy: [
      ['1. Operator', `${cfg.operator} (individual). Contact: ${mail}`],
      ['2. Information we collect', '<ul><li><b>Anonymous user ID</b>: Firebase Authentication issues an anonymous ID when you open the App.</li><li><b>Sign in with Apple</b>: if you sign in to publish, like, or report, we receive the user ID issued by Apple. We do not collect your email address or name.</li><li><b>Content you publish</b>: the stage data (emitter settings, etc.), stage name, author name, the replay of your clear, publish time, and device language.</li><li><b>Usage</b>: play counts, clears, likes, and reports (including which stage was reported by whom).</li><li><b>Comments and rankings</b>: comments you write (text, time, ranking name) and clear records you send to the ranking (clear time or damage, plus a replay used for verification). A ranking name consists only of words provided by the App and an automatically assigned 4-digit number; it contains no real name.</li><li><b>Ads</b>: ad impressions and interactions; if you allow tracking, the advertising identifier (IDFA).</li><li><b>Purchases</b>: whether you purchased "Remove Ads", looks, shot styles, or "Your own images". We do not collect payment details.</li><li><b>Your own images</b>: images you choose for the "Your own images" feature are stored only on your device. We never upload or collect them, and we do not access your whole photo library (the App only receives the single image you pick).</li><li><b>Server logs</b>: IP addresses and similar data are temporarily logged to operate the servers.</li></ul>'],
      ['3. How we use it', 'To publish, display, and share stages; handle abuse and inappropriate content; compute play statistics; serve ads; manage purchase status; and improve and support the App.'],
      ['4. Service providers', '<ul><li>Google (Firebase: authentication, database, storage, functions, hosting)</li><li>Apple (Sign in with Apple, App Store, in-app purchase)</li><li>Google AdMob (ads)</li><li>RevenueCat (purchase status)</li></ul>These providers handle data under their own privacy policies. Data may be processed on servers in Japan, the United States, and other countries.'],
      ['5. Ads and tracking', 'Before showing ads, we ask for consent where required by local law (Google User Messaging Platform). If you decline iOS "Allow Tracking", the advertising identifier is not used and ads are not personalized. You can change this anytime in iOS Settings.'],
      ['6. What is public', 'Published stages, stage names, author names, play/clear/like counts, comments, and ranking names and records are visible to other users. Other data (user ID, reports, block list) is not public. Your list of blocked authors is stored on your device.'],
      ['7. Retention and deletion', 'You can delete your account anytime from Settings in the App. We then delete (or unpublish) the stages, comments and ranking records you published, and related data. Records needed for safety, such as reports, may be kept in a form that does not identify you.'],
      ['8. Children', 'The App is not directed at children. Parents should supervise what children publish.'],
      ['9. Changes', 'We will announce changes to this policy on this page.'],
      ['10. Contact', `For access or deletion requests, contact ${mail}.`],
    ],
    support: [
      ['Contact', `For bugs, questions, reports of inappropriate stages, or data deletion requests, email ${mail}. Including the 5-character stage ID helps us respond faster.`],
      ['FAQ', '<ul><li><b>How do I restore my purchase?</b> Tap "Restore Purchases" on the purchase screen. You need the same Apple ID you used to buy it.</li><li><b>I found an inappropriate stage.</b> Use "Report" on the stage detail screen. You can also "Block author" to hide their stages.</li><li><b>How do I delete my account?</b> Go to Settings → Delete account in the App.</li><li><b>Do I need to sign in to publish?</b> Yes. Playing needs no sign-in; publishing, liking, and reporting require Sign in with Apple.</li><li><b>I can\'t clear my own stage.</b> You must clear your stage in a test play before you can publish it.</li></ul>'],
    ],
  },
};

function page(lang, key, title, bodyHtml, extraHead = '') {
  const t = T[lang];
  const nav = `<nav><a href="/${lang}/">${t.home}</a><a href="/${lang}/terms">${t.terms}</a><a href="/${lang}/privacy">${t.privacy}</a><a href="/${lang}/support">${t.support}</a><a href="/${t.otherLang}/${key === 'index' ? '' : key}" hreflang="${t.otherLang}">${t.other}</a></nav>`;
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title} | ${t.name}</title>${extraHead}<style>${CSS}</style></head><body><main>${nav}${bodyHtml}<footer>© ${t.name}</footer></main></body></html>`;
}

for (const lang of ['ja', 'en']) {
  const t = T[lang];
  write(`${lang}/index.html`, page(lang, 'index', t.name,
    `<h1>${t.name}</h1><p>${t.tagline}</p><p>${t.intro}</p><p><a class="btn" href="${cfg.appStoreUrl}">${t.store}</a></p>`,
    `<meta name="description" content="${t.intro}">`));
  for (const key of ['terms', 'privacy', 'support']) {
    const sections = BODY[lang][key].map(([h, b]) => `<h2>${h}</h2><p>${b}</p>`).join('');
    write(`${lang}/${key}.html`, page(lang, key, t[key], `<h1>${t[key]}</h1><p class="dim">${t.updated}: ${cfg.updated}</p>${sections}`));
  }
}
write('index.html', `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Danmaku Maker</title><script>var l=(navigator.language||'en').slice(0,2)==='ja'?'ja':'en';location.replace('/'+l+'/')</script><noscript><meta http-equiv="refresh" content="0;url=/en/"></noscript></head><body><a href="/ja/">日本語</a> · <a href="/en/">English</a></body></html>`);
write('404.html', `<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>404 | Danmaku Maker</title><style>${CSS}</style></head><body><main><h1>${T.ja.notFoundTitle} / ${T.en.notFoundTitle}</h1><p>${T.ja.notFoundBody}</p><p>${T.en.notFoundBody}</p><p><a href="/ja/">日本語</a> · <a href="/en/">English</a></p></main></body></html>`);

const aasa = JSON.stringify({
  applinks: { details: [{ appIDs: [`${cfg.teamId}.${cfg.bundleId}`], components: [{ '/': '/s/*', comment: 'Stage share links' }] }] },
}, null, 2);
write('.well-known/apple-app-site-association', aasa);
write('apple-app-site-association', aasa);
// AdMob のアプリ確認(広告配信の制限解除)用
// 広告の販売元の一覧。AdMob と、メディエーションで入札する Unity Ads(Organization core ID)。AppLovin は承認後に足す
const appAds = [
  'google.com, pub-3863314847163872, DIRECT, f08c47fec0942fa0',
  'unity.com, 15669668771527, DIRECT, 96cabb5fbdde37a7',
].join('\n') + '\n';
// ストアの開発者サイト URL が /ja/ /en/ 付きなので、そこにも同じものを置く
for (const rel of ['app-ads.txt', 'ja/app-ads.txt', 'en/app-ads.txt']) write(rel, appAds);
console.log('pages generated in', out);
