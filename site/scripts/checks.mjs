#!/usr/bin/env node
// Behavioural checks against the running site on :3000.
//   node scripts/checks.mjs
import { chromium } from "playwright-core";
import { createHash } from "node:crypto";
import { SCRIPTS, OSES, SITE } from "./data.mjs";

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
const basename = (file) => file.split("/").pop();

/* ---------- mobile menu ---------- */

{
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.goto(`${BASE}?os=linux`, { waitUntil: "networkidle" });

  await page.getByRole("button", { name: "Open menu" }).click();
  if ((await page.locator("#mobile-menu").getAttribute("aria-hidden")) !== "false") {
    fail("menu opens", "aria-hidden stayed true");
  } else {
    pass("menu opens and marks itself expanded");
  }

  const focused = await page.evaluate(() => document.activeElement?.textContent?.trim());
  if (focused === "Scripts") pass("focus moves to the first menu link");
  else fail("menu focus", `activeElement was ${focused}`);

  await page.keyboard.press("Escape");
  await page.waitForTimeout(350);
  if ((await page.locator("#mobile-menu").getAttribute("aria-hidden")) !== "true") {
    fail("Escape closes the menu");
  } else {
    pass("Escape closes the menu");
  }

  await page.getByRole("button", { name: "Open menu" }).click();
  await page.locator("#mobile-menu a[href='#safety']").click();
  await page.waitForTimeout(600);
  if ((await page.locator("#mobile-menu").getAttribute("aria-hidden")) !== "true") {
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
  await page.goto(`${BASE}?os=linux`, { waitUntil: "networkidle" });

  const button = page.locator("[data-copy='linux/setup-laravel.sh']");
  await button.click();
  await page.waitForTimeout(250);

  const clipboard = await page.evaluate(() => navigator.clipboard.readText());
  const expected = `bash <(curl -fsSL ${BASE}/downloads/linux/setup-laravel.sh)`;
  if (clipboard === expected) pass("copy button writes the Linux install command");
  else fail("clipboard", `got ${JSON.stringify(clipboard)}`);

  const label = (await button.textContent()).trim();
  if (label === "Copied") pass("copy button shows a success state");
  else fail("copy state", `label was ${label}`);

  const status = await page.locator("#copy-status").textContent();
  if (status.includes("setup-laravel.sh")) pass("status region announces the copied file");
  else fail("copy status", status);

  await page.locator(".faq summary").first().click();
  if ((await page.locator(".faq details").first().getAttribute("open")) !== null) {
    pass("FAQ item opens");
  } else {
    fail("FAQ item opens");
  }

  await context.close();
}

/* ---------- operating system switch ---------- */

{
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(`${BASE}?os=linux`, { waitUntil: "networkidle" });

  const list = page.locator("#script-list");
  if ((await list.getAttribute("data-os")) === "linux") pass("list starts on Linux");
  else fail("initial OS", await list.getAttribute("data-os"));

  await page.getByRole("button", { name: "macOS", exact: true }).click();
  await page.waitForTimeout(120);
  if ((await list.getAttribute("data-os")) === "mac") pass("macOS switch updates the list");
  else fail("macOS switch", await list.getAttribute("data-os"));

  const macCommand = await page
    .locator(".script .variant[data-os='mac'] [data-cmd='mac/setup-skills.sh']")
    .textContent();
  if (macCommand.includes("/downloads/mac/setup-skills.sh"))
    pass("macOS command points at the mac download");
  else fail("macOS command", macCommand);

  const macHidden = await page.locator(".script .variant[data-os='linux']").first().isHidden();
  if (macHidden) pass("Linux variants are hidden while macOS is active");
  else fail("variant visibility", "linux variant still visible");

  const detail = await page.locator("a[data-detail='setup-skills']").getAttribute("href");
  if (detail === "scripts/setup-skills-mac.html") pass("detail link follows the OS");
  else fail("detail link", detail);

  if (new URL(page.url()).searchParams.get("os") === "mac") pass("OS choice is written to the URL");
  else fail("OS URL", page.url());

  await page.getByRole("button", { name: "Windows", exact: true }).click();
  await page.waitForTimeout(120);
  const winCommand = await page
    .locator(".script .variant[data-os='windows'] [data-cmd='windows/setup-skills.ps1']")
    .textContent();
  if (winCommand.startsWith("irm ") && winCommand.includes("setup-skills.ps1"))
    pass("Windows command uses irm and the .ps1 name");
  else fail("Windows command", winCommand);

  const tag = await page.locator("#s-setup-skills").locator("xpath=../..").locator("[data-tag]").textContent();
  if (tag.trim() === "no admin") pass("tags switch with the platform");
  else fail("OS tag", tag);

  const sudoVisible = await page.locator("#script-list .script[data-sudo='yes']:visible").count();
  if (sudoVisible === 3) pass("sudo filter data follows the platform (3 admin scripts on Windows)");
  else fail("sudo data", `${sudoVisible} rows marked yes`);

  await page.close();
}

/* ---------- SEO and social metadata ---------- */

{
  const page = await browser.newPage();
  await page.goto(BASE, { waitUntil: "networkidle" });
  const html = await page.content();
  const meta = (attr, key) => {
    const pattern = new RegExp(`<meta ${attr}="${key}" content="([^"]*)"`);
    return html.match(pattern)?.[1] || "";
  };

  const description = meta("name", "description");
  if (description.length > 0 && description.length <= 160)
    pass(`meta description is ${description.length} characters`);
  else fail("meta description", `${description.length} characters`);

  const canonical = html.match(/<link rel="canonical" href="([^"]*)"/)?.[1] || "";
  if (canonical === `${SITE.url}/`) pass("canonical URL is absolute and points at the site");
  else fail("canonical", canonical || "missing");

  if (meta("property", "og:url") === `${SITE.url}/`) pass("og:url is set");
  else fail("og:url", meta("property", "og:url") || "missing");

  const ogImage = meta("property", "og:image");
  if (ogImage === SITE.image && /^https:\/\//.test(ogImage)) pass("og:image is absolute");
  else fail("og:image", ogImage || "missing");

  if (meta("property", "og:site_name") === "Scripture") pass("og:site_name is set");
  else fail("og:site_name", meta("property", "og:site_name") || "missing");

  if (meta("property", "og:locale") === "en_US") pass("og:locale is set");
  else fail("og:locale", meta("property", "og:locale") || "missing");

  if (meta("name", "twitter:image") === SITE.image) pass("twitter:image is absolute");
  else fail("twitter:image", meta("name", "twitter:image") || "missing");

  const ico = await page.request.get(`${BASE}/favicon.ico`);
  if (ico.ok() && (ico.headers()["content-type"] || "").includes("image"))
    pass("favicon.ico is served as an image");
  else fail("favicon.ico", `${ico.status()} ${ico.headers()["content-type"] || ""}`);

  const pngIcon = await page.request.get(`${BASE}/favicon-32x32.png`);
  if (pngIcon.ok() && (pngIcon.headers()["content-type"] || "").includes("image/png"))
    pass("32px PNG favicon is served");
  else fail("favicon-32x32.png", `${pngIcon.status()}`);

  const appleIcon = await page.request.get(`${BASE}/apple-touch-icon.png`);
  if (appleIcon.ok()) pass("apple-touch-icon is served");
  else fail("apple-touch-icon", `${appleIcon.status()}`);

  const manifestResponse = await page.request.get(`${BASE}/manifest.json`);
  const manifest = manifestResponse.ok() ? await manifestResponse.json() : null;
  if (manifest && manifest.name && (manifest.icons || []).length >= 3)
    pass("web app manifest lists the icons");
  else fail("web app manifest", `${manifestResponse.status()}`);

  const detail = await page.request.get(`${BASE}/scripts/laravel-mac.html`);
  const detailHtml = await detail.text();
  const detailCanonical =
    detailHtml.match(/<link rel="canonical" href="([^"]*)"/)?.[1] || "";
  if (detailCanonical === `${SITE.url}/scripts/laravel-mac.html`)
    pass("detail page canonical is absolute");
  else fail("detail canonical", detailCanonical || "missing");

  const og = await page.request.get(`${BASE}/og.png`);
  const body = await og.body();
  if (og.ok() && body.length > 1000 && body[1] === 0x50 && body[2] === 0x4e)
    pass("og.png is a valid PNG on the site");
  else fail("og.png", `${og.status()}, ${body.length} bytes`);

  await page.close();
}

/* ---------- hero terminal demo ---------- */

{
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(BASE, { waitUntil: "networkidle" });

  const toggle = page.locator("[data-term-toggle]");
  const termBody = page.locator("[data-term-body]");
  const box = await toggle.boundingBox();
  if (box && Math.round(box.width) >= 24 && Math.round(box.height) >= 24)
    pass("demo pause control is at least 24x24");
  else fail("demo pause control", JSON.stringify(box));

  const typing = await termBody.innerText();
  await page.waitForTimeout(700);
  if ((await termBody.innerText()) !== typing) pass("hero terminal demo animates");
  else fail("hero terminal demo", "content did not change");

  await toggle.click();
  await page.waitForTimeout(500);
  const paused = await termBody.innerText();
  await page.waitForTimeout(800);
  if ((await termBody.innerText()) === paused) pass("demo pauses when asked");
  else fail("demo pause", "content kept changing");
  if ((await toggle.getAttribute("aria-pressed")) === "true")
    pass("pause control reports its state");
  else fail("pause state", await toggle.getAttribute("aria-pressed"));

  await toggle.click();
  await page.waitForTimeout(600);
  if ((await termBody.innerText()) !== paused) pass("demo restarts after pause");
  else fail("demo resume", "content did not change");
  await page.close();

  const reduced = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await reduced.emulateMedia({ reducedMotion: "reduce" });
  await reduced.goto(BASE, { waitUntil: "networkidle" });
  if ((await reduced.locator("[data-term-body]").innerText()).includes("INSTALL REPORT"))
    pass("reduced motion shows the final report instead of animating");
  else fail("reduced motion demo", "report missing");

  const play = reduced.locator("[data-term-toggle]");
  if ((await play.isVisible()) && (await play.getAttribute("aria-label")) === "Play the demo")
    pass("reduced motion offers a Play control");
  else fail("reduced motion play control", "missing or mislabeled");

  const beforePlay = await reduced.locator("[data-term-body]").innerText();
  await play.click();
  await reduced.waitForTimeout(900);
  if ((await reduced.locator("[data-term-body]").innerText()) !== beforePlay)
    pass("Play starts the animation for reduced motion");
  else fail("reduced motion play", "content did not change");
  await reduced.close();
}

/* ---------- demo follows the platform ---------- */

{
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(`${BASE}?os=linux`, { waitUntil: "networkidle" });
  if ((await page.locator(".term__shell").innerText()) === "bash")
    pass("demo uses bash on Linux");
  else fail("demo shell label", await page.locator(".term__shell").innerText());

  await page.locator('[data-os-set="windows"]').click();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(1800);
  const windowsText = await page.locator("[data-term-body]").innerText();
  if (windowsText.includes("irm setup-skills.ps1"))
    pass("demo switches to PowerShell on Windows");
  else fail("demo Windows command", windowsText.slice(0, 100));
  if ((await page.locator(".term__shell").innerText()) === "pwsh")
    pass("demo title bar switches to pwsh");
  else fail("demo shell label after switch", await page.locator(".term__shell").innerText());

  await page.locator('[data-os-set="linux"]').click();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(1200);
  if ((await page.locator("[data-term-body]").innerText()).includes("bash <(curl"))
    pass("demo switches back to bash on Linux");
  else fail("demo Linux command", "bash missing");
  await page.close();

  const reducedWindows = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await reducedWindows.emulateMedia({ reducedMotion: "reduce" });
  await reducedWindows.goto(`${BASE}?os=windows`, { waitUntil: "networkidle" });
  const staticWindows = await reducedWindows.locator("[data-term-body]").innerText();
  if (staticWindows.includes("PS>") && staticWindows.includes("setup-skills.ps1"))
    pass("static demo matches Windows");
  else fail("static Windows demo", staticWindows.slice(0, 100));
  await reducedWindows.close();
}

/* ---------- every link resolves ---------- */

{
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(`${BASE}?os=linux`, { waitUntil: "networkidle" });

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
  await page.goto(`${BASE}?os=linux`, { waitUntil: "networkidle" });

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

  if ((await page.getByRole("button", { name: "Uses sudo" }).getAttribute("aria-pressed")) === "true") {
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

  for (const script of SCRIPTS) {
    for (const os of OSES) {
      const variant = script.variants[os.id];
      const slug = `${script.slug}-${os.id}`;
      const response = await page.request.get(`${BASE}/scripts/${slug}.html`);
      const html = await response.text();
      const lines = manifest.files[variant.file].lines;

      if (response.ok()) pass(`page /scripts/${slug}`);
      else fail(`page /scripts/${slug}`, `status ${response.status()}`);

      if (html.includes('id="L1"') && html.includes(`id="L${lines}"`)) {
        pass(`line anchors 1-${lines} on ${slug}`);
      } else {
        fail(`line anchors ${slug}`, `missing L1 or L${lines}`);
      }
    }
  }

  await page.goto(`${BASE}/scripts/laravel-mac.html`, { waitUntil: "networkidle" });
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  );
  if (overflow === 0) pass("detail page has no overflow at 390px");
  else fail("detail overflow", `${overflow}px`);

  const label = await page.locator(".viewer").getAttribute("aria-label");
  if (label.includes("mac/setup-laravel.sh") && label.includes("500")) {
    pass("viewer names the file and line count");
  } else fail("viewer label", label);

  const tabs = await page.locator(".os-switch--page a").count();
  if (tabs === 3) pass("detail page offers three platform tabs");
  else fail("detail tabs", `${tabs} tabs`);

  await page.close();
}

/* ---------- narrow viewport, reduced motion, no JS ---------- */

{
  const page = await browser.newPage({ viewport: { width: 320, height: 640 } });
  await page.goto(`${BASE}?os=linux`, { waitUntil: "networkidle" });
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
  await page.goto(`${BASE}?os=linux`, { waitUntil: "networkidle" });
  const hidden = await page.evaluate(
    () =>
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

  const linuxVisible = await page.locator(".variant[data-os='linux']").first().isVisible();
  const winHidden = await page.locator(".variant[data-os='windows']").first().isHidden();
  if (linuxVisible && winHidden) pass("without JS the Linux download is the visible default");
  else fail("no JS platform default", `linux=${linuxVisible} windowsHidden=${winHidden}`);

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
  await page.goto(`${BASE}?os=linux`, { waitUntil: "networkidle" });

  const manifest = await (await page.request.get(`${BASE}/downloads/manifest.json`)).json();

  for (const [file, meta] of Object.entries(manifest.files)) {
    const response = await page.request.get(`${BASE}/downloads/${file}`);
    const hash = createHash("sha256").update(await response.body()).digest("hex");
    if (hash === meta.sha256) pass(`hash ${file}`);
    else fail(`hash ${file}`, "download does not match manifest");

    const disposition = response.headers()["content-disposition"] || "";
    if (disposition.includes(basename(file))) pass(`attachment header ${file}`);
    else fail(`attachment header ${file}`, disposition);
  }

  await page.close();
}

await browser.close();

console.log(failures.length ? `\n${failures.length} failure(s)` : "\nAll checks passed.");
process.exitCode = failures.length ? 1 : 0;
