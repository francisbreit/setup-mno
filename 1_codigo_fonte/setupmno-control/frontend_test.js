"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");

require("./web/markdown.js");

const { render } = globalThis.SetupMNOMarkdown;

assert.equal(
  render("A versão é **4.93.3**."),
  "A versão é <strong>4.93.3</strong>."
);
assert.equal(
  render("Use `docker service ls`."),
  "Use <code>docker service ls</code>."
);
assert.equal(
  render("1. N8N\n2. STRAPI"),
  "1. N8N\n2. STRAPI"
);

const malicious = render('**seguro** <img src=x onerror="alert(1)"> <script>alert(2)</script>');
assert.match(malicious, /<strong>seguro<\/strong>/);
assert.doesNotMatch(malicious, /<img|<script|onerror="/);
assert.match(malicious, /&lt;img/);

const html = fs.readFileSync("./web/index.html", "utf8");
const app = fs.readFileSync("./web/app.js", "utf8");
assert.match(html, /data-view="audit"[\s\S]*data-view="settings"/);
assert.match(html, /Central de Configurações/);
assert.match(html, /data-action="settings"/);
assert.doesNotMatch(html, /type="password"[^>]*settings/i);
for (const provider of ["OpenAI", "OpenRouter", "DeepSeek", "Ollama"]) {
  assert.match(html + app, new RegExp(provider));
}
assert.match(app, /openTerminal\("settings"\)/);
assert.match(html, /id="rag-inspection-title"/);
assert.match(html, /Validação de fundamentação/);
assert.match(html, /somente depois que as citações da resposta correspondem às evidências/);
assert.match(app, /event\.type === "retrieval"/);
assert.match(app, /event\.type === "grounding"/);
assert.match(app, /applyGroundingAudit/);
assert.match(app, /RAG validado/);
assert.match(app, /citation-missing/);
assert.match(app, /typeof inspection\.usedInAnswer !== "boolean"/);
assert.match(app, /Evidências relevantes enviadas · validação pendente/);
assert.match(app, /Citações validadas · resposta fundamentada/);
assert.match(app, /inspection\.promptSourceCount/);

console.log("Markdown seguro, Central de Configurações e validação RAG conferidos.");
