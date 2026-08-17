/* ===========================================================================
   Agentelic — the identifying animation. SHELL.md §8.

   What it depicts: a build pipeline. Units enter at the top, descend stage by
   stage, and at the gate some are refused and fall away. That is the subject of
   this site, which is why it is the thing that moves.

   RULE 2, and it is the whole reason this file is separate and closed:
   IT RENDERS NO DATA AND ASSERTS NOTHING.

   - It reads nothing from the document. It takes no argument, no dataset, no
     attribute, no query string.
   - It writes nothing back into the document except its own <g> children.
   - Its two constants below are DELIBERATELY not any figure this page prints.
     gpscoord.com published `12 Active Pathfinders` for months where the 12 was
     `for (let i = 0; i < 12; i++)` inside a decorative canvas. launch-gate.mjs
     parses the block below and refuses to publish if either number appears as a
     standalone number anywhere in the page's text.

   Delete the <script> tag that loads this file and every figure, chip, status
   row, hash and word on the page is still there.
   =========================================================================== */

/* IDENTITY-CONSTANTS-START — parsed by launch-gate.mjs. Numbers here must not
   appear as text on the page, and the gate refuses the build if one does. They
   are chosen to be nobody's measurement: the real pipeline has four stages, the
   deployed surface has ten tools, and neither number is here. */
const STAGES = 9;
const UNITS = 13;
/* IDENTITY-CONSTANTS-END */

(function pipeline() {
  "use strict";
  const root = document.querySelector("[data-identity-animation]");
  if (!root) return;
  const layer = root.querySelector("#ident-units");
  if (!layer) return;

  const NS = "http://www.w3.org/2000/svg";
  const TOP = 40;
  const BOT = 420;
  const X = 150;
  const SPAN = (BOT - TOP) / (STAGES - 1);
  const GATE = 4; // the stage index whose plate is the refusing one

  // Each unit is a closed record: a position along the pipe and whether this
  // pass through the gate refused it. Nothing outside this closure can read it.
  const units = [];
  for (let i = 0; i < UNITS; i++) {
    const el = document.createElementNS(NS, "rect");
    el.setAttribute("width", "11");
    el.setAttribute("height", "11");
    el.setAttribute("rx", "2.5");
    layer.appendChild(el);
    units.push({ el, t: -(i / UNITS) * (STAGES - 1), refused: false, drift: 0 });
  }

  // Reset a unit at the top of the pipe. `refused` is decided once, here, by
  // the unit's own index parity and a rotating offset — no randomness that
  // could be mistaken for sampling, and no input from anywhere.
  let pass = 0;
  function respawn(u, i) {
    u.t = -0.6;
    u.drift = 0;
    u.refused = (i + pass) % 3 === 0;
    if (i === 0) pass++;
  }

  function paint() {
    for (const u of units) {
      const t = u.t;
      if (t < -0.5) {
        u.el.setAttribute("opacity", "0");
        continue;
      }
      const y = TOP + Math.max(0, t) * SPAN;
      const stalled = u.refused && t >= GATE;
      const x = X + (stalled ? u.drift : 0);
      const fade = stalled ? Math.max(0, 1 - u.drift / 46) : 1;
      u.el.setAttribute("x", (x - 5.5).toFixed(1));
      u.el.setAttribute("y", (y - 5.5).toFixed(1));
      u.el.setAttribute("fill", stalled ? "var(--warn)" : "var(--acc)");
      u.el.setAttribute("opacity", (fade * (t < 0 ? 1 + t * 2 : 0.92)).toFixed(2));
    }
  }

  paint(); // first frame, always — this is also the reduced-motion rendering

  const reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)");
  if (reduce && reduce.matches) return; // one frame and stop. Not optional.

  // Cheap: capped frame rate, stopped when the tab is hidden, stopped when the
  // pipe scrolls out of view. The visibility test is a rect check on a timer,
  // NOT an IntersectionObserver — IO does not fire in a non-compositing
  // renderer and an animation that never starts reads as a broken page.
  const FRAME = 1000 / 24;
  let last = 0;
  let onScreen = true;
  let raf = 0;

  function visible() {
    const r = root.getBoundingClientRect();
    return r.bottom > 0 && r.top < (window.innerHeight || 0) + 80;
  }
  setInterval(function () {
    onScreen = visible();
  }, 900);

  function step(now) {
    raf = requestAnimationFrame(step);
    if (document.hidden || !onScreen) {
      last = now;
      return;
    }
    if (now - last < FRAME) return;
    const dt = Math.min(120, now - last) / 1000;
    last = now;
    for (let i = 0; i < units.length; i++) {
      const u = units[i];
      if (u.refused && u.t >= GATE) {
        u.drift += dt * 34;
        if (u.drift > 48) respawn(u, i);
      } else {
        u.t += dt * 0.62;
        if (u.t > STAGES - 1 + 0.6) respawn(u, i);
      }
    }
    paint();
  }
  raf = requestAnimationFrame(step);

  // If the tab is restored, do not integrate the whole hidden interval at once.
  document.addEventListener("visibilitychange", function () {
    last = performance.now();
  });
})();
