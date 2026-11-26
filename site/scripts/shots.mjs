#!/usr/bin/env node
// Browser QA for the site. Requires the dev server on :3000.
//   node scripts/shots.mjs
import { chromium } from "playwright-core";
import { mkdir } from "node:fs/promises";

const BASE = process.env.SITE_URL || "http://127.0.0.1:3000/";
const CHROME = process.env.CHROME_PATH || "/usr/bin/chromium";
const OUT = new URL("../shots/", import.meta.url).pathname;

await mkdir(OUT, { recursive: true });

const browser = await chromium.launch({
  executablePath: CHROME,
  args: ["--no-sandbox", "--disable-gpu"],
});

const problems = [];

async function capture(name, width, height, fullPage, query = "") {
  const page = await browser.newPage({
    viewport: { width, height },
    deviceScaleFactor: 1,
    reducedMotion: "reduce",
  });

  page.on("console", (message) => {
    if (message.type() === "error") problems.push(`${name} console: ${message.text()}`);
  });
  page.on("pageerror", (error) => problems.push(`${name} page: ${error.message}`));
  page.on("requestfailed", (request) => {
    problems.push(`${name} request failed: ${request.url()}`);
  });

  await page.goto(BASE + query, { waitUntil: "networkidle" });

  // Walk the page so every IntersectionObserver reveal has fired.
  await page.evaluate(async () => {
    const step = Math.round(window.innerHeight * 0.75);
    for (let y = 0; y < document.body.scrollHeight; y += step) {
      window.scrollTo(0, y);
      await new Promise((resolve) => setTimeout(resolve, 140));
    }
    window.scrollTo(0, document.body.scrollHeight);
    await new Promise((resolve) => setTimeout(resolve, 1200));
    window.scrollTo(0, 0);
    await new Promise((resolve) => setTimeout(resolve, 300));
  });
  await page.waitForTimeout(700);

  const metrics = await page.evaluate(() => ({
    overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    title: document.title,
    hiddenSections: [...document.querySelectorAll("main section")]
      .filter((node) => Number(getComputedStyle(node).opacity) < 0.9)
      .map((node) => node.id || node.getAttribute("aria-labelledby") || node.className),
    smallTargets: [...document.querySelectorAll("a, button, summary")]
      .filter((node) => {
        const rect = node.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0 && (rect.width < 24 || rect.height < 24);
      })
      .map((node) => node.textContent.trim().slice(0, 40)),
  }));

  await page.screenshot({ path: `${OUT}${name}.png`, fullPage });

  console.log(
    `${name.padEnd(8)} ${width}x${height} overflowX=${metrics.overflowX} hiddenSections=${JSON.stringify(metrics.hiddenSections)} smallTargets=${metrics.smallTargets.length ? JSON.stringify(metrics.smallTargets) : 0}`
  );

  await page.close();
}

async function captureSection(name, width, height, selector, query = "") {
  const page = await browser.newPage({
    viewport: { width, height },
    deviceScaleFactor: 1,
    reducedMotion: "reduce",
  });
  await page.goto(BASE + query, { waitUntil: "networkidle" });
  const section = page.locator(selector);
  await section.scrollIntoViewIfNeeded();
  await page.waitForTimeout(900);
  await section.screenshot({ path: `${OUT}${name}.png` });
  await page.close();
  console.log(`${name.padEnd(16)} section ${selector}`);
}

await capture("desktop", 1440, 900, false);
await capture("full", 1440, 900, true);
await capture("tablet", 820, 1180, true);
await capture("mobile", 390, 844, true);
await capture("full-windows", 1440, 900, true, "?os=windows");
await capture("mobile-windows", 390, 844, true, "?os=windows");

await captureSection("mobile-scripts", 390, 844, "#scripts");
await captureSection("mobile-safety", 390, 844, "#safety");
await captureSection("mobile-faq", 390, 844, "#faq");
await captureSection("desktop-scripts", 1440, 900, "#scripts");
await captureSection("desktop-scripts-windows", 1440, 900, "#scripts", "?os=windows");
await captureSection("desktop-scripts-mac", 1440, 900, "#scripts", "?os=mac");

await browser.close();

if (problems.length) {
  console.log("\nProblems:");
  for (const problem of problems) console.log(`- ${problem}`);
  process.exitCode = 1;
} else {
  console.log("\nNo console errors or failed requests.");
}
