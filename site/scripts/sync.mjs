#!/usr/bin/env node
// Copies every script variant from linux/, mac/ and windows/ into
// public/downloads/<os>/, hashes each file and writes manifest.json.
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { copyFile, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { SCRIPTS, OSES } from "./data.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const siteRoot = resolve(here, "..");
const repoRoot = resolve(siteRoot, "..");
const downloadsRoot = join(siteRoot, "public", "downloads");

function shortCommit() {
  try {
    return execFileSync("git", ["rev-parse", "--short", "HEAD"], {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "local";
  }
}

await mkdir(downloadsRoot, { recursive: true });

const files = {};

for (const os of OSES) {
  await mkdir(join(downloadsRoot, os.id), { recursive: true });
}

for (const script of SCRIPTS) {
  for (const os of OSES) {
    const variant = script.variants[os.id];
    if (!variant) throw new Error(`Missing ${os.id} variant for ${script.slug}`);

    const sourcePath = join(repoRoot, variant.source);
    const destPath = join(downloadsRoot, variant.file);
    const bytes = await readFile(sourcePath);
    const info = await stat(sourcePath);
    await copyFile(sourcePath, destPath);

    files[variant.file] = {
      os: os.id,
      slug: script.slug,
      source: variant.source,
      bytes: info.size,
      lines: bytes.toString("utf8").split("\n").length - (bytes.at(-1) === 10 ? 1 : 0),
      sha256: createHash("sha256").update(bytes).digest("hex"),
      updatedAt: info.mtime.toISOString(),
    };
  }
}

const manifest = {
  generatedAt: new Date().toISOString(),
  commit: shortCommit(),
  platforms: OSES.map((os) => ({ id: os.id, label: os.label })),
  files,
};

await writeFile(
  join(downloadsRoot, "manifest.json"),
  JSON.stringify(manifest, null, 2) + "\n"
);

for (const [file, meta] of Object.entries(files)) {
  console.log(
    `${file.padEnd(34)} ${String(meta.lines).padStart(6)} lines  ${meta.sha256.slice(0, 12)}`
  );
}
console.log(
  `manifest written to public/downloads/manifest.json (${Object.keys(files).length} files, commit ${manifest.commit})`
);
