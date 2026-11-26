// Small, dependency free behaviours. Everything degrades without JS.
(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const status = document.getElementById("copy-status");

  const say = (message) => {
    if (status) status.textContent = message;
  };

  /* ---------- downloads: command text + metadata ---------- */

  const origin = location.origin && location.origin !== "null" ? location.origin : "";

  document.querySelectorAll("[data-cmd]").forEach((node) => {
    const file = node.dataset.cmd;
    node.textContent = `bash <(curl -fsSL ${origin}/downloads/${file})`;
  });

  fetch("/downloads/manifest.json", { cache: "no-cache" })
    .then((response) => (response.ok ? response.json() : Promise.reject(new Error("no manifest"))))
    .then((manifest) => {
      Object.entries(manifest.files || {}).forEach(([file, meta]) => {
        document.querySelectorAll(`[data-meta="${file}"]`).forEach((node) => {
          const kb = Math.max(1, Math.round(meta.bytes / 1024));
          const lines = Number(meta.lines).toLocaleString("en-US");
          node.textContent = `${lines} lines · ${kb} KB · sha256 ${meta.sha256.slice(0, 12)}`;
        });
      });

      const sync = document.querySelector("[data-sync]");
      if (sync) {
        const date = new Date(manifest.generatedAt);
        const stamp = date.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
        sync.textContent = manifest.commit === "local"
          ? `Local build · ${stamp}`
          : `Synced ${stamp} · commit ${manifest.commit}`;
      }
    })
    .catch(() => {
      document.querySelectorAll("[data-meta]").forEach((node) => {
        node.textContent = "Hash unavailable in this preview";
      });
    });

  /* ---------- copy buttons ---------- */

  async function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    const ok = document.execCommand("copy");
    document.body.removeChild(area);
    if (!ok) throw new Error("copy failed");
  }

  document.querySelectorAll("[data-copy]").forEach((button) => {
    const label = button.querySelector("span");
    const original = label ? label.textContent : "Copy command";
    let resetTimer;

    button.addEventListener("click", async () => {
      const file = button.dataset.copy;
      button.disabled = true;
      if (label) label.textContent = "Copying…";

      try {
        await copyText(`bash <(curl -fsSL ${origin}/downloads/${file})`);
        if (label) label.textContent = "Copied";
        say(`Install command for ${file} copied to the clipboard.`);
      } catch {
        if (label) label.textContent = "Copy failed";
        say(`Copy failed. Select the command for ${file} and copy it manually.`);
      } finally {
        button.disabled = false;
        clearTimeout(resetTimer);
        resetTimer = setTimeout(() => {
          if (label) label.textContent = original;
        }, 1800);
      }
    });
  });

  /* ---------- mobile menu ---------- */

  const menu = document.getElementById("mobile-menu");
  const openButton = document.getElementById("menu-open");
  const closeButton = document.getElementById("menu-close");

  const setMenu = (open) => {
    if (!menu || !openButton) return;
    menu.classList.toggle("is-open", open);
    menu.setAttribute("aria-hidden", String(!open));
    openButton.setAttribute("aria-expanded", String(open));
    document.body.classList.toggle("menu-open", open);

    if (open) {
      const first = menu.querySelector("a");
      if (first) first.focus({ preventScroll: true });
    } else {
      openButton.focus({ preventScroll: true });
    }
  };

  openButton?.addEventListener("click", () => setMenu(true));
  closeButton?.addEventListener("click", () => setMenu(false));
  menu?.querySelectorAll("a").forEach((link) => link.addEventListener("click", () => setMenu(false)));
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && menu?.classList.contains("is-open")) setMenu(false);
  });
  window.matchMedia("(min-width: 900px)").addEventListener("change", (event) => {
    if (event.matches && menu?.classList.contains("is-open")) setMenu(false);
  });

  /* ---------- reveals ---------- */

  const revealTargets = document.querySelectorAll(".section, .cta");
  if (!reduceMotion && "IntersectionObserver" in window) {
    revealTargets.forEach((node) => node.classList.add("will-reveal"));
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-in");
          observer.unobserve(entry.target);
        });
      },
      { threshold: 0.08, rootMargin: "0px 0px -8% 0px" }
    );
    revealTargets.forEach((node) => observer.observe(node));
  }

  /* ---------- tagline, one word at a time ---------- */

  const tagline = document.querySelector("[data-words]");
  if (tagline && !reduceMotion && "IntersectionObserver" in window) {
    const text = tagline.textContent.trim();
    tagline.textContent = "";
    tagline.classList.add("is-split");

    const words = text.split(/\s+/);
    const nodes = words.map((word, index) => {
      const span = document.createElement("span");
      span.className = "word";
      span.textContent = index === words.length - 1 ? word : word + " ";
      tagline.appendChild(span);
      return span;
    });

    const wordObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-lit");
          wordObserver.unobserve(entry.target);
        });
      },
      { threshold: 0, rootMargin: "0px 0px -20% 0px" }
    );
    nodes.forEach((node) => wordObserver.observe(node));
  }
})();
