// ============================================================
//  DATA — swap with fetch('/api/causes').then(r => r.json())
// ============================================================


function truncateWords(text, limit = 10) {
    const words = text.trim().split(/\s+/);
    return words.length > limit
        ? words.slice(0, limit).join(" ") + '...'
        : text;
}

// ============================================================
//  CARD TEMPLATE — edit this to change card layout globally
// ============================================================
function renderCauseCard(card) {
  return `
    <div class="swiper-slide" style="width:auto;height:auto;display:flex;align-items:center;min-height:500px;">
      <div class="emotions-slider-item">
        ${card.badge ? `<div class="emotions-slider-item__badge">${card.badge}</div>` : ''}
        <div class="emotions-slider-item__image">
          <img src="${card.image}" alt="${card.title}" loading="lazy">
        </div>
        <div class="emotions-slider-item__content">
          <div class="emotions-slider-item__header">
            <div class="emotions-slider-item__header-inner">
            </div>
          </div>
          <div class="emotions-slider-item__info">
            <h3 class="emotions-slider-item__title">${truncateWords(card.title)}</h3>
            <p class="emotions-slider-item__text">${card.text}</p>
          </div>
          <div class="emotions-slider-item__footer">
            <a class="emotions-slider-item__btn" href="#" onclick="event.preventDefault()">
              <span class="emotions-slider-item__btn-text">Donate Now</span>
              <span class="emotions-slider-item__btn-icon"> →</span>
            </a>
          </div>
        </div>
      </div>
    </div>`;
}

// ============================================================
//  NEWS CAROUSEL — data + card template (home page)
// ============================================================
const newsData = [
  {
    image: 'assets/img/birds.jpg',
    category: 'Conservation',
    date: 'Oct 20, 2026',
    title: 'Winter bird census kicks off across the Sundarbans',
    text: 'NACOM survey teams are out at dawn recording migratory and resident waterfowl population trends for this year\u2019s national winter census.',
  },
  {
    image: 'assets/img/nature.webp',
    category: 'Restoration',
    date: 'Oct 14, 2026',
    title: 'Mangrove restoration drive plants 5,000 new saplings',
    text: 'Community volunteers joined the forest department to restore degraded mudflats with native mangrove species along the coast.',
  },
  {
    image: 'assets/img/Physical-Infrastructures.jpg',
    category: 'Event',
    date: 'Oct 08, 2026',
    title: 'Coastal livelihood training held for Haor communities',
    text: 'Fishers and farmers learned climate-resilient practices for keeping income steady through the monsoon flooding season.',
  },
  {
    image: 'assets/img/8638.jpeg',
    category: 'Awareness',
    date: 'Oct 02, 2026',
    title: 'Climate adaptation workshop for young eco-clubs',
    text: 'Students from twelve districts explored local biodiversity and drafted their own school-based conservation action plans.',
  },
  {
    image: 'assets/img/cher.jpg',
    category: 'Fisheries',
    date: 'Sep 26, 2026',
    title: 'Fisheries co-management meeting concludes in Khulna',
    text: 'Stakeholders agreed on reserved-area rules that protect breeding grounds while sustaining family fishing incomes.',
  },
  {
    image: 'assets/img/hower.jpg',
    category: 'Partnership',
    date: 'Sep 18, 2026',
    title: 'NACOM signs new MoU on community forestry',
    text: 'A multi-year agreement will expand participatory forest management to new unions in the north-eastern districts.',
  },
];

function renderNewsHeadline(n) {
  return `
    <div class="swiper-slide">
      <a class="news-heading" href="news.html">
        <span class="news-heading__meta">
          <span class="news-heading__dot"></span>${n.category} · ${n.date}
        </span>
        <h3 class="news-heading__title">${n.title} <span class="arrow">→</span></h3>
      </a>
    </div>`;
}

// ============================================================
//  INIT ALL CAROUSELS
// ============================================================
document.addEventListener('DOMContentLoaded', () => {
  // Carousels only exist on pages that load carousel.js
  if (typeof Carousel !== 'undefined') {

  // 1. Hero — static, fade, 3 slides, autoplay every 3s
  new Carousel('#heroSlider', {
    type: 'hero',
    delay: 3000,
  });

  // 2. Causes cards — dynamic data, autoplay, hover pause
  

  // 3. Logo strip — infinite, no controls, constant scroll
  new Carousel('#logoSlider', {
    type: 'logos',
    speed: 3500,
  });

  // 4. News headlines — auto-slide right→left, pauses on hover
  //    (text stops so it can be read); each headline links to news.html
  new Carousel('#newsSlider', {
    type: 'news',
    data: newsData,
    renderFn: renderNewsHeadline,
    delay: 3200,
  });

  }
  // ── Mobile menu toggle ──────────────────────────────────────
});

const mainNav = document.getElementById('mainNav');
const menuToggle = document.getElementById('menuToggle');
const langToggleWrap = document.querySelector('.lang-toggle-wrap');
const headerActions = document.querySelector('.header-actions');
const navUl = mainNav.querySelector('ul');

const mq = window.matchMedia('(max-width: 900px)');

function placeLangToggle(e) {
  if (e.matches) {
    mainNav.appendChild(langToggleWrap); // move into mobile nav
  } else {
    headerActions.insertBefore(langToggleWrap, menuToggle); // move back to header
    mainNav.classList.remove('open');
    mainNav.style.maxHeight = '';
  }
}
placeLangToggle(mq); // run once on load
mq.addEventListener('change', placeLangToggle);

menuToggle.addEventListener('click', () => {
  const isOpen = mainNav.classList.toggle('open');
  if (isOpen) {
    // measure real content height and animate to it
    mainNav.style.maxHeight = mainNav.scrollHeight + 'px';
  } else {
    mainNav.style.maxHeight = '0px';
  }
});

// re-measure if a dropdown inside the mobile menu opens/closes content height
mainNav.querySelectorAll('li.drop > button').forEach(btn => {
  btn.addEventListener('click', () => {
    if (!mq.matches) return; // desktop uses hover, ignore
    btn.parentElement.classList.toggle('open');
    if (mainNav.classList.contains('open')) {
      mainNav.style.maxHeight = mainNav.scrollHeight + 'px';
    }
  });
});

// new for drop active

const currentPath = window.location.pathname;

document.querySelectorAll('.main-nav > ul > li').forEach(li => {
  li.classList.remove('active');
  const link = li.querySelector('a[href]');
  if (link && link.getAttribute('href') === currentPath) {
    li.classList.add('active');
  }
});

// number animation
const counters = document.querySelectorAll(".numba");

const animateCounter = (counter) => {
  const target = +counter.textContent.replace(/,/g, "");
  const duration = 3000; // Animation duration (2 seconds)
  const startTime = performance.now();

  const updateCounter = (currentTime) => {
    const elapsed = currentTime - startTime;
    const progress = Math.min(elapsed / duration, 1);

    const currentValue = Math.floor(progress * target);

    counter.textContent = currentValue.toLocaleString();

    if (progress < 1) {
      requestAnimationFrame(updateCounter);
    } else {
      counter.textContent = target.toLocaleString();
    }
  };

  requestAnimationFrame(updateCounter);
};

const observer = new IntersectionObserver(
  (entries, observer) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        animateCounter(entry.target);
        observer.unobserve(entry.target); // Run only once
      }
    });
  },
  {
    threshold: 0.5,
  }
);

counters.forEach((counter) => observer.observe(counter));

// ============================================================
//  THEME TOGGLE — dark / light mode (persisted via localStorage)
// ============================================================
(function () {
  const themeToggle = document.getElementById('themeToggle');
  const themeIcon = document.getElementById('themeIcon');
  const html = document.documentElement;

  if (!themeToggle || !themeIcon) return;

  const SAVED_KEY = 'nacom-theme';

  function updateIcon(isDark) {
    themeIcon.textContent = isDark ? '☀️' : '🌙';
    themeToggle.title = isDark ? 'Switch to light mode' : 'Switch to dark mode';
  }

  function setTheme(theme) {
    if (theme === 'dark') {
      html.setAttribute('data-theme', 'dark');
      localStorage.setItem(SAVED_KEY, 'dark');
      updateIcon(true);
    } else {
      html.removeAttribute('data-theme');
      localStorage.setItem(SAVED_KEY, 'light');
      updateIcon(false);
    }
  }

  // Resolve initial theme: saved preference > system preference > light
  const saved = localStorage.getItem(SAVED_KEY);
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const initial = saved === 'dark' || (!saved && prefersDark) ? 'dark' : 'light';

  setTheme(initial);

  themeToggle.addEventListener('click', () => {
    const isDark = html.getAttribute('data-theme') === 'dark';
    setTheme(isDark ? 'light' : 'dark');
  });
})();

// ============================================================
//  THEMATIC CARDS — hovering a card swaps the right-hand image
//  (read by index.html only; every .why-box carries data-image)
// ============================================================
(function () {
  const section = document.querySelector('.why-section');
  if (!section) return;

  const frame = section.querySelector('.why-image-frame');
  const img = frame ? frame.querySelector('img') : null;
  if (!frame || !img) return;

  const DEFAULT_SRC = img.getAttribute('src');
  const DEFAULT_ALT = img.getAttribute('alt');
  const SWAP_DELAY_MS = 180; // matches the CSS fade-out duration
  let swapTimer = null;

  // Pre-warm the browser cache so the first hover doesn't flash blank
  section.querySelectorAll('.why-box[data-image]').forEach((box) => {
    const pre = new Image();
    pre.src = box.dataset.image;
    pre.decoding = 'async';
  });

  function swapTo(src, alt) {
    if (img.dataset.current === src) return;
    img.dataset.current = src;
    frame.classList.add('is-swapping');
    clearTimeout(swapTimer);
    swapTimer = setTimeout(() => {
      img.setAttribute('src', src);
      img.setAttribute('alt', alt || DEFAULT_ALT);
    }, SWAP_DELAY_MS);
  }

  function swapBack() {
    swapTo(DEFAULT_SRC, DEFAULT_ALT);
  }

  section.querySelectorAll('.why-box[data-image]').forEach((box) => {
    const src = box.dataset.image;

    box.addEventListener('pointerenter', (e) => {
      if (e.pointerType === 'touch') return; // touch users tap instead
      swapTo(src);
    });
    box.addEventListener('pointerleave', swapBack);

    // Tap on touch screens + keyboard focus support
    box.setAttribute('tabindex', '0');
    box.addEventListener('click', () => swapTo(src));
    box.addEventListener('focus', () => swapTo(src));
    box.addEventListener('blur', swapBack);
  });

  // If a remote image fails to load, fall back to the default photo
  img.addEventListener('error', () => {
    const failed = img.dataset.current;
    if (failed && failed !== DEFAULT_SRC) {
      img.dataset.current = failed;
      img.setAttribute('src', DEFAULT_SRC);
    }
  });

  // Fade the new image back in once it has finished loading
  img.addEventListener('load', () => frame.classList.remove('is-swapping'));
})();
