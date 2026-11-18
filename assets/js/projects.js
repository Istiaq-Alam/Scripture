/**
 * projects.js
 * Renders project rows (table) from projectsData and wires up:
 *  - top status pills (all / ongoing / completed)   -> single-select
 *  - top keyword search box                         -> free text
 *  - top year dropdown + sidebar year checkboxes    -> synced (dropdown quick-select)
 *  - sidebar development-partner checkboxes         -> multi-select (OR)
 *  - sidebar location checkboxes                    -> multi-select (OR)
 * All active filters combine with AND across groups.
 */

class ProjectsFilter {
  constructor(data, els) {
    this.data = data;
    this.grid = els.grid; // <tbody>
    this.noResults = els.noResults;
    this.yearList = els.yearList;
    this.partnerList = els.partnerList;
    this.locationList = els.locationList;
    this.statusButtons = els.statusButtons;
    this.searchInput = els.searchInput;
    this.yearSelect = els.yearSelect;
    this.pagination = els.pagination;

    // pagination: 20 projects per page
    this.pageSize = 20;
    this.page = 1;

    this.state = {
      status: "all",
      locations: new Set(),
      years: new Set(),
      partners: new Set(),
      query: "",
    };

    this._searchTimer = null;

    this.init();
  }

  init() {
    this.renderFilterList(this.yearList, this.getUniqueCounts("year"), "year");
    this.renderFilterList(
      this.partnerList,
      this.getUniqueCounts("donorganization", "partner"),
      "partner",
    );
    this.renderFilterList(
      this.locationList,
      this.getUniqueCounts("location"),
      "location",
    );
    this.populateYearDropdown();
    this.bindStatusButtons();
    this.readStatusFromUrl();
    this.bindLists();
    this.bindYearDropdown();
    this.bindSearch();
    this.bindPagination();
    this.updateTriggerLabels();
    this.render();
  }

  /**
   * Update the trigger buttons of the stacked top dropdown filters:
   * the status label mirrors the selected option, Year/Location/Partners
   * show a count badge of how many options are checked, and triggers
   * with an active filter get the highlighted "has-filter" style.
   */
  updateTriggerLabels() {
    // Status — label mirrors the currently selected option
    const statusDd = document.getElementById("ddStatus");
    const active = this.statusButtons
      ? Array.from(this.statusButtons).find((b) =>
          b.classList.contains("is-active"),
        )
      : null;
    if (statusDd && active) {
      const label = statusDd.querySelector(".filter-dd__label");
      if (label) {
        label.textContent =
          active.dataset.status === "all"
            ? "All statuses"
            : active.textContent.trim();
      }
      statusDd.classList.toggle("has-filter", this.state.status !== "all");
    }

    // Multi-select filters — count badge
    const sync = (ddId, set) => {
      const dd = document.getElementById(ddId);
      if (!dd) return;
      const badge = dd.querySelector(".filter-dd__count");
      if (badge) {
        badge.textContent = set.size;
        badge.hidden = set.size === 0;
      }
      dd.classList.toggle("has-filter", set.size > 0);
    };
    sync("ddYear", this.state.years);
    sync("ddLocation", this.state.locations);
    sync("ddPartner", this.state.partners);
  }

  /**
   * Unique values with row counts.
   * `fallbackValue` is used when a project misses the field (e.g. no partner).
   */
  getUniqueCounts(field, fallbackValue) {
    const counts = new Map();
    this.data.forEach((project) => {
      const value = project[field] || fallbackValue || "—";
      counts.set(value, (counts.get(value) || 0) + 1);
    });

    const sorted = [...counts.entries()].sort((a, b) => {
      return typeof a[0] === "number" && typeof b[0] === "number"
        ? b[0] - a[0] // years, newest first
        : String(a[0]).localeCompare(String(b[0]));
    });

    return sorted;
  }

  renderFilterList(listEl, entries, type) {
    if (!listEl) return;
    listEl.innerHTML = entries
      .map(
        ([value, count]) => `
      <li>
        <label class="filter-option">
          <span class="filter-option__label">
            <input type="checkbox" data-filter-type="${type}" value="${value}">
            ${value}
          </span>
          <span class="filter-option__count">(${count})</span>
        </label>
      </li>
    `,
      )
      .join("");
  }

  populateYearDropdown() {
    if (!this.yearSelect) return;
    const years = [...new Set(this.data.map((p) => p.year))]
      .filter((y) => y != null)
      .sort((a, b) => b - a);
    const extra = years.length
      ? years.map((y) => `<option value="${y}">${y}</option>`).join("")
      : "";
    this.yearSelect.insertAdjacentHTML("beforeend", extra);
  }

  bindStatusButtons() {
    this.statusButtons.forEach((btn) => {
      btn.addEventListener("click", () => {
        this.statusButtons.forEach((b) => {
          b.classList.remove("is-active");
          b.setAttribute("aria-selected", "false");
        });
        btn.classList.add("is-active");
        btn.setAttribute("aria-selected", "true");
        this.state.status = btn.dataset.status;
        this.updateTriggerLabels();
        this.syncUrlStatus();
        this.resetPage();
        this.render();
      });
    });
  }

  /**
   * "Our Works" menu deep-links: Current Work -> ?status=ongoing,
   * Past Work -> ?status=completed. Apply that to the pills before the
   * first render so the table, its label and the URL all agree.
   */
  readStatusFromUrl() {
    const status = new URLSearchParams(window.location.search).get("status");
    if (status !== "ongoing" && status !== "completed") return;

    this.state.status = status;
    this.statusButtons.forEach((btn) => {
      const match = btn.dataset.status === status;
      btn.classList.toggle("is-active", match);
      btn.setAttribute("aria-selected", match ? "true" : "false");
    });
    this.updateTriggerLabels();
  }

  /** Keep the address bar shareable when the status pill changes. */
  syncUrlStatus() {
    const url = new URL(window.location.href);
    if (this.state.status === "all") url.searchParams.delete("status");
    else url.searchParams.set("status", this.state.status);
    window.history.replaceState(null, "", url);
  }

  bindLists() {
    this.bindList(this.yearList, "year");
    this.bindList(this.partnerList, "partner");
    this.bindList(this.locationList, "location");
  }

  bindList(listEl, type) {
    if (!listEl) return;
    listEl.addEventListener("change", (e) => {
      if (e.target.type !== "checkbox") return;

      const value = type === "year" ? Number(e.target.value) : e.target.value;
      const set =
        type === "year"
          ? this.state.years
          : type === "partner"
            ? this.state.partners
            : this.state.locations;

      if (e.target.checked) set.add(value);
      else set.delete(value);

      if (type === "year") this.syncYearDropdown();
      this.updateTriggerLabels();
      this.resetPage();
      this.render();
    });
  }

  /**
   * Top dropdown acts as a quick single-select that mirrors the sidebar
   * year checkboxes. When several years are checked, the dropdown shows
   * "N years selected".
   */
  syncYearDropdown() {
    if (!this.yearSelect) return;
    const set = this.state.years;
    if (set.size === 1) {
      this.yearSelect.value = String([...set][0]);
    } else if (set.size === 0) {
      this.yearSelect.value = "";
    } else {
      let custom = this.yearSelect.querySelector('option[data-custom]');
      if (!custom) {
        custom = new Option("", "__custom");
        custom.dataset.custom = "1";
        this.yearSelect.appendChild(custom);
      }
      custom.textContent = `${set.size} years selected`;
      this.yearSelect.value = "__custom";
    }
  }

  bindYearDropdown() {
    if (!this.yearSelect) return;
    this.yearSelect.addEventListener("change", () => {
      const value = this.yearSelect.value;
      this.state.years.clear();
      if (value && value !== "__custom") this.state.years.add(Number(value));

      // Keep the sidebar checkboxes in sync (no sidebar year list since it
      // moved to the top dropdown — guard in case a list is reintroduced)
      if (this.yearList) {
        this.yearList.querySelectorAll("input").forEach((input) => {
          input.checked = this.state.years.has(Number(input.value));
        });
      }
      this.resetPage();
      this.render();
    });
  }

  bindSearch() {
    if (!this.searchInput) return;
    this.searchInput.addEventListener("input", () => {
      clearTimeout(this._searchTimer);
      this._searchTimer = setTimeout(() => {
        this.state.query = this.searchInput.value.trim().toLowerCase();
        this.resetPage();
        this.render();
      }, 250);
    });
  }

  getFilteredProjects() {
    const query = this.state.query;
    return this.data.filter((project) => {
      const statusMatch =
        this.state.status === "all" || project.status === this.state.status;

      const locationMatch =
        this.state.locations.size === 0 ||
        this.state.locations.has(project.location);

      const yearMatch =
        this.state.years.size === 0 || this.state.years.has(project.year);

      const partnerMatch =
        this.state.partners.size === 0 ||
        this.state.partners.has(project.donorganization);

      const haystack =
        `${project.title} ${project.location} ${project.donorganization || ""} ${project.description || ""}`.toLowerCase();
      const queryMatch = !query || haystack.includes(query);

      return statusMatch && locationMatch && yearMatch && partnerMatch && queryMatch;
    });
  }

  /**
   * Reset to page 1 whenever the underlying filter set changes, so the
   * user never lands on an empty page after tightening a filter.
   */
  resetPage() {
    this.page = 1;
  }

  render() {
    const filtered = this.getFilteredProjects();

    // pagination: slice the filtered list to the current page of 20 rows
    const totalPages = Math.max(1, Math.ceil(filtered.length / this.pageSize));
    if (this.page > totalPages) this.page = totalPages;
    if (this.page < 1) this.page = 1;
    const start = (this.page - 1) * this.pageSize;
    const pageItems = filtered.slice(start, start + this.pageSize);

    this.grid.innerHTML = pageItems
      .map((p, index) => this.rowTemplate(p, start + index))
      .join("");
    this.noResults.hidden = filtered.length !== 0;
    this.renderPagination(totalPages);
  }

  /**
   * Bottom-right pagination. Rendered only when the filtered list spans
   * more than one page (i.e. more than `pageSize` projects).
   */
  renderPagination(totalPages) {
    if (!this.pagination) return;
    this.pagination.hidden = totalPages <= 1;
    this.pagination.innerHTML = totalPages <= 1
      ? ""
      : this.paginationTemplate(totalPages);
  }

  /**
   * Page buttons: first, last and a window around the current page,
   * with "…" separators. Prev/next step through pages when possible.
   */
  paginationTemplate(totalPages) {
    const current = this.page;
    const parts = [];

    parts.push(`<button type="button" class="pp-btn pp-prev" data-page="${current - 1}"${current === 1 ? " disabled" : ""} aria-label="Previous page"><i class="fa-solid fa-angle-left" aria-hidden="true"></i></button>`);

    let last = 0;
    for (let p = 1; p <= totalPages; p++) {
      const edge = p === 1 || p === totalPages;
      const near = Math.abs(p - current) <= 2;
      if (!edge && !near) continue;
      if (p - last > 1) parts.push(`<span class="pp-gap">…</span>`);
      parts.push(
        `<button type="button" class="pp-num${p === current ? " is-active" : ""}" data-page="${p}" aria-label="Page ${p}"${p === current ? ' aria-current="page"' : ""}>${p}</button>`,
      );
      last = p;
    }

    parts.push(`<button type="button" class="pp-btn pp-next" data-page="${current + 1}"${current === totalPages ? " disabled" : ""} aria-label="Next page"><i class="fa-solid fa-angle-right" aria-hidden="true"></i></button>`);

    return parts.join("");
  }

  /** One global click listener handles every page button via data-page. */
  bindPagination() {
    if (!this.pagination) return;
    this.pagination.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-page]");
      if (!btn || btn.disabled) return;
      const page = Number(btn.dataset.page);
      if (!page || page === this.page) return;
      this.page = page;
      this.render();
      const table = document.querySelector(".projects-table-wrap");
      if (table) table.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  }

  static escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/"/g, "&quot;");
  }

  statusBadge(project) {
    const isOngoing = project.status === "ongoing";
    const label = isOngoing ? "Ongoing" : "Completed";
    const cls = isOngoing ? "status-pill--ongoing" : "status-pill--completed";
    return `<span class="status-pill ${cls}">${label}</span>`;
  }

  rowTemplate(project, index) {
    const title = ProjectsFilter.escapeHtml(project.title);

    return `
      <tr class="project-row" data-id="${project.id}">
        <td class="col-id" data-label="SL No">${index + 1}</td>
        <td class="col-name" data-label="Project Name">
          <span class="col-name__text" title="${title}">${title}</span>
        </td>
        <td class="col-location" data-label="Location">${project.location}</td>
        <td class="col-patner" data-label="Development Partner">${project.donorganization || "—"}</td>
        <td class="col-date" data-label="Start Date">${project.startDate}</td>
        <td class="col-budget" data-label="Budget">${project.budget}</td>
        <td class="col-status" data-label="Status">${this.statusBadge(project)}</td>
        <td class="col-action" data-label="">
          <a class="view-btn" href="project.html?id=${project.id}">Read more</a>
        </td>
      </tr>
    `;
  }
}

// ---- Bootstrap: projects.html table ----
document.addEventListener("DOMContentLoaded", () => {
  const tableBody = document.getElementById("projectsGrid");
  if (!tableBody || typeof projectsData === "undefined") return;

  // Modern filter dropdown buttons: one opens at a time, click-outside
  // and Escape close them (open/close is presentation-level, so it lives
  // beside the ProjectsFilter bootstrap rather than inside the class)
  const dds = document.querySelectorAll(".filter-dd");
  const closeAll = () =>
    dds.forEach((dd) => {
      dd.classList.remove("open");
      const b = dd.querySelector(".filter-dd__btn");
      if (b) b.setAttribute("aria-expanded", "false");
    });

  dds.forEach((dd) => {
    const btn = dd.querySelector(".filter-dd__btn");
    if (!btn) return;
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      const willOpen = !dd.classList.contains("open");
      closeAll();
      if (willOpen) {
        dd.classList.add("open");
        btn.setAttribute("aria-expanded", "true");
      }
    });
    // clicks on checkboxes/options inside the panel must not close it
    const panel = dd.querySelector(".filter-dd__panel");
    if (panel) panel.addEventListener("click", (e) => e.stopPropagation());
  });
  document.addEventListener("click", closeAll);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeAll();
  });

  const filter = new ProjectsFilter(projectsData, {
    grid: tableBody,
    noResults: document.getElementById("noResults"),
    yearList: document.getElementById("yearFilterList"),
    partnerList: document.getElementById("partnerFilterList"),
    locationList: document.getElementById("locationFilterList"),
    statusButtons: document.querySelectorAll(".status-btn"),
    searchInput: document.getElementById("projectSearch"),
    yearSelect: document.getElementById("yearDropdown"),
    pagination: document.getElementById("projectsPagination"),
  });
  // exposed for debugging/testing in the browser console
  window.projectsFilter = filter;
});

// ---- Bootstrap: home page card teaser (separate element, separate ID) ----
document.addEventListener("DOMContentLoaded", () => {
  const grid = document.getElementById("homeProjectsGrid");
  if (!grid || typeof projectsData === "undefined") return;

  const CARD_COUNT = 8; // 4 columns x 2 rows on desktop, see CSS
  const cards = projectsData.slice(0, CARD_COUNT);
  grid.innerHTML = cards.map(homeCardTemplate).join("");
});

function homeCardTemplate(project) {
  const badguClass =
    project.status === "ongoing" ? "badgu--ongoing" : "badgu--completed";
  const badguLabel = project.status === "ongoing" ? "Ongoing" : "Completed";

  return `
    <article class="project-card">
      <div class="card-image">
        <!-- Home teaser uses the shared placeholder until project photography is final. -->
        <img src="assets/img/placeholder.png" alt="" loading="lazy">
      </div>
      <div class="card-body">
        <h3 class="card-title">${project.title}</h3>
        <span class="badgu ${badguClass}">${badguLabel}</span>
        <div class="card-meta">
          <p class="card-meta__text">
            <strong>Location:</strong> ${project.location}<br>
            <strong>Start date:</strong> ${project.startDate}
          </p>
          <a class="view-btn" href="project.html?id=${project.id}">View</a>
        </div>
      </div>
    </article>
  `;
}
