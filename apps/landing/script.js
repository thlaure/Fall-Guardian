(function () {
  'use strict';

  var prefersReduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ── Countdown ring ── */
  var ring     = document.querySelector('.ring-progress');
  var numberEl = document.getElementById('ring-number');

  function animateNumber(el, from, to, duration) {
    var startTime = null;
    function step(ts) {
      if (!startTime) { startTime = ts; }
      var p = Math.min((ts - startTime) / duration, 1);
      var eased = 1 - Math.pow(1 - p, 3);
      el.textContent = String(Math.round(from + (to - from) * eased));
      if (p < 1) { requestAnimationFrame(step); }
    }
    requestAnimationFrame(step);
  }

  if (ring && numberEl) {
    if (prefersReduced) {
      ring.style.strokeDashoffset = '63';
      numberEl.textContent = '27';
    } else {
      ring.style.transition = 'none';
      ring.style.strokeDashoffset = '0';
      numberEl.textContent = '30';
      ring.getBoundingClientRect(); /* force reflow */
      setTimeout(function () {
        ring.style.transition = 'stroke-dashoffset 1.5s cubic-bezier(0.4, 0, 0.6, 1)';
        ring.style.strokeDashoffset = '63';
        animateNumber(numberEl, 30, 27, 1500);
      }, 700);
    }
  }

  /* ── Scroll reveal ── */
  if (!prefersReduced && 'IntersectionObserver' in window) {
    var revealObs = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          revealObs.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12 });

    document.querySelectorAll('.reveal').forEach(function (el) {
      revealObs.observe(el);
    });
  } else {
    document.querySelectorAll('.reveal').forEach(function (el) {
      el.classList.add('visible');
    });
  }

  /* ── FAQ accordion ── */
  document.querySelectorAll('.faq-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var expanded = btn.getAttribute('aria-expanded') === 'true';
      var answer   = document.getElementById(btn.getAttribute('aria-controls'));
      btn.setAttribute('aria-expanded', String(!expanded));
      if (answer) { answer.hidden = expanded; }
    });
  });

  /* ── Waitlist form ── */
  var form        = document.getElementById('waitlist-form');
  if (!form) { return; }

  var emailInput   = document.getElementById('wl-email');
  var consentInput = document.getElementById('wl-consent');
  var errEmail     = document.getElementById('err-email');
  var errConsent   = document.getElementById('err-consent');
  var formStatus   = document.getElementById('form-status');
  var EMAIL_RE     = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  function setError(el, input, msg) {
    el.textContent = msg;
    if (input) { input.classList.add('field-invalid'); }
  }

  function clearError(el, input) {
    el.textContent = '';
    if (input) { input.classList.remove('field-invalid'); }
  }

  emailInput.addEventListener('input',    function () { clearError(errEmail, emailInput); });
  consentInput.addEventListener('change', function () { clearError(errConsent, null); });

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var valid = true;
    var focus = null;

    var val = emailInput.value.trim();
    if (!val) {
      setError(errEmail, emailInput, 'Email address is required.');
      valid = false; focus = focus || emailInput;
    } else if (!EMAIL_RE.test(val)) {
      setError(errEmail, emailInput, 'Please enter a valid email address.');
      valid = false; focus = focus || emailInput;
    } else {
      clearError(errEmail, emailInput);
    }

    if (!consentInput.checked) {
      setError(errConsent, null, 'Your consent is required to join the waitlist.');
      valid = false; focus = focus || consentInput;
    } else {
      clearError(errConsent, null);
    }

    if (!valid) { if (focus) { focus.focus(); } return; }

    form.hidden = true;
    formStatus.hidden = false;
    formStatus.focus();
  });
}());
