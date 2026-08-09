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
  responseProfile: "technical_diagnosis",
  promptVersion: "1.3.0",
  responseContractVersion: "1.1.0",
  promptSHA256: "a".repeat(64),
  question: "hostname-secreto"
});
assert.ok(Object.isFrozen(routeSnapshot));
assert.deepEqual(routeSnapshot, {
  specialist: "infrastructure_diagnostician",
  specialistName: "Mestre de operação e infraestrutura",
  risk: "low",
  riskName: "baixo",
  responseProfile: "technical_diagnosis",
  responseProfileName: "Análise técnica",
  promptVersion: "1.3.0",
  responseContractVersion: "1.1.0"
});
assert.equal(routeMetadata.snapshot({ specialist: "execute_shell", riskLevel: "high", responseProfile: "risk_review", promptVersion: "1.3.0", responseContractVersion: "1.1.0" }), null);
assert.equal(routeMetadata.snapshot({ specialist: "scope_guard", riskLevel: "low", responseProfile: "safe_redirect", promptVersion: "<script>", responseContractVersion: "1.1.0" }), null);
assert.equal(routeMetadata.snapshot({ specialist: "setup_specialist", riskLevel: "low", responseProfile: "invented", promptVersion: "1.3.0", responseContractVersion: "1.1.0" }), null);

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
assert.match(render("## Conclusão\n\n- Instalador homologado"), /<h4>Conclusão<\/h4>[\s\S]*<li>Instalador homologado<\/li>/);

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
assert.match(html, /id="idle-warning-dialog"/);
assert.match(html, /continuará executando no tmux/);
assert.match(app, /PANEL_IDLE_MS = 15 \* 60 \* 1000/);
assert.match(app, /TERMINAL_IDLE_MS = 30 \* 60 \* 1000/);
assert.match(app, /\/api\/session\/activity/);
assert.match(app, /setupmno-terminal-activity/);
assert.match(html, /Cloudflare Access com MFA/);
assert.match(html, /id="assistant-route-specialist"/);
assert.match(html, /id="assistant-disabled"/);
assert.match(html, /Assistente com IA desativado/);
assert.match(html, /id="assistant-diagnostic-run"/);
const disabledAssistant = html.match(/<section id="assistant-disabled"[\s\S]*?<\/section>/)?.[0] || "";
assert.equal((disabledAssistant.match(/<button/g) || []).length, 1);
assert.doesNotMatch(disabledAssistant, /<textarea|<form/);
assert.match(app, /function assistantModeUsesLLM/);
assert.match(app, /function renderAssistantAvailability/);
assert.match(app, /function runLocalDiagnostic/);
assert.match(html, /id="installation-type"/);
assert.match(html, /id="setup-plan"/);
assert.match(app, /Cloudflare Tunnel/);
assert.match(app, /Tradicional \(Traefik\)/);
assert.match(app, /chat com LLM é um recurso do plano PRO/);
assert.match(app, /operationalContextPartial/);
assert.match(app, /métricas ativas/);
assert.match(app, /dados ausentes não são inventados/);
assert.match(app, /state\.assistantMode === "later"/);
assert.match(app, /openai", "openrouter", "deepseek", "ollama/);
assert.match(html, /Roteador local/);
assert.match(html, /sem usar uma segunda LLM/);
assert.match(app, /event\.type === "route"/);
assert.match(app, /updateAssistantRoute/);
assert.match(routeSource, /Revisor de segurança/);
assert.match(routeSource, /Arquiteto de Blueprints/);
assert.match(routeSource, /Mestre de deploys e soluções/);
assert.match(routeSource, /Guardião de escopo/);
assert.match(app, /route\.promptRegistryVersion/);
assert.match(app, /route\.promptVersion/);
assert.match(app, /route\.promptSHA256/);
assert.match(app, /slice\(0, 12\)/);
assert.match(html, /assistant-route\.js\?v=/);
assert.match(app, /attachAssistantMessageRoute/);
assert.match(app, /message-route-specialist/);
assert.match(app, /snapshot\.specialistName.*snapshot\.responseProfileName/);
assert.match(app, /direct_overview: "explicação direta"/);
assert.match(app, /setAssistantMessageRouteUnavailable/);
assert.doesNotMatch(app, /target\._assistantMessageRoute\s*=\s*route/);
assert.match(styles, /\.message-route\s*\{[^}]*flex-wrap:\s*wrap/);
assert.match(styles, /\.message-route-risk\.risk-high/);
assert.match(styles, /@media \(max-width: 650px\)[\s\S]*\.message-route-specialist/);
assert.match(styles, /html, body\s*\{[^}]*max-width:\s*100%[^}]*overflow-x:\s*clip/);
assert.match(styles, /\.app-shell\s*\{[^}]*max-width:\s*100%[^}]*min-width:\s*0[^}]*overflow-x:\s*clip/);
assert.match(styles, /\.workspace\s*\{[^}]*width:\s*calc\(100% - var\(--sidebar\)\)[^}]*max-width:\s*calc\(100% - var\(--sidebar\)\)[^}]*min-width:\s*0[^}]*overflow-x:\s*clip/);
assert.match(styles, /@media \(max-width: 900px\)[\s\S]*\.workspace\s*\{[^}]*width:\s*100%[^}]*max-width:\s*100%[^}]*margin-left:\s*0/);
assert.match(html, /id="rag-inspection-title"/);
assert.match(html, /Validação de fundamentação/);
assert.match(html, /somente depois que as citações da resposta correspondem às evidências/);
assert.match(app, /event\.type === "retrieval"/);
assert.match(app, /event\.type === "quality"/);
assert.match(app, /renderAnswerQuality/);
assert.match(app, /message-route-quality/);
assert.match(app, /message-route-installation/);
assert.match(app, /message-route-integration/);
assert.match(app, /Instalador homologado/);
assert.match(app, /Integrações em expansão/);
assert.match(styles, /maturity-structural/);
assert.match(styles, /maturity-homologated/);
assert.match(styles, /assurance-homologated/);
assert.match(styles, /integration-not-mapped/);
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
assert.match(html, /Blueprints Beta/);
assert.match(html, /Guia manual em evolução/);
assert.match(html, /conecte as ferramentas com validações e rollback claros/);
assert.match(html, /id="blueprint-dialog"/);
assert.match(app, /api\("\/api\/blueprints"\)/);
assert.match(app, /function renderBlueprints/);
assert.match(app, /function openBlueprint/);
assert.match(app, /Blueprint Beta/);
assert.match(app, /ainda não concluiu a homologação técnica/);
assert.match(app, /Baixar Blueprint em ZIP/);
assert.match(app, /\/api\/blueprints\/\$\{encodeURIComponent\(item\.blueprintId\)\}\/download/);
for (const field of ["item.title", "item.summary", "item.objective", "item.blueprintId", "item.bundleSHA256"]) {
  assert.match(app, new RegExp(`escapeHTML\\(${field.replace(".", "\\.")}\\)`));
}
assert.match(html, /id="blueprint-recommendation-form"/);
assert.match(html, /Recomendação contextual local/);
assert.match(html, /Nenhuma LLM ou deploy é executado/);
assert.match(app, /\/api\/blueprints\/recommend/);
assert.match(app, /function renderBlueprintRecommendation/);
assert.match(app, /Blueprint\(s\) relacionado\(s\)/);
assert.match(app, /Não instale neste servidor ainda/);
assert.match(app, /recusado\(s\) pelos gates/);
assert.match(app, /memoryAvailableGB/);
assert.match(app, /Passo a passo de instalação e integração/);
assert.match(app, /Confirme que o ecossistema funciona/);
assert.match(app, /Plano de rollback/);
assert.match(app, /Informações técnicas e procedência/);
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
assert.match(html, /Feedback do Assistente/);
assert.match(html, /Sem conteúdo da conversa/);
assert.match(html, /id="feedback-dialog"/);
assert.match(html, /Nenhuma pergunta, resposta ou texto livre será incluído/);
const feedbackDialog = html.match(/<dialog id="feedback-dialog"[\s\S]*?<\/dialog>/)?.[0] || "";
assert.doesNotMatch(feedbackDialog, /<textarea|type="text"/);
assert.match(app, /event\.type === "feedback"/);
assert.match(app, /\/api\/feedback/);
assert.match(app, /\/api\/feedback\/review/);
assert.match(app, /\/api\/feedback\/delete/);
assert.match(app, /!\$\("feedback-consent"\)\.checked/);
assert.match(app, /consent:\s*true/);
assert.match(app, /function renderMessageFeedback/);
assert.match(app, /function renderFeedbackReview/);
assert.match(app, /document\.createElement\("article"\)/);
assert.match(app, /metadata\.textContent/);
assert.doesNotMatch(app, /feedback[^\n]*(question|answer)\s*:/i);
assert.match(styles, /\.message-feedback/);
assert.match(styles, /\.feedback-report-grid/);
assert.match(styles, /\.feedback-dialog::backdrop/);
assert.match(styles, /@media \(max-width: 650px\)[\s\S]*\.feedback-dialog\[open\]/);

console.log("Markdown, RAG, Blueprints, evals e feedback privado conferidos.");
