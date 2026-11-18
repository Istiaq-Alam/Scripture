/**
 * map.js — Leaflet project map (reusable component)
 *
 * Data now comes from the shared `projectsData` array in
 * js/projects-data.js instead of a separate copy here, so
 * projects.html, project-detail.html, and this map all read
 * from one source.
 *
 * The map is locked to Bangladesh: it can't be panned or zoomed out
 * to show neighbouring countries. The overview map is overlaid with
 * all 64 districts (bd-districts.js) so each district is individually
 * visible, hoverable and clickable; a lighter silhouette layer behind
 * them keeps the country a single solid shape, and a division-border
 * overlay (js/Divisions.js) adds the 8 administrative divisions on
 * top for structure. The single-project map still uses the division
 * layer to highlight which division a project sits in.
 *
 * Load order matters:
 *   <script src="js/projects-data.js"></script>
 *   <script src="js/Divisions.js"></script>       (window.BD_DIVISIONS_GEOJSON)
 *   <script src="js/bd-districts.js"></script>   (window.BD_DISTRICTS_GEOJSON)
 *   <script src="js/newmap.js"></script>
 *
 * USAGE
 * -----
 * 1) Overview map with every project pinned — auto-initializes,
 *    no extra JS needed. Popups are ON by default (home page use):
 *      <div data-eco-map="all" style="height:480px"></div>
 *
 *    To show markers only, with no popup card (e.g. a mini "all
 *    projects" map embedded inside project-detail.html), add
 *    data-eco-map-popup="false":
 *      <div data-eco-map="all" data-eco-map-popup="false" style="height:300px"></div>
 *
 *    Same toggle works if you call it manually:
 *      ProjectMap.renderAll(el, { showPopup: false });
 *
 *    To turn off the division overlay on a particular map, pass
 *    showDivisions: false:
 *      ProjectMap.renderAll(el, { showDivisions: false });
 *
 * 2) Single-project map (this is what project-detail.js calls):
 *      ProjectMap.render(containerEl, { lat, lng, name, location, status })
 *
 *    This also draws the division layer by default and highlights
 *    whichever division the project's point falls inside. Pass
 *    showDivisions: false to turn that off.
 *
 * Both modes expect Leaflet's JS + CSS already loaded on the page.
 *
 * There's no tile provider — the division layer is the entire map,
 * so nothing needs an API key and nothing outside Bangladesh can
 * ever appear. The background color is set inline (#eaf3ee); to
 * change it, edit setPlainBackground() below rather than fighting
 * Leaflet's own CSS in your stylesheet. Also add this for the
 * division tooltip (markers/popups already have styles elsewhere):
 *   .eco-division-tooltip { font-family: 'Inter', sans-serif; font-weight: 600; }
 *   .eco-division-tooltip__bn { font-weight: 400; opacity: .7; margin-left: 4px; }
 */

// ── Bangladesh-only viewport ────────────────────────────────────
// Roughly the country's bounding box. Padded a little in
// restrictToBangladesh() so the coastline/border isn't flush
// against the edge of the map.
const BD_BOUNDS = L.latLngBounds([20.3, 88.0], [26.7, 92.75]);

function isWithinBangladesh(lat, lng) {
  return BD_BOUNDS.pad(0.1).contains([lat, lng]);
}

// Locks panning/zooming to Bangladesh so no other country is ever
// visible, regardless of how far the user drags or scrolls.
function restrictToBangladesh(map) {
  const padded = BD_BOUNDS.pad(0.08);
  map.setMaxBounds(padded);
  map.options.maxBoundsViscosity = 1.0;
  map.on('drag', () => map.panInsideBounds(padded, { animate: false }));
}

// Fits the view to Bangladesh's actual shape (the bounds of whatever
// layer is passed — districts fill the country on the overview map)
// and then pins minZoom to whatever zoom that took. That's what stops
// the "free space around the map" problem. animate:false is important:
// with an animated fit, getZoom() can return a stale value, and the
// minZoom pin (and the whole initial framing) becomes wrong.
function fitToBangladesh(map, boundsSource) {
  const bounds = boundsSource && boundsSource.getBounds ? boundsSource.getBounds() : BD_BOUNDS;
  map.fitBounds(bounds, { padding: [10, 10], animate: false });
  map.setMinZoom(Math.max(4, map.getZoom() - 0.5));
}

// Re-fits whenever the container itself changes size (responsive
// layout, orientation change, sidebar toggling, etc.) instead of
// leaving the map at whatever zoom it happened to load at.
function observeMapResize(mapEl, map, onResize) {
  if (typeof ResizeObserver === 'undefined') return;
  const ro = new ResizeObserver(() => {
    map.invalidateSize();
    onResize();
  });
  ro.observe(mapEl);
}

// ── Division overlay (8 administrative divisions) ────────────────
const DIVISION_COLORS = {
  BD10: '#7fb8a3', // Barisal
  BD20: '#e8a35c', // Chattagram
  BD30: '#4caf6e', // Dhaka
  BD40: '#6b9bd1', // Khulna
  BD45: '#c98bc9', // Mymensingh
  BD50: '#d4c05c', // Rajshahi
  BD55: '#e07a7a', // Rangpur
  BD60: '#8ec9e0', // Sylhet
};

function styleForDivision(feature, highlightPcode) {
  const pcode = feature.properties.pcode;
  const isHighlighted = !!highlightPcode && pcode === highlightPcode;
  return {
    color: '#102017',
    weight: isHighlighted ? 2 : 1,
    fillColor: DIVISION_COLORS[pcode] || '#4caf6e',
    fillOpacity: isHighlighted ? 0.55 : 0.28,
  };
}

/**
 * Draws the 8-division choropleth layer on a map.
 *
 * options.highlightPcode — pcode of one division to visually pick
 * out (used by renderSingle for "this project is in Dhaka division").
 * options.interactive (default true) — hover highlight + click to
 * zoom into a division.
 */
function addDivisionsLayer(map, options = {}) {
  const fc = window.BD_DIVISIONS_GEOJSON;
  if (!fc || typeof L === 'undefined') return null;

  const highlightPcode = options.highlightPcode || null;
  const interactive = options.interactive !== false;

  const layer = L.geoJSON(fc, {
    style: (feature) => styleForDivision(feature, highlightPcode),
    onEachFeature: (feature, lyr) => {
      const p = feature.properties;
      lyr.bindTooltip(
        `${p.name} <span class="eco-division-tooltip__bn">${p.bn_name}</span>`,
        { sticky: true, className: 'eco-division-tooltip' }
      );

      if (!interactive) return;

      lyr.on('mouseover', function () {
        this.setStyle({ fillOpacity: 0.55, weight: 2 });
      });
      lyr.on('mouseout', function () {
        layer.resetStyle(this);
      });
      lyr.on('click', function () {
        map.fitBounds(this.getBounds(), { padding: [20, 20] });
      });
    },
  }).addTo(map);

  return layer;
}

// ── District layer (64 districts) + country silhouette ──────────
// The overview map reads as one clean green country silhouette with
// fine hairline district borders — hovering any district fills it in,
// shows its name (English + Bangla), and clicking flies the camera to
// that district. The silhouette layer underneath (divisions with no
// stroke) hides any hairline seams between independently simplified
// district polygons, so the country still reads as one solid shape.
const DISTRICT_STYLE = {
  color: '#9cc3ac', // hairline border
  weight: 0.7,
  fillColor: '#4caf6e',
  fillOpacity: 0.04,
};

function addDistrictSilhouette(map) {
  const fc = window.BD_DIVISIONS_GEOJSON;
  if (!fc || typeof L === 'undefined') return null;
  return L.geoJSON(fc, {
    interactive: false,
    style: {
      stroke: false,
      fillColor: '#e7f2ea',
      fillOpacity: 1,
    },
  }).addTo(map);
}

function addDistrictsLayer(map) {
  const fc = window.BD_DISTRICTS_GEOJSON;
  if (!fc || typeof L === 'undefined') return null;

  const layer = L.geoJSON(fc, {
    style: () => ({ ...DISTRICT_STYLE }),
    onEachFeature: (feature, lyr) => {
      const p = feature.properties;
      lyr.bindTooltip(
        `${p.name} <span class="eco-district-tooltip__bn">${p.bn_name}</span>`,
        { sticky: true, className: 'eco-district-tooltip' }
      );

      lyr.on('mouseover', function () {
        this.setStyle({ color: '#2e7d54', weight: 1.4, fillOpacity: 0.22 });
      });
      lyr.on('mouseout', function () {
        layer.resetStyle(this);
      });
      lyr.on('click', function () {
        map.flyToBounds(this.getBounds(), { padding: [30, 30], duration: 0.6 });
      });
    },
  }).addTo(map);

  return layer;
}

// Division borders drawn on top of the district hairlines — no fill,
// non-interactive (hover passes through to the district underneath).
function addDivisionStructure(map) {
  const fc = window.BD_DIVISIONS_GEOJSON;
  if (!fc || typeof L === 'undefined') return;
  L.geoJSON(fc, {
    interactive: false,
    style: {
      color: '#41654f',
      weight: 1.3,
      opacity: 0.8,
      fillColor: '#4caf6e',
      fillOpacity: 0,
    },
  }).addTo(map);
}

// Ray-casting point-in-polygon test, used to figure out which
// division a project's lat/lng falls inside (for renderSingle's
// highlight). Handles Polygon and MultiPolygon, holes included.
function pointInRing(point, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    const intersect =
      yi > point[1] !== yj > point[1] &&
      point[0] < ((xj - xi) * (point[1] - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

function pointInGeometry(lat, lng, geometry) {
  const point = [lng, lat];
  const polygons = geometry.type === 'Polygon' ? [geometry.coordinates] : geometry.coordinates;
  return polygons.some(([outer, ...holes]) => {
    if (!pointInRing(point, outer)) return false;
    return !holes.some((hole) => pointInRing(point, hole));
  });
}

function findDivisionForPoint(lat, lng) {
  const fc = window.BD_DIVISIONS_GEOJSON;
  if (!fc) return null;
  return fc.features.find((f) => pointInGeometry(lat, lng, f.geometry)) || null;
}

// ── Marker colors / labels ──────────────────────────────────────
const STATUS_COLOR = {
  ongoing:   '#FFBF00',
  completed: '#2f6b45',

};
 
const STATUS_LABEL = {
  ongoing:   'Ongoing',
  completed: 'Completed',
};
 
// ── Custom DivIcon marker ───────────────────────────────────────
function createMarkerIcon(status) {
  const color = STATUS_COLOR[status] || STATUS_COLOR.ongoing;
  return L.divIcon({
    className: '',
    html: `
      <div class="eco-pin" style="--pin-color:${color}">
        <div class="eco-pin__dot"></div>
        <div class="eco-pin__pulse"></div>
      </div>`,
    iconSize:    [20, 20],
    iconAnchor:  [10, 10],
    popupAnchor: [0, -18],
  });
}
 
// ── Popup HTML for an overview-map pin ──────────────────────────
// Shows a LIST of that location's projects: up to 6 titles, ongoing
// projects on top, completed below; a click opens the project page.

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// Ongoing first, completed after; newest first within each group.
function sortProjectGroup(group) {
  return group.slice().sort((a, b) => {
    if (a.status !== b.status) return a.status === "ongoing" ? -1 : 1;
    return (Number(b.year) || 0) - (Number(a.year) || 0);
  });
}

const MAX_POPUP_ITEMS = 6;

function buildLocationPopup(location, group) {
  // group arrives pre-sorted by renderAll; touch-up for direct callers
  const projects = sortProjectGroup(group);
  const shown = projects.slice(0, MAX_POPUP_ITEMS);
  const hiddenCount = projects.length - shown.length;

  const items = shown
    .map((p) => {
      const color = STATUS_COLOR[p.status] || STATUS_COLOR.ongoing;
      const title = escapeHtml(p.title);
      return `
        <li class="eco-popup__row eco-popup__row--${p.status === 'ongoing' ? 'ongoing' : 'completed'}">
          <a href="project.html?id=${p.id}" title="${title}">
            <span class="eco-popup__dot" style="--dot-color:${color}"></span>
            <span class="eco-popup__name">${title}</span>
            <span class="eco-popup__arrow" aria-hidden="true">→</span>
          </a>
        </li>`;
    })
    .join("");

  return `
    <div class="eco-popup eco-popup--list">
      <div class="eco-popup__list-head">
        <svg class="eco-popup__pin" width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M12 2C7.58 2 4 5.58 4 10c0 5.25 7 12 8 12s8-6.75 8-12c0-4.42-3.58-8-8-8zm0 11a3 3 0 1 1 0-6 3 3 0 0 1 0 6z"/>
        </svg>
        <span class="eco-popup__loc-name">${escapeHtml(location)}</span>
        <span class="eco-popup__count">${projects.length} project${projects.length === 1 ? "" : "s"}</span>
      </div>
      <ul class="eco-popup__list">${items}</ul>${
        hiddenCount > 0
          ? `
      <div class="eco-popup__more-hint">+ ${hiddenCount} more project${hiddenCount === 1 ? "" : "s"} in ${escapeHtml(location)}</div>`
          : ""
      }
    </div>`;
}

function toLatLng(p) {
  if (Array.isArray(p.coords)) return p.coords;
  return [p.lat, p.lng];
}
 
// ── Background (no tile provider) ───────────────────────────────
// CARTO's free basemap tiles now require an API key in production,
// which is what was showing as red "API KEY REQUIRED" crosses over
// the neighbouring countries. Rather than sign up for a tile API
// key, this map skips tiles altogether: the division layer IS the
// map. That also guarantees nothing outside Bangladesh can ever
// show through gaps between divisions, no matter how far someone
// drags or zooms.
function setPlainBackground(mapEl) {
  mapEl.classList.add('eco-map--no-tiles');
  // Set inline too — Leaflet's own CSS sets a grey background on
  // .leaflet-container, and inline style always wins the cascade
  // regardless of stylesheet load order.
  mapEl.style.background = '#fbfdfc';
}
 
// Re-enable scroll-zoom only once the user is actively interacting
// with the map, so the page can still scroll normally otherwise.
function guardScrollZoom(mapEl, map) {
  mapEl.addEventListener('click', () => map.scrollWheelZoom.enable());
  mapEl.addEventListener('mouseleave', () => map.scrollWheelZoom.disable());
}
 
/**
 * Renders every project as a pin on one map — the overview / "all
 * projects" map. Pulls from projectsData by default; pass a custom
 * `data` array via options to override.
 *
 * options.showPopup (default true) — when false, markers render
 * with no click/hover popup card at all (used on project-detail.html
 * so the mini map doesn't compete with the page's own project info).
 * options.showDivisions (default true) — division overlay (single map).
 * options.showDistricts (default true) — 64-district hairline country
 *   map used as the overview/map-card background layer.
 *
 * There's no zoom/center option anymore — the view always fits
 * itself to Bangladesh's actual shape for whatever size the
 * container element is, and re-fits if that container is resized.
 * That's what used to need manual zoom tuning (7 leaves gaps, 8
 * overflows); now it's automatic regardless of container size.
 */
function renderAll(container, options = {}) {
  const mapEl = typeof container === 'string' ? document.getElementById(container) : container;
  if (!mapEl || typeof L === 'undefined') return null;
 
  const data = options.data || (typeof projectsData !== 'undefined' ? projectsData : []);
 
  // Falls back to the element's data-eco-map-popup attribute so the
  // auto-init pass (below) can opt individual maps out via markup
  // alone, with no JS call needed.
  const showPopup = options.showPopup !== undefined
    ? options.showPopup
    : mapEl.dataset.ecoMapPopup !== 'false';

  const showDistricts = options.showDistricts !== false;

  const map = L.map(mapEl, {
    zoomControl: false, // re-added below, bottom-right, glass-styled
    zoomSnap: 0.25, // finer zoom steps so fitBounds fits the card exactly
    scrollWheelZoom: false,
    attributionControl: false,
    maxZoom: 12,
  });

  setPlainBackground(mapEl);
  restrictToBangladesh(map);

  // Bottom-right glass zoom buttons (minimal world-class control chrome).
  L.control.zoom({ position: 'bottomright' }).addTo(map);

  // District-level country: silhouette -> hairline districts -> division borders.
  let boundsSource = BD_BOUNDS;
  if (showDistricts) {
    addDistrictSilhouette(map);
    const districtsLayer = addDistrictsLayer(map);
    if (districtsLayer) boundsSource = districtsLayer;
    addDivisionStructure(map);
  }
  fitToBangladesh(map, boundsSource);
  observeMapResize(mapEl, map, () => fitToBangladesh(map, boundsSource));
 
  // Group the pins by location BEFORE rendering: every pin's popup
  // lists that location's projects — up to 6 titles with ongoing
  // projects on top and completed ones below.
  const byLocation = new Map();
  const validProjects = [];
  data.forEach((p) => {
    const coords = toLatLng(p);
    if (coords[0] == null || coords[1] == null) return;
    if (!isWithinBangladesh(coords[0], coords[1])) return; // only Bangladesh is shown

    validProjects.push(p);
    const key = p.location || "Unknown";
    if (!byLocation.has(key)) byLocation.set(key, []);
    byLocation.get(key).push(p);
  });
  byLocation.forEach((group) => sortProjectGroup(group));

  validProjects.forEach((p) => {
    const coords = toLatLng(p);
    const marker = L.marker(coords, {
      icon: createMarkerIcon(p.status),
      riseOnHover: true, // hovered pin floats above its overlapping siblings
    });

    if (showPopup) {
      const group = byLocation.get(p.location || "Unknown") || [p];
      marker.bindPopup(buildLocationPopup(p.location || "Unknown", group), {
        maxWidth: 320,
        className: "eco-popup-wrap",
        closeButton: false, // hover card — closes when the mouse leaves
        autoPan: false,     // panning moves markers under the cursor → flicker
      });

      // Hover lifecycle: open on pin hover; close shortly after the mouse
      // leaves — unless it moved onto the card itself (links stay clickable).
      // The grace period lets the pointer cross overlapping pins of the same
      // location without the card flickering between them.
      const HOVER_GRACE = 160;
      let closeTimer = null;
      const scheduleClose = () => {
        clearTimeout(closeTimer);
        closeTimer = setTimeout(() => marker.closePopup(), HOVER_GRACE);
      };
      const cancelClose = () => clearTimeout(closeTimer);

      // Pointer on the card keeps it alive. The popup DOM element is only
      // available once Leaflet has added it, so bind there.
      const popup = marker.getPopup();

      // With autoPan off, a tall or edge-hugging card can poke outside the
      // map frame; measure after open and slide card + arrow just inside.
      const PADDING = 10;
      const openHoverPopup = () => {
        cancelClose();
        marker.openPopup();
        // popup geometry is final once openPopup() returns; a 0ms follow-up
        // is enough to measure and clamp it inside the map frame
        setTimeout(() => {
          const leafletPopup = popup.getElement();
          if (!leafletPopup) return;
          const parts = [
            leafletPopup.querySelector(".leaflet-popup-content-wrapper"),
            leafletPopup.querySelector(".leaflet-popup-tip-container"),
          ].filter(Boolean);
          if (!parts.length) return;
          // reset first: clamp is recomputed for every open
          parts.forEach((part) => (part.style.translate = ""));
          const frame = mapEl.getBoundingClientRect();
          const card = parts[0].getBoundingClientRect();
          const dx =
            (card.left < frame.left + PADDING ? frame.left + PADDING - card.left : 0) +
            (card.right > frame.right - PADDING ? frame.right - PADDING - card.right : 0);
          const dy =
            card.top < frame.top + PADDING ? frame.top + PADDING - card.top : 0;
          if (dx || dy) {
            parts.forEach((part) => (part.style.translate = `${dx}px ${dy}px`));
          }
        });
      };

      marker.on("mouseover", openHoverPopup);
      marker.on("mouseout", scheduleClose);

      // Touch devices have no hover: tap a pin once to open it, tap the
      // map anywhere else to dismiss (Leaflet's default close-on-click).
      marker.on("click", openHoverPopup);

      const bindCardEvents = () => {
        const el = popup.getElement();
        if (!el || el.dataset.ecoHover === "1") return;
        el.dataset.ecoHover = "1";
        el.addEventListener("mouseenter", cancelClose);
        el.addEventListener("mouseleave", scheduleClose);
      };
      popup.on("add", bindCardEvents);
      if (popup.getElement()) bindCardEvents();
    }

    marker.addTo(map);
  });
 
  guardScrollZoom(mapEl, map);
  return map;
}
 
/**
 * Renders a single pin centered on one project. This is the function
 * project-detail.js calls for the per-project "Map" box:
 *   ProjectMap.render(containerEl, { lat, lng, name, location, status })
 *
 * options via the same `point` object:
 * point.showDivisions (default true) — draws the division overlay
 * and highlights whichever division this project sits in.
 */
function renderSingle(container, point = {}) {
  const mapEl = typeof container === 'string' ? document.getElementById(container) : container;
  if (!mapEl) return null;
 
  if (typeof L === 'undefined' || point.lat == null || point.lng == null) {
    mapEl.innerHTML = '<p class="map-fallback">Map unavailable</p>';
    return null;
  }

  if (!isWithinBangladesh(point.lat, point.lng)) {
    mapEl.innerHTML = '<p class="map-fallback">Map unavailable</p>';
    return null;
  }
 
  const map = L.map(mapEl, {
    center: [point.lat, point.lng],
    zoom: 10,
    minZoom: 4,
    zoomControl: true,
    scrollWheelZoom: false,
    attributionControl: false,
  });
 
  setPlainBackground(mapEl);
  restrictToBangladesh(map);

  const showDivisions = point.showDivisions !== false;
  if (showDivisions) {
    const division = findDivisionForPoint(point.lat, point.lng);
    addDivisionsLayer(map, { highlightPcode: division ? division.properties.pcode : null });
  }
 
  const marker = L.marker([point.lat, point.lng], {
    icon: createMarkerIcon(point.status || 'ongoing'),
  }).addTo(map);
 
  if (point.showPopup && point.name) {
    marker
      .bindPopup(`
        <div class="eco-popup eco-popup--compact">
          <h3 class="eco-popup__title">${point.name}</h3>
          ${point.location ? `<div class="eco-popup__loc">${point.location}</div>` : ''}
        </div>
      `)
      .openPopup();
  }
 
  guardScrollZoom(mapEl, map);
  return map;
}
 
// ── Public API ───────────────────────────────────────────────────
window.ProjectMap = {
  renderAll,
  render: renderSingle,
};
 
// ── Auto-init any overview maps declared via data attribute ──────
// Doesn't touch single-project maps — those are rendered explicitly
// by whichever page calls ProjectMap.render(), e.g. project-detail.js.
document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('[data-eco-map="all"]').forEach((el) => renderAll(el));
});