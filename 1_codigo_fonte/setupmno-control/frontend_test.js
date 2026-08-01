"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");

require("./web/markdown.js");
require("./web/assistant-route.js");

const { render } = globalThis.SetupMNOMarkdown;
const routeMetadata = globalThis.SetupMNOAssistantRoute;

const routeSnapshot = routeMetadata.snapshot({
  specialist: "infrastructure_diagnostician",
  riskLevel: "low",
  promptVersion: "1.3.0",
  responseContractVersion: "1.1.0",
  promptSHA256: "a".repeat(64),
  question: "hostname-secreto"
});
assert.ok(Object.isFrozen(routeSnapshot));
assert.deepEqual(routeSnapshot, {
  specialist: "infrastructure_diagnostician",
  specialistName: "Diagnóstico de infraestrutura",
  risk: "low",
  riskName: "baixo",
  promptVersion: "1.3.0",
  responseContractVersion: "1.1.0"
});
assert.equal(routeMetadata.snapshot({ specialist: "execute_shell", riskLevel: "high", promptVersion: "1.3.0", responseContractVersion: "1.1.0" }), null);
assert.equal(routeMetadata.snapshot({ specialist: "scope_guard", riskLevel: "low", promptVersion: "<script>", responseContractVersion: "1.1.0" }), null);

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
const routeSource = fs.readFileSync("./web/assistant-route.js", "utf8");
const styles = fs.readFileSync("./web/styles.css", "utf8");
assert.match(html, /data-view="audit"[\s\S]*data-view="settings"/);
assert.match(html, /Central de Configurações/);
assert.match(html, /data-action="settings"/);
assert.doesNotMatch(html, /type="password"[^>]*settings/i);
for (const provider of ["OpenAI", "OpenRouter", "DeepSeek", "Ollama"]) {
  assert.match(html + app, new RegExp(provider));
}
assert.match(app, /openTerminal\("settings"\)/);
assert.match(html, /id="assistant-route-specialist"/);
assert.match(html, /Roteador local/);
assert.match(html, /sem usar uma segunda LLM/);
assert.match(app, /event\.type === "route"/);
assert.match(app, /updateAssistantRoute/);
assert.match(routeSource, /Revisor de segurança/);
assert.match(routeSource, /Arquiteto de Blueprints/);
assert.match(routeSource, /Guardião de escopo/);
assert.match(app, /route\.promptRegistryVersion/);
assert.match(app, /route\.promptVersion/);
assert.match(app, /route\.promptSHA256/);
assert.match(app, /slice\(0, 12\)/);
assert.match(html, /assistant-route\.js\?v=/);
assert.match(app, /attachAssistantMessageRoute/);
assert.match(app, /message-route-specialist/);
assert.match(app, /textContent = snapshot\.specialistName/);
assert.match(app, /setAssistantMessageRouteUnavailable/);
assert.doesNotMatch(app, /target\._assistantMessageRoute\s*=\s*route/);
assert.match(styles, /\.message-route\s*\{[^}]*flex-wrap:\s*wrap/);
assert.match(styles, /\.message-route-risk\.risk-high/);
assert.match(styles, /@media \(max-width: 650px\)[\s\S]*\.message-route-specialist/);
assert.match(html, /id="rag-inspection-title"/);
assert.match(html, /Validação de fundamentação/);
assert.match(html, /somente depois que as citações da resposta correspondem às evidências/);
assert.match(app, /event\.type === "retrieval"/);
assert.match(app, /event\.type === "grounding"/);
assert.match(app, /event\.type === "blueprint_simulation"/);
assert.match(app, /renderBlueprintSimulation/);
assert.match(app, /Blueprint fictício e não implantável/);
assert.match(styles, /\.blueprint-simulation-banner/);
assert.match(app, /applyGroundingAudit/);
assert.match(app, /RAG validado/);
assert.match(app, /citation-missing/);
assert.match(app, /typeof inspection\.usedInAnswer !== "boolean"/);
assert.match(app, /Evidências relevantes enviadas · validação pendente/);
assert.match(app, /Citações validadas · resposta fundamentada/);
assert.match(app, /inspection\.promptSourceCount/);
assert.match(html, /data-view="blueprints"/);
assert.match(html, /id="view-blueprints"/);
assert.match(html, /Blueprints homologados/);
assert.match(html, /Exemplos fictícios/);
assert.match(html, /Simulação — não implantável/);
assert.match(html, /não executa instalações/);
assert.match(html, /id="blueprint-dialog"/);
assert.match(app, /api\("\/api\/blueprints"\)/);
assert.match(app, /function renderBlueprints/);
assert.match(app, /function openBlueprint/);
assert.match(app, /Blueprint fictício|Exemplo fictício/);
assert.match(app, /não autoriza deploy/);
assert.match(app, /Downloads e caminhos internos não são expostos/);
assert.doesNotMatch(html + app, /downloadBlueprint|\/api\/blueprints\/download/);
for (const field of ["item.title", "item.summary", "item.objective", "item.blueprintId", "item.bundleSHA256"]) {
  assert.match(app, new RegExp(`escapeHTML\\(${field.replace(".", "\\.")}\\)`));
}
assert.match(html, /id="blueprint-recommendation-form"/);
assert.match(html, /Recomendação contextual local/);
assert.match(html, /Nenhuma LLM ou deploy é executado/);
assert.match(app, /\/api\/blueprints\/recommend/);
assert.match(app, /function renderBlueprintRecommendation/);
assert.match(app, /Simulação com exemplos fictícios/);
assert.match(app, /recusado\(s\) pelos gates/);
assert.match(app, /memoryAvailableGB/);
assert.doesNotMatch(app, /data-action="terminal"[^\n]*blueprint-match/);
assert.match(app, /Fluxo editorial verificável/);
assert.match(app, /Promoção bloqueada/);
assert.match(app, /Exemplos ficam fora da trilha de promoção/);
assert.match(app, /Evidências de homologação/);
assert.match(app, /Selo determinístico da versão/);
assert.match(app, /Caminhos internos não são expostos/);
for (const field of [
  "entry.changedAt", "entry.note", "entry.actor", "gate.title",
  "entry.sha256", "versionSeal.manifestSHA256", "versionSeal.payloadSHA256"
]) {
  assert.match(app, new RegExp(`escapeHTML\\(${field.replace(".", "\\.")}[^)]*\\)`));
}
assert.doesNotMatch(html + app, /promoteBlueprint|approveBlueprint|uploadEvidence|\/api\/blueprints\/promote/);
assert.doesNotMatch(html, /class="nav-item" data-view="evals"/);
assert.match(html, /id="view-evals"/);
assert.match(html, /id="assistant-quality-card"/);
assert.match(html, /data-action="quality-report"/);
assert.match(html, /data-action="quality-return"/);
assert.match(html, /Qualidade do Assistente/);
assert.match(html, /Documentação correta/);
assert.match(html, /Especialista correto/);
assert.match(html, /Respostas baseadas nas fontes/);
assert.match(html, /O relatório contém somente métricas agregadas/);
assert.match(app, /api\("\/api\/evals"\)/);
assert.match(app, /function renderEvals/);
assert.match(app, /Qualidade verificada/);
assert.match(app, /testes automatizados aprovados antes desta release/);
assert.match(app, /quality-report/);
assert.match(app, /quality-return/);
assert.match(app, /metrics\.recallAt5/);
assert.match(app, /metrics\.credentialLeakCount/);
assert.match(app, /report\.datasetSHA256/);
assert.doesNotMatch(html + app, /evalQuestion|evalReferenceAnswer|evalExpectedDocuments/);
assert.match(styles, /\.eval-summary-grid/);
assert.match(styles, /\.assistant-quality-card/);
assert.match(styles, /@media \(max-width: 650px\)[\s\S]*\.eval-intro/);
assert.match(html, /id="provider-eval-run"/);
assert.match(html, /Canário de respostas críticas/);
assert.match(html, /Nenhum dado do servidor participa do teste/);
assert.match(html, /revisão humana obrigatória/);
assert.match(app, /\/api\/evals\/provider/);
assert.match(app, /\/api\/evals\/provider\/review/);
assert.match(app, /CONSUMO DE API AUTORIZADO/);
assert.match(app, /window\.confirm/);
assert.match(app, /answer\.textContent = item\.providerResponse/);
assert.doesNotMatch(app, /innerHTML\s*=\s*item\.providerResponse/);
assert.match(styles, /\.provider-eval-panel/);
assert.match(styles, /\.provider-eval-cases/);

console.log("Markdown, RAG, Blueprints e relatório agregado de evals conferidos.");
