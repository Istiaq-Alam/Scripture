#!/usr/bin/env node
// Builds public/scripts/<slug>-<os>.html for every script and OS in data.mjs.
// Each page carries the full source with stable line anchors (#L12) and an
// operating system switcher that links to the sibling pages.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { SCRIPTS, OSES, SITE } from "./data.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const siteRoot = resolve(here, "..");
const repoRoot = resolve(siteRoot, "..");
const outDir = join(siteRoot, "public", "scripts");
const manifest = JSON.parse(
  await readFile(join(siteRoot, "public", "downloads", "manifest.json"), "utf8")
);

const esc = (value) =>
  String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

const clip = (text, max = 158) =>
  text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text;

const stamp = new Intl.DateTimeFormat("en-GB", {
  day: "numeric",
  month: "short",
  year: "numeric",
}).format(new Date(manifest.generatedAt));

const sprite = `<svg class="sprite" aria-hidden="true" focusable="false" xmlns="http://www.w3.org/2000/svg">
  <symbol id="i-check" viewBox="0 0 16 16"><path d="M3 8.4 6.2 11.6 13 4.8"/></symbol>
  <symbol id="i-download" viewBox="0 0 20 20"><path d="M10 3v9m0 0 3.5-3.5M10 12 6.5 8.5M3.5 15.5h13"/></symbol>
  <symbol id="i-copy" viewBox="0 0 20 20"><rect x="7" y="7" width="9.5" height="9.5" rx="2"/><path d="M13 5.5A2.5 2.5 0 0 0 10.5 3h-5A2.5 2.5 0 0 0 3 5.5v5A2.5 2.5 0 0 0 5.5 13"/></symbol>
  <symbol id="i-arrow" viewBox="0 0 20 20"><path d="M4 10h11m0 0-4-4m4 4-4 4"/></symbol>
</svg>`;

function shell({ title, description, canonical, body }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(clip(description))}">
<link rel="canonical" href="${esc(canonical)}">
<meta name="theme-color" content="#131209">
<link rel="icon" href="../favicon.ico" sizes="48x48">
<link rel="icon" href="../favicon-32x32.png" type="image/png" sizes="32x32">
<link rel="icon" href="../favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="../apple-touch-icon.png" sizes="180x180">
<link rel="manifest" href="../manifest.json">
<meta property="og:type" content="article">
<meta property="og:site_name" content="${esc(SITE.name)}">
<meta property="og:locale" content="${esc(SITE.locale)}">
<meta property="og:url" content="${esc(canonical)}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(clip(description, 200))}">
<meta property="og:image" content="${esc(SITE.image)}">
<meta property="og:image:type" content="image/png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Scripture: your dev setup in one script, for Linux, macOS and Windows.">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:image" content="${esc(SITE.image)}">
<meta name="twitter:image:alt" content="Scripture: your dev setup in one script, for Linux, macOS and Windows.">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&family=Geist+Mono:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="../styles.css">
<noscript><style>[data-copy] { display: none; }</style></noscript>
</head>
<body data-downloads="../downloads/">
<a class="skip" href="#main">Skip to content</a>
${sprite}
<header class="nav" id="top">
  <div class="nav__pill">
    <a class="brand" href="../" aria-label="Scripture, back to the home page">
      <span class="brand__mark" aria-hidden="true"></span>
      <span class="brand__name">Scripture</span>
    </a>
    <nav class="nav__links" aria-label="Sections">
      <a href="../#scripts">Scripts</a>
      <a href="../#how">How it works</a>
      <a href="../#safety">Safety</a>
      <a href="../#themes">Design library</a>
      <a href="../#faq">FAQ</a>
    </nav>
    <button class="nav__menu" id="menu-open" type="button" aria-expanded="false" aria-controls="mobile-menu">
      <span class="sr-only">Open menu</span>
      <span class="nav__lines" aria-hidden="true"><i></i><i></i></span>
    </button>
  </div>
</header>
<div class="mobile" id="mobile-menu" aria-hidden="true">
  <div class="mobile__top">
    <span class="brand"><span class="brand__mark" aria-hidden="true"></span><span class="brand__name">Scripture</span></span>
    <button class="mobile__close" id="menu-close" type="button">
      <span class="sr-only">Close menu</span>
      <span class="nav__lines nav__lines--close" aria-hidden="true"><i></i><i></i></span>
    </button>
  </div>
  <nav class="mobile__links" aria-label="Sections">
    <a href="../#scripts" style="--i:0">Scripts</a>
    <a href="../#how" style="--i:1">How it works</a>
    <a href="../#safety" style="--i:2">Safety</a>
    <a href="../#themes" style="--i:3">Design library</a>
    <a href="../#faq" style="--i:4">FAQ</a>
  </nav>
  <p class="mobile__foot">Linux, macOS and Windows. Read every script before you run it.</p>
</div>
<main id="main">
${body}
</main>
<footer class="footer">
  <div class="wrap footer__inner">
    <p>Scripts are provided as is. Read them before you run them.</p>
    <p class="footer__meta">
      <span data-sync>Synced ${esc(stamp)} · commit ${esc(manifest.commit)}</span>
      <a href="../privacy.html">Privacy</a>
      <a href="../terms.html">Terms</a>
    </p>
  </div>
</footer>
<p class="sr-only" id="copy-status" role="status" aria-live="polite"></p>
<script src="../app.js" defer></script>
</body>
</html>
`;
}

await mkdir(outDir, { recursive: true });

for (const script of SCRIPTS) {
  for (const os of OSES) {
    const variant = script.variants[os.id];
    const meta = manifest.files[variant.file];

    if (!meta) {
      throw new Error(`No manifest entry for ${variant.file}; run scripts/sync.mjs first.`);
    }

    const source = await readFile(join(repoRoot, variant.source), "utf8");
    const lines = source.split("\n");
    if (lines.at(-1) === "") lines.pop();

    const rows = lines
      .map((line, index) => {
        const n = index + 1;
        const isComment = /^\s*#/.test(line);
        return `<div class="cl${isComment ? " cl--comment" : ""}" id="L${n}"><a class="cl__n" href="#L${n}" aria-hidden="true" tabindex="-1">${n}</a><span class="cl__c">${esc(line) || " "}</span></div>`;
      })
      .join("\n");

    const tabs = OSES.map(
      (entry) =>
        `<a class="filter-btn${entry.id === os.id ? " is-current" : ""}" href="${script.slug}-${entry.id}.html"${
          entry.id === os.id ? ' aria-current="page"' : ""
        }>${esc(entry.label)}</a>`
    ).join("\n          ");

    const flagTable = variant.flags.length
      ? `<h2>Flags</h2>
      <table class="flags">
        <caption class="sr-only">Command line flags for ${esc(variant.file)}</caption>
        <tbody>
          ${variant.flags
            .map(
              ([flag, effect]) =>
                `<tr><th scope="row"><code>${esc(flag)}</code></th><td>${esc(effect)}</td></tr>`
            )
            .join("\n          ")}
        </tbody>
      </table>`
      : "";

    const downloadName = variant.file.split("/").pop();
    const checksumCommand = os.checksum.replace("{file}", downloadName);

    const body = `<section class="detail">
  <div class="wrap">
    <a class="back" href="../#scripts"><svg class="i i--flip" aria-hidden="true"><use href="#i-arrow"/></svg>All scripts</a>

    <div class="detail__head">
      <div>
        <h1>${esc(script.name)}</h1>
        <p class="detail__file"><code>${esc(variant.file)}</code><span class="tag${variant.sudoFilter === "yes" ? " tag--warn" : ""}">${esc(variant.tag)}</span></p>
        <p class="lead">${esc(script.summary)}</p>
      </div>
      <div class="detail__actions">
        <a class="btn btn--primary" href="../downloads/${esc(variant.file)}" download>
          <svg class="i" aria-hidden="true"><use href="#i-download"/></svg>Download for ${esc(os.label)}
        </a>
        <button class="btn btn--ghost" type="button" data-copy="${esc(variant.file)}" aria-label="Copy the ${esc(os.label)} install command for ${esc(script.name)}">
          <svg class="i" aria-hidden="true"><use href="#i-copy"/></svg><span>Copy command</span>
        </button>
      </div>
    </div>

    <div class="os-switch os-switch--page" role="group" aria-label="Choose your operating system">
      <span class="os-switch__label">Your system</span>
          ${tabs}
    </div>

    <dl class="meta-grid">
      <div><dt>Platform</dt><dd>${esc(os.label)} · ${esc(os.shell)}<br>${meta.lines.toLocaleString("en-US")} lines · ${Math.max(1, Math.round(meta.bytes / 1024))} KB</dd></div>
      <div><dt>Needs</dt><dd>${esc(variant.needs)}</dd></div>
      <div><dt>Writes</dt><dd>${esc(variant.writes)}</dd></div>
      <div><dt>Privileges</dt><dd>${esc(variant.sudo)}</dd></div>
    </dl>

    <div class="detail__body">
      <div class="prose">
        <h2>Before you run it</h2>
        <p>${esc(variant.note)}</p>
        <p>Read the source below or download the file and open it in your editor. The hash in the viewer header is the sha256 of the exact file this page serves.</p>
        ${flagTable}
      </div>
      <aside class="checksum">
        <h2 class="checksum__title">Checksum</h2>
        <code class="checksum__hash">${esc(meta.sha256)}</code>
        <p class="checksum__note">sha256 · ${esc(downloadName)} · synced ${esc(stamp)}</p>
        <p class="checksum__note">Compare it after downloading:</p>
        <pre class="checksum__cmd">${esc(checksumCommand)}</pre>
      </aside>
    </div>

    <section class="source" aria-labelledby="source-title">
      <div class="source__bar">
        <h2 id="source-title">Source</h2>
        <span class="source__meta">${esc(variant.file)} · ${meta.lines.toLocaleString("en-US")} lines</span>
        <a class="source__download" href="../downloads/${esc(variant.file)}" download>Download the file</a>
      </div>
      <div class="viewer" tabindex="0" role="region" aria-label="Source of ${esc(variant.file)}, ${meta.lines} lines">
        <pre class="code">${rows}</pre>
      </div>
      <p class="source__note">Line links are permanent: append <code>#L120</code> to this page to jump to line 120.</p>
    </section>

    <a class="back back--bottom" href="../#scripts"><svg class="i i--flip" aria-hidden="true"><use href="#i-arrow"/></svg>All scripts</a>
  </div>
</section>`;

    const html = shell({
      title: `${script.name} for ${os.label} — ${downloadName} — Scripture`,
      description: `${script.summary} ${os.label} version.`,
      canonical: `${SITE.url}/scripts/${script.slug}-${os.id}.html`,
      body,
    });

    await writeFile(join(outDir, `${script.slug}-${os.id}.html`), html);
    console.log(`${`${script.slug}-${os.id}`.padEnd(24)} ${String(lines.length).padStart(6)} lines`);
  }
}

console.log(`pages written to public/scripts/`);
