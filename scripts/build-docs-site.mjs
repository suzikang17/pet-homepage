#!/usr/bin/env node
// Builds the self-contained docs browser at docs/site/index.html from the markdown
// docs (planning / features / architecture / specs / devlog). No dependencies.
// Run after editing docs:  node scripts/build-docs-site.mjs   (or: npm run docs:site)
import { readFileSync, writeFileSync, readdirSync, mkdirSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const docs = (p) => join(root, "docs", p);

function frontmatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---\n?/);
  const meta = {};
  if (m) {
    for (const line of m[1].split("\n")) {
      const i = line.indexOf(":");
      if (i > 0) meta[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^["']|["']$/g, "");
    }
    text = text.slice(m[0].length);
  }
  return { meta, body: text.trim() };
}

const mdFiles = (dir, pattern = /\.md$/) =>
  readdirSync(docs(dir))
    .filter((f) => pattern.test(f) && f !== "index.md")
    .sort()
    .map((f) => join(dir, f));

const collections = [
  { id: "architecture", label: "Architecture", files: ["architecture.md"], desc: "How the system hangs together — one page." },
  { id: "features", label: "Features", files: mdFiles("features", /^\d.*\.md$/), desc: "What exists today: capabilities, status + entry points." },
  { id: "planning", label: "Planning", files: mdFiles("planning"), desc: "Why this product should exist — Phase-0 chapters + roadmap." },
  { id: "specs", label: "Specs", files: mdFiles("superpowers/specs"), desc: "Frozen designs, as approved." },
  { id: "devlog", label: "Devlog", files: mdFiles("devlog", /^2\d.*\.md$/), desc: "What happened, day by day." },
];

const out = { collections: [], docs: {} };
for (const c of collections) {
  const ids = [];
  for (const f of c.files) {
    const raw = readFileSync(docs(f), "utf8");
    const { meta, body } = frontmatter(raw);
    const id = basename(f, ".md");
    const h1 = body.match(/^# (.+)$/m);
    out.docs[id] = { id, col: c.id, title: meta.title || (h1 ? h1[1] : id), meta, body };
    ids.push(id);
  }
  out.collections.push({ id: c.id, label: c.label, desc: c.desc, docs: ids });
}

const template = readFileSync(join(root, "scripts", "docs-site-template.html"), "utf8");
// `</` would terminate the inline <script> if a doc body contains it.
const json = JSON.stringify(out).replaceAll("</", "<\\/");
const html = template.replace("__DOCS_JSON__", json);

mkdirSync(docs("site"), { recursive: true });
writeFileSync(docs("site/index.html"), html);
console.log(`docs/site/index.html — ${Object.keys(out.docs).length} docs, ${Math.round(html.length / 1024)}KB`);
