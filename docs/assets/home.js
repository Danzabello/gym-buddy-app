/* Gym Buddy home page motion. GSAP + ScrollTrigger + Lenis, all self-hosted.
   The page is complete without this file: if anything below is missing or
   throws, html.motion is removed and every section shows in its final state. */
(function () {
  'use strict';
  window.__gb = 1; // tells the inline head script that this file ran

  var root = document.documentElement;
  var reduce = matchMedia('(prefers-reduced-motion: reduce)');
  // A change of the reduced-motion setting mid-visit just reloads the page.
  reduce.addEventListener('change', function () { location.reload(); });

  // Pause avatars that are off screen (works without GSAP too).
  var avs = document.querySelectorAll('.av');
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { e.target.classList.toggle('paused', !e.isIntersecting); });
    }, { rootMargin: '80px' });
    avs.forEach(function (a) { a.classList.add('paused'); io.observe(a); });
  }

  var g = window.gsap, ST = window.ScrollTrigger;
  if (reduce.matches || !g || !ST) { root.classList.remove('motion'); return; }

  try {
    g.registerPlugin(ST);
    ST.config({ ignoreMobileResize: true });

    // Parallax: far layers move least. Slow and soft (scrub 0.8 s).
    [['.l-sky', -3], ['.l-grid', -6], ['.l-hills', -12], ['.l-sparks', -24], ['.l-bear', -10], ['.l-max', -18]]
      .forEach(function (l) {
        g.to(l[0], { yPercent: l[1], ease: 'none',
          scrollTrigger: { trigger: '.hero', start: 'top top', end: 'bottom top', scrub: 0.8 } });
      });
    g.to('.hero-copy', { yPercent: -6, ease: 'none',
      scrollTrigger: { trigger: '.hero', start: 'top top', end: 'bottom top', scrub: 0.8 } });

    // Reveal on scroll.
    ST.batch('.rv', {
      start: 'top 88%', once: true,
      onEnter: function (els) {
        g.to(els, { opacity: 1, y: 0, duration: 1.1, ease: 'power3.out', stagger: 0.12, overwrite: true });
      }
    });

    // The streak panel grows to fill the screen as you scroll through its track.
    var track = document.querySelector('.expand-track');
    if (track) {
      var tl = g.timeline({ defaults: { ease: 'none' },
        scrollTrigger: { trigger: track, start: 'top top', end: 'bottom bottom', scrub: 0.8 } });
      tl.to('.expand-panel', { clipPath: 'inset(0vh 0vw round 0px)', duration: 0.45 }, 0)
        .to('.ring-arc', { strokeDashoffset: 0, duration: 0.4 }, 0.1)
        .to('.expand-text', { opacity: 1, duration: 0.2 }, 0.55);
    }

    // Smooth scroll and cursor follower: fine pointer + hover + no reduced
    // motion only. Touch and keyboard keep native scrolling.
    var fine = matchMedia('(prefers-reduced-motion: no-preference) and (hover: hover) and (pointer: fine)');
    var lenis, tick, dropCursor;

    function cursorOn() {
      var c = document.createElement('div');
      c.className = 'cursor';
      c.setAttribute('aria-hidden', 'true');
      document.body.appendChild(c);
      var qx = g.quickTo(c, 'x', { duration: 0.7, ease: 'power3' });
      var qy = g.quickTo(c, 'y', { duration: 0.7, ease: 'power3' });
      function move(e) { qx(e.clientX); qy(e.clientY); c.classList.add('on'); }
      function over(e) { c.classList.toggle('grow', !!(e.target.closest && e.target.closest('a, button, .card'))); }
      function leave() { c.classList.remove('on'); }
      addEventListener('pointermove', move, { passive: true });
      document.addEventListener('pointerover', over, { passive: true });
      root.addEventListener('mouseleave', leave);
      return function () {
        removeEventListener('pointermove', move);
        document.removeEventListener('pointerover', over);
        root.removeEventListener('mouseleave', leave);
        c.remove();
      };
    }

    function enable() {
      if (window.Lenis) {
        lenis = new window.Lenis({ autoRaf: false, lerp: 0.085, wheelMultiplier: 0.9 });
        lenis.on('scroll', ST.update);
        tick = function (t) { lenis.raf(t * 1000); };
        g.ticker.add(tick);
        g.ticker.lagSmoothing(0);
      }
      dropCursor = cursorOn();
    }
    function disable() {
      if (lenis) { g.ticker.remove(tick); lenis.destroy(); lenis = null; }
      if (dropCursor) { dropCursor(); dropCursor = null; }
    }
    function sync() { disable(); if (fine.matches) enable(); }
    fine.addEventListener('change', sync);
    sync();
  } catch (err) {
    // Fall back to the static page: kill any half-built triggers, show everything.
    try { ST.getAll().forEach(function (t) { t.kill(); }); } catch (e) { /* ignore */ }
    root.classList.remove('motion');
    g.set('.layer, .rv, .expand-panel, .expand-text, .ring-arc', { clearProps: 'all' });
  }
})();
