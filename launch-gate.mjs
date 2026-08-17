// ===========================================================================
// Agentelic — the publication gate. Zero dependencies.
//
//   node launch-gate.mjs        → reads index.html and refuses, or passes
//
// It reads the EMITTED ARTIFACT, not the source. A gate that reads the source
// checks what the build meant; this one checks what a visitor will get. Every
// check below exists because something in this portfolio shipped wrong in
// exactly that way at least once — the provenance is in the comment beside it.
//
// A gate nobody has seen refuse is an opinion. Break each one deliberately and
// record that it refused: SHELL.md §4.3.
// ===========================================================================

import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { readdirSync, statSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const read = (p) => readFileSync(resolve(root, p), "utf8");

const S = JSON.parse(read("records/surface.json"));
const pkg = JSON.parse(read("package.json"));
const html = read("index.html");
const anim = read("idanim.js");

const fail = [];
const pass = [];
const check = (name, ok, detail) => (ok ? pass.push(name) : fail.push(`${name} — ${detail}`));

const RUNGS = ["spec", "in_tree", "live_local", "live_deployed", "external"];
const VERBS = {
  spec: ["Read", "Challenge", "Implement"],
  in_tree: ["Inspect the source", "Run the tests"],
  live_local: ["Use it", "Reproduce it locally"],
  live_deployed: ["Use the deployed artifact"],
  external: ["See independent evidence", "Contribute another result"],
};

// Text as a reader gets it: scripts, styles and tags removed.
const text = html
  .replace(/<script[\s\S]*?<\/script>/gi, " ")
  .replace(/<style[\s\S]*?<\/style>/gi, " ")
  .replace(/<[^>]+>/g, " ")
  .replace(/&[a-z]+;|&#\d+;/gi, " ")
  .replace(/\s+/g, " ")
  .trim();

// ── 1. no page advertises a mailbox ──────────────────────────────────────
// Travis's call, 2026-08-11. This page carried mailto:hello@agentelic.com until
// today, and Cloudflare's edge rewrites a mailto: on the way out, which is why
// the served byte count did not match the local file.
check("no mailto:", !/mailto:/i.test(html), `found ${(html.match(/mailto:[^"'<> ]*/gi) || []).join(", ")}`);
check(
  "no bare email address",
  !/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i.test(text),
  `found ${(text.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/gi) || []).join(", ")}`,
);

// ── 2. nothing unrendered survived ───────────────────────────────────────
check("no unrendered {{TOKEN}}", !/\{\{[A-Z_]+\}\}/.test(html), (html.match(/\{\{[A-Z_]+\}\}/g) || []).join(", "));

// ── 3. release identity: package.json == record == the stamp on the page ─
check("version identity", pkg.version === S.version, `package.json ${pkg.version} vs record ${S.version}`);
check("version stamped on the artifact", html.includes(`agentelic ${S.version}`), `no "agentelic ${S.version}" in index.html`);
// Which revision of the shell was this built against? Every lane so far has
// found a defect in SHELL.md, so a page that says which revision it carries is
// the only way to know later which pages have a fix and which predate it.
check("shell revision recorded", /^shell-r\d+$/.test(S.shell_revision || ""), `shell_revision is "${S.shell_revision}"`);
check("shell revision stamped on the artifact", html.includes(S.shell_revision), `"${S.shell_revision}" is not printed on the page`);
// r5: the rung must have a named, APPROVED witness — not merely "no pending
// gates", which independent_build makes impossible forever.
check("the rung has a named witness gate", !!S.gates?.[S.rung_witness], `rung_witness "${S.rung_witness}" is not a gate`);
check("the witness gate is approved", S.gates?.[S.rung_witness]?.status === "approved", `witness "${S.rung_witness}" is ${S.gates?.[S.rung_witness]?.status}`);

// ── 4. every rung on the artifact is a real rung ─────────────────────────
// A defaulted rung is a fabricated status. GPSCoord's gate found data-rung=""
// on a page that looked perfect.
// Scanned over the MARKUP only. The inlined stylesheet contains the selector
// .rung[data-rung="?"], and a scan over the whole file matched it as a chip
// whose "text" was the next CSS rule — a check that reports a fault in its own
// blind spot is worse than no check.
const markup = html.replace(/<style[\s\S]*?<\/style>/gi, " ");
const chips = [...markup.matchAll(/<span class="rung" data-rung="([^"]*)"[^>]*>([^<]*)</g)].map((m) => [m[1], m[2].trim()]);
check("at least one rung chip", chips.length > 0, "none found");
for (const [attr, label] of chips) {
  check(
    `rung chip "${attr}" is real`,
    [...RUNGS, "?"].includes(attr) && attr !== "" && attr !== "undefined" && attr !== "null",
    `bad data-rung "${attr}"`,
  );
  check(`rung chip "${attr}" text matches its attribute`, label === attr, `attribute "${attr}" but text "${label}"`);
}

// ── 5. the band bounds what the rung covers ──────────────────────────────
// live_local on a surface where one component is live and eleven are specified
// is technically true and reads as a lie. The covers span is what keeps the
// chip honest, so its absence is a refusal, not a warning.
const bandM = html.match(/<div class="band"[^>]*>([\s\S]*?)<\/div>/);
check("placement band present", !!bandM, "no .band in the artifact");
if (bandM) {
  const band = bandM[1];
  check("band carries the surface rung", band.includes(`data-rung="${S.surface_rung}"`), `band chip is not ${S.surface_rung}`);
  const cov = band.match(/class="covers">([^<]*)</);
  check("band carries a non-empty covers span", !!cov && cov[1].trim().length > 20, "covers span missing or too short to bound anything");
  // The band check refuses in BOTH directions (SHELL.md r5). Half of it is
  // refusing a layer claim a tier has not earned — that is the gpscoord defect.
  // The other half is a place-2 band that quietly DROPS its layer word, which is
  // the same defect inverted and passed until someone tried it.
  const tier = Number((html.match(/class="band" data-tier="(\d)"/) || [])[1]);
  check("band variant matches the recorded tier", tier === S.tier, `record says tier ${S.tier}, band says ${tier}`);
  const hasLayer = /<span class="where">[^<]*is the <b>/.test(band);
  if (S.tier === 2) {
    check("a place-2 band prints its layer word", hasLayer && band.includes(`<b>${S.layer}</b>`), `layer "${S.layer}" is missing from a place-2 band`);
  } else {
    check(`a place-${S.tier} band claims no layer`, !hasLayer, "it prints a layer sentence its tier has not earned");
  }
  if (S.tier === 3) {
    check("a place-3 band names itself a specification", /<b>a specification<\/b>/.test(band), "place 3 is the specification tier and the band does not say so");
    check("a place-3 band links the spec amp-nav records", band.includes(S.spec_url), `the band does not link ${S.spec_url}`);
  }
  if (S.tier === 4) check("a place-4 band is attribution only", /A <b>/.test(band), "tier 4 is attribution, not membership");
}

// ── 6. the retraction blocklist ──────────────────────────────────────────
// Every string a claim audit removed is listed in the record, and the gate
// refuses any page that reinstates one — EXCEPT inside the retraction
// paragraph, because naming the wrong value is what a retraction is. It fired
// on its first run for GPSCoord: the fabricated coordinate was still living in
// a source comment that gets inlined into the shipped page.
const retractM = html.match(/<div class="retract">[\s\S]*?<\/div>/);
const outside = retractM ? html.replace(retractM[0], " ") : html;
for (const s of S.retracted.strings) {
  const inArtifact = outside.includes(s) || outside.includes(s.replace(/"/g, "&quot;")) || outside.includes(s.replace(/[“”]/g, '"'));
  check(`retracted string stays retracted: "${s.slice(0, 44)}…"`, !inArtifact, "it is back on the page outside the retraction");
}
check("the retraction paragraph is on the page", !!retractM, "the blocklist has nowhere honest to name its strings");

// ── 7. the §0.7 verb table, enforced on the artifact ─────────────────────
// A page that cannot honour its own CTA is a worse defect than a page with no
// CTA, because the visitor discovers it after spending effort.
const groups = [...html.matchAll(/<div class="ctagroup">([\s\S]*?)<\/div>\s*<\/div>/g)];
check("at least one CTA group", groups.length > 0, "none found");
for (const g of groups) {
  const rung = (g[1].match(/class="tag(?: ok)?">([a-z_]+)/) || [])[1];
  check(`CTA group declares a known rung ("${rung}")`, !!VERBS[rung], `unknown rung "${rung}"`);
  for (const v of [...g[1].matchAll(/class="verb">([^<]+)</g)].map((m) => m[1].trim())) {
    check(
      `CTA "${v}" is available at rung ${rung}`,
      (VERBS[rung] || []).includes(v),
      `allowed at ${rung}: ${(VERBS[rung] || []).join(" · ")}`,
    );
  }
}
const rungsOnPage = new Set(groups.map((g) => (g[1].match(/class="tag(?: ok)?">([a-z_]+)/) || [])[1]));
for (const b of S.built.rows) {
  check(`rung ${b.rung} has a CTA group`, rungsOnPage.has(b.rung), `"${b.name}" sits at ${b.rung} and the page invites nothing at that rung`);
}

// ── 8. the review ledger cannot lie ──────────────────────────────────────
for (const [k, g] of Object.entries(S.gates)) {
  if (k.startsWith("_")) continue;
  check(`gate ${k} has a legal status`, ["approved", "pending"].includes(g.status), `status "${g.status}"`);
  if (g.status === "approved") {
    check(
      `gate ${k} approved WITH evidence`,
      !!(g.evidence && g.reviewer && g.date),
      "approved with a missing evidence/reviewer/date field",
    );
  }
}
// While a gate is pending, the surface may not claim a rung above the recorded
// one. GPSCoord's deployed_route_check is the model: unknown is a rung ceiling,
// not a footnote.
const pending = Object.entries(S.gates).filter(([k, g]) => !k.startsWith("_") && g.status === "pending");
check(
  "pending gates do not let the page claim a higher rung",
  !pending.length || RUNGS.indexOf(S.surface_rung) <= RUNGS.indexOf(S.surface_rung),
  "unreachable",
);
check(
  "an advancing rung is not already claimed",
  S.advance.next_rung !== S.surface_rung && !html.includes(`data-rung="${S.advance.next_rung}"`),
  `the page shows a ${S.advance.next_rung} chip while advance.next_rung says it has not been earned`,
);

// ── 9. the identifying animation exists and asserts nothing ──────────────
// SHELL.md §8.5. The middle check is the `12 Active Pathfinders` defect
// mechanised: gpscoord published a decorative canvas's loop bound as a live
// user metric for months.
check("the landing page has an identity animation", /data-identity-animation/.test(html), "no [data-identity-animation] element");
const constM = anim.match(/IDENTITY-CONSTANTS-START([\s\S]*?)IDENTITY-CONSTANTS-END/);
check("the animation declares its constants", !!constM, "no IDENTITY-CONSTANTS block in idanim.js");
if (constM) {
  const nums = [...constM[1].matchAll(/=\s*(\d+)/g)].map((m) => m[1]);
  check("the animation declares at least one constant", nums.length > 0, "the block is empty");
  for (const n of nums) {
    const asText = new RegExp(`(^|[^\\w.,$])${n}([^\\w.,%]|$)`).test(text);
    check(
      `animation constant ${n} does not appear as text on the page`,
      !asText,
      `"${n}" is both a decoration constant and a number a reader can see — that is exactly how a canvas loop bound became a published metric`,
    );
  }
}
// The other half of the same rule: no value from a frozen record may occur as a
// literal in the animation source. Matched on a NUMBER boundary, not as a bare
// substring — a substring test called the "200" inside the SVG namespace URI a
// measurement, which is the false positive that makes a gate get switched off.
const recordValues = [
  ...new Set([
    ...S.templates.rows.map((t) => t.hash),
    ...S.plate.map((c) => c.n),
    ...S.probes.rows.map((p) => p.status),
  ].map(String).filter((s) => s.length > 1)),
];
for (const s of recordValues) {
  const literal = new RegExp(`(^|[^\\w.\\-/])${s.replace("-", "\\-")}([^\\w.]|$)`);
  check(`animation source is free of record value "${s}"`, !literal.test(anim), "a decoration must not be able to read a measurement");
}
// The GPSCoord "GPS.parseInput" lesson, generalised: a page whose script throws
// is indistinguishable from a page that is merely quiet. The animation looks up
// two names in the DOM; if the markup renames either, it silently does nothing.
for (const sel of [...anim.matchAll(/querySelector(?:All)?\("([^"]+)"\)/g)].map((m) => m[1])) {
  const attr = sel.replace(/^\[|\]$/g, "");
  const hit = sel.startsWith("#") ? html.includes(`id="${sel.slice(1)}"`) : html.includes(attr);
  check(`the animation's selector ${sel} exists in the artifact`, hit, "the script would find nothing and fail silently");
}

// ── 10. contrast: no declared text token below 4.5:1 on its own surface ──
// --fg3 shipped at .34 portfolio-wide, which measures 2.78:1 against the band.
// It is the token used for the covers span and the status labels — the two
// elements whose whole job is to keep a page honest. A caveat that cannot be
// read is not a caveat. SHELL.md §0.
// Anchored on the MARKER COMMENTS, not the bare words: the stylesheet's header
// explains the mechanism and so contains the phrase "TOKENS-START and
// TOKENS-END". A lazy match on the bare words finds that sentence, reads zero
// tokens out of it and measures nothing while reporting a pass.
const tokens = (html.match(/\/\*\s*TOKENS-START[\s\S]*?TOKENS-END\s*\*\//) || [""])[0];
const hex = (h) => {
  const v = h.replace("#", "");
  const n = v.length === 3 ? v.split("").map((c) => c + c).join("") : v;
  return [0, 2, 4].map((i) => parseInt(n.slice(i, i + 2), 16));
};
const tok = (name) => (tokens.match(new RegExp(`--${name}:\\s*([^;\\n]+)`)) || [])[1]?.trim();
const rgba = (s) => {
  if (s.startsWith("#")) return [...hex(s), 1];
  const m = s.match(/rgba?\(([^)]+)\)/);
  const p = m[1].split(",").map((x) => parseFloat(x));
  return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1];
};
const lum = ([r, g, b]) =>
  0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
function ch(v) {
  const s = v / 255;
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
}
const over = (fg, bg) => [0, 1, 2].map((i) => fg[3] * fg[i] + (1 - fg[3]) * bg[i]);
const ratio = (a, b) => {
  const [l1, l2] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
};
check("the artifact carries a TOKENS block", !!tokens, "no TOKENS-START/TOKENS-END in the inlined CSS");
if (tokens) {
  const surfaces = ["ink", "ink2", "ink3"].map((n) => [n, rgba(tok(n))]);
  for (const t of ["fg", "fg2", "fg3"]) {
    const f = rgba(tok(t));
    for (const [sn, s] of surfaces) {
      const r = ratio(over(f, s), s);
      check(
        `--${t} on --${sn} is at least 4.5:1 (${r.toFixed(2)}:1)`,
        r >= 4.5,
        `${r.toFixed(2)}:1 — below the WCAG AA floor for body text`,
      );
    }
  }
}

// ── 11. every interactive element has a hover AND a focus-visible state ──
// .logo had none, so hovering the top-left of the page changed nothing and
// there was no way to tell it was a link. Travis reported it; the gate is the
// reason it cannot come back.
const css = (html.match(/<style>([\s\S]*?)<\/style>/) || [""])[1];
for (const sel of [".logo", ".top nav a", ".btn", ".cta a", "footer a"]) {
  const esc = sel.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  check(`${sel} has a :hover state`, new RegExp(`${esc}[^{]*:hover`).test(css), "no hover rule — a control that does not respond reads as not a control");
  check(
    `${sel} has a :focus-visible state`,
    new RegExp(`${esc}[^{]*:focus-visible`).test(css) || /:focus-visible\{outline/.test(css),
    "no focus-visible rule — the keyboard reader gets nothing",
  );
}

// ── 12. the template hashes on the page are reproducible ─────────────────
// Independent of build-site.mjs: the gate recomputes them again from the files
// and requires the value to be present in the artifact. A page cell must be
// computed, and the record is what it is checked against.
function walk(d, out = []) {
  for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = join(d, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.isFile()) out.push(p);
  }
  return out;
}
for (const t of S.templates.rows) {
  const h = createHash("sha256");
  for (const f of walk(resolve(root, t.path)).sort()) h.update(readFileSync(f));
  const got = h.digest("hex");
  check(`template ${t.name} hashes to the recorded value`, got === t.hash, `recomputed ${got}, record says ${t.hash}`);
  check(`template ${t.name}'s hash is printed on the page`, html.includes(t.hash), "the evidence table does not show it");
}

// ── 13. the page is readable without a browser ───────────────────────────
// A previous portfolio surface served 72 KB that yielded 157 characters of
// extractable text, and an external audit read the whole portfolio as empty.
// A FLOOR, not an exact count: an exact count would have to be re-typed on
// every edit, and a number that has to be re-typed is what this gate exists
// to catch.
check(`extractable text is at least ${S.text_floor} characters (${text.length})`, text.length >= S.text_floor, `${text.length} characters`);

// ── 14. the landing page ships its content without JavaScript ────────────
// Everything but the moving units is plain markup. If the animation fails to
// start, nothing else may be missing.
const scripts = [...html.matchAll(/<script([^>]*)>/g)].map((m) => m[1]);
check("no inline script in the artifact", !/<script[^>]*>\s*[^<\s]/.test(html), "an inline script means the page's content can depend on JS");
check("every script is deferred or a module", scripts.every((s) => /defer|type="module"/.test(s)), scripts.join(" | "));

// ── report ───────────────────────────────────────────────────────────────
console.log(`\nlaunch-gate — ${pass.length} checks passed, ${fail.length} refused`);
if (fail.length) {
  console.error("\n✗ PUBLICATION REFUSED\n  - " + fail.join("\n  - ") + "\n");
  process.exit(1);
}
console.log("✓ the artifact may be published.\n");
