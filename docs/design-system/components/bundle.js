/* @ds-bundle: {"format":4,"namespace":"PK4","components":[{"name":"Panel"},{"name":"LampWindow"},{"name":"LampLens"},{"name":"NixieReadout"},{"name":"DrumCounter"},{"name":"MovingCoilMeter"},{"name":"EdgewiseMeter"},{"name":"PushButton"},{"name":"RoundPushButton"},{"name":"GuardedButton"},{"name":"RotarySelector"},{"name":"ToggleSwitch"},{"name":"PencilStrip"},{"name":"Annunciator"}]} */
(function () {
  'use strict';
  var NS = 'http://www.w3.org/2000/svg';
  function h(tag, attrs, kids) {
    var el = document.createElement(tag), k;
    attrs = attrs || {};
    for (k in attrs) {
      if (k === 'class') el.className = attrs[k];
      else if (k === 'text') el.textContent = attrs[k];
      else el.setAttribute(k, attrs[k]);
    }
    (kids || []).forEach(function (c) { if (c) el.appendChild(c); });
    return el;
  }
  function s(tag, attrs) {
    var el = document.createElementNS(NS, tag), k;
    for (k in attrs) el.setAttribute(k, attrs[k]);
    return el;
  }
  var counters = {};
  function des(prefix) { counters[prefix] = (counters[prefix] || 0) + 1; return prefix + counters[prefix]; }
  function tag(prefix) { return h('div', { 'class': 'pk-tag', text: des(prefix) }); }
  function plate(text, title) { return h('div', { 'class': 'pk-plate' + (title ? ' is-title' : ''), text: text }); }

  /* ---------- finishes: smooth sprayed paint. No bumps: a real panel is flat satin enamel, and what the eye reads
     is (1) a very fine, low-contrast grain, (2) faint large-scale unevenness of the coat, (3) the room light falling off across it. ---------- */
  function paint(grain, mottle, seed) {                 /* both noises are centred on mid-grey so 'overlay' keeps the paint colour exact */
    function band(amount) { var s0 = amount.toFixed(3), i0 = (0.5 - amount / 2).toFixed(3); return '<feFuncR type="linear" slope="' + s0 + '" intercept="' + i0 + '"/><feFuncG type="linear" slope="' + s0 + '" intercept="' + i0 + '"/><feFuncB type="linear" slope="' + s0 + '" intercept="' + i0 + '"/>'; }
    var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512">' +
      '<filter id="g" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="' + seed + '" stitchTiles="stitch"/><feColorMatrix type="saturate" values="0"/><feComponentTransfer>' + band(grain) + '<feFuncA type="linear" slope="0" intercept="1"/></feComponentTransfer></filter>' +
      '<filter id="m" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB"><feTurbulence type="fractalNoise" baseFrequency="0.006" numOctaves="2" seed="' + (seed + 5) + '" stitchTiles="stitch"/><feColorMatrix type="saturate" values="0"/><feComponentTransfer>' + band(mottle) + '<feFuncA type="linear" slope="0" intercept="0.5"/></feComponentTransfer></filter>' +
      '<rect width="512" height="512" filter="url(#g)"/><rect width="512" height="512" filter="url(#m)"/></svg>';
    return 'url("data:image/svg+xml,' + encodeURIComponent(svg) + '")';
  }
  var root = document.documentElement.style;
  root.setProperty('--tex-hammer', paint(0.16, 0.22, 7));       /* 1 satin grey-green enamel */
  root.setProperty('--tex-ivory', paint(0.12, 0.18, 11));       /* 2 satin ivory enamel */
  root.setProperty('--tex-graphite', paint(0.30, 0.30, 23));    /* 3 matte graphite, a touch more tooth */
  var FINISHES = [['hammer', '1 Grey-green enamel'], ['ivory', '2 Ivory enamel'], ['graphite', '3 Matte graphite']];
  function finish(name) { document.body.setAttribute('data-finish', name); try { localStorage.setItem('pk4-finish', name); } catch (e) {} }
  function finishSwitch() {
    var saved = 'hammer'; try { saved = localStorage.getItem('pk4-finish') || 'hammer'; } catch (e) {}
    var bar = h('div', { 'class': 'pk-finish' }, [h('span', { text: 'Panel finish' })]);
    FINISHES.forEach(function (f) {
      var b = h('button', { type: 'button', 'aria-pressed': String(f[0] === saved), text: f[1] });
      b.addEventListener('click', function () { finish(f[0]); [].forEach.call(bar.querySelectorAll('button'), function (x) { x.setAttribute('aria-pressed', String(x === b)); }); });
      bar.appendChild(b);
    });
    finish(saved); return bar;
  }
  /* ---------- screw: domed slotted head in a countersink, slot at a random angle ---------- */
  function screw(size) {
    size = size || 18; var id = 'sc' + (++screwId), svg = s('svg', { width: size, height: size, viewBox: '0 0 20 20', 'class': 'pk-screwsvg', 'aria-hidden': 'true' }), d = s('defs', {});
    var g = s('radialGradient', { id: id, cx: 0.36, cy: 0.3, r: 0.8 });
    [[0, '#ffffff'], [0.3, '#d6d8d1'], [0.7, '#8b8e86'], [1, '#4c4f48']].forEach(function (st) { g.appendChild(s('stop', { offset: st[0], 'stop-color': st[1] })); });
    d.appendChild(g); svg.appendChild(d);
    svg.appendChild(s('circle', { cx: 10, cy: 10.6, r: 9.4, fill: '#000', 'fill-opacity': 0.45 }));          /* countersink shadow */
    svg.appendChild(s('circle', { cx: 10, cy: 10, r: 8.6, fill: '#1d1f1c' }));
    svg.appendChild(s('circle', { cx: 10, cy: 10, r: 7.6, fill: 'url(#' + id + ')' }));
    var slot = s('g', { transform: 'rotate(' + Math.round(Math.random() * 170 - 85) + ' 10 10)' });
    slot.appendChild(s('rect', { x: 2.6, y: 8.9, width: 14.8, height: 2.4, rx: 0.6, fill: '#15160f' }));
    slot.appendChild(s('rect', { x: 2.6, y: 11.2, width: 14.8, height: 0.7, fill: '#ffffff', 'fill-opacity': 0.55 }));
    svg.appendChild(slot); return svg;
  }
  var screwId = 0;

  /* ---------- sound: three sources only ---------- */
  var ctx = null;
  var sound = {
    enabled: true,
    _ctx: function () {
      if (!sound.enabled) return null;
      try { ctx = ctx || new (window.AudioContext || window.webkitAudioContext)(); if (ctx.state === 'suspended') ctx.resume(); } catch (e) { ctx = null; }
      return ctx;
    },
    _burst: function (ms, freq, gain) {
      var c = sound._ctx(); if (!c) return;
      var n = Math.floor(c.sampleRate * ms / 1000), buf = c.createBuffer(1, n, c.sampleRate), d = buf.getChannelData(0), i;
      for (i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / n, 3);
      var src = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain();
      src.buffer = buf; f.type = 'bandpass'; f.frequency.value = freq; f.Q.value = 1.2; g.gain.value = gain;
      src.connect(f); f.connect(g); g.connect(c.destination); src.start();
    },
    click: function () { sound._burst(18, 2600, 0.5); },          /* button contact */
    clunk: function () { sound._burst(70, 320, 0.9); },            /* relay, selector detent, toggle, guard */
    tick: function () { sound._burst(10, 1400, 0.25); },           /* one drum wheel step */
    _buzz: null,
    buzzer: function (on) {
      var c = sound._ctx();
      if (!on) { if (sound._buzz) { sound._buzz.stop(); sound._buzz = null; } return; }
      if (!c || sound._buzz) return;
      var o = c.createOscillator(), g = c.createGain();
      o.type = 'square'; o.frequency.value = 420; g.gain.value = 0.04;
      o.connect(g); g.connect(c.destination); o.start(); sound._buzz = o;
    }
  };

  /* ---------- LampWindow / LampLens ---------- */
  function LampWindow(o) {
    var el = h('div', { 'class': 'pk-window', 'data-color': o.color || 'white', 'data-state': o.state || 'off', role: 'status' },
      [h('span', { 'class': 'pk-bloom' }), h('span', { text: o.label }), o.code === false ? null : h('span', { 'class': 'pk-des', text: des('HL') })]);
    if (String(o.label).length > 9) { el.style.fontSize = '12px'; el.style.lineHeight = '1'; }     /* two-line labels drop one point */
    if (o.ink) el.setAttribute('data-ink', o.ink);                     /* 'light' | 'dark': trial variants; default is per-colour ink */
    return el;
  }
  function lamp(el, state) { el.setAttribute('data-state', state); }   /* off | on | flash | test */
  function LampLens(o) {
    var lens = h('div', { 'class': 'pk-lens', 'data-color': o.color || 'white', 'data-state': o.state || 'off', role: 'status', 'aria-label': o.label },
      [h('span', { 'class': 'pk-lens-glass' }), h('span', { 'class': 'pk-lens-lit' }), h('span', { 'class': 'pk-lens-dome' })]);
    var wrap = h('div', { 'class': 'pk-col' }, [lens, h('div', { 'class': 'pk-lenscap', text: o.label }), tag('HL')]);
    wrap.lens = lens; return wrap;
  }

  /* ---------- NixieReadout ---------- */
  function NixieReadout(o) {
    var box = h('div', { 'class': 'pk-nixie' + (o.xl ? ' is-xl' : ''), role: 'status', 'aria-label': o.label });
    String(o.value).split('').forEach(function (ch) {
      box.appendChild(h('div', { 'class': 'pk-digit' + (/[.:]/.test(ch) ? ' is-sep' : '') }, [h('span', { text: ch }), h('span', { 'class': 'pk-ghost' })]));
    });
    var lab = plate(o.label); if (o.labelWidth) lab.style.width = o.labelWidth + 'px';              /* fixed label width lines up a column of readouts */
    var row = h('div', { 'class': 'pk-row' }, [h('div', { 'class': 'pk-col' }, [lab, tag('HG')]), box, o.unit ? h('div', { 'class': 'pk-unit', text: o.unit }) : null]);
    row.box = box; return row;
  }
  function nixie(row, value) {           /* same length string; separators stay */
    var cells = (row.box || row).children, str = String(value), i;
    for (i = 0; i < cells.length && i < str.length; i++) (function (cell, ch) {
      var cur = cell.children[0], ghost = cell.children[1];
      if (cur.textContent === ch) return;
      ghost.textContent = cur.textContent; cur.textContent = ch;
      cell.classList.add('is-change');
      setTimeout(function () { cell.classList.remove('is-change'); }, 60);
    })(cells[i], str.charAt(i));
  }

  /* ---------- DrumCounter ---------- */
  function DrumCounter(o) {
    var box = h('div', { 'class': 'pk-drum', role: 'status', 'aria-label': o.label }), i, j;
    for (i = 0; i < o.digits; i++) {
      var strip = h('div', { 'class': 'pk-strip' });
      for (j = 0; j < 21; j++) strip.appendChild(h('span', { text: String(j % 10) }));
      box.appendChild(h('div', { 'class': 'pk-wheel' }, [strip]));
    }
    var col = h('div', { 'class': 'pk-col' }, [box, plate(o.label), o.unit ? h('div', { 'class': 'pk-unit', text: o.unit }) : null, tag('PC')]);
    col.box = box; col.value = 0; drum(col, o.value || 0, true); return col;
  }
  function drum(col, value, silent) {     /* wheels only roll forward, carrying like a real odometer */
    var wheels = col.box.children, n = wheels.length, str = ('0000000000' + Math.floor(value)).slice(-n), i;
    for (i = 0; i < n; i++) (function (strip, d, delay) {
      var was = strip._d || 0, pos = d < was ? d + 10 : d;
      if (d === was) return;
      setTimeout(function () {
        strip.style.transform = 'translateY(' + (-pos * 32) + 'px)';
        if (!silent) sound.tick();
        if (pos >= 10) setTimeout(function () { strip.style.transition = 'none'; strip.style.transform = 'translateY(' + (-d * 32) + 'px)'; void strip.offsetHeight; strip.style.transition = ''; }, 340);
      }, delay);
      strip._d = d;
    })(wheels[i].firstChild, +str.charAt(i), (n - 1 - i) * 45);
    col.value = value;
  }

  /* ---------- meters ---------- */
  function glassOver(svg, w, hgt, rx) {               /* the dial sits behind glass: shadow from the housing at the top, one diagonal reflection */
    var id = 'gl' + (++screwId), d = s('defs', {}), g = s('linearGradient', { id: id, x1: 0, y1: 0, x2: 0, y2: 1 });
    [[0, 0.55], [0.12, 0.12], [0.3, 0]].forEach(function (st) { g.appendChild(s('stop', { offset: st[0], 'stop-color': '#000', 'stop-opacity': st[1] })); });
    d.appendChild(g); svg.appendChild(d);
    svg.appendChild(s('rect', { x: 2, y: 2, width: w - 4, height: hgt - 4, rx: rx, fill: 'url(#' + id + ')', 'pointer-events': 'none' }));
    var rg = s('linearGradient', { id: id + 'r', x1: 0, y1: 0, x2: 1, y2: 0.35 }), bl = s('filter', { id: id + 'b', x: '-20%', y: '-20%', width: '140%', height: '140%' }), cp = s('clipPath', { id: id + 'c' });
    [[0, 0], [0.18, 0.2], [0.34, 0.08], [0.5, 0]].forEach(function (st) { rg.appendChild(s('stop', { offset: st[0], 'stop-color': '#fff', 'stop-opacity': st[1] })); });
    bl.appendChild(s('feGaussianBlur', { stdDeviation: Math.max(3, w * 0.03) })); cp.appendChild(s('rect', { x: 2, y: 2, width: w - 4, height: hgt - 4, rx: rx }));
    d.appendChild(rg); d.appendChild(bl); d.appendChild(cp);
    var refl = s('g', { 'clip-path': 'url(#' + id + 'c)', 'pointer-events': 'none' });     /* a soft band of room light across the glass, no hard edge */
    refl.appendChild(s('polygon', { points: (-w * 0.1) + ',' + (-hgt * 0.1) + ' ' + (w * 0.62) + ',' + (-hgt * 0.1) + ' ' + (w * 0.3) + ',' + (hgt * 1.1) + ' ' + (-w * 0.1) + ',' + (hgt * 1.1), fill: 'url(#' + id + 'r)', filter: 'url(#' + id + 'b)' }));
    svg.appendChild(refl);
    svg.appendChild(s('rect', { x: 1, y: 1, width: w - 2, height: hgt - 2, rx: rx, fill: 'none', stroke: '#000', 'stroke-opacity': 0.6, 'stroke-width': 2 }));
  }
  function MovingCoilMeter(o) {
    var cx = 110, cy = 118, r = 88, svg = s('svg', { width: 220, height: 140, viewBox: '0 0 220 140', role: 'img', 'aria-label': o.label }), i;
    function pt(f, rr) { var a = (210 + 120 * f) * Math.PI / 180; return [cx + rr * Math.cos(a), cy + rr * Math.sin(a)]; }
    function arc(f0, f1, rr, cls, w) { var a = pt(f0, rr), b = pt(f1, rr); return s('path', { d: 'M ' + a[0].toFixed(1) + ' ' + a[1].toFixed(1) + ' A ' + rr + ' ' + rr + ' 0 0 1 ' + b[0].toFixed(1) + ' ' + b[1].toFixed(1), fill: 'none', 'class': cls, 'stroke-width': w }); }
    svg.appendChild(s('rect', { x: 1, y: 1, width: 218, height: 138, rx: 6, 'class': 'pk-face' }));
    svg.appendChild(arc(0, 1, r, 'pk-tick', 2));
    if (o.red) { var z = arc(o.red[0], o.red[1], r - 7, 'pk-redzone', 9); z.style.fill = 'none'; svg.appendChild(z); }
    for (i = 0; i <= 10; i++) { var a = pt(i / 10, r), b = pt(i / 10, r - (i % 5 ? 8 : 14)); svg.appendChild(s('line', { x1: a[0], y1: a[1], x2: b[0], y2: b[1], 'class': 'pk-tick', 'stroke-width': i % 5 ? 1 : 2 })); }
    ['0', '50', '100'].forEach(function (t, k) { var p = pt(k / 2, r - 28), tx = s('text', { x: p[0], y: p[1] + 5, 'text-anchor': 'middle' }); tx.textContent = t; svg.appendChild(tx); });
    var unit = s('text', { x: cx, y: 98, 'text-anchor': 'middle' }); unit.textContent = o.unit || '%'; svg.appendChild(unit);
    var g = s('g', { 'class': 'pk-needle' });
    g.appendChild(s('line', { x1: cx, y1: cy, x2: cx, y2: cy - 84, stroke: '#111', 'stroke-width': 2.5 }));
    svg.appendChild(g); svg.appendChild(s('circle', { cx: cx, cy: cy, r: 7, fill: '#111' }));
    glassOver(svg, 220, 140, 6);
    var wrap = h('div', { 'class': 'pk-meter' }, [svg, plate(o.label), tag('PA')]);
    wrap.needle = g; meter(wrap, o.value || 0); return wrap;
  }
  function meter(wrap, f) { f = Math.max(-0.03, Math.min(1.03, f)); wrap.needle.style.transform = 'rotate(' + (-60 + 120 * f) + 'deg)'; wrap.value = f; }
  function EdgewiseMeter(o) {
    var top = 16, bot = 204, svg = s('svg', { width: 70, height: 220, viewBox: '0 0 70 220', role: 'img', 'aria-label': o.label }), k;
    svg.appendChild(s('rect', { x: 1, y: 1, width: 68, height: 218, rx: 3, 'class': 'pk-face' }));
    svg.appendChild(s('rect', { x: 6, y: bot - (bot - top) * 0.2, width: 6, height: (bot - top) * 0.2, 'class': 'pk-redzone', stroke: 'none' }));
    for (k = 0; k <= 10; k++) {
      var y = bot - (bot - top) * k / 10;
      svg.appendChild(s('line', { x1: 14, y1: y, x2: 14 + (k % 5 ? 10 : 18), y2: y, 'class': 'pk-tick', 'stroke-width': k % 5 ? 1 : 2 }));
      if (k % 5 === 0) { var t = s('text', { x: 62, y: y + 5, 'text-anchor': 'end' }); t.textContent = String(k * 10); svg.appendChild(t); }
    }
    var p = s('polygon', { points: '12,0 40,-5 40,5', 'class': 'pk-pointer', fill: '#c8321f', stroke: '#111', 'stroke-width': 1 });
    svg.appendChild(p); glassOver(svg, 70, 220, 3);
    var wrap = h('div', { 'class': 'pk-meter' }, [svg, plate(o.label), tag('PA')]);
    wrap.pointer = p; wrap._span = [top, bot]; edge(wrap, o.value || 0); return wrap;
  }
  function edge(wrap, f) { f = Math.max(0, Math.min(1, f)); wrap.pointer.style.transform = 'translateY(' + (wrap._span[1] - (wrap._span[1] - wrap._span[0]) * f) + 'px)'; wrap.value = f; }

  /* ---------- buttons ---------- */
  function press(btn, onRelease) {
    function down(e) { if (e.type === 'keydown' && e.key !== ' ' && e.key !== 'Enter') return; if (btn._down) return; btn._down = true; btn.classList.add('is-down'); sound.click(); if (btn._onDown) btn._onDown(); }
    function up() { if (!btn._down) return; btn._down = false; btn.classList.remove('is-down'); sound.click(); if (onRelease) onRelease(); }
    btn.addEventListener('pointerdown', down); btn.addEventListener('keydown', down);
    btn.addEventListener('pointerup', up); btn.addEventListener('pointerleave', up); btn.addEventListener('keyup', up);
  }
  /* command(): the lamp answers the MACHINE, never the finger. */
  function command(btn, o) {
    o = o || {};
    if (btn._busy) return; btn._busy = true;
    var answer = o.simulate === 'fail' ? null : (o.confirmAfter || 450);
    setTimeout(function () {
      btn._busy = false;
      if (answer === null) { btn.classList.add('is-fail'); sound.clunk(); setTimeout(function () { btn.classList.remove('is-fail'); }, 1000); return; }
      sound.clunk(); if (o.onConfirm) o.onConfirm();
    }, answer === null ? 3000 : answer);
  }
  function capButton(cls, cap, label, tone) {     /* frame > hole > cap + the shadow the hole throws on a sunk cap */
    var c = h('span', { 'class': 'pk-cap', text: cap });
    return h('button', { type: 'button', 'class': cls, 'aria-label': label, 'data-tone': tone || '' }, [h('span', { 'class': 'pk-hole' }, [c, h('span', { 'class': 'pk-shade' })])]);
  }
  function PushButton(o) {
    var b = capButton('pk-btn', o.cap, o.label, o.tone);
    press(b, function () {
      command(b, { confirmAfter: o.confirmAfter, simulate: o.simulate, onConfirm: function () {
        if (o.momentary) { b.classList.add('is-lit'); setTimeout(function () { b.classList.remove('is-lit'); }, 600); }
        else b.classList.toggle('is-lit');
        if (o.onConfirm) o.onConfirm(b.classList.contains('is-lit'));
      } });
    });
    var col = h('div', { 'class': 'pk-col' }, [b, plate(o.label), tag('SB')]); col.button = b; return col;
  }
  function RoundPushButton(o) {
    var on = LampLens({ label: 'On', color: 'green', state: o.on ? 'on' : 'off' }), off = LampLens({ label: 'Off', color: 'white', state: o.on ? 'off' : 'on' });
    var b = capButton('pk-round', o.cap, o.label);
    var state = !!o.on;
    press(b, function () {
      lamp(on.lens, 'off'); lamp(off.lens, 'off');                      /* both dark while waiting */
      command(b, { confirmAfter: o.confirmAfter || 700, onConfirm: function () { state = !state; lamp(on.lens, state ? 'on' : 'off'); lamp(off.lens, state ? 'off' : 'on'); } });
    });
    var lenses = h('div', { 'class': 'pk-row' }, [on, off]); lenses.style.gap = '16px';
    return h('div', { 'class': 'pk-col' }, [lenses, b, plate(o.label), tag('SB')]);
  }
  function GuardedButton(o) {
    var b = capButton('pk-btn', o.cap, o.label, 'red');
    var flap = h('button', { type: 'button', 'class': 'pk-flap', 'aria-label': 'Guard of ' + o.label + ', lift or lower' });
    var key = o.key ? h('button', { type: 'button', 'class': 'pk-key', 'aria-label': 'Key switch of ' + o.label }) : null;
    var well = h('div', { 'class': 'pk-guard-well' }, [key, b]);
    var guard = h('div', { 'class': 'pk-guard' }, [well, flap, h('div', { 'class': 'pk-hinge' })]), closeT, holdT;
    function open() { guard.classList.remove('is-closing'); guard.classList.add('is-open'); sound.clunk(); arm(); }
    function close() {                                   /* falls under gravity, bounces twice, slams */
      if (!guard.classList.contains('is-open')) return;
      clearTimeout(closeT); guard.classList.remove('is-open'); guard.classList.add('is-closing');
      setTimeout(sound.clunk, 270); setTimeout(sound.click, 440);
      setTimeout(function () { guard.classList.remove('is-closing'); }, 540);
    }
    function arm() { clearTimeout(closeT); closeT = setTimeout(close, 5000); }
    flap.addEventListener('click', function () { if (guard.classList.contains('is-open')) close(); else open(); });
    if (key) key.addEventListener('click', function () { key.classList.toggle('is-armed'); sound.clunk(); });
    b._onDown = function () {
      arm();
      if (key && !key.classList.contains('is-armed')) return;
      holdT = setTimeout(function () { sound.clunk(); command(b, { confirmAfter: 300, onConfirm: function () { b.classList.add('is-lit'); if (o.onConfirm) o.onConfirm(); setTimeout(function () { b.classList.remove('is-lit'); close(); }, 1500); } }); }, 2000);
    };
    press(b, function () { clearTimeout(holdT); });                     /* released early: the time-delay relay drops out, nothing is sent, nothing shows */
    return h('div', { 'class': 'pk-col' }, [guard, plate(o.label), h('div', { 'class': 'pk-lenscap', text: o.key ? 'Key + hinged guard' : 'Hinged guard' }), tag('SB')]);
  }

  /* ---------- RotarySelector / ToggleSwitch / PencilStrip ---------- */
  var uid = 0;
  function defs(svg, id) {                           /* shared metal, bakelite and shadow paints */
    var d = s('defs', {}), g, f;
    function grad(kind, gid, attrs, stops) { g = s(kind, attrs); g.setAttribute('id', gid + id); stops.forEach(function (st) { g.appendChild(s('stop', { offset: st[0], 'stop-color': st[1], 'stop-opacity': st[2] === undefined ? 1 : st[2] })); }); d.appendChild(g); }
    grad('linearGradient', 'alu', { x1: 0, y1: 0, x2: 1, y2: 1 }, [[0, '#eceee8'], [0.45, '#c3c5bd'], [1, '#9da097']]);
    grad('radialGradient', 'bak', { cx: 0.38, cy: 0.3, r: 0.85 }, [[0, '#5b5b55'], [0.45, '#262624'], [1, '#080807']]);
    grad('linearGradient', 'bar', { x1: 0, y1: 0, x2: 1, y2: 0 }, [[0, '#0b0b0a'], [0.3, '#4e4e49'], [0.5, '#2c2c29'], [0.8, '#141413'], [1, '#050505']]);
    grad('linearGradient', 'steel', { x1: 0, y1: 0, x2: 1, y2: 0 }, [[0, '#6f726b'], [0.35, '#f4f5f0'], [0.6, '#b4b7af'], [1, '#55584f']]);
    grad('radialGradient', 'spec', { cx: 0.35, cy: 0.25, r: 0.6 }, [[0, '#ffffff', 0.35], [1, '#ffffff', 0]]);
    f = s('filter', { id: 'blur' + id, x: '-40%', y: '-40%', width: '180%', height: '180%' }); f.appendChild(s('feGaussianBlur', { stdDeviation: 4 })); d.appendChild(f);
    svg.appendChild(d);
  }
  function RotarySelector(o) {
    var n = o.positions || 4, step = 60, start = -step * (n - 1) / 2, id = ++uid, C = 120, i;
    var size = o.size || 160, svg = s('svg', { width: size, height: size, viewBox: '0 0 240 240', 'aria-hidden': 'true' }); defs(svg, id);
    svg.appendChild(s('circle', { cx: C, cy: C, r: 114, fill: 'url(#alu' + id + ')', stroke: '#2a2a27', 'stroke-width': 2 }));
    svg.appendChild(s('circle', { cx: C, cy: C, r: 110, fill: 'none', stroke: '#ffffff', 'stroke-opacity': 0.45, 'stroke-width': 1 }));
    for (i = 0; i < n; i++) {
      var a = (start + step * i - 90) * Math.PI / 180, cs = Math.cos(a), sn = Math.sin(a);
      svg.appendChild(s('line', { x1: C + 66 * cs, y1: C + 66 * sn, x2: C + 78 * cs, y2: C + 78 * sn, stroke: '#1b1b19', 'stroke-width': 3 }));
      var t = s('text', { x: C + 96 * cs, y: C + 96 * sn + 10, 'text-anchor': 'middle', 'font-size': 30 }); t.textContent = String(i + 1); svg.appendChild(t);
      svg.appendChild(s('circle', { cx: C + 96 * cs, cy: C + 96 * sn, r: 20, fill: '#000', 'fill-opacity': 0, 'data-pos': i + 1 }));
    }
    [[-1, 1], [1, 1]].forEach(function (p) { svg.appendChild(s('circle', { cx: C + p[0] * 62, cy: C + p[1] * 78, r: 4.5, fill: 'url(#steel' + id + ')', stroke: '#2a2a27' })); });
    svg.appendChild(s('circle', { cx: C + 5, cy: C + 8, r: 56, fill: '#000', 'fill-opacity': 0.55, filter: 'url(#blur' + id + ')' }));
    svg.appendChild(s('circle', { cx: C, cy: C, r: 54, fill: 'url(#bak' + id + ')', stroke: '#000', 'stroke-width': 1.5 }));
    var turn = s('g', { 'class': 'pk-knobturn' });
    turn.appendChild(s('circle', { cx: C, cy: C, r: 51, fill: 'none', stroke: '#000', 'stroke-opacity': 0.75, 'stroke-width': 5, 'stroke-dasharray': '3.2 3.475' }));
    turn.appendChild(s('rect', { x: C - 15, y: C - 60, width: 30, height: 120, rx: 13, fill: '#000', 'fill-opacity': 0.5, filter: 'url(#blur' + id + ')', transform: 'translate(3 5)' }));
    turn.appendChild(s('rect', { x: C - 15, y: C - 60, width: 30, height: 120, rx: 13, fill: 'url(#bar' + id + ')', stroke: '#000', 'stroke-width': 1 }));
    turn.appendChild(s('rect', { x: C - 1.75, y: C - 55, width: 3.5, height: 34, rx: 1.5, fill: '#f1efe6' }));
    turn.appendChild(s('circle', { cx: C, cy: C, r: 7, fill: 'url(#steel' + id + ')', stroke: '#111' }));
    turn.appendChild(s('rect', { x: C - 6, y: C - 1, width: 12, height: 2, fill: '#222' }));
    svg.appendChild(turn);
    svg.appendChild(s('circle', { cx: C, cy: C, r: 54, fill: 'url(#spec' + id + ')', 'pointer-events': 'none' }));
    var knob = h('button', { type: 'button', 'class': 'pk-svgbtn', role: 'slider', 'aria-label': 'Session selector', 'aria-valuemin': '1', 'aria-valuemax': String(n) }); knob.appendChild(svg);
    var el = knob; el.position = o.value || 1;
    function angle(pos) { return start + step * (pos - 1); }
    function set(pos) { el.position = pos; turn.style.transform = 'rotate(' + angle(pos) + 'deg)'; knob.setAttribute('aria-valuenow', pos); if (o.onChange) o.onChange(pos); }
    function stepBy(dir) {                              /* one detent; at an end stop the knob only leans on the pin */
      var pos = el.position + dir;
      if (pos < 1 || pos > n) { sound.click(); turn.style.transform = 'rotate(' + (angle(el.position) + dir * 6) + 'deg)'; setTimeout(function () { turn.style.transform = 'rotate(' + angle(el.position) + 'deg)'; }, 90); return false; }
      sound.clunk(); set(pos); return true;
    }
    function goTo(target) { var dir = target > el.position ? 1 : -1; (function go() { if (el.position === target) return; stepBy(dir); setTimeout(go, 110); })(); }
    knob.addEventListener('click', function (e) {
      var hit = e.target && e.target.getAttribute && e.target.getAttribute('data-pos');
      if (hit) { goTo(+hit); return; }
      var r = knob.getBoundingClientRect(); stepBy(e.clientX - r.left >= r.width / 2 ? 1 : -1);   /* right half: clockwise, left half: back */
    });
    knob.addEventListener('keydown', function (e) { if (e.key === 'ArrowRight' || e.key === 'ArrowUp') stepBy(1); if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') stepBy(-1); });
    set(el.position);
    var col = h('div', { 'class': 'pk-col' }, [plate(o.label || 'Session selector'), knob, tag('SA')]); col.selector = el; return col;
  }
  function ToggleSwitch(o) {
    var id = ++uid, svg = s('svg', { width: 72, height: 140, viewBox: '0 0 72 140', 'aria-hidden': 'true' }), cx = 36, cy = 70, i, pts = [];
    defs(svg, id);
    svg.appendChild(s('rect', { x: 1, y: 1, width: 70, height: 138, rx: 5, fill: 'url(#alu' + id + ')', stroke: '#2a2a27', 'stroke-width': 2 }));
    [[9, 9], [63, 9], [9, 131], [63, 131]].forEach(function (p) { svg.appendChild(s('circle', { cx: p[0], cy: p[1], r: 3.5, fill: 'url(#steel' + id + ')', stroke: '#2a2a27' })); });
    [['ON', 19], ['OFF', 131]].forEach(function (l) { var t = s('text', { x: cx, y: l[1], 'text-anchor': 'middle', 'font-size': 12 }); t.textContent = l[0]; svg.appendChild(t); });
    for (i = 0; i < 6; i++) pts.push((cx + 17 * Math.cos(Math.PI / 3 * i)).toFixed(1) + ',' + (cy + 17 * Math.sin(Math.PI / 3 * i)).toFixed(1));
    svg.appendChild(s('polygon', { points: pts.join(' '), fill: '#000', 'fill-opacity': 0.4, transform: 'translate(2 3)' }));
    svg.appendChild(s('polygon', { points: pts.join(' '), fill: 'url(#steel' + id + ')', stroke: '#33352f', 'stroke-width': 1 }));
    svg.appendChild(s('circle', { cx: cx, cy: cy, r: 11, fill: '#8a8d85', stroke: '#33352f' }));
    svg.appendChild(s('circle', { cx: cx, cy: cy, r: 8, fill: '#0c0c0b' }));
    var lever = s('g', { 'class': 'pk-lever' }), d = 'M' + (cx - 4) + ',' + cy + ' L' + (cx - 7.5) + ',' + (cy - 36) + ' A7.5,7.5 0 0 1 ' + (cx + 7.5) + ',' + (cy - 36) + ' L' + (cx + 4) + ',' + cy + ' Z';
    lever.appendChild(s('path', { d: d, fill: '#000', 'fill-opacity': 0.45, transform: 'translate(4 3)', filter: 'url(#blur' + id + ')' }));
    lever.appendChild(s('path', { d: d, fill: 'url(#steel' + id + ')', stroke: '#33352f', 'stroke-width': 1 }));
    lever.appendChild(s('circle', { cx: cx - 2, cy: cy - 38, r: 3, fill: '#fff', 'fill-opacity': 0.7 }));
    svg.appendChild(s('circle', { cx: cx, cy: cy, r: 7.5, fill: 'url(#steel' + id + ')', stroke: '#33352f' }));   /* the tip seen end-on, mid-throw */
    svg.appendChild(lever);
    var t = h('button', { type: 'button', 'class': 'pk-svgbtn is-rect' + (o.on ? ' is-on' : ''), role: 'switch', 'aria-checked': o.on ? 'true' : 'false', 'aria-label': o.label }); t.appendChild(svg);
    t.addEventListener('click', function () { var on = !t.classList.contains('is-on'); t.classList.toggle('is-on', on); t.setAttribute('aria-checked', on ? 'true' : 'false'); setTimeout(sound.clunk, 60); if (o.onChange) o.onChange(on); });
    return h('div', { 'class': 'pk-col' }, [plate(o.label), t, tag('SA')]);
  }
  function PencilStrip(o) { return h('input', { type: 'text', 'class': 'pk-pencil', maxlength: '12', 'aria-label': o.label || 'Project name, in pencil', value: o.value || '' }); }

  /* ---------- Panel ---------- */
  function Panel(o, kids) {
    var head = h('div', { 'class': 'pk-panel-head' }, [screw(), plate(o.title, true), screw()]);
    var foot = h('div', { 'class': 'pk-panel-head' }, [screw(), screw()]);
    var p = h('section', { 'class': 'pk-panel' }, [head].concat(kids || []).concat([foot])); if (o.width) p.style.width = o.width + 'px'; if (o.finish) p.setAttribute('data-finish', o.finish); return p;
  }

  /* ---------- Annunciator: the alarm state machine ---------- */
  function Annunciator(o) {
    var rows = o.rows, cols = o.sessions || 4, cells = {}, grid = h('div'), r, c;
    grid.style.cssText = 'display:grid;grid-template-columns:190px repeat(' + cols + ',var(--window-w));gap:8px;align-items:center';
    grid.appendChild(plate('Session'));
    for (c = 1; c <= cols; c++) { var num = h('div', { text: String(c) }); num.style.cssText = 'font:700 30px/32px var(--font-label);text-align:center'; grid.appendChild(num); }
    if (o.pencil) { grid.appendChild(plate('Project · pencil')); for (c = 1; c <= cols; c++) grid.appendChild(PencilStrip({ value: (o.pencil[c - 1] || ''), label: 'Project name, session ' + c })); }
    rows.forEach(function (row) {
      grid.appendChild(plate(row.label));
      for (var c2 = 1; c2 <= cols; c2++) { var w = LampWindow({ label: row.cap, color: row.color, code: o.code }); cells[row.id + ':' + c2] = { el: w, alarm: !!row.alarm, active: false, acked: false }; grid.appendChild(w); }
    });
    var grille = h('div', { 'class': 'pk-grille' });
    function refresh() {
      var unacked = false, k;
      for (k in cells) { var x = cells[k]; if (grid._test) { lamp(x.el, 'test'); continue; } if (!x.active) lamp(x.el, 'off'); else if (x.alarm && !x.acked) { lamp(x.el, 'flash'); unacked = true; } else lamp(x.el, 'on'); }
      var sounding = unacked && !grid._silenced; grille.classList.toggle('is-sounding', sounding); sound.buzzer(sounding);
    }
    var api = {
      el: grid, grille: grille,
      set: function (rowId, session, active) { var x = cells[rowId + ':' + session]; if (!x || x.active === active) return; x.active = active; x.acked = false; if (active && x.alarm) grid._silenced = false; sound.clunk(); refresh(); },
      acknowledge: function () { for (var k in cells) if (cells[k].active) cells[k].acked = true; refresh(); },
      silence: function () { grid._silenced = true; refresh(); },
      lampTest: function (on) { grid._test = on; refresh(); }
    };
    return api;
  }

  window.PK4 = { h: h, plate: plate, tag: tag, screw: screw, finish: finish, finishSwitch: finishSwitch, sound: sound, Panel: Panel, LampWindow: LampWindow, LampLens: LampLens, lamp: lamp, NixieReadout: NixieReadout, nixie: nixie, DrumCounter: DrumCounter, drum: drum, MovingCoilMeter: MovingCoilMeter, meter: meter, EdgewiseMeter: EdgewiseMeter, edge: edge, PushButton: PushButton, RoundPushButton: RoundPushButton, GuardedButton: GuardedButton, RotarySelector: RotarySelector, ToggleSwitch: ToggleSwitch, PencilStrip: PencilStrip, Annunciator: Annunciator, press: press, command: command };
})();
