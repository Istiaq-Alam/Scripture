#!/usr/bin/env node
// Behavioural checks against the running site on :3000.
//   node scripts/checks.mjs
import { chromium } from "playwright-core";
import { createHash } from "node:crypto";

const BASE = process.env.SITE_URL || "http://127.0.0.1:3000";
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || "/usr/bin/chromium",
  args: ["--no-sandbox", "--disable-gpu"],
});

const failures = [];
const pass = (label) => console.log(`ok   ${label}`);
const fail = (label, detail) => {
  failures.push(`${label}${detail ? `: ${detail}` : ""}`);
  console.log(`FAIL ${label}${detail ? `: ${detail}` : ""}`);
};

/* ---------- mobile menu ---------- */

{
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.goto(BASE, { waitUntil: "networkidle" });

  await page.getByRole("button", { name: "Open menu" }).click();
  if (await page.locator("#mobile-menu").getAttribute("aria-hidden") !== "false") {
    fail("menu opens", "aria-hidden stayed true");
  } else {
    pass("menu opens and marks itself expanded");
  }

  const focused = await page.evaluate(() => document.activeElement?.textContent?.trim());
  if (focused === "Scripts") pass("focus moves to the first menu link");
  else fail("menu focus", `activeElement was ${focused}`);

  await page.keyboard.press("Escape");
  await page.waitForTimeout(350);
  if (await page.locator("#mobile-menu").getAttribute("aria-hidden") !== "true") {
    fail("Escape closes the menu");
  } else {
    pass("Escape closes the menu");
  }

  await page.getByRole("button", { name: "Open menu" }).click();
  await page.locator("#mobile-menu a[href='#safety']").click();
  await page.waitForTimeout(600);
  if (await page.locator("#mobile-menu").getAttribute("aria-hidden") !== "true") {
    fail("menu link closes the menu");
  } else {
    pass("menu link closes the menu and jumps to the section");
  }

  await page.close();
}

/* ---------- copy command + FAQ ---------- */

{
  const context = await browser.newContext({ permissions: ["clipboard-read", "clipboard-write"] });
  const page = await context.newPage();
  await page.goto(BASE, { waitUntil: "networkidle" });

  const button = page.locator("[data-copy='setup-laravel.sh']");
  await button.click();
  await page.waitForTimeout(250);

  const clipboard = await page.evaluate(() => navigator.clipboard.readText());
  const expected = `bash <(curl -fsSL ${BASE}/downloads/setup-laravel.sh)`;
  if (clipboard === expected) pass("copy button writes the install command");
  else fail("clipboard", `got ${JSON.stringify(clipboard)}`);

  const label = (await button.textContent()).trim();
  if (label === "Copied") pass("copy button shows a success state");
  else fail("copy state", `label was ${label}`);

  const status = await page.locator("#copy-status").textContent();
  if (status.includes("setup-laravel.sh")) pass("status region announces the copied file");
  else fail("copy status", status);

  await page.locator(".faq summary").first().click();
  if (await page.locator(".faq details").first().getAttribute("open") !== null) {
    pass("FAQ item opens");
  } else {
    fail("FAQ item opens");
  }

  await context.close();
}

/* ---------- every link resolves ---------- */

{
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(BASE, { waitUntil: "networkidle" });

  const links = await page.$$eval("a[href]", (nodes) =>
    [...new Set(nodes.map((node) => node.getAttribute("href")))]
  );

  for (const href of links) {
    if (href.startsWith("#")) {
      const exists = await page.locator(href).count();
      if (exists === 1) pass(`anchor ${href}`);
      else fail(`anchor ${href}`, "no matching id");
      continue;
    }
    const response = await page.request.get(new URL(href, BASE).href);
    if (response.ok()) pass(`link ${href}`);
    else fail(`link ${href}`, `status ${response.status()}`);
  }

  await page.close();
}

/* ---------- search and filters ---------- */

{
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(BASE, { waitUntil: "networkidle" });

  const search = page.locator("#script-search");
  const visibleRows = () => page.locator("#script-list .script:visible").count();

  await search.fill("laravel");
  await page.waitForTimeout(120);
  if ((await visibleRows()) === 1) pass("search narrows the list to one script");
  else fail("search", `${await visibleRows()} rows visible`);

  const countText = await page.locator("#filter-count").innerText();
  if (countText === "1 of 5 scripts") pass("result count updates");
  else fail("result count", countText);

  if (new URL(page.url()).searchParams.get("q") === "laravel") pass("search writes the query into the URL");
  else fail("search URL", page.url());

  await search.fill("");
  await page.getByRole("button", { name: "Uses sudo" }).click();
  await page.waitForTimeout(120);
  if ((await visibleRows()) === 3) pass("sudo filter keeps the three scripts that use it");
  else fail("sudo filter", `${await visibleRows()} rows`);

  if (await page.getByRole("button", { name: "Uses sudo" }).getAttribute("aria-pressed") === "true") {
    pass("active filter reports aria-pressed");
  } else {
    fail("filter state", "aria-pressed not set");
  }

  await search.fill("zzzz");
  await page.waitForTimeout(120);
  if (await page.locator("#script-empty").isVisible()) pass("empty state appears when nothing matches");
  else fail("empty state", "not visible");

  await page.locator("#clear-filters").click();
  await page.waitForTimeout(120);
  if ((await visibleRows()) === 5 && (await search.inputValue()) === "") {
    pass("clear filters restores the full list");
  } else {
    fail("clear filters", `${await visibleRows()} rows`);
  }

  await page.close();
}

/* ---------- detail pages and source viewer ---------- */

{
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const manifest = await (await page.request.get(`${BASE}/downloads/manifest.json`)).json();
  const pages = [
    ["setup-skills", "setup-skills.sh"],
    ["laravel", "setup-laravel.sh"],
    ["freebuff-zsh", "setup-freebuff-zsh.sh"],
    ["gitcli", "gitcli.sh"],
    ["claude-code", "ClaudeCode.sh"],
  ];

  for (const [slug, file] of pages) {
    const response = await page.request.get(`${BASE}/scripts/${slug}.html`);
    const html = await response.text();
    const lines = manifest.files[file].lines;

    if (response.ok()) pass(`page /scripts/${slug}`);
    else fail(`page /scripts/${slug}`, `status ${response.status()}`);

    if (html.includes('id="L1"') && html.includes(`id="L${lines}"`)) {
      pass(`line anchors 1-${lines} on ${slug}`);
    } else {
      fail(`line anchors ${slug}`, `missing L1 or L${lines}`);
    }
  }

  await page.goto(`${BASE}/scripts/laravel.html`, { waitUntil: "networkidle" });
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  );
  if (overflow === 0) pass("detail page has no overflow at 390px");
  else fail("detail overflow", `${overflow}px`);

  const label = await page.locator(".viewer").getAttribute("aria-label");
  if (label.includes("setup-laravel.sh") && label.includes("1765")) pass("viewer names the file and line count");
  else fail("viewer label", label);

  await page.close();
}

/* ---------- narrow viewport, reduced motion, no JS ---------- */

{
  const page = await browser.newPage({ viewport: { width: 320, height: 640 } });
  await page.goto(BASE, { waitUntil: "networkidle" });
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  );
  if (overflow === 0) pass("no horizontal overflow at 320px");
  else fail("320px overflow", `${overflow}px`);
  await page.close();
}

{
  const context = await browser.newContext({ reducedMotion: "reduce" });
  const page = await context.newPage();
  await page.goto(BASE, { waitUntil: "networkidle" });
  const hidden = await page.evaluate(() =>
    [...document.querySelectorAll("main section")].filter(
      (node) => Number(getComputedStyle(node).opacity) < 0.9
    ).length
  );
  if (hidden === 0) pass("reduced motion shows every section");
  else fail("reduced motion", `${hidden} section(s) hidden`);
  await context.close();
}

{
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(BASE, { waitUntil: "load" });
  const copyVisible = await page.locator("[data-copy]").first().isVisible();
  if (!copyVisible) pass("copy buttons are hidden without JS");
  else fail("no JS", "copy button still visible");

  const sectionsVisible = await page.evaluate(() =>
    [...document.querySelectorAll("main section")].every(
      (node) => Number(getComputedStyle(node).opacity) > 0.9
    )
  );
  if (sectionsVisible) pass("every section is readable without JS");
  else fail("no JS", "a section stayed hidden");
  await context.close();
}

/* ---------- downloads match the manifest ---------- */

{
  const page = await browser.newPage();
  await page.goto(BASE, { waitUntil: "networkidle" });

  const manifest = await (await page.request.get(`${BASE}/downloads/manifest.json`)).json();

  for (const [file, meta] of Object.entries(manifest.files)) {
    const response = await page.request.get(`${BASE}/downloads/${file}`);
    const hash = createHash("sha256").update(await response.body()).digest("hex");
    if (hash === meta.sha256) pass(`hash ${file}`);
    else fail(`hash ${file}`, "download does not match manifest");

    const disposition = response.headers()["content-disposition"] || "";
    if (disposition.includes(file)) pass(`attachment header ${file}`);
    else fail(`attachment header ${file}`, disposition);
  }

  await page.close();
}

await browser.close();

console.log(failures.length ? `\n${failures.length} failure(s)` : "\nAll checks passed.");
process.exitCode = failures.length ? 1 : 0;
