// ===========================================================================
// Agentelic — the site generator. Zero dependencies.
//
//   node build-site.mjs        → writes index.html and idanim.js at the repo root
//
// The direction of dependency is the whole point (SHELL.md §4.1): a page cell is
// COMPUTED, and records/surface.json is what it is CHECKED AGAINST. Nothing on
// the emitted page states a rung, a status, a count or a hash that is not in the
// record, and the two template hashes are not copied from the record at all —
// they are recomputed from priv/templates/ with the algorithm the running
// product uses, and the build exits non-zero if they disagree.
//
// This build makes no network call. Every observation on the page is frozen,
// dated, and stated as an observation.
// ===========================================================================

import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { resolve, dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const read = (p) => readFileSync(resolve(root, p), "utf8");
const S = JSON.parse(read("records/surface.json"));

const die = (msg) => {
  console.error(`\n✗ BUILD REFUSED — ${msg}\n`);
  process.exit(1);
};

const esc = (s) =>
  String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

// ── the five rungs, and the verbs each one has earned ─────────────────────
// SITES.md §0.7 is mechanical, so it is implemented mechanically. A page that
// asks for something its rung has not earned does not get emitted.
const RUNGS = ["spec", "in_tree", "live_local", "live_deployed", "external"];
const VERBS = {
  spec: ["Read", "Challenge", "Implement"],
  in_tree: ["Inspect the source", "Run the tests"],
  live_local: ["Use it", "Reproduce it locally"],
  live_deployed: ["Use the deployed artifact"],
  external: ["See independent evidence", "Contribute another result"],
};
// Order the groups strongest-evidence-first, so the reader meets the real thing
// before the specification.
const RUNG_ORDER = ["external", "live_deployed", "live_local", "in_tree", "spec"];

// A defaulted rung is a fabricated status, so there is no default.
function rungChip(value) {
  const r = RUNGS.includes(value) ? value : "?";
  return `<span class="rung" data-rung="${r}" title="spec · in_tree · live_local · live_deployed · external">${r}</span>`;
}

// ── 1. validate the record ────────────────────────────────────────────────
const errors = [];

if (!RUNGS.includes(S.surface_rung)) errors.push(`surface_rung "${S.surface_rung}" is not one of ${RUNGS.join(", ")}`);
if (!S.surface_rung_covers) errors.push("surface_rung_covers is missing — the chip is not honest without the bound it covers");
if (!/^\d{4}-\d{2}-\d{2}$/.test(S.verified_at || "")) errors.push(`verified_at must be an ISO date, got ${S.verified_at}`);
if (!/^\d{4}-\d{2}-\d{2}$/.test(S.probes?.measured_at || "")) errors.push("probes.measured_at must be an ISO date");
for (const f of ["statement", "source", "limit"]) if (!S.status?.[f]) errors.push(`status.${f} is missing`);
for (const f of ["next_rung", "requires"]) if (!S.advance?.[f]) errors.push(`advance.${f} is missing`);
if (S.advance?.next_rung && !RUNGS.includes(S.advance.next_rung)) errors.push(`advance.next_rung "${S.advance.next_rung}" is not a rung`);
// The band, checked in BOTH directions (SHELL.md r5). Refusing a layer claim a
// tier has not earned is only half of it: a tier-2 band that quietly DROPS its
// layer word is the same defect inverted, and it passed until someone tried it.
// The entitlement comes from amp-nav, which records `layer` on place-2 entries
// only — place 3 is the specification tier and place 4 is outside the story.
if (![2, 3, 4].includes(S.tier)) errors.push(`tier must be 2, 3 or 4 (amp-nav place), got ${S.tier}`);
if (S.tier === 2 && !S.layer) errors.push("a place-2 surface MUST print its layer word — dropping it is the tier-4 defect inverted (SHELL.md r5)");
if (S.tier !== 2 && S.layer) errors.push(`a place-${S.tier} surface may not claim the layer "${S.layer}" — amp-nav records a layer for place-2 entries only (SHELL.md §1)`);
if (S.tier === 3 && !S.spec_url) errors.push("a place-3 band names the surface as a specification and must link the spec amp-nav records for it");

// r5: the gate that WITNESSES the rung. "Any pending gate blocks live_deployed"
// is too blunt — independent_build is pending forever by construction, so a
// surface could never advance at all. Name which gate carries the rung; the
// others stay pending without blocking it.
if (!S.rung_witness) errors.push("surface has no rung_witness — name the gate that witnesses the rung (SHELL.md r5)");
else {
  const w = S.gates?.[S.rung_witness];
  if (!w) errors.push(`rung_witness "${S.rung_witness}" is not a gate in this record`);
  else if (w.status !== "approved") errors.push(`rung_witness "${S.rung_witness}" is ${w.status} — the rung ${S.surface_rung} has no approved witness`);
}

// Every capability carries a real rung, and the strongest one is the surface's.
(S.built?.rows || []).forEach((b, i) => {
  if (!RUNGS.includes(b.rung)) errors.push(`built.rows[${i}] (${b.name}): rung "${b.rung}" is not one of ${RUNGS.join(", ")}`);
  if (!b.note) errors.push(`built.rows[${i}] (${b.name}): missing note`);
  if (b.rung !== S.surface_rung && !b.needs) errors.push(`built.rows[${i}] (${b.name}): a row below the surface rung must say what it needs`);
});
const best = (S.built?.rows || [])
  .map((b) => RUNGS.indexOf(b.rung))
  .reduce((a, n) => Math.max(a, n), -1);
if (best >= 0 && RUNGS[best] !== S.surface_rung) {
  errors.push(
    `surface_rung is "${S.surface_rung}" but the best-evidenced capability is "${RUNGS[best]}" — the surface rung is the rung of its best-evidenced shipped artifact (SHELL.md §1)`,
  );
}

// The gate ledger cannot lie: approved needs its evidence, reviewer and date.
for (const [k, g] of Object.entries(S.gates || {})) {
  if (k.startsWith("_")) continue;
  if (!["approved", "pending"].includes(g.status)) errors.push(`gate ${k}: status must be approved or pending, got "${g.status}"`);
  if (g.status === "approved") {
    for (const f of ["evidence", "reviewer", "date"]) {
      if (!g[f]) errors.push(`gate ${k} is approved with no ${f} — an approved gate without its evidence is a claim, not a review`);
    }
  }
}

// Contact is never a mailbox. Travis's call, 2026-08-11.
if (S.contact?.kind === "mailto" || /^mailto:/i.test(S.contact?.url || "")) {
  errors.push("contact.url is a mailto: — contact goes through an issue tracker or a hosted form, never a mailbox");
}

// A CTA group may only exist for a rung some capability actually has, and every
// verb must be one the rung has earned.
const presentRungs = new Set((S.built?.rows || []).map((b) => b.rung));
for (const [rung, actions] of Object.entries(S.cta || {})) {
  if (rung.startsWith("_")) continue;
  if (!VERBS[rung]) errors.push(`cta declares an unknown rung: ${rung}`);
  else if (!presentRungs.has(rung)) errors.push(`cta group "${rung}" has no capability at that rung — a page cannot invite what it does not have`);
  for (const a of actions) {
    if (!VERBS[rung]?.includes(a.verb)) {
      errors.push(`CTA "${a.verb}" is not available at rung ${rung} — allowed: ${(VERBS[rung] || []).join(" · ")}`);
    }
    if (/^mailto:/i.test(a.href || "")) errors.push(`CTA "${a.verb}" points at a mailto:`);
  }
}
for (const r of presentRungs) {
  if (!S.cta?.[r]) errors.push(`there is a capability at rung ${r} and no CTA group for it`);
}

if (errors.length) die("records/surface.json is not publishable:\n  - " + errors.join("\n  - "));

// ── 2. recompute the template hashes ──────────────────────────────────────
// The algorithm is lib/agentelic/templates/registry.ex, compute_template_hash/1:
//   Path.wildcard(dir/**/*) |> filter(regular?) |> sort |> map(read!) |> join
//   |> sha256 |> Base.encode16(:lower)
// If this recomputation and the frozen record disagree, the page does not get
// emitted. That is the check, and it is the site's whole evidence claim.
function walk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.isFile()) out.push(p);
  }
  return out;
}
function templateHash(dir) {
  const abs = resolve(root, dir);
  if (!statSync(abs).isDirectory()) die(`template path is not a directory: ${dir}`);
  const files = walk(abs).sort();
  if (!files.length) die(`template path holds no files: ${dir}`);
  const h = createHash("sha256");
  for (const f of files) h.update(readFileSync(f));
  return { hash: h.digest("hex"), files: files.map((f) => relative(abs, f)) };
}
const templates = (S.templates?.rows || []).map((t) => {
  const got = templateHash(t.path);
  if (got.hash !== t.hash) {
    die(
      `template "${t.name}" does not hash to what the deployed server returned.\n` +
        `    record (${S.templates.returned_by}):\n      ${t.hash}\n` +
        `    recomputed from ${t.path}:\n      ${got.hash}\n` +
        `  Either the templates changed and were not redeployed, or the record is stale.\n` +
        `  Do not edit the record to make this pass without re-asking the deployed server.`,
    );
  }
  return { ...t, files: got.files, computed: got.hash };
});
if (!templates.length) die("records/surface.json declares no templates — the page's evidence section would be empty");

// ── 3. render ─────────────────────────────────────────────────────────────
// The band. A tier-4 surface drops the layer claim; Agentelic is place 3, so it
// keeps it. SHELL.md §1.
// Three variants, one per amp-nav place. The band claims exactly what the nav
// has granted and no more: a layer word is a place-2 entitlement, place 3 is the
// specification tier, place 4 is outside the story and gets attribution only.
const WHERE = {
  2: () => `${esc(S.surface)} is the <b>${esc(S.layer)}</b> layer of ${esc(S.parent)}`,
  3: () => `${esc(S.surface)} is <b>a specification</b> in the ${esc(S.parent)} world &mdash; <a href="${esc(S.spec_url)}">read it</a>`,
  4: () => `A <b>${esc(S.parent)}</b> project`,
};
const band = `<div class="band" data-tier="${S.tier}"><span class="where">${WHERE[S.tier]()}</span>${rungChip(S.surface_rung)}<span class="covers">That rung covers ${esc(S.surface_rung_covers)}.</span></div>`;

const plate = `<div class="grid plate">
${S.plate.map((c) => `<div><div class="n${c.n === "0" || c.l.toLowerCase().includes("500") ? " q" : ""}">${esc(c.n)}</div><div class="l">${esc(c.l)}</div><div class="w">${esc(c.witness)}</div></div>`).join("\n")}
</div>`;

const probes = `<div class="scroll"><table>
<thead><tr><th>Request, as issued</th><th>Returned</th><th>What it establishes</th></tr></thead>
<tbody>
${S.probes.rows
  .map(
    (p) =>
      `<tr><td class="code">${esc(p.request)}</td><td class="st ${p.ok ? "ok" : "bad"}">${esc(p.status)}</td><td class="wide">${esc(p.establishes)}</td></tr>`,
  )
  .join("\n")}
</tbody></table></div>`;

const hashes = `<div class="scroll"><table>
<thead><tr><th>Template</th><th>Files</th><th>SHA-256, recomputed here</th><th>Deployed</th></tr></thead>
<tbody>
${templates
  .map(
    (t) =>
      `<tr><td class="code">${esc(t.name)}</td><td class="wide">${t.files.map(esc).join("<br>")}</td><td class="hash">${esc(t.computed)}</td><td class="st ok">match</td></tr>`,
  )
  .join("\n")}
</tbody></table></div>`;

const built = `<div class="grid">
${S.built.rows
  .map(
    (b) =>
      `<div><div class="head"><h3>${esc(b.name)}</h3>${rungChip(b.rung)}</div><p>${esc(b.note)}</p>${b.needs ? `<div class="needs"><b>Needs:</b> ${esc(b.needs)}</div>` : ""}</div>`,
  )
  .join("\n")}
</div>`;

const status = `<dl class="status">
<div><dt>Status</dt><dd><strong>${esc(S.surface_rung)}</strong> — ${esc(S.status.statement)}</dd></div>
<div><dt>Last verified</dt><dd>${esc(S.verified_at)}</dd></div>
<div><dt>Source</dt><dd>${esc(S.status.source)}</dd></div>
<div class="limit"><dt>Limit</dt><dd>${esc(S.status.limit)}</dd></div>
<div><dt>Next rung</dt><dd><strong>${esc(S.advance.next_rung)}</strong> — ${esc(S.advance.requires)}</dd></div>
</dl>`;

const retraction = `<div class="retract"><h3>What used to be here</h3><p>${esc(S.retracted.paragraph)}</p></div>`;

const pricing = `<div class="tiers">
${S.pricing.tiers
  .map(
    (t) =>
      `<div><div class="l">${esc(t.name)}</div><div class="p">${esc(t.price)}${t.unit ? `<small>${esc(t.unit)}</small>` : ""}</div><div class="d">${esc(t.detail)}</div></div>`,
  )
  .join("\n")}
</div>`;

const cta = RUNG_ORDER.filter((r) => S.cta?.[r])
  .map((r) => {
    const strong = ["live_deployed", "live_local", "external"].includes(r);
    const cards = S.cta[r]
      .map(
        (a) =>
          `<a href="${esc(a.href)}"><span class="verb">${esc(a.verb)}</span><span class="what">${a.what}</span></a>`,
      )
      .join("\n");
    return `<div class="ctagroup"><div class="tag${strong ? " ok" : ""}">${esc(r)} &mdash; ${esc(S.cta._labels[r])}</div><div class="cta">\n${cards}\n</div></div>`;
  })
  .join("\n");

// ── 4. emit ───────────────────────────────────────────────────────────────
// Keep the source commented, ship it dense: strip comments and indentation at
// emit. It costs nothing and it is worth doing everywhere (SHELL.md §5).
const css = read("src/shell.css")
  .replace(/\/\*(?!\s*TOKENS-(?:START|END))[\s\S]*?\*\//g, "")
  .split("\n")
  .map((l) => l.trim())
  .filter(Boolean)
  .join("\n");

const stamp = `agentelic ${S.version} · ${S.shell_revision} · record ${S.verified_at} · built ${new Date().toISOString().slice(0, 10)}`;


// The zero the pricing paragraph cites is the plate cell, not a re-typed word.
const zero = S.plate.find((c) => c.n === "0");
if (!zero) die("the plate has no zero — the pricing paragraph cites one and there must be a cell behind it");

let html = read("src/landing.html")
  .replace(/\{\{CSS\}\}/g, css)
  .replace(/\{\{BAND\}\}/g, band)
  .replace(/\{\{PLATE\}\}/g, plate)
  .replace(/\{\{PROBES\}\}/g, probes)
  .replace(/\{\{PROBE_DATE\}\}/g, esc(S.probes.measured_at))
  .replace(/\{\{HASHES\}\}/g, hashes)
  .replace(/\{\{BUILT\}\}/g, built)
  .replace(/\{\{STATUS\}\}/g, status)
  .replace(/\{\{RETRACTION\}\}/g, retraction)
  .replace(/\{\{PRICING_HEAD\}\}/g, esc(S.pricing.label))
  .replace(/\{\{PRICING_FLAG\}\}/g, esc(S.pricing.flag))
  .replace(/\{\{PRICING_ZERO\}\}/g, esc(`${zero.n} ${zero.l.toLowerCase()}`))
  .replace(/\{\{PRICING\}\}/g, pricing)
  .replace(/\{\{CTA\}\}/g, cta)
  .replace(/\{\{QUESTION\}\}/g, esc(S.question))
  .replace(/\{\{ORIGIN\}\}/g, esc(S.origin))
  .replace(/\{\{REPO\}\}/g, esc(S.repo))
  .replace(/\{\{SPEC\}\}/g, esc(S.spec_url || "https://docs.ampersandboxdesign.com/#/agentelic.com/docs/spec/README.md"))
  .replace(/\{\{CONTACT\}\}/g, esc(S.contact.url))
  .replace(/\{\{FORM_ENDPOINT\}\}/g, esc(S.contact.endpoint))
  .replace(/\{\{STAMP\}\}/g, esc(stamp))
  .replace(/\{\{YEAR\}\}/g, String(new Date().getFullYear()));

// r5: every §N a reader can SEE must resolve to a real heading in the spec it
// cites. Fenced code blocks are stripped first — a "# 3 lines to join a cluster"
// inside a fence is not a heading, and that bug has already bitten once.
{
  const visible = html
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ");
  const cited = [...new Set([...visible.matchAll(/§\s*([0-9]+(?:\.[0-9]+)*)/g)].map((m) => m[1]))];
  if (cited.length) {
    const specPath = resolve(root, "docs/spec/README.md");
    if (!existsSync(specPath)) die(`the page cites §${cited.join(", §")} and docs/spec/README.md does not exist`);
    const spec = readFileSync(specPath, "utf8").replace(/^```[\s\S]*?^```/gm, "");
    const heads = [...spec.matchAll(/^#{1,6}\s+.*$/gm)].map((m) => m[0]);
    for (const n of cited) {
      const hit = heads.some((h) => new RegExp(`(^|[^0-9.])${n.replace(/\./g, "\\.")}([^0-9.]|$)`).test(h));
      if (!hit) die(`the page cites §${n} and docs/spec/README.md has no heading numbered ${n} (fences stripped before extracting headings)`);
    }
  }
}

const left = html.match(/\{\{[A-Z_]+\}\}/g);
if (left) die(`unrendered token(s) survived into the artifact: ${[...new Set(left)].join(", ")}`);

writeFileSync(resolve(root, "index.html"), html);
writeFileSync(resolve(root, "idanim.js"), read("src/idanim.js"));
writeFileSync(resolve(root, "contact.js"), read("src/contact.js"));

// ── 5. the emit manifest — SHELL.md r6, hole 2 ────────────────────────────
// If this file THROWS, the previous index.html stays on disk and a gate that
// only reads the artifact approves a STALE ARTIFACT. Nothing proved the page
// came from the source beside it. So the last thing a SUCCESSFUL build does is
// record the sha256 of every input it read and every file it wrote.
//
// That is what makes the gate able to refuse alone:
//   · a source hash that no longer matches  → the build has not run since the
//     source changed, which is exactly the "build threw" case;
//   · an artifact hash that no longer matches → someone hand-edited the emitted
//     page, which this repo's CLAUDE.md forbids and nothing enforced.
//
// No timestamp on purpose: the manifest then changes only when the bytes do, so
// its diff is exactly the set of artifact changes and never build noise.
{
  const sha = (p) => createHash("sha256").update(readFileSync(resolve(root, p))).digest("hex");
  const sources = {};
  for (const p of ["src/landing.html", "src/shell.css", "src/idanim.js", "src/contact.js", "records/surface.json", "build-site.mjs"]) sources[p] = sha(p);
  const artifacts = {};
  for (const p of ["index.html", "idanim.js", "contact.js"]) artifacts[p] = sha(p);
  const build_id = createHash("sha256").update(Object.entries(sources).map(([k, v]) => `${k}:${v}`).join("\n")).digest("hex").slice(0, 16);
  writeFileSync(
    resolve(root, "records/build.json"),
    JSON.stringify({
      _comment:
        "Written by build-site.mjs as the last act of a SUCCESSFUL emit. launch-gate.mjs recomputes every hash here and refuses if one moved: a source that no longer matches means the build did not run since the source changed (a build that throws leaves the old index.html in place), and an artifact that no longer matches means the emitted page was hand-edited. SHELL.md r6, hole 2. Do not edit by hand — rebuild.",
      build_id,
      sources,
      artifacts,
    }, null, 2) + "\n",
  );
}

console.log(
  `✓ built index.html — ${html.length} bytes · rung ${S.surface_rung} · ` +
    `${S.built.rows.length} capabilities across ${presentRungs.size} rungs · ` +
    `${templates.length} template hash(es) recomputed and matched · ` +
    `${S.probes.rows.length} frozen probes (${S.probes.measured_at})`,
);
