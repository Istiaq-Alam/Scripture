#!/usr/bin/env node
// Copies the installers from the repo root into public/downloads, hashes each
// one and writes manifest.json so the page can show real sizes and checksums.
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { copyFile, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const siteRoot = resolve(here, "..");
const repoRoot = resolve(siteRoot, "..");
const outDir = join(siteRoot, "public", "downloads");

// source name in the repo -> name served to visitors
const SCRIPTS = [
  ["Setup-skills.sh", "setup-skills.sh"],
  ["setup-laravel.sh", "setup-laravel.sh"],
  ["setup-freebuff-zsh.sh", "setup-freebuff-zsh.sh"],
  ["gitcli.sh", "gitcli.sh"],
  ["ClaudeCode.sh", "ClaudeCode.sh"],
];

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

await mkdir(outDir, { recursive: true });

const files = {};

for (const [sourceName, name] of SCRIPTS) {
  const source = join(repoRoot, sourceName);
  const bytes = await readFile(source);
  const info = await stat(source);
  await copyFile(source, join(outDir, name));

  files[name] = {
    bytes: info.size,
    lines: bytes.toString("utf8").split("\n").length - (bytes.at(-1) === 10 ? 1 : 0),
    sha256: createHash("sha256").update(bytes).digest("hex"),
    updatedAt: info.mtime.toISOString(),
  };
}

const manifest = {
  generatedAt: new Date().toISOString(),
  commit: shortCommit(),
  files,
};

await writeFile(join(outDir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");

for (const [name, meta] of Object.entries(files)) {
  console.log(`${name.padEnd(24)} ${String(meta.lines).padStart(6)} lines  ${meta.sha256.slice(0, 12)}`);
}
console.log(`manifest written to public/downloads/manifest.json (commit ${manifest.commit})`);
