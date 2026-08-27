"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

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
assert.match(html, /data-view="settings"[\s\S]*data-view="help"/);
assert.match(html, /data-view="blueprints"[^>]*>[\s\S]*?<em>BETA<\/em>[\s\S]*?id="nav-blueprint-count"/);
assert.match(html, /data-view="assistant"[^>]*>[\s\S]*?<em>BETA<\/em>/);
assert.match(html, /Área BETA · Ecossistemas guiados passo a passo/);
assert.match(html, /MNO Insights · BETA/);
assert.match(html, /Qualidade do modelo/);
assert.match(html, /a precisão e a consistência da resposta também dependem diretamente da LLM escolhida/);
assert.match(html, /Modelos gratuitos são indicados somente para testes/);
assert.match(html, /Modelos recomendados · revisão 25\/08\/2026/);
assert.match(html, /openai\/gpt-5\.6-terra/);
assert.match(html, /deepseek-v4-pro/);
assert.match(html, /qwen3:30b/);
assert.match(html, /execute o canário de quatro perguntas críticas/);
assert.match(html, /id="view-help"/);
assert.match(html, /Central de Ajuda/);
assert.match(html, /Seus primeiros 10 minutos/);
assert.match(html, /BETA · Manual completo em breve[\s\S]*<h3>Blueprints<\/h3>/);
assert.match(html, /O que significa a etiqueta BETA/);
assert.match(html, /“Em breve” indica algo que ainda não está disponível/);
assert.match(html, /Assistente MNO[\s\S]*help-status">BETA/);
assert.match(html, /Assistente MNO[\s\S]*diagnóstico local sem LLM/);
assert.match(html, /O <strong>Selo Essencial<\/strong> confirma que o instalador entregou a aplicação funcionando/);
assert.match(html, /No modo Tradicional, conecte-se ao servidor por SSH/);
assert.match(html, /No Windows com WSL2, abra o Docker Desktop/);
assert.match(html, /id="help-search"/);
assert.match(html, /data-help-filter="start"/);
assert.match(html, /data-help-topic/);
assert.match(app, /function bindHelpCenter/);
assert.match(app, /function filterHelpTopics/);
assert.match(app, /normalize\("NFD"\)/);
assert.match(app, /state\.view !== "help"/);
assert.match(styles, /\.help-search-panel/);
assert.match(styles, /\.help-start-card/);
assert.match(styles, /@media \(max-width: 650px\)[\s\S]*\.help-feature-grid/);
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
assert.match(html, /Cloudflare Access, sessão protegida/);
assert.doesNotMatch(html, /MFA já foram validados/);
assert.match(app, /Access ·/);
assert.match(html, /id="assistant-route-specialist"/);
assert.match(html, /id="assistant-disabled"/);
assert.match(html, /Assistente com IA desativado/);
assert.match(html, /id="assistant-diagnostic-run"/);
assert.match(html, /Especialista SRE · BETA/);
assert.match(html, /Nenhuma alteração será realizada/);
assert.match(html, /O SRE-4 acrescenta um plano consultivo obrigatório/);
assert.match(html, /id="assistant-plan-card"/);
assert.match(html, /Plano consultivo · BETA/);
assert.match(html, /id="assistant-runbook-card"/);
assert.match(html, /Runbooks homologados · BETA/);
assert.match(html, /id="assistant-strix-card"/);
assert.match(html, /Laboratório Strix · BETA/);
assert.match(html, /executor isolado ainda não foi homologado/);
assert.match(html, /SRE-6 · BETA · Preparação/);
assert.match(app, /openTerminal\("strix"\)/);
assert.match(app, /data\.plan\) && data\.capabilities\?\.strixDiagnostics === true/);
assert.match(app, /button\.dataset\.action === "strix" && !state\.strixDiagnosticsAccess/);
assert.match(app, /diagnóstico Strix SRE-6 está disponível nos planos PRO e PRO MASTER/);
assert.match(html, /Preparação segura · PRO e PRO MASTER/);
assert.match(html, /Governança, exceções e homologação continuam exclusivas do PRO MASTER/);
assert.match(html, /SRE-4 em BETA/);
assert.match(html, /SRE-5 em BETA/);
assert.match(html, /Runbook homologado SRE-5 · BETA/);
assert.match(html, /Gate de qualidade em BETA/);
assert.match(app, /event\.type === "output_gate"/);
assert.match(app, /function renderAssistantOutputGate/);
assert.match(app, /Gate de qualidade BETA acionado/);
assert.match(styles, /\.assistant-output-gate/);
assert.match(html, /Executar diagnóstico seguro \(BETA\)/);
assert.match(styles, /\.sre-readonly-banner/);
assert.match(styles, /\.consultative-plan\s*\{/);
assert.match(styles, /\.runbook-recommendation\s*\{/);
assert.match(styles, /@media \(max-width: 650px\)[\s\S]*\.consultative-plan-grid\s*\{[^}]*grid-template-columns:\s*1fr/);
assert.match(app, /event\.type === "plan"/);
assert.match(app, /event\.type === "runbook"/);
assert.match(app, /function renderConsultativePlan/);
assert.match(app, /function renderRunbookRecommendation/);
assert.match(app, /recommendation\?\.automaticExecution !== false/);
assert.match(app, /recommendation\?\.freeCommandAllowed !== false/);
assert.match(app, /runbook\?\.handoffAction === "sre"/);
assert.match(app, /runbook\?\.mutatesState === false/);
assert.match(app, /plan\?\.schemaVersion !== 1/);
assert.match(app, /plan\?\.maturity !== "beta"/);
assert.match(app, /plan\?\.executed !== false/);
assert.match(app, /plan\?\.executable !== false/);
assert.match(app, /Nenhuma ação foi executada\. Este plano não contém comandos nem autorização de mudança/);
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
assert.match(app, /Motor local verificado/);
assert.match(app, /testes do motor local aprovados/);
assert.match(app, /Valide a LLM configurada no canário/);
assert.match(app, /Modelo gratuito: recomendado somente para testes/);
assert.match(app, /A qualidade final depende também deste modelo/);
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
assert.match(html, /id="homologation-runner-card"/);
assert.match(html, /data-maintainer-only/);
assert.match(html, /PRO MASTER/);
assert.match(html, /canonical_import_wizard\.sh/);
assert.match(html, /Leia o dry-run/);
assert.match(html, /concede o Selo Essencial por arquitetura/);
assert.match(html, /data-action="homologation"/);
assert.match(app, /function renderHomologationRunner/);
assert.match(html, /id="supply-chain-status"/);
assert.match(app, /function renderSupplyChainStatus/);
assert.match(app, /CycloneDX 1\.6/);
assert.match(app, /ainda sem assinatura independente/);
assert.match(app, /homologação essencial automática por arquitetura/);
assert.match(app, /openTerminal\("homologation"\)/);
assert.match(app, /state\.maintainerAccess/);
assert.match(app, /applyMaintainerAccessState/);
assert.match(app, /intent: pendingTerminalIntent \|\| "installer"/);
assert.match(app, /Recurso exclusivo do plano PRO MASTER/);
assert.match(app, /"installer", "settings", "homologation", "sre", "strix", "gateway"/);
assert.match(app, /action\.dataset\.action === "sre"/);
assert.match(html, /data-action="sre"/);
assert.match(app, /homologation:\s*\{\s*title:\s*"Central do Mantenedor"/);
assert.match(app, /Homologação, validação e selo · PRO MASTER/);
assert.match(app, /\}\[intent\]\s*\|\|\s*\{/);
assert.match(styles, /\.homologation-runner-card\.available/);
assert.doesNotMatch(html + app, /homologationAutomaticPromotion\s*[:=]\s*true/);
assert.match(html, /Central de Homologação/);
assert.match(html, /id="view-homologation"/);
assert.match(html, /id="homologation-quarantine"/);
assert.match(html, /Selo Essencial/);
assert.match(html, /Homologar uma aplicação/);
assert.match(html, /data-maintainer-only hidden data-help-topic/);
assert.match(html, /RUNNER → Homologação automática/);
assert.match(html, /WordPress · ARM64/);
assert.match(app, /Selo essencial concedido/);
assert.match(app, /\/api\/homologation/);
assert.match(app, /function refreshHomologation/);
assert.match(app, /function renderHomologation/);
assert.match(app, /Selo Essencial: concedido[\s\S]*Publicação automática: não/);
assert.match(styles, /\.homologation-review-card\.status-quarantine/);

const terminalElements = new Map();
const helpTopics = [
  { dataset: { helpCategory: "solve", helpSearch: "docker desktop wsl2" }, textContent: "Docker não responde", tagName: "ARTICLE", hidden: false, open: false },
  { dataset: { helpCategory: "operate", helpSearch: "assistente diagnóstico" }, textContent: "Assistente MNO", tagName: "DETAILS", hidden: false, open: false }
];
function terminalElement(id) {
  if (!terminalElements.has(id)) {
    terminalElements.set(id, {
      id,
      open: false,
      src: "",
      textContent: "",
      innerHTML: "",
      style: { setProperty() {}, removeProperty() {} },
      showModal() { this.open = true; },
      close() { this.open = false; }
    });
  }
  return terminalElements.get(id);
}
const terminalContext = vm.createContext({
  console,
  Intl,
  URLSearchParams,
  setTimeout,
  clearTimeout,
  document: {
    addEventListener() {},
    getElementById: terminalElement,
    querySelectorAll(selector) { return selector === "[data-help-topic]" ? helpTopics : []; },
    activeElement: null
  },
  window: {
    matchMedia() { return { matches: false }; },
    requestAnimationFrame(callback) { callback(); },
    visualViewport: { height: 800, addEventListener() {} },
    innerHeight: 800,
    addEventListener() {},
    scrollTo() {},
    location: { origin: "https://control.example.com" }
  }
});
vm.runInContext(app, terminalContext, { filename: "web/app.js" });
vm.runInContext(`renderSupplyChainStatus({
  supplyChainAvailable: true,
  supplyChainImageReferences: 12,
  supplyChainDigestPinnedImages: 3,
  supplyChainUnresolvedReferences: 2
})`, terminalContext);
assert.match(terminalElement("supply-chain-status").textContent, /12 referências de imagem \(3 por digest\)/);
assert.match(terminalElement("supply-chain-status").textContent, /2 expressões não resolvidas/);
vm.runInContext(`applyReleaseMetadata({
  setupVersion: "7.34.3",
  architecture: "amd64",
  catalogEntries: 158
})`, terminalContext);
assert.match(terminalElement("supply-chain-status").textContent, /12 referências de imagem \(3 por digest\)/);
assert.doesNotMatch(terminalElement("supply-chain-status").textContent, /ainda não estão disponíveis/);
assert.equal(vm.runInContext('normalizeHelpText("Configurações e Aplicação")', terminalContext), "configuracoes e aplicacao");
terminalElement("help-search").value = "WSL2";
vm.runInContext("filterHelpTopics()", terminalContext);
assert.equal(helpTopics[0].hidden, false);
assert.equal(helpTopics[1].hidden, true);
assert.equal(terminalElement("help-result-count").textContent, "1 tópico encontrado");
vm.runInContext('openAuthorizedTerminal("homologation")', terminalContext);
assert.equal(terminalElement("terminal-dialog").open, true);
assert.equal(terminalElement("terminal-title").textContent, "Central do Mantenedor");
assert.match(terminalElement("terminal-frame").src, /^\/terminal\/\?arg=homologation&/);
assert.match(terminalElement("terminal-warning").innerHTML, /nunca publica commit, tag ou release/);

console.log("Markdown, RAG, Blueprints, evals e feedback privado conferidos.");
