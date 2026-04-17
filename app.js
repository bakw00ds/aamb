(function () {
  'use strict';

  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- Hamburger + mobile nav panel ---------- */
  var hb = document.getElementById('hamburger-btn');
  var mnav = document.getElementById('mobile-nav');

  function setNavOpen(open) {
    if (!hb || !mnav) return;
    hb.setAttribute('aria-expanded', open ? 'true' : 'false');
    hb.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
    if (open) {
      mnav.hidden = false;
      mnav.classList.add('is-open');
    } else {
      mnav.classList.remove('is-open');
      mnav.hidden = true;
    }
  }

  if (hb && mnav) {
    hb.addEventListener('click', function () {
      var open = hb.getAttribute('aria-expanded') === 'true';
      setNavOpen(!open);
    });
    // Close when any in-panel anchor is tapped (link still scrolls to target)
    mnav.addEventListener('click', function (e) {
      var a = e.target.closest('a');
      if (a) setNavOpen(false);
    });
    // ESC closes
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && hb.getAttribute('aria-expanded') === 'true') {
        setNavOpen(false);
        hb.focus();
      }
    });
    // If viewport grows past the hamburger breakpoint while open, close it
    window.matchMedia('(min-width: 981px)').addEventListener('change', function (ev) {
      if (ev.matches) setNavOpen(false);
    });
  }

  /* ---------- IntersectionObserver reveals ---------- */
  var revealSelector = '.section-head, .price-board, .about-grid, .gallery-item, .review-card, .diff-item, .product-card, .fv-card, .blog-card, .gc-card';
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) {
          e.target.classList.add('is-in');
          io.unobserve(e.target);
        }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
    document.querySelectorAll(revealSelector).forEach(function (el) { io.observe(el); });
  } else {
    document.querySelectorAll(revealSelector).forEach(function (el) { el.classList.add('is-in'); });
  }

  /* ---------- Hero carousel ---------- */
  var carousel = document.querySelector('.hero-carousel');
  if (carousel) {
    var slides = carousel.querySelectorAll('.slide');
    var dots = carousel.querySelectorAll('[data-carousel-dot]');
    var live = carousel.querySelector('[data-carousel-live]');
    var prev = carousel.querySelector('[data-carousel-prev]');
    var next = carousel.querySelector('[data-carousel-next]');
    var total = slides.length;
    var current = 0;
    var timer = null;
    var paused = false;

    function show(i) {
      current = (i + total) % total;
      slides.forEach(function (s, idx) {
        var on = idx === current;
        s.classList.toggle('is-active', on);
        if (on) { s.removeAttribute('aria-hidden'); } else { s.setAttribute('aria-hidden', 'true'); }
      });
      dots.forEach(function (d, idx) {
        if (idx === current) { d.setAttribute('aria-current', 'true'); } else { d.removeAttribute('aria-current'); }
      });
      if (live) { live.textContent = 'Slide ' + (current + 1) + ' of ' + total; }
    }

    function tick() { show(current + 1); }
    function start() {
      if (reduceMotion || paused) return;
      stop();
      timer = setInterval(tick, 6000);
    }
    function stop() { if (timer) { clearInterval(timer); timer = null; } }

    dots.forEach(function (d) {
      d.addEventListener('click', function () {
        var i = parseInt(d.getAttribute('data-carousel-dot'), 10);
        show(i); start();
      });
    });
    if (prev) prev.addEventListener('click', function () { show(current - 1); start(); });
    if (next) next.addEventListener('click', function () { show(current + 1); start(); });

    carousel.addEventListener('mouseenter', function () { paused = true; stop(); });
    carousel.addEventListener('mouseleave', function () { paused = false; start(); });

    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState !== 'visible') { stop(); } else { start(); }
    });

    // Keyboard: arrows navigate, space toggles
    carousel.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowLeft') { e.preventDefault(); show(current - 1); start(); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); show(current + 1); start(); }
      else if (e.key === ' ' && e.target && e.target.tagName !== 'A' && e.target.tagName !== 'BUTTON') {
        e.preventDefault();
        if (timer) { stop(); paused = true; } else { paused = false; start(); }
      }
    });

    // Touch/swipe
    var startX = 0, startY = 0, tracking = false;
    carousel.addEventListener('pointerdown', function (e) {
      if (e.pointerType !== 'touch') return;
      tracking = true; startX = e.clientX; startY = e.clientY;
    });
    carousel.addEventListener('pointerup', function (e) {
      if (!tracking) return;
      tracking = false;
      var dx = e.clientX - startX;
      var dy = e.clientY - startY;
      if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) {
        if (dx < 0) show(current + 1); else show(current - 1);
        start();
      }
    });
    carousel.addEventListener('pointercancel', function () { tracking = false; });

    if (reduceMotion) {
      // Force static first slide
      show(0);
    } else {
      show(0);
      start();
    }
  }

  /* ---------- Email obfuscation (data-u + data-d) ---------- */
  // Visible email links with .email-link class — not currently used on the page
  // but pattern is documented for when a real email replaces the placeholder.
  document.querySelectorAll('.email-link').forEach(function (el) {
    var u = el.getAttribute('data-u');
    var d = el.getAttribute('data-d');
    if (!u || !d) return;
    var addr = u + '@' + d;
    el.setAttribute('href', 'mailto:' + addr);
    if (!el.textContent.trim() || el.querySelector('.email-fallback')) {
      el.textContent = addr;
    }
  });

  // Contact form: assemble action from data-u/data-d at runtime (no raw address in source)
  var form = document.getElementById('contact-form');
  if (form) {
    form.addEventListener('submit', function (e) {
      // Honeypot check (client-side courtesy; server must enforce too)
      var hp = form.querySelector('#f-website');
      if (hp && hp.value) { e.preventDefault(); return; }
      var u = form.getAttribute('data-u');
      var d = form.getAttribute('data-d');
      if (u && d) {
        form.setAttribute('action', 'mailto:' + u + '@' + d);
        form.setAttribute('enctype', 'text/plain');
      }
    });
  }

  /* ---------- First-visit popup ---------- */
  var POPUP_KEY = 'aam-popup-dismissed-v1';
  var backdrop = document.getElementById('popup-backdrop');
  var popupImg = document.getElementById('popup-img');
  var popupFallback = document.getElementById('popup-fallback');
  var lastFocus = null;

  function showFallback() {
    if (popupImg) popupImg.classList.add('is-hidden');
    if (popupFallback) popupFallback.classList.add('is-shown');
  }

  if (popupImg) {
    popupImg.addEventListener('error', showFallback);
    // If naturalWidth resolves to 0, the image failed without firing `error` (rare edge).
    popupImg.addEventListener('load', function () {
      if (popupImg.naturalWidth === 0) showFallback();
    });
  }

  function trapFocus(e) {
    if (!backdrop.classList.contains('is-open')) return;
    if (e.key !== 'Tab') return;
    var focusables = backdrop.querySelectorAll('a[href], button, input, textarea, [tabindex]:not([tabindex="-1"])');
    if (!focusables.length) return;
    var first = focusables[0];
    var last = focusables[focusables.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  }

  function openPopup() {
    if (!backdrop) return;
    lastFocus = document.activeElement;
    backdrop.hidden = false;
    backdrop.classList.add('is-open');
    requestAnimationFrame(function () { backdrop.classList.add('is-visible'); });
    var closeBtn = backdrop.querySelector('.popup-close');
    if (closeBtn) closeBtn.focus();
    document.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
  }

  function closePopup() {
    if (!backdrop) return;
    try { localStorage.setItem(POPUP_KEY, '1'); } catch (_) {}
    backdrop.classList.remove('is-visible');
    setTimeout(function () {
      backdrop.classList.remove('is-open');
      backdrop.hidden = true;
      document.body.style.overflow = '';
      if (lastFocus && typeof lastFocus.focus === 'function') { lastFocus.focus(); }
    }, reduceMotion ? 0 : 400);
    document.removeEventListener('keydown', onKey);
  }

  function onKey(e) {
    if (e.key === 'Escape') { closePopup(); }
    else { trapFocus(e); }
  }

  if (backdrop) {
    backdrop.addEventListener('click', function (e) {
      if (e.target === backdrop) closePopup();
    });
    backdrop.querySelectorAll('[data-popup-close]').forEach(function (b) {
      b.addEventListener('click', closePopup);
    });

    var dismissed = false;
    try { dismissed = localStorage.getItem(POPUP_KEY) === '1'; } catch (_) {}
    if (!dismissed) {
      setTimeout(openPopup, reduceMotion ? 0 : 600);
    }
  }
})();
