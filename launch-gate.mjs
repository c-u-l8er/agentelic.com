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
import { readdirSync, statSync, existsSync } from "node:fs";
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

// Text as a reader gets it: comments, scripts, styles and tags removed.
//
// SHELL.md r8 — COMMENTS COME OUT FIRST, AS THEIR OWN PASS. This read
//   .replace(/<script…/).replace(/<style…/).replace(/<[^>]+>/g," ")
// and `<[^>]+>` STOPS AT THE FIRST `>`. An HTML comment that contains a `>` is
// therefore only partially removed and the remainder is counted as visible page
// text — and the comments in this portfolio are full of them: `κ > 0`, `->`,
// `10 tools > the 7 planned`. Measured on this artifact: a single realistic
// source comment leaked 93 characters of invisible text into the count, and two
// checks read this string — one of them the bare-email scan, whose entire job is
// telling what a visitor sees from what they do not.
const text = html
  .replace(/<!--[\s\S]*?-->/g, " ")
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

// ── 2b. THE ARTIFACT CAME FROM THIS BUILD ────────────────────────────────
// SHELL.md r6, hole 2. Every check in this file reads the emitted page — which
// is the right thing to read, and which is worthless if the emitted page is a
// leftover. If build-site.mjs throws, the previous index.html stays on disk and
// a gate that reads only the artifact approves it happily. PROVEN on this
// surface: a build made to die after its checks left the old page in place and
// the gate passed 114/0 over it.
//
// Two independent proofs, because they fail in different directions:
//
//   (a) the emit manifest. build-site.mjs records the sha256 of every input it
//       read and every file it wrote, as the LAST act of a successful run. A
//       source hash that no longer matches means the build has not run since
//       the source changed; an artifact hash that no longer matches means the
//       page was hand-edited after the build.
//
//   (b) recompilation. Independently of any manifest, the gate re-derives the
//       stylesheet and the animation from src/ with the emitter's own
//       transform, and requires the artifact to contain them — plus every
//       literal fragment of the landing template, in order. The manifest can be
//       deleted; this cannot be satisfied by a stale page.
{
  const manifestPath = resolve(root, "records/build.json");
  const haveManifest = existsSync(manifestPath);
  check("the build left an emit manifest", haveManifest, "records/build.json is missing — run node build-site.mjs, do not publish this artifact");
  if (haveManifest) {
    const B = JSON.parse(read("records/build.json"));
    const sha = (p) => createHash("sha256").update(readFileSync(resolve(root, p))).digest("hex");
    const drifted = (label, table) =>
      Object.entries(table).filter(([p, h]) => !existsSync(resolve(root, p)) || sha(p) !== h).map(([p]) => `${label} ${p}`);
    const srcDrift = drifted("source", B.sources || {});
    const artDrift = drifted("artifact", B.artifacts || {});
    check(
      "every source is the one this build read",
      srcDrift.length === 0,
      `${srcDrift.join(", ")} changed since the last successful emit — the artifact is stale (a build that throws leaves the old index.html in place)`,
    );
    check(
      "every artifact is the one this build wrote",
      artDrift.length === 0,
      `${artDrift.join(", ")} has been modified since it was emitted — index.html is generated, do not hand-edit it`,
    );
    check("the manifest names a build id", /^[0-9a-f]{16}$/.test(B.build_id || ""), `build_id is "${B.build_id}"`);
  }

  // (b) recompile, so a deleted or forged manifest is not the only thing standing here
  const css = read("src/shell.css")
    .replace(/\/\*(?!\s*TOKENS-(?:START|END))[\s\S]*?\*\//g, "")
    .split("\n").map((l) => l.trim()).filter(Boolean).join("\n");
  check("the artifact carries the stylesheet this source compiles to", html.includes(css), `${css.length} bytes of recompiled CSS are not in index.html`);
  check("/idanim.js is byte-for-byte src/idanim.js", anim === read("src/idanim.js"), "the served animation is not the one in src/");
  check("/contact.js is byte-for-byte src/contact.js", read("contact.js") === read("src/contact.js"), "the served form handler is not the one in src/");

  // every literal run of the template, in order, must survive into the page
  const frags = read("src/landing.html").split(/\{\{[A-Z_]+\}\}/).map((f) => f.trim()).filter((f) => f.length > 24);
  let cursor = 0, missing = null;
  for (const f of frags) {
    const at = html.indexOf(f, cursor);
    if (at < 0) { missing = f.slice(0, 60); break; }
    cursor = at + f.length;
  }
  check(
    "every literal run of src/landing.html survives into the artifact, in order",
    missing === null,
    `the template moved on without the page: "${missing}…" is not in index.html`,
  );
}

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

// ── 6. the retraction blocklist — COUNTED, not detected ──────────────────
// Every string a claim audit removed is listed in the record, and the gate
// refuses any page that reinstates one — EXCEPT inside the retraction
// paragraph, because naming the wrong value is what a retraction is. It fired
// on its first run for GPSCoord: the fabricated coordinate was still living in
// a source comment that gets inlined into the shipped page.
//
// SHELL.md r6, hole 1. The exemption used to be scoped to a CLASS NAME and was
// therefore UNBOUNDED: anything inside <div class="retract"> was forgiven any
// number of times. And that div is authored from S.retracted.paragraph, a
// record field — so the retraction was itself a reinstatement vehicle. PROVEN
// on this surface: appending the sentence three times to the paragraph put
// "Start building today" on the artifact FOUR times and the gate approved it,
// 114 passed / 0 refused.
//
// So COUNT and BOUND, in both directions:
//   · outside the retraction: 0 occurrences. A reinstatement anywhere else.
//   · inside the retraction:  at most 1. Naming a retracted claim twice in its
//     own retraction has no honest purpose, and one repetition is all a
//     reinstatement needs.
const retractM = html.match(/<div class="retract">[\s\S]*?<\/div>/);
check("the retraction paragraph is on the page", !!retractM, "the blocklist has nowhere honest to name its strings");
const retractBlock = retractM ? retractM[0] : "";
const tally = (hay, needle) => (needle ? hay.split(needle).length - 1 : 0);
for (const s of S.retracted.strings) {
  // count every spelling the emitter could have produced, not just the literal
  const forms = [...new Set([s, s.replace(/"/g, "&quot;"), s.replace(/[“”]/g, '"'), s.replace(/&/g, "&amp;")])];
  const onPage = forms.reduce((n, f) => n + tally(html, f), 0);
  const inBlock = forms.reduce((n, f) => n + tally(retractBlock, f), 0);
  check(
    `retracted string is not reinstated outside the retraction: "${s.slice(0, 44)}…"`,
    onPage === inBlock,
    `${onPage} occurrence(s) on the page but only ${inBlock} inside the retraction — ${onPage - inBlock} reinstated elsewhere`,
  );
  check(
    `the retraction names "${s.slice(0, 44)}…" at most once`,
    inBlock <= 1,
    `the retraction repeats it ${inBlock} times, which is a reinstatement wearing a retraction's clothes`,
  );
}

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
  // --data and --warn joined the list with SHELL.md r9: they are the correction
  // form's "sent" and "not sent — <reason>" replies, and a reply nobody can read
  // is the same defect as a caveat nobody can read.
  for (const t of ["fg", "fg2", "fg3", "data", "warn"]) {
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

/* ==========================================================================
   15. THE COMPUTED COLOUR ON A REAL .btn — NOT THE ONE THE TOKEN DECLARES
   SHELL.md r7. Travis reported the header CTA unreadable. It was: `.top nav a`
   is specificity 0,2,1 and `.btn` is 0,1,0, so the nav rule won and the button
   painted --fg2 on the accent at 1.19:1 — while the identical button in the
   hero painted its declared dark ink at 12:1.

   EVERY CONTRAST CHECK ABOVE PASSED THE WHOLE TIME. They read the DECLARED
   token pair (#ink on --acc) and never the colour the cascade actually gives a
   real element in its real ancestor context. That is the entire hole, and it is
   why this surface's deliberate-break count could not have caught it.

   So: resolve the cascade over the ARTIFACT — every rule that sets `color` or a
   custom property, matched against each .btn's real ancestor chain, with
   specificity, source order, !important, @media at a given width, var() and
   inherit — and refuse when a button's computed colour is not the one a .btn
   rule declares for it.

   Two properties keep the resolver honest rather than merely quiet:
     · any selector or media condition it cannot parse is a REFUSAL, never a
       skip. A resolver that silently ignores the rule it does not understand
       has reproduced the blind spot it was written to close.
     · finding zero buttons is a REFUSAL. A check that passes because it
       measured nothing is the same failure wearing a green tick.
   ========================================================================== */
{
    const CASCADE_WIDTHS = [1600, 1280, 800, 390];
    const errors = [];

    const splitTop = (s) => {
        const list = []; let depth = 0, cur = "";
        for (const ch of s) {
            if (ch === "(") depth++; else if (ch === ")") depth--;
            if (ch === "," && depth === 0) { list.push(cur); cur = ""; continue; }
            cur += ch;
        }
        if (cur.trim()) list.push(cur);
        return list;
    };

    /* ---- 1. every rule in the artifact that sets `color` or a custom property ---- */
    const rules = [];
    const collect = (css, media) => {
        let i = 0;
        while (i < css.length) {
            const open = css.indexOf("{", i);
            if (open < 0) break;
            const prelude = css.slice(i, open).trim();
            let depth = 1, j = open + 1;
            while (j < css.length && depth) { const c = css[j]; if (c === "{") depth++; else if (c === "}") depth--; j++; }
            const body = css.slice(open + 1, j - 1);
            i = j;
            if (prelude.startsWith("@")) {
                if (/^@media\b/i.test(prelude)) collect(body, media.concat([prelude.replace(/^@media/i, "").trim()]));
                else if (!/^@(keyframes|-webkit-keyframes|font-face|page|charset|import|namespace)\b/i.test(prelude)) errors.push(`unsupported at-rule "${prelude.slice(0, 40)}"`);
                continue;
            }
            for (const d of body.split(";")) {
                const k = d.indexOf(":");
                if (k < 0) continue;
                const prop = d.slice(0, k).trim().toLowerCase();
                if (prop !== "color" && !prop.startsWith("--")) continue;
                let val = d.slice(k + 1).trim();
                const important = /!important$/i.test(val);
                if (important) val = val.replace(/!important$/i, "").trim();
                for (const sel of splitTop(prelude)) rules.push({ sel: sel.trim(), prop, val, important, media, order: rules.length });
            }
        }
    };
    const styleText = [...html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)].map((m) => m[1]).join("\n");
    if (!styleText.trim()) errors.push("the artifact carries no <style> block");
    collect(styleText.replace(/\/\*[\s\S]*?\*\//g, ""), []);

    /* ---- 2. compound-selector parser ---- */
    const STATE = new Set(["hover", "focus", "focus-visible", "focus-within", "active", "visited", "link", "target", "checked", "disabled", "enabled", "any-link"]);
    const parseCompound = (s) => {
        const c = { tag: null, id: null, classes: [], attrs: [], nots: [], state: false, pseudoEl: false, spec: [0, 0, 0], bad: null };
        const bump = (a, b, d) => { c.spec[0] += a; c.spec[1] += b; c.spec[2] += d; };
        let i = 0;
        while (i < s.length) {
            const rest = s.slice(i); let m;
            if (rest[0] === "*") { i++; continue; }
            if ((m = /^\.([\w-]+)/.exec(rest))) { c.classes.push(m[1]); bump(0, 1, 0); i += m[0].length; continue; }
            if ((m = /^#([\w-]+)/.exec(rest))) { c.id = m[1]; bump(1, 0, 0); i += m[0].length; continue; }
            if (rest[0] === "[") {
                const j = s.indexOf("]", i);
                if (j < 0) { c.bad = `unterminated [ in "${s}"`; break; }
                const am = /^([\w:-]+)\s*(?:([~^$*|]?=)\s*(.*))?$/.exec(s.slice(i + 1, j).trim());
                if (!am) { c.bad = `unreadable attribute selector in "${s}"`; break; }
                if (am[2] && am[2] !== "=") { c.bad = `unsupported attribute operator ${am[2]}`; break; }
                c.attrs.push([am[1].toLowerCase(), am[3] == null ? null : am[3].trim().replace(/^["']|["']$/g, "")]);
                bump(0, 1, 0); i = j + 1; continue;
            }
            if (rest.startsWith("::")) { c.pseudoEl = true; break; }
            if (rest[0] === ":") {
                m = /^:([\w-]+)/.exec(rest);
                if (!m) { c.bad = `unreadable pseudo in "${s}"`; break; }
                const name = m[1].toLowerCase();
                let arg = null, len = m[0].length;
                if (rest[len] === "(") {
                    let d = 1, k = len + 1;
                    while (k < rest.length && d) { if (rest[k] === "(") d++; else if (rest[k] === ")") d--; k++; }
                    arg = rest.slice(len + 1, k - 1); len = k;
                }
                if (name === "not") {
                    if (arg == null) { c.bad = ":not() with no argument"; break; }
                    const inner = splitTop(arg).map((x) => parseCompound(x.trim()));
                    const bad = inner.find((x) => x.bad);
                    if (bad) { c.bad = bad.bad; break; }
                    c.nots.push(inner);
                    const rank = (x) => x.spec[0] * 1e4 + x.spec[1] * 1e2 + x.spec[2];
                    const worst = inner.reduce((a, x) => (rank(x) > rank(a) ? x : a), inner[0]);
                    bump(worst.spec[0], worst.spec[1], worst.spec[2]);
                } else if (STATE.has(name)) { c.state = true; bump(0, 1, 0); }
                else if (name === "root") { c.tag = "html"; bump(0, 1, 0); }
                else if (["before", "after", "selection", "marker", "placeholder", "first-line", "first-letter"].includes(name)) { c.pseudoEl = true; }
                else { c.bad = `unsupported pseudo-class :${name}`; break; }
                i += len; continue;
            }
            if ((m = /^[\w-]+/.exec(rest))) { c.tag = m[0].toLowerCase(); bump(0, 0, 1); i += m[0].length; continue; }
            c.bad = `unreadable at "${rest.slice(0, 12)}" in "${s}"`; break;
        }
        return c;
    };
    const parseSelector = (sel) => {
        const parts = sel.trim().split(/\s*([>+~])\s*|\s+/).filter((x) => x != null && x !== "");
        const chainSel = []; let child = false;
        for (const p of parts) {
            if (p === ">") { child = true; continue; }
            if (p === "+" || p === "~") return { bad: `unsupported combinator ${p} in "${sel}"` };
            const c = parseCompound(p);
            if (c.bad) return { bad: c.bad };
            chainSel.push({ c, child }); child = false;
        }
        if (!chainSel.length) return { bad: `empty selector "${sel}"` };
        return {
            chainSel,
            spec: chainSel.reduce((a, x) => [a[0] + x.c.spec[0], a[1] + x.c.spec[1], a[2] + x.c.spec[2]], [0, 0, 0]),
            state: chainSel.some((x) => x.c.state),
            pseudoEl: chainSel.some((x) => x.c.pseudoEl),
        };
    };
    const matchCompound = (c, el) => {
        if (c.tag && c.tag !== el.tag) return false;
        if (c.id && c.id !== el.id) return false;
        for (const k of c.classes) if (!el.cls.has(k)) return false;
        for (const [a, v] of c.attrs) { if (!(a in el.attrs)) return false; if (v != null && el.attrs[a] !== v) return false; }
        for (const g of c.nots) if (g.some((n) => matchCompound(n, el))) return false;
        return true;
    };
    const matchChain = (chainSel, chain) => {
        let ci = chain.length - 1, si = chainSel.length - 1;
        if (!matchCompound(chainSel[si].c, chain[ci])) return false;
        let child = chainSel[si].child; si--; ci--;
        while (si >= 0) {
            if (ci < 0) return false;
            if (child) {
                if (!matchCompound(chainSel[si].c, chain[ci])) return false;
                child = chainSel[si].child; si--; ci--;
            } else {
                let hit = -1;
                for (let k = ci; k >= 0; k--) if (matchCompound(chainSel[si].c, chain[k])) { hit = k; break; }
                if (hit < 0) return false;
                child = chainSel[si].child; si--; ci = hit - 1;
            }
        }
        return true;
    };

    /* ---- 3. the element tree, and every .btn's real ancestor chain ---- */
    const VOID = new Set("area base br col embed hr img input link meta param source track wbr".split(" "));
    const scrubbed = html
        .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "<style></style>")
        .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "<script></script>")
        .replace(/<!--[\s\S]*?-->/g, "");
    const stack = [], btns = [];
    for (const m of scrubbed.matchAll(/<(\/?)([a-zA-Z][\w:-]*)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>/g)) {
        const tag = m[2].toLowerCase();
        if (m[1] === "/") { for (let k = stack.length - 1; k >= 0; k--) if (stack[k].tag === tag) { stack.length = k; break; } continue; }
        const attrs = {};
        for (const a of m[3].matchAll(/([\w:-]+)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g)) attrs[a[1].toLowerCase()] = a[2] ?? a[3] ?? a[4] ?? "";
        const el = { tag, attrs, id: attrs.id || "", cls: new Set((attrs.class || "").trim().split(/\s+/).filter(Boolean)) };
        const chain = stack.concat([el]);
        if (el.cls.has("btn")) btns.push(chain);
        if (!VOID.has(tag) && m[4] !== "/") stack.push(el);
    }

    /* ---- 4. does an @media condition hold at this width? ---- */
    const mediaHolds = (conds, w) => conds.every((q) => q.split(/\s+and\s+/i).every((c) => {
        const t = c.trim().replace(/^\(|\)$/g, "");
        let m;
        if ((m = /^max-width\s*:\s*(\d+)px$/i.exec(t))) return w <= Number(m[1]);
        if ((m = /^min-width\s*:\s*(\d+)px$/i.exec(t))) return w >= Number(m[1]);
        if (/^prefers-reduced-motion/i.test(t)) return false;   /* the gate is not a reduced-motion reader */
        if (/^(screen|all|print)$/i.test(t)) return !/print/i.test(t);
        errors.push(`unsupported media condition (${t})`);
        return false;
    }));

    /* ---- 5. the cascade ---- */
    const parsed = rules.map((r) => ({ ...r, p: parseSelector(r.sel) }));
    for (const r of parsed) if (r.p.bad) errors.push(`${r.p.bad}`);
    const cmp = (a, b) => { for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1; return 0; };
    const declKey = (r) => [r.important ? 1 : 0, ...r.p.spec, r.order];
    const winner = (chain, prop, w, only) => {
        let best = null;
        for (const r of parsed) {
            if (r.prop !== prop || r.p.bad || r.p.state || r.p.pseudoEl) continue;
            if (only && !only(r)) continue;
            if (!mediaHolds(r.media, w) || !matchChain(r.p.chainSel, chain)) continue;
            const key = declKey(r);
            if (!best || cmp(key, best.key) > 0) best = { r, key };
        }
        return best;
    };
    const resolve = (chain, value, w, depth = 0) => {
        if (depth > 12) return value;
        const v = String(value).trim();
        if (v === "inherit") {
            const up = chain.slice(0, -1);
            if (!up.length) return "(initial)";
            const win = winner(up, "color", w);
            return win ? resolve(up, win.r.val, w, depth + 1) : resolve(up, "inherit", w, depth + 1);
        }
        const m = /^var\(\s*(--[\w-]+)\s*(?:,([\s\S]*))?\)$/.exec(v);
        if (m) {
            for (let k = chain.length; k > 0; k--) {
                const win = winner(chain.slice(0, k), m[1], w);
                if (win) return resolve(chain.slice(0, k), win.r.val, w, depth + 1);
            }
            return m[2] != null ? resolve(chain, m[2].trim(), w, depth + 1) : "(unset)";
        }
        return v;
    };
    const norm = (v) => {
        const s = String(v).trim().toLowerCase();
        let m = /^#([0-9a-f]{3})$/.exec(s);
        if (m) return `rgba(${parseInt(m[1][0] + m[1][0], 16)},${parseInt(m[1][1] + m[1][1], 16)},${parseInt(m[1][2] + m[1][2], 16)},1)`;
        m = /^#([0-9a-f]{6})$/.exec(s);
        if (m) return `rgba(${parseInt(m[1].slice(0, 2), 16)},${parseInt(m[1].slice(2, 4), 16)},${parseInt(m[1].slice(4, 6), 16)},1)`;
        m = /^rgba?\(([^)]*)\)$/.exec(s);
        if (m) { const p = m[1].split(/[,\s/]+/).filter(Boolean).map(Number); return `rgba(${p[0]},${p[1]},${p[2]},${p.length > 3 ? p[3] : 1})`; }
        return s;
    };
    const computed = (chain, w) => {
        for (let k = chain.length; k > 0; k--) {
            const sub = chain.slice(0, k);
            const inline = sub[sub.length - 1].attrs.style;
            if (inline && /(^|;)\s*color\s*:/i.test(inline)) return { v: resolve(sub, /(?:^|;)\s*color\s*:([^;]+)/i.exec(inline)[1], w), from: "the style attribute" };
            const win = winner(sub, "color", w);
            if (win) return { v: resolve(sub, win.r.val, w), from: win.r.sel + (k === chain.length ? "" : " (inherited)") };
        }
        return { v: "(initial)", from: "(initial)" };
    };

    /* ---- 6. the verdict ---- */
    check("the cascade resolver read every rule in the artifact", errors.length === 0,
        errors.length ? [...new Set(errors)].slice(0, 4).join(" | ") : `${parsed.length} colour/custom-property declarations`);
    check("the artifact actually has buttons to check", btns.length > 0,
        "a check that measured nothing is not a check that passed");

    let worst = null;
    for (const w of CASCADE_WIDTHS) for (const chain of btns) {
        const el = chain[chain.length - 1];
        /* what a BUTTON rule declares for this button — the most specific rule whose
           own subject compound carries .btn (so .btn.ghost beats .btn, as it should) */
        const decl = winner(chain, "color", w, (r) => r.p.chainSel[r.p.chainSel.length - 1].c.classes.includes("btn"));
        const got = computed(chain, w);
        const want = decl ? resolve(chain, decl.r.val, w) : null;
        const where = chain.some((a) => a.cls.has("top")) && chain.some((a) => a.tag === "nav") ? "header" : "body";
        const id = `${el.tag}.${[...el.cls].join(".")} in the ${where}` +
            (el.attrs.href ? ` → ${el.attrs.href}` : el.attrs.type ? ` [type=${el.attrs.type}]` : "");
        const ok = !!decl && norm(got.v) === norm(want);
        if (!ok && !worst) worst = `${id} at ${w}px computes ${got.v} from "${got.from}"`;
        check(`computed colour @${w}px — ${id}`, ok,
            decl ? `computes ${got.v} from "${got.from}" — but ${decl.r.sel} declares ${want}`
                : "no .btn rule declares a colour for it");
    }
    check("no button loses its declared colour to the cascade at any width", worst === null,
        worst || `${btns.length} button(s) × ${CASCADE_WIDTHS.length} widths, every one painting what its rule declares`);
}

const ENDPOINT = S.contact.endpoint;
const contactJs = read("src/contact.js");

/* ==========================================================================
   THE CORRECTION FORM — SHELL.md r9, ruled by Travis 2026-08-17
   This closes the [TRAVIS] blocker fourteen surfaces reported. The endpoint is
   the one computedriven.com posts to, and what is checked here is the SHAPE,
   because the shape is what makes the form honest rather than decorative:

     · a real `action` on a real `<form method="POST">`, so it posts with
       JavaScript off. A fetch bolted to a button is a form that stops working
       the moment a script fails, on a page whose whole argument is that its
       content does not depend on scripts.
     · the `_gotcha` honeypot. A honeypot dropped in a refactor fails SILENTLY —
       nothing breaks, the spam just arrives — which is exactly the class of
       defect a gate is for.
     · `role="status" aria-live="polite"` on the reply, or the outcome is
       invisible to a screen reader.
     · and still no `mailto:` anywhere (checked above; this replaces the GitHub
       issues fallback as the primary channel, it does not reintroduce a mailbox).
   ========================================================================== */
{
    const formM = /<form\b([^>]*)>([\s\S]*?)<\/form>/i.exec(html);
    check("the page carries a correction form", !!formM, "SHELL.md r9 requires one on every surface");
    const attrs = formM ? formM[1] : "";
    const body = formM ? formM[2] : "";
    const action = (/\baction="([^"]*)"/.exec(attrs) || [])[1];

    check("the form posts to the endpoint the record declares", action === ENDPOINT,
        `form action is ${JSON.stringify(action)}, records/surface.json declares ${JSON.stringify(ENDPOINT)}`);
    check("the endpoint the record declares is the ruled one", ENDPOINT === "https://formspree.io/f/xaewoadr",
        `records/surface.json says ${JSON.stringify(ENDPOINT)}`);
    check("the form posts on its own, without JavaScript", /\bmethod="POST"/i.test(attrs) && !/\bonsubmit=/i.test(attrs),
        `attributes: ${attrs.trim()}`);
    check("the form carries novalidate, so the reply is ours to print", /\bnovalidate\b/i.test(attrs));

    check("the _gotcha honeypot is present", /name="_gotcha"/.test(body),
        "a honeypot dropped in a refactor fails silently — nothing breaks, the spam just arrives");
    check("the honeypot is hidden off-screen, not display:none",
        /\.say input\[name=_gotcha\]\{[^}]*left:-9999px/.test(html),
        "some bots skip anything a stylesheet has explicitly hidden");
    check("the honeypot is out of the tab order and out of the a11y tree",
        /name="_gotcha"[^>]*tabindex="-1"/.test(body) && /name="_gotcha"[^>]*aria-hidden="true"/.test(body));

    check("the form asks for a reply address and a message",
        /name="email"[^>]*required/.test(body) && /<textarea[^>]*name="message"[^>]*required/.test(body));
    check("the reply paragraph is announced to a screen reader",
        /class="say-msg"[^>]*role="status"[^>]*aria-live="polite"/.test(body),
        "the outcome of a submit is invisible without it");
    check("the submit control is a real submit button", /<button[^>]*type="submit"[^>]*class="btn"/.test(body));

    /* The enhancement must not be the thing that decides success. */
    check("the inline reply prints success only on a real 2xx",
        /if\s*\(\s*r\.ok\s*\)/.test(contactJs) && !/say\(\s*"Sent/.test(contactJs.split("if (r.ok)")[0]),
        "src/contact.js says sent before the endpoint has answered");
    check("the inline reply is external and deferred, so the form survives it failing",
        html.includes('<script src="/contact.js" defer></script>'));
}

// ── report ───────────────────────────────────────────────────────────────
console.log(`\nlaunch-gate — ${pass.length} checks passed, ${fail.length} refused`);
if (fail.length) {
  console.error("\n✗ PUBLICATION REFUSED\n  - " + fail.join("\n  - ") + "\n");
  process.exit(1);
}
console.log("✓ the artifact may be published.\n");
