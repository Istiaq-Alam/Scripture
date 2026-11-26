#!/usr/bin/env node
// Renders scripts/og.html to public/og.png at 1200x630.
import { chromium } from "playwright-core";

const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || "/usr/bin/chromium",
  args: ["--no-sandbox", "--disable-gpu"],
});

const page = await browser.newPage({
  viewport: { width: 1200, height: 630 },
  deviceScaleFactor: 1,
});

await page.goto(new URL("./og.html", import.meta.url).href, { waitUntil: "networkidle" });
await page.evaluate(() => document.fonts.ready);
await page.waitForTimeout(400);
await page.screenshot({ path: new URL("../public/og.png", import.meta.url).pathname });

await browser.close();
console.log("wrote public/og.png");
