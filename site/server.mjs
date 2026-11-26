#!/usr/bin/env node
// Small static server for the site. No dependencies, no framework.
//   npm start   -> syncs downloads, then serves http://localhost:3000
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { dirname, extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const PUBLIC = resolve(here, "public");
const PORT = Number(process.env.PORT || 3000);

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".ico": "image/x-icon",
  ".sh": "text/x-shellscript; charset=utf-8",
  ".ps1": "text/plain; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
};

function resolveFile(pathname) {
  const clean = decodeURIComponent(pathname.split("?")[0]);
  const target = resolve(PUBLIC, "." + clean);

  // Refuse anything that escapes public/.
  if (target !== PUBLIC && !target.startsWith(PUBLIC + sep)) return null;
  return target;
}

async function findFile(target) {
  const candidates = [];

  if (target.endsWith(sep)) candidates.push(join(target, "index.html"));
  else {
    if (extname(target)) candidates.push(target);
    candidates.push(target + ".html", join(target, "index.html"));
  }

  for (const candidate of candidates) {
    try {
      const info = await stat(candidate);
      if (info.isFile()) return { path: candidate, size: info.size };
    } catch {
      // try the next candidate
    }
  }
  return null;
}

const server = createServer(async (req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405, { Allow: "GET, HEAD", "Content-Type": "text/plain; charset=utf-8" });
    res.end("Method not allowed");
    return;
  }

  const target = resolveFile(req.url || "/");
  if (!target) {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Bad request");
    return;
  }

  const found = await findFile(target, req.url || "/");
  const ext = found ? extname(found.path) : "";

  if (!found) {
    const notFound = await readFile(join(PUBLIC, "404.html")).catch(() => null);
    res.writeHead(404, {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-cache",
    });
    res.end(req.method === "HEAD" ? undefined : notFound || "Not found");
    return;
  }

  const body = await readFile(found.path);
  const headers = {
    "Content-Type": TYPES[ext] || "application/octet-stream",
    "Content-Length": found.size,
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Cache-Control": ext === ".html" ? "no-cache" : "public, max-age=300",
  };

  if (ext === ".sh" || ext === ".ps1") {
    headers["Content-Disposition"] = `attachment; filename="${found.path.split(sep).pop()}"`;
  }

  res.writeHead(200, headers);
  res.end(req.method === "HEAD" ? undefined : body);

  if (process.env.QUIET !== "1") {
    console.log(`${res.statusCode} ${req.method} ${req.url}`);
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`Serving ${PUBLIC}`);
  console.log(`http://localhost:${PORT}`);
});
