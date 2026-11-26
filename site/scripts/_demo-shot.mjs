import { chromium } from "playwright-core";

const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || "/usr/bin/chromium",
  args: ["--no-sandbox", "--disable-gpu"],
});

async function shot(name, width, height, { reduced = false, waitFor = null } = {}) {
  const page = await browser.newPage({
    viewport: { width, height },
    deviceScaleFactor: 1,
    reducedMotion: reduced ? "reduce" : "no-preference",
  });
  await page.goto("http://127.0.0.1:3000/", { waitUntil: "networkidle" });
  if (waitFor) await page.locator(waitFor).waitFor({ timeout: 15000 });
  else await page.waitForTimeout(2600);
  await page.locator(".term").screenshot({ path: `/tmp/${name}.png` });
  console.log(name, await page.locator("[data-term-body]").innerText());
  await page.close();
}

await shot("demo-desktop-menu", 1440, 900);
await shot("demo-desktop-report", 1440, 900, { waitFor: ".t-panel" });
await shot("demo-mobile-menu", 390, 844);
await shot("demo-reduced", 1440, 900, { reduced: true });
await browser.close();
