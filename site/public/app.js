// Small, dependency free behaviours. Everything degrades without JS.
(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const status = document.getElementById("copy-status");

  const say = (message) => {
    if (status) status.textContent = message;
  };

  /* ---------- downloads: command text + metadata ---------- */

  const downloadsBase = document.body.dataset.downloads || "downloads/";
  const downloadUrl = (file) => new URL(`${downloadsBase}${file}`, location.href).href;
  const basename = (file) => file.split("/").pop();

  const OSES = ["linux", "mac", "windows"];

  const commandFor = (file) => {
    const url = downloadUrl(file);
    if (file.endsWith(".ps1")) {
      const name = basename(file);
      return `irm ${url} -OutFile ${name}; .\\${name}`;
    }
    return `bash <(curl -fsSL ${url})`;
  };

  const renderCommands = () => {
    document.querySelectorAll("[data-cmd]").forEach((node) => {
      node.textContent = commandFor(node.dataset.cmd);
    });
  };

  const detectOs = () => {
    const hint = (
      navigator.userAgentData?.platform ||
      navigator.platform ||
      navigator.userAgent ||
      ""
    ).toLowerCase();
    if (hint.includes("win")) return "windows";
    if (hint.includes("mac")) return "mac";
    return "linux";
  };

  const requested = new URLSearchParams(location.search).get("os");
  let currentOs = OSES.includes(requested) ? requested : detectOs();

  const osButtons = [...document.querySelectorAll("[data-os-set]")];
  const scriptList = document.getElementById("script-list");

  let applyFilters = () => {};

  function setOs(os, updateUrl = true) {
    if (!OSES.includes(os)) os = "linux";
    currentOs = os;

    if (scriptList) scriptList.dataset.os = os;
    osButtons.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.osSet === os));
    });

    document.querySelectorAll("[data-detail]").forEach((link) => {
      link.href = `scripts/${link.dataset.detail}-${os}.html`;
    });

    document.querySelectorAll("#script-list .script").forEach((row) => {
      const sudo = row.dataset[`sudo${os[0].toUpperCase()}${os.slice(1)}`];
      if (sudo) row.dataset.sudo = sudo;
      const tag = row.dataset[`tag${os[0].toUpperCase()}${os.slice(1)}`];
      const tagNode = row.querySelector("[data-tag]");
      if (tagNode && tag) {
        tagNode.textContent = tag;
        tagNode.classList.toggle("tag--warn", row.dataset.sudo === "yes");
      }
    });

    renderCommands();
    applyFilters();

    if (updateUrl) {
      const next = new URLSearchParams(location.search);
      next.set("os", os);
      history.replaceState(null, "", `${location.pathname}?${next.toString()}${location.hash}`);
    }
  }

  osButtons.forEach((button) => {
    button.addEventListener("click", () => setOs(button.dataset.osSet));
  });

  renderCommands();

  fetch(new URL(`${downloadsBase}manifest.json`, location.href), { cache: "no-cache" })
    .then((response) => (response.ok ? response.json() : Promise.reject(new Error("no manifest"))))
    .then((manifest) => {
      Object.entries(manifest.files || {}).forEach(([file, meta]) => {
        document.querySelectorAll(`[data-meta="${file}"]`).forEach((node) => {
          const kb = Math.max(1, Math.round(meta.bytes / 1024));
          const lines = Number(meta.lines).toLocaleString("en-US");
          node.textContent = `${lines} lines · ${kb} KB · sha256 ${meta.sha256.slice(0, 12)}`;
        });
      });

      const totalLines = Object.values(manifest.files || {}).reduce(
        (sum, meta) => sum + Number(meta.lines || 0),
        0
      );
      document.querySelectorAll("[data-total-lines]").forEach((node) => {
        node.textContent = totalLines.toLocaleString("en-US");
      });

      const sync = document.querySelector("[data-sync]");
      if (sync) {
        const date = new Date(manifest.generatedAt);
        const stamp = date.toLocaleDateString("en-GB", {
          day: "numeric",
          month: "short",
          year: "numeric",
        });
        sync.textContent =
          manifest.commit === "local"
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
        await copyText(commandFor(file));
        if (label) label.textContent = "Copied";
        say(`Install command for ${basename(file)} copied to the clipboard.`);
      } catch {
        if (label) label.textContent = "Copy failed";
        say(`Copy failed. Select the command for ${basename(file)} and copy it manually.`);
      } finally {
        button.disabled = false;
        clearTimeout(resetTimer);
        resetTimer = setTimeout(() => {
          if (label) label.textContent = original;
        }, 1800);
      }
    });
  });

  /* ---------- search and filters ---------- */

  const searchInput = document.getElementById("script-search");
  const filterButtons = [...document.querySelectorAll("[data-filter]")];
  const scriptRows = [...document.querySelectorAll("#script-list .script")];
  const filterCount = document.getElementById("filter-count");
  const emptyState = document.getElementById("script-empty");
  const clearFilters = document.getElementById("clear-filters");

  if (searchInput && filterCount && scriptRows.length) {
    const buildSearchIndex = () => {
      scriptRows.forEach((row) => {
        const variant = row.querySelector(`.variant[data-os="${currentOs}"]`);
        const detail = variant ? variant.textContent : "";
        row.dataset.search = `${row.querySelector("h3")?.textContent || ""} ${detail}`
          .replace(/\s+/g, " ")
          .trim()
          .toLowerCase();
      });
    };

    let privilege = "all";
    const params = new URLSearchParams(location.search);
    if (params.get("q")) searchInput.value = params.get("q");
    if (["no", "yes"].includes(params.get("sudo"))) privilege = params.get("sudo");

    const apply = (updateUrl = true) => {
      const terms = searchInput.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
      let shown = 0;

      scriptRows.forEach((row) => {
        const matchesTerms = terms.every((term) => row.dataset.search.includes(term));
        const matchesPrivilege = privilege === "all" || row.dataset.sudo === privilege;
        const visible = matchesTerms && matchesPrivilege;
        row.hidden = !visible;
        if (visible) shown += 1;
      });

      filterButtons.forEach((button) => {
        button.setAttribute("aria-pressed", String(button.dataset.filter === privilege));
      });

      filterCount.textContent =
        shown === scriptRows.length
          ? `${scriptRows.length} scripts`
          : `${shown} of ${scriptRows.length} scripts`;
      if (emptyState) emptyState.hidden = shown !== 0;

      if (updateUrl) {
        const next = new URLSearchParams();
        if (searchInput.value.trim()) next.set("q", searchInput.value.trim());
        if (privilege !== "all") next.set("sudo", privilege);
        next.set("os", currentOs);
        history.replaceState(
          null,
          "",
          `${location.pathname}?${next.toString()}${location.hash}`
        );
      }
    };

    const buildAndApply = (updateUrl = true) => {
      buildSearchIndex();
      apply(updateUrl);
    };

    applyFilters = () => {
      if (!scriptRows.length) return;
      buildSearchIndex();
      apply(false);
    };

    searchInput.addEventListener("input", () => buildAndApply());

    filterButtons.forEach((button) => {
      button.addEventListener("click", () => {
        privilege = button.dataset.filter;
        buildAndApply();
      });
    });

    clearFilters?.addEventListener("click", () => {
      searchInput.value = "";
      privilege = "all";
      buildAndApply();
      searchInput.focus();
    });

    buildAndApply(false);
  }

  setOs(currentOs, false);

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
