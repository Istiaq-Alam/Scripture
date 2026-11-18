/**
 * ============================================================
 *  Carousel.js — Reusable Swiper-based carousel component
 *  Usage:
 *    new Carousel(selector, options)
 *
 *  Types:
 *    'hero'  — full-width image slides, arrows, dots, static HTML
 *    'cards' — centered card carousel, dynamic data via renderFn
 *    'logos' — infinite auto-scroll logo strip, no controls
 *
 *  Options:
 *    type        {string}   'hero' | 'cards' | 'logos'
 *    data        {Array}    items to render  (cards / logos)
 *    renderFn    {Function} (item) => HTML string
 *    autoplay    {boolean}  override autoplay (default per type)
 *    delay       {number}   autoplay delay ms (default 3000)
 *    speed       {number}   transition speed ms
 * ============================================================
 */

class Carousel {
  constructor(selector, options = {}) {
    this.root = typeof selector === 'string'
      ? document.querySelector(selector)
      : selector;

    if (!this.root) return;

    this.opts = options;
    this.swiper = null;

    // Render dynamic slides if data provided
    if (options.data && options.renderFn) {
      this._renderSlides(options.data, options.renderFn);
    }

    // Build Swiper config based on type
    const config = this._buildConfig(options.type || 'cards');
    const swiperEl = this.root.querySelector('.swiper');
    if (!swiperEl) return;

    this.swiper = new Swiper(swiperEl, config);

    // Hover pause — cards & news pause while hovered; hero must keep
    // sliding, logos (conveyor belt) is never paused
    if (config.autoplay && options.type !== 'logos' && options.type !== 'hero') {
      this.root.addEventListener('mouseenter', () => this.swiper.autoplay.stop());
      this.root.addEventListener('mouseleave', () => this.swiper.autoplay.start());
    }
  }

  // ── Render dynamic slides into .swiper-wrapper ──────────────
  _renderSlides(data, renderFn) {
    const wrapper = this.root.querySelector('.swiper-wrapper');
    if (wrapper) wrapper.innerHTML = data.map(renderFn).join('');
  }

  // ── Build Swiper config per type ────────────────────────────
  _buildConfig(type) {
    const shared = {
      speed: this.opts.speed || 700,
      observer: true,
      watchSlidesProgress: true,
    };

    const nav = {
      nextEl: this.root.querySelector('.carousel-next'),
      prevEl: this.root.querySelector('.carousel-prev'),
      disabledClass: 'disabled',
    };

    const pagination = {
      el: this.root.querySelector('.carousel-pagination'),
      type: 'bullets',
      bulletClass: 'carousel-dot',
      bulletActiveClass: 'active',
      clickable: true,
    };

    const configs = {
      // ── HERO ──────────────────────────────────────────────
      hero: {
        ...shared,
        slidesPerView: 1,
        loop: true,
        effect: 'fade',
        fadeEffect: { crossFade: true },
        a11y: false,
        autoplay: {
          delay: this.opts.delay || 3000,
          disableOnInteraction: false,
          pauseOnMouseEnter: false,
        },
        navigation: nav,
        pagination,
      },

      // ── CARDS ─────────────────────────────────────────────
      cards: {
        ...shared,
        slidesPerView: 'auto',
        spaceBetween: 20,
        centeredSlides: true,
        initialSlide: 1,
        loop: true,
        autoplay: this.opts.autoplay !== false
          ? { delay:  2800, disableOnInteraction: false }
          : false,
        navigation: nav,
        pagination,
        breakpoints: { 768: { spaceBetween: 32 } },
      },

      // ── LOGOS ─────────────────────────────────────────────
      // Key: speed sets scroll duration, delay:0 + cssEase:'linear'
      // makes it a smooth conveyor belt with zero stutter
      logos: {
        slidesPerView: 'auto',
        spaceBetween: 56,
        loop: true,
        speed: 4000,
        cssEase: 'linear',              // ← makes the belt perfectly smooth
        autoplay:{
          delay: 0.5,
          disableOnInteraction: false,
          pauseOnMouseEnter: false,
        },
        // freeMode: {
        //   enabled: true,
        //   momentum: false,              // ← prevents rubber-band on drag
        // },
        grabCursor: true,
        allowTouchMove: true,
      },
      // ── NEWS ──────────────────────────────────────────────
      // Auto-sliding news headlines. Hover pause is handled by the
      // manual mouseenter/leave listeners below (stop/start), so the
      // sliding — and therefore the text — stops while it's hovered.
      news: {
        ...shared,
        slidesPerView: 1,
        spaceBetween: 40,
        loop: true,
        grabCursor: true,
        autoplay: {
          delay: this.opts.delay || 3200,
          disableOnInteraction: false,
        },
        navigation: nav,
        pagination,
        breakpoints: {
          720:  { slidesPerView: 2 },
          1080: { slidesPerView: 3 },
        },
      },
    };

    return configs[type] || configs.cards;
  }

  // ── Public API ───────────────────────────────────────────────
  pause()  { this.swiper?.autoplay.stop(); }
  resume() { this.swiper?.autoplay.start(); }
  destroy(){ this.swiper?.destroy(true, true); }
  next()   { this.swiper?.slideNext(); }
  prev()   { this.swiper?.slidePrev(); }
}
