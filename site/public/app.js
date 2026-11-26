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

  // Set by the hero terminal demo so the platform switch can retarget it.
  let demoSyncOs = null;

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
    demoSyncOs?.(os);

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

  /* ---------- hero terminal: a replay of the setup-skills script ---------- */

  const termDemo = document.querySelector("[data-term-demo]");
  if (termDemo) {
    const termBody = termDemo.querySelector("[data-term-body]");
    const termToggle = termDemo.querySelector("[data-term-toggle]");
    const termShell = termDemo.querySelector("[data-term-shell]");

    const shellFor = (os) => (os === "windows" ? "pwsh" : "bash");
    const promptFor = (os) => (os === "windows" ? "PS>" : "$");
    const commandsFor = (os) =>
      os === "windows"
        ? ["irm setup-skills.ps1 -OutFile setup-skills.ps1", ".\\setup-skills.ps1"]
        : ["bash <(curl -fsSL setup-skills.sh)"];

    const paintStaticCommand = (os) => {
      termShell.textContent = shellFor(os);
      termDemo.querySelectorAll("[data-term-static-prompt]").forEach((prompt) => {
        prompt.textContent = promptFor(os);
      });

      const first = termDemo.querySelector("[data-term-static-cmd]");
      if (!first) return;
      const old = [...termDemo.querySelectorAll("[data-term-static-cmd]")];
      const lines = commandsFor(os).map((command) => {
        const line = document.createElement("p");
        line.className = "t-line t-cmd";
        line.dataset.termStaticCmd = "";
        const prompt = document.createElement("span");
        prompt.className = "t-prompt";
        prompt.textContent = promptFor(os);
        line.append(prompt, ` ${command}`);
        return line;
      });
      old[0].replaceWith(...lines);
      old.slice(1).forEach((line) => line.remove());
    };

    const make = (html) => {
      const template = document.createElement("template");
      template.innerHTML = html.trim();
      return template.content.firstElementChild;
    };
    const scrollTerm = () => {
      termBody.scrollTop = termBody.scrollHeight;
    };
    const addLine = (node) => {
      termBody.append(node);
      scrollTerm();
      return node;
    };
    const stepLine = (key, label) => {
      const line = make(
        '<p class="t-step"><span class="t-key">❯</span> <span class="t-step__key"></span><span class="t-step__label"></span></p>'
      );
      line.querySelector(".t-step__key").textContent = key ? `${key} ` : "";
      line.querySelector(".t-step__label").textContent = label;
      return line;
    };
    const okLine = (label) => {
      const line = make(
        '<p class="t-line t-ok"><svg class="i" aria-hidden="true"><use href="#i-check"/></svg><span></span></p>'
      );
      line.querySelector("span").textContent = label;
      return line;
    };

    let demoRun = 0;
    let demoSession = 0;
    let wake = null;
    let spinning = null;
    let playing = false;
    let userPaused = false;
    let demoStarted = false;
    let demoOs = currentOs;
    let inView = true;

    const wait = (ms) =>
      new Promise((resolve) => {
        const id = setTimeout(resolve, ms);
        wake = () => {
          clearTimeout(id);
          resolve();
        };
      });

    const runDemo = async () => {
      const current = ++demoRun;
      const alive = () => current === demoRun;

      while (alive()) {
        termBody.textContent = "";
        termBody.scrollTop = 0;

        const commands = commandsFor(demoOs);
        for (const [index, command] of commands.entries()) {
          const cmd = addLine(
            make(
              `<p class="t-line t-cmd"><span class="t-prompt">${promptFor(demoOs)}</span> <span data-term-typed></span><span class="t-cursor"></span></p>`
            )
          );
          const typed = cmd.querySelector("[data-term-typed]");
          for (const char of command) {
            if (!alive()) return;
            typed.textContent += char;
            scrollTerm();
            await wait(22);
          }
          if (index < commands.length - 1) {
            await wait(220);
            if (!alive()) return;
            cmd.querySelector(".t-cursor")?.remove();
          } else {
            await wait(550);
            if (!alive()) return;
            cmd.querySelector(".t-cursor")?.remove();
          }
        }

        addLine(
          make(
            '<div class="t-head"><p class="t-title">Setup skills</p><p class="t-sub">design + engineering skills installer</p></div>'
          )
        );
        addLine(stepLine("1/5", "Design System - choose your design"));
        await wait(300);
        if (!alive()) return;
        addLine(make('<p class="t-line t-meta">Found 214 design systems</p>'));

        const menu = addLine(
          make(
            '<ul class="t-menu"><li class="is-active">Vercel</li><li>Linear</li><li>Apple</li><li>Stripe</li></ul>'
          )
        );
        const hint = addLine(make('<p class="t-hint">↑↓ move · Enter select</p>'));
        await wait(750);
        if (!alive()) return;

        const items = [...menu.children];
        for (const index of [1, 2]) {
          items.forEach((item) => item.classList.remove("is-active"));
          items[index].classList.add("is-active");
          await wait(420);
          if (!alive()) return;
        }
        await wait(300);
        if (!alive()) return;

        menu.remove();
        hint.remove();
        addLine(okLine("DESIGN.md for 'Apple' copied to project root"));
        await wait(550);
        if (!alive()) return;

        addLine(stepLine("2/5", "Installing: Impeccable"));
        const task = addLine(
          make('<p class="t-line t-task"><span class="t-braille">⠋</span> <span></span></p>')
        );
        task.querySelector("span:last-child").textContent = "Running npx skills add";
        let frame = 0;
        spinning = setInterval(() => {
          task.querySelector(".t-braille").textContent =
            "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[frame++ % 10];
        }, 80);
        await wait(1200);
        clearInterval(spinning);
        spinning = null;
        if (!alive()) return;
        task.remove();
        addLine(okLine("Impeccable installed (verified: impeccable)"));
        await wait(420);
        if (!alive()) return;

        for (const [key, label, done] of [
          ["3/5", "Installing: Taste Skill", "Taste Skill installed"],
          [
            "4/5",
            "Installing: Vercel Web Design Guidelines",
            "Vercel Web Design Guidelines installed",
          ],
        ]) {
          addLine(stepLine(key, label));
          await wait(420);
          if (!alive()) return;
          addLine(okLine(done));
          await wait(300);
          if (!alive()) return;
        }

        addLine(stepLine("5/5", "Playwright MCP"));
        await wait(380);
        if (!alive()) return;
        addLine(okLine("Created .mcp.json with Playwright MCP"));
        await wait(500);
        if (!alive()) return;

        addLine(stepLine("", "SUMMARY"));
        const panel = make(
          '<div class="t-panel"><p class="t-panel__title">INSTALL REPORT</p></div>'
        );
        for (const row of [
          "Folder: ~/projects/acme",
          "DESIGN.md (design system)",
          "CLAUDE.md (agent rules)",
          "Playwright MCP (.mcp.json)",
          "skill-instructions.md",
          "Skill: Impeccable",
        ]) {
          const line = document.createElement("p");
          const flag = document.createElement("span");
          flag.className = "t-flag";
          flag.textContent = "[OK]";
          line.append(flag, row);
          panel.append(line);
        }
        addLine(panel);
        addLine(make('<p class="t-line t-note">ALL DONE - NEXT STEPS</p>'));
        addLine(make('<p class="t-line t-hint">1. Start your AI agent in this folder</p>'));
        addLine(
          make(
            `<p class="t-line t-last"><span class="t-prompt">${promptFor(demoOs)}</span> <span class="t-cursor"></span></p>`
          )
        );
        await wait(2800);
      }
    };

    const startDemo = () => {
      if (playing || userPaused || !inView || document.hidden) return;
      const session = ++demoSession;
      demoStarted = true;
      termDemo.classList.add("is-live");
      playing = true;
      runDemo().finally(() => {
        if (session === demoSession) playing = false;
      });
    };

    const stopDemo = () => {
      demoSession += 1;
      demoRun += 1;
      playing = false;
      if (wake) wake();
      if (spinning) {
        clearInterval(spinning);
        spinning = null;
      }
    };

    termToggle?.addEventListener("click", () => {
      userPaused = !userPaused;
      termToggle.setAttribute("aria-pressed", String(userPaused));
      termToggle.setAttribute(
        "aria-label",
        userPaused ? "Play the demo" : "Pause the demo"
      );
      termDemo.classList.toggle("is-paused", userPaused);
      if (userPaused) {
        stopDemo();
      } else {
        startDemo();
      }
    });

    if ("IntersectionObserver" in window) {
      const demoObserver = new IntersectionObserver(
        ([entry]) => {
          inView = entry.isIntersecting;
          if (!inView) stopDemo();
          else if (!userPaused) startDemo();
        },
        { threshold: 0.25 }
      );
      demoObserver.observe(termDemo);
    }

    document.addEventListener("visibilitychange", () => {
      if (document.hidden) stopDemo();
      else if (!userPaused && inView) startDemo();
    });

    demoSyncOs = (os) => {
      if (os === demoOs) return;
      demoOs = os;
      termShell.textContent = shellFor(os);

      if (!demoStarted) {
        paintStaticCommand(os);
        return;
      }

      const wasPaused = userPaused;
      stopDemo();
      if (wasPaused) {
        userPaused = false;
        termToggle?.setAttribute("aria-pressed", "false");
        termToggle?.setAttribute("aria-label", "Pause the demo");
        termDemo.classList.remove("is-paused");
      }
      startDemo();
    };

    if (reduceMotion) {
      paintStaticCommand(currentOs);
      userPaused = true;
      termToggle?.setAttribute("aria-pressed", "true");
      termToggle?.setAttribute("aria-label", "Play the demo");
      termDemo.classList.add("is-paused");
    } else {
      paintStaticCommand(currentOs);
      startDemo();
    }
  }

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
