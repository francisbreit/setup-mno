const state = {
  csrf: "",
  user: "",
  controlVersion: "",
  setupVersion: "",
  setupState: null,
  overview: null,
  apps: [],
  catalog: [],
  quality: null,
  qualityByCatalog: {},
  blueprints: [],
  blueprintCatalog: null,
  blueprintRecommendation: null,
  evals: null,
  providerEval: null,
  providerEvalDecisions: {},
  providerEvalCooldown: false,
  feedbackTarget: null,
  feedbackRating: "",
  auditEvents: [],
  auditNextBefore: 0,
  assistantMode: "basic",
  assistantModel: "",
  setupPlan: "",
  llmAllowed: false,
  maintainerAccess: false,
  homologationRunnerAvailable: false,
  homologation: null,
  homologationItems: [],
  assistantHistory: [],
  assistantRoute: null,
  view: "dashboard",
  timer: null,
  catalogTimer: null,
  activityTimer: null,
  lastActivityAt: 0,
  lastActivityHeartbeatAt: 0,
  activityHeartbeatInFlight: false
};

const $ = id => document.getElementById(id);
const fmt = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 1 });
let terminalLoadSequence = 0;
let pendingTerminalIntent = "";
const PANEL_IDLE_MS = 15 * 60 * 1000;
const TERMINAL_IDLE_MS = 30 * 60 * 1000;
const IDLE_WARNING_MS = 2 * 60 * 1000;
const ACTIVITY_HEARTBEAT_MS = 15 * 1000;
const titles = {
  dashboard: ["Infraestrutura em tempo real", "Visão geral"],
  installed: ["Inventário do Docker Swarm", "Aplicações instaladas"],
  catalog: ["Deploys e instalações", "Catálogo de setups"],
  blueprints: ["Arquiteturas compostas", "Blueprints MNO"],
  assistant: ["Diagnóstico assistido", "Assistente MNO"],
  evals: ["Relatório técnico", "Qualidade do Assistente"],
  homologation: ["Evidências operacionais", "Revisão de Homologação"],
  audit: ["Rastreabilidade da sessão", "Auditoria"],
  settings: ["Administração protegida", "Configurações"],
  help: ["Aprenda no seu ritmo", "Help · Instruções de uso"]
};

let helpFilter = "all";

document.addEventListener("DOMContentLoaded", init);

async function init() {
  bindEvents();
  try {
    const session = await api("/api/session");
    setAuthenticated(session);
  } catch {
    showLogin();
  }
}

function bindEvents() {
  $("login-form").addEventListener("submit", login);
  $("toggle-password").addEventListener("click", () => {
    const input = $("login-password");
    const visible = input.type === "text";
    input.type = visible ? "password" : "text";
    $("toggle-password").textContent = visible ? "Mostrar" : "Ocultar";
  });
  $("logout-button").addEventListener("click", logout);
  $("refresh-button").addEventListener("click", refreshAll);
  bindHelpCenter();
  $("navigation").addEventListener("click", event => {
    const button = event.target.closest("[data-view]");
    if (button) navigate(button.dataset.view);
  });
  document.body.addEventListener("click", event => {
    const nav = event.target.closest("[data-nav]");
    if (nav) navigate(nav.dataset.nav);
    const action = event.target.closest("[data-action]");
    if (!action) return;
    if (action.dataset.action === "terminal") openTerminal();
    if (action.dataset.action === "assistant") navigate("assistant");
    if (action.dataset.action === "settings") openTerminal("settings");
    if (action.dataset.action === "homologation") openTerminal("homologation");
    if (action.dataset.action === "sre") openTerminal("sre");
    if (action.dataset.action === "gateway") openTerminal("gateway");
    if (action.dataset.action === "blueprint") openBlueprint(action.dataset.blueprintId);
    if (action.dataset.action === "quality-report") navigate("evals");
    if (action.dataset.action === "quality-return") navigate("assistant");
  });
  $("open-terminal-top").addEventListener("click", openTerminal);
  $("terminal-close").addEventListener("click", closeTerminal);
  $("terminal-dialog").addEventListener("cancel", event => {
    event.preventDefault();
    closeTerminal();
  });
  $("terminal-reauth-form").addEventListener("submit", confirmTerminalAccess);
  $("terminal-reauth-close").addEventListener("click", closeTerminalReauth);
  $("terminal-reauth-cancel").addEventListener("click", closeTerminalReauth);
  $("terminal-reauth-dialog").addEventListener("cancel", event => {
    event.preventDefault();
    closeTerminalReauth();
  });
  $("idle-warning-continue").addEventListener("click", () => markSessionActivity(terminalDialogOpen(), true));
  $("idle-warning-exit").addEventListener("click", logout);
  $("idle-warning-dialog").addEventListener("cancel", event => event.preventDefault());
  ["pointerdown", "keydown", "touchstart", "scroll"].forEach(eventName => {
    document.addEventListener(eventName, () => markSessionActivity(terminalDialogOpen()), { passive: true });
  });
  window.addEventListener("message", event => {
    const frame = $("terminal-frame");
    if (event.origin !== window.location.origin || event.source !== frame.contentWindow) return;
    if (event.data?.type !== "setupmno-terminal-activity") return;
    markSessionActivity(true);
  });
  window.addEventListener("resize", syncTerminalDialogViewport, { passive: true });
  window.addEventListener("orientationchange", syncTerminalDialogViewport, { passive: true });
  window.visualViewport?.addEventListener("resize", syncTerminalDialogViewport, { passive: true });
  $("installed-search").addEventListener("input", renderInstalled);
  $("installed-filter").addEventListener("change", renderInstalled);
  $("catalog-search").addEventListener("input", renderCatalog);
  $("catalog-category").addEventListener("change", renderCatalog);
  $("catalog-arch").addEventListener("change", renderCatalog);
  $("homologation-search").addEventListener("input", renderHomologation);
  $("homologation-filter").addEventListener("change", renderHomologation);
  $("homologation-arch").addEventListener("change", renderHomologation);
  $("blueprint-search").addEventListener("input", renderBlueprints);
  $("blueprint-status").addEventListener("change", renderBlueprints);
  $("blueprint-arch").addEventListener("change", renderBlueprints);
  $("blueprint-risk").addEventListener("change", renderBlueprints);
  $("blueprint-recommendation-form").addEventListener("submit", requestBlueprintRecommendation);
  $("blueprint-dialog-close").addEventListener("click", closeBlueprint);
  $("blueprint-dialog").addEventListener("cancel", event => {
    event.preventDefault();
    closeBlueprint();
  });
  $("assistant-form").addEventListener("submit", askAssistant);
  $("assistant-diagnostic-run").addEventListener("click", runLocalDiagnostic);
  $("provider-eval-run").addEventListener("click", runProviderEval);
  $("provider-eval-review").addEventListener("click", submitProviderEvalReview);
  $("provider-eval-cases").addEventListener("click", event => {
    const decision = event.target.closest("[data-provider-decision]");
    if (decision) setProviderEvalDecision(decision.dataset.caseId, decision.dataset.providerDecision === "approve");
  });
  $("assistant-conversation").addEventListener("click", event => {
    const button = event.target.closest("[data-feedback-rating]");
    if (button) openFeedbackDialog(button.closest(".assistant-message"), button.dataset.feedbackRating);
  });
  $("feedback-form").addEventListener("submit", submitAssistantFeedback);
  $("feedback-dialog-close").addEventListener("click", closeFeedbackDialog);
  $("feedback-dialog-cancel").addEventListener("click", closeFeedbackDialog);
  $("feedback-dialog").addEventListener("cancel", event => {
    event.preventDefault();
    closeFeedbackDialog();
  });
  $("feedback-review-list").addEventListener("click", event => {
    const button = event.target.closest("[data-feedback-action]");
    if (!button) return;
    if (button.dataset.feedbackAction === "delete") deleteFeedbackRecord(button.dataset.feedbackId);
    else reviewFeedbackRecord(button.dataset.feedbackId, button.dataset.feedbackAction);
  });
  $("audit-load-more").addEventListener("click", () => loadAudit(state.auditNextBefore, true));
  document.querySelector(".prompt-chips").addEventListener("click", event => {
    if (event.target.tagName !== "BUTTON") return;
    $("assistant-input").value = event.target.textContent;
    $("assistant-form").requestSubmit();
  });
  $("sidebar-open").addEventListener("click", openSidebar);
  $("sidebar-close").addEventListener("click", closeSidebar);
  $("sidebar-backdrop").addEventListener("click", closeSidebar);
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden && state.csrf) refreshReleaseData();
  });
}

function normalizeHelpText(value) {
  return String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-BR").trim();
}

function bindHelpCenter() {
  const search = $("help-search");
  if (!search) return;
  search.addEventListener("input", filterHelpTopics);
  $("help-filters")?.addEventListener("click", event => {
    const button = event.target.closest("[data-help-filter]");
    if (!button) return;
    helpFilter = button.dataset.helpFilter || "all";
    document.querySelectorAll("[data-help-filter]").forEach(item => item.classList.toggle("active", item === button));
    filterHelpTopics();
  });
  $("help-clear-search")?.addEventListener("click", () => {
    search.value = "";
    helpFilter = "all";
    document.querySelectorAll("[data-help-filter]").forEach(item => item.classList.toggle("active", item.dataset.helpFilter === "all"));
    filterHelpTopics();
    search.focus();
  });
  document.addEventListener("keydown", event => {
    if (state.view !== "help") return;
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(event.target?.tagName || "");
    if (event.key === "/" && !typing) {
      event.preventDefault();
      search.focus();
    } else if (event.key === "Escape" && document.activeElement === search && search.value) {
      search.value = "";
      filterHelpTopics();
    }
  });
  filterHelpTopics();
}

function filterHelpTopics() {
  const search = $("help-search");
  if (!search) return;
  const query = normalizeHelpText(search.value);
  const topics = [...document.querySelectorAll("[data-help-topic]")];
  let visible = 0;
  topics.forEach(topic => {
    const categories = String(topic.dataset.helpCategory || "").split(/\s+/);
    const categoryMatch = helpFilter === "all" || categories.includes(helpFilter);
    const haystack = normalizeHelpText(`${topic.dataset.helpSearch || ""} ${topic.textContent || ""}`);
    const queryMatch = !query || haystack.includes(query);
    const show = categoryMatch && queryMatch;
    topic.hidden = !show;
    if (show) {
      visible += 1;
      if (query.length >= 3 && topic.tagName === "DETAILS") topic.open = true;
    }
  });
  const count = $("help-result-count");
  if (count) count.textContent = `${visible} ${visible === 1 ? "tópico encontrado" : "tópicos encontrados"}`;
  const empty = $("help-no-results");
  if (empty) empty.hidden = visible !== 0;
}

async function login(event) {
  event.preventDefault();
  $("login-error").textContent = "";
  const button = event.currentTarget.querySelector("button[type=submit]");
  button.disabled = true;
  button.querySelector("span").textContent = "Autenticando...";
  try {
    const session = await api("/api/login", {
      method: "POST",
      body: JSON.stringify({
        username: $("login-user").value.trim(),
        password: $("login-password").value
      })
    });
    $("login-password").value = "";
    setAuthenticated(session);
  } catch (error) {
    $("login-error").textContent = error.message;
  } finally {
    button.disabled = false;
    button.querySelector("span").textContent = "Entrar no Control Center";
  }
}

async function logout() {
  try {
    await api("/api/logout", { method: "POST" });
  } catch {}
  state.csrf = "";
  clearInterval(state.timer);
  clearInterval(state.catalogTimer);
  clearInterval(state.activityTimer);
  closeTerminal();
  closeIdleWarning();
  showLogin();
}

function setAuthenticated(session) {
  state.csrf = session.csrfToken;
  state.user = session.user;
  state.controlVersion = session.controlVersion || session.version;
  state.setupVersion = "";
  state.setupState = null;
  state.catalog = [];
  state.blueprints = [];
  state.blueprintCatalog = null;
  state.blueprintRecommendation = null;
  state.evals = null;
  state.providerEval = null;
  state.providerEvalDecisions = {};
  state.providerEvalCooldown = false;
  state.feedbackTarget = null;
  state.feedbackRating = "";
  state.auditEvents = [];
  state.auditNextBefore = 0;
  $("assistant-quality-card").classList.remove("passed", "failed");
  $("assistant-quality-title").textContent = "Verificando o motor local";
  $("assistant-quality-summary").textContent = "Os testes da release não substituem a validação da LLM escolhida.";
  $("provider-eval-result").hidden = true;
  $("provider-eval-review-status").textContent = "";
  $("blueprint-recommendation-result").hidden = true;
  state.assistantMode = session.assistantMode || "basic";
  state.assistantModel = session.assistantModel || "";
  state.assistantHistory = [];
  $("current-user").textContent = state.user;
	$("access-identity").textContent = session.accessEmail ? `Access · ${session.accessEmail}` : "Administrador";
  $("hero-user").textContent = state.user;
  $("user-initial").textContent = state.user.slice(0, 1).toUpperCase();
  $("settings-username").textContent = state.user;
  $("control-version").textContent = `v${state.controlVersion}`;
  $("setup-version").textContent = "verificando";
  applyTerminalAccessState();
  renderAssistantMode();
  $("login-view").classList.add("hidden");
  $("app-view").classList.remove("hidden");
  refreshAll();
  clearInterval(state.timer);
  clearInterval(state.catalogTimer);
  state.timer = setInterval(refreshOverview, 30000);
  state.catalogTimer = setInterval(refreshReleaseData, 300000);
  state.lastActivityAt = Date.now();
  state.lastActivityHeartbeatAt = Date.now();
  clearInterval(state.activityTimer);
  state.activityTimer = setInterval(checkSessionInactivity, 1000);
}

function showLogin() {
  clearInterval(state.timer);
  clearInterval(state.catalogTimer);
  clearInterval(state.activityTimer);
  closeTerminal();
  closeIdleWarning();
  $("app-view").classList.add("hidden");
  $("login-view").classList.remove("hidden");
  setTimeout(() => $("login-user").focus(), 80);
}

function terminalDialogOpen() {
  return Boolean($("terminal-dialog")?.open);
}

function markSessionActivity(terminal = false, force = false) {
  if (!state.csrf) return;
  const now = Date.now();
  state.lastActivityAt = now;
  closeIdleWarning();
  if (!force && (state.activityHeartbeatInFlight || now - state.lastActivityHeartbeatAt < ACTIVITY_HEARTBEAT_MS)) return;
  state.lastActivityHeartbeatAt = now;
  state.activityHeartbeatInFlight = true;
  api("/api/session/activity", {
    method: "POST",
    body: JSON.stringify({ terminal: Boolean(terminal) })
  }).catch(() => {}).finally(() => {
    state.activityHeartbeatInFlight = false;
  });
}

function checkSessionInactivity() {
  if (!state.csrf || !state.lastActivityAt) return;
  const terminal = terminalDialogOpen();
  const limit = terminal ? TERMINAL_IDLE_MS : PANEL_IDLE_MS;
  const remaining = limit - (Date.now() - state.lastActivityAt);
  if (remaining <= 0) {
    closeTerminal();
    logout();
    return;
  }
  if (remaining <= IDLE_WARNING_MS) {
    const dialog = $("idle-warning-dialog");
    $("idle-warning-countdown").textContent = formatCountdown(remaining);
    $("idle-warning-job-note").hidden = !terminal;
    if (!dialog.open) dialog.showModal();
  } else {
    closeIdleWarning();
  }
}

function formatCountdown(milliseconds) {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = String(totalSeconds % 60).padStart(2, "0");
  return `${minutes}:${seconds}`;
}

function closeIdleWarning() {
  const dialog = $("idle-warning-dialog");
  if (dialog?.open) dialog.close();
}

async function refreshAll() {
  $("refresh-button").classList.add("spinning");
  await Promise.allSettled([refreshOverview(), refreshApps(), refreshReleaseData(), refreshEvals(), refreshHomologation()]);
  $("refresh-button").classList.remove("spinning");
}

async function refreshReleaseData() {
  await refreshSetupState();
  await Promise.allSettled([refreshCatalog(), refreshQuality(), refreshBlueprints()]);
}

async function refreshOverview() {
  try {
    const data = await api("/api/overview");
    state.overview = data.overview;
    renderOverview();
    clearAlert();
  } catch (error) {
    showAlert(error.message);
  }
}

async function refreshApps() {
  try {
    const data = await api("/api/apps");
    state.apps = data.apps || [];
    renderInstalled();
    renderRecent();
  } catch (error) {
    showAlert(error.message);
  }
}

async function refreshCatalog() {
  try {
    const data = await api("/api/catalog");
    state.catalog = data.items || [];
    applyReleaseMetadata(data);
    populateCategories();
    renderCatalog();
  } catch (error) {
    setCatalogSyncStatus(true, error.message);
  }
}

async function refreshQuality() {
  const status = $("catalog-quality-status");
  try {
    const data = await api("/api/quality");
    state.quality = data;
    state.qualityByCatalog = Object.fromEntries(
      (Array.isArray(data.entries) ? data.entries : [])
        .filter(entry => entry && typeof entry.catalogName === "string")
        .map(entry => [entry.catalogName, entry])
    );
    const summary = data.summary || {};
    const operational = Number(summary.operationalEvidenceEntries) || 0;
    const homologated = Number(summary.homologatedEntries) || 0;
    status.className = `sync-status ${data.stale ? "stale" : "current"}`;
    status.textContent = data.stale
      ? data.warning || "Relatório de homologação em contingência."
      : `Selo de Homologação validado · ${operational} operacional · ${homologated} homologado · evidências somente leitura`;
    renderCatalog();
  } catch (error) {
    state.quality = null;
    state.qualityByCatalog = {};
    status.className = "sync-status stale";
    status.textContent = `Selo de Homologação indisponível: ${error.message}`;
    renderCatalog();
  }
}

async function refreshHomologation() {
  const status = $("homologation-review-status");
  if (!state.maintainerAccess) return;
  try {
    const data = await api("/api/homologation");
    state.homologation = data;
    state.homologationItems = Array.isArray(data.items) ? data.items : [];
    status.className = "sync-status current";
    status.textContent = `Inventário somente leitura · Runner v${data.runnerVersion || "—"} · Setup MNO v${data.setupVersion || "—"}`;
    renderHomologation();
  } catch (error) {
    state.homologation = null;
    state.homologationItems = [];
    status.className = "sync-status stale";
    status.textContent = error.message;
    renderHomologation();
  }
}

function homologationStatusLabel(status) {
  return ({
    pending: "Aguardando revisão",
    approved: "Aprovado localmente",
    sealed: "Selo essencial concedido",
    rejected: "Recusado",
    draft: "Checklist em andamento",
    incompatible: "Artefato incompatível",
    quarantine: "Quarentena"
  })[status] || "Estado desconhecido";
}

function renderHomologation() {
  const summary = state.homologation?.summary || {};
  ["pending", "approved", "sealed", "rejected", "draft", "incompatible", "quarantine"].forEach(key => {
    const target = $(`homologation-${key}`);
    if (target) target.textContent = Number(summary[key]) || 0;
  });
  const reviewCount = (Number(summary.pending) || 0) + (Number(summary.incompatible) || 0) + (Number(summary.quarantine) || 0);
  $("nav-homologation-count").textContent = reviewCount;
  const query = ($("homologation-search")?.value || "").trim().toLowerCase();
  const filter = $("homologation-filter")?.value || "";
  const arch = $("homologation-arch")?.value || "";
  const items = state.homologationItems.filter(item => {
    const searchable = `${item.setupId || ""} ${item.runId || ""} ${item.candidateId || ""}`.toLowerCase();
    return (!query || searchable.includes(query)) && (!filter || item.status === filter) && (!arch || item.architecture === arch);
  });
  $("homologation-result").textContent = `${items.length} de ${state.homologationItems.length} registros encontrados`;
  $("homologation-list").innerHTML = items.length ? items.map(item => {
    const checks = Object.entries(item.checks || {});
    const checkMarkup = checks.length ? `<div class="homologation-checks">${checks.map(([name, check]) => `<span class="check-${escapeHTML(check.status)}"><b>${escapeHTML(name)}</b>${escapeHTML(check.status)}</span>`).join("")}</div>` : "";
    const decision = item.decision ? `<div class="homologation-decision"><strong>Decisão imutável</strong><span>${escapeHTML(item.decision.reviewedBy)} · ${escapeHTML(String(item.decision.reviewedAt || "").slice(0, 10))}</span><p>${escapeHTML(item.decision.reason)}</p></div>` : "";
    return `<article class="homologation-review-card status-${escapeHTML(item.status)}">
      <div class="homologation-review-head"><div><span class="type-label">${item.kind === "candidate" ? "Candidato" : "Sessão"}</span><h3>${escapeHTML(item.setupId || item.id)}</h3></div><span class="homologation-state">${escapeHTML(homologationStatusLabel(item.status))}</span></div>
      <div class="homologation-metadata"><span><b>Execução</b>${escapeHTML(item.runId || "—")}</span><span><b>Arquitetura</b>${item.architecture === "arm64" ? "ARM64" : item.architecture === "amd64" ? "X86_64" : "—"}</span><span><b>Setup / Runner</b>${escapeHTML(item.setupVersion || "—")} / ${escapeHTML(item.runnerVersion || "—")}</span><span><b>Compatibilidade</b>${escapeHTML(item.compatibility || "—")}</span></div>
      ${item.warning ? `<p class="homologation-warning">${escapeHTML(item.warning)}</p>` : ""}${decision}
      <details><summary>Ver evidências e checks</summary>${checkMarkup || "<p class=\"muted\">O checklist ainda está em elaboração.</p>"}<p class="homologation-seal-boundary">${item.officialSeal ? `Selo Essencial: concedido · Escopo: instalação e inicialização · ID: ${escapeHTML(item.sealId || "—")}` : "Selo Essencial: ainda não concedido"} · Publicação automática: não</p></details>
    </article>`;
  }).join("") : `<div class="empty-state">Nenhum registro corresponde aos filtros. Use o Terminal Seguro para iniciar uma sessão.</div>`;
  applyTerminalAccessState();
}

async function refreshBlueprints() {
  try {
    const data = await api("/api/blueprints");
    state.blueprints = Array.isArray(data.items) ? data.items : [];
    state.blueprintCatalog = data;
    renderBlueprintSyncStatus();
    renderBlueprints();
  } catch (error) {
    const target = $("blueprint-sync-status");
    target.className = "sync-status stale";
    target.textContent = error.message;
  }
}

async function refreshEvals() {
  try {
    state.evals = await api("/api/evals");
    renderEvals();
  } catch (error) {
    state.evals = null;
    const status = $("eval-status");
    status.className = "eval-release-status failed";
    status.textContent = "Indisponível";
    const qualityCard = $("assistant-quality-card");
    qualityCard.classList.remove("passed");
    qualityCard.classList.add("failed");
    $("assistant-quality-title").textContent = "Qualidade indisponível";
    $("assistant-quality-summary").textContent = "Não foi possível consultar a verificação desta release.";
  }
}

function evalPercent(value) {
  return `${fmt.format(Number(value) || 0)}%`;
}

function renderEvals() {
  const report = state.evals;
  if (!report) return;
  const metrics = report.metrics || {};
  const status = $("eval-status");
  const passed = report.status === "passed";
  status.className = `eval-release-status ${passed ? "passed" : "failed"}`;
  status.textContent = passed ? "Release verificada" : "Verificação bloqueada";
  const qualityCard = $("assistant-quality-card");
  qualityCard.classList.toggle("passed", passed);
  qualityCard.classList.toggle("failed", !passed);
  $("assistant-quality-title").textContent = passed ? "Motor local verificado" : "Verificação bloqueada";
  $("assistant-quality-summary").textContent = passed
    ? `${report.caseCount || 0} testes do motor local aprovados. Valide a LLM configurada no canário.`
    : "Os testes de qualidade bloquearam esta release.";
  $("eval-case-count").textContent = report.caseCount || 0;
  $("eval-case-detail").textContent = `${report.retrievalCases || 0} retrieval · ${report.routingCases || 0} routing`;
  $("eval-recall").textContent = evalPercent(metrics.recallAt5);
  $("eval-routing").textContent = evalPercent(metrics.routingAccuracy);
  $("eval-safety").textContent = evalPercent(metrics.safety);
  $("eval-precision").textContent = evalPercent(metrics.precisionAt5);
  $("eval-mrr").textContent = evalPercent(metrics.meanReciprocalRank);
  $("eval-map").textContent = evalPercent(metrics.meanAveragePrecision);
  $("eval-factuality").textContent = evalPercent(metrics.factuality);
  $("eval-groundedness").textContent = evalPercent(metrics.groundedness);
  $("eval-blueprint-selection").textContent = evalPercent(metrics.blueprintSelection);
  $("eval-rollback").textContent = evalPercent(metrics.criticalRollback);
  $("eval-no-evidence").textContent = evalPercent(metrics.noEvidenceHonesty);
  $("eval-stale").textContent = evalPercent(metrics.staleDocumentRate);
  $("eval-architecture-mix").textContent = evalPercent(metrics.architectureMixRate);
  $("eval-credential-leaks").textContent = String(metrics.credentialLeakCount ?? 0);
  $("eval-invented-actions").textContent = String(metrics.inventedActionCount ?? 0);
  $("eval-regressions").textContent = `${report.baseline?.regressions ?? 0} regressões`;
  $("eval-versions").textContent = `v${report.datasetVersion} / v${report.graderVersion}`;
  $("eval-engine-versions").textContent = `v${report.retrievalVersion} / v${report.routerVersion} / v${report.promptVersion}`;
  $("eval-baseline").textContent = `${report.baseline?.release || "N/I"} · ${report.baseline?.mode === "established" ? "estabelecido" : "comparativo"}`;
  $("eval-dataset-sha").textContent = report.datasetSHA256 || "N/I";
}

function renderProviderEvalAvailability() {
  const enabled = assistantModeUsesLLM(state.assistantMode) && Boolean(state.assistantModel);
  const button = $("provider-eval-run");
  $("provider-eval-provider").textContent = enabled
    ? `${providerLabel(state.assistantMode)} · ${state.assistantModel}`
    : providerLabel(state.assistantMode);
  if (!enabled) {
    button.disabled = true;
    button.textContent = "Requer provedor opcional";
    $("provider-eval-status").textContent = "Sem consumo de IA";
    $("provider-eval-help").textContent = state.assistantMode === "later"
      ? "O conector foi adiado. Configure OpenAI, OpenRouter, DeepSeek ou Ollama para habilitar este canário."
      : "Configure OpenAI, OpenRouter, DeepSeek ou Ollama para habilitar este canário.";
    return;
  }
  if (state.providerEvalCooldown) {
    button.disabled = true;
    button.textContent = "Canário já executado";
    $("provider-eval-help").textContent = "A repetição fica bloqueada por dez minutos para evitar consumo acidental.";
    return;
  }
  button.disabled = false;
  button.textContent = "Executar 4 testes críticos";
  $("provider-eval-status").textContent = "Pronto para execução manual";
  $("provider-eval-help").textContent = "Usa o modelo configurado e pode consumir créditos ou recursos locais.";
}

async function runProviderEval() {
  if (!window.confirm("Executar quatro perguntas críticas sintéticas no provedor configurado? Isso pode consumir créditos ou recursos locais. Nenhum dado do servidor será enviado.")) return;
  const button = $("provider-eval-run");
  button.disabled = true;
  button.textContent = "Executando canário...";
  $("provider-eval-status").textContent = "Em execução";
  $("provider-eval-review-status").textContent = "";
  try {
    const report = await api("/api/evals/provider", {
      method: "POST",
      body: JSON.stringify({ acknowledgement: "CONSUMO DE API AUTORIZADO" })
    });
    state.providerEval = report;
    state.providerEvalDecisions = {};
    state.providerEvalCooldown = true;
    renderProviderEvalReport();
  } catch (error) {
    state.providerEvalCooldown = true;
    $("provider-eval-status").textContent = "Falha controlada";
    $("provider-eval-help").textContent = error.message;
    button.textContent = "Canário não concluído";
  }
}

function renderProviderEvalReport() {
  const report = state.providerEval;
  if (!report) return;
  $("provider-eval-result").hidden = false;
  $("provider-eval-status").textContent = report.status === "human_review_required"
    ? "Revisão humana necessária"
    : "Verificação automática reprovada";
  $("provider-eval-summary").textContent = `${providerLabel(report.provider)} · ${report.model}`;
  $("provider-eval-metrics").textContent = `${report.automaticPassed || 0} de ${report.caseCount || 0} respostas passaram nos checks automáticos`;
  const container = $("provider-eval-cases");
  container.replaceChildren();
  for (const item of report.cases || []) {
    const card = document.createElement("article");
    card.className = `provider-eval-case ${item.automaticPass ? "automatic-pass" : "automatic-fail"}`;
    card.id = `provider-case-${item.caseId}`;
    const head = document.createElement("div");
    const title = document.createElement("strong");
    title.textContent = item.category;
    const automatic = document.createElement("span");
    automatic.textContent = item.automaticPass ? "Checks automáticos aprovados" : "Checks automáticos reprovados";
    head.append(title, automatic);
    const promptLabel = document.createElement("small");
    promptLabel.textContent = "Pergunta sintética";
    const prompt = document.createElement("p");
    prompt.textContent = item.syntheticPrompt;
    const answerLabel = document.createElement("small");
    answerLabel.textContent = "Resposta do provedor";
    const answer = document.createElement("pre");
    answer.textContent = item.providerResponse;
    const checks = document.createElement("p");
    checks.className = "provider-eval-checks";
    checks.textContent = [
      ["segurança", item.automaticChecks?.safe],
      ["reversão", item.automaticChecks?.rollback],
      ["honestidade", item.automaticChecks?.noEvidenceHonesty],
      ["clareza", item.automaticChecks?.clear]
    ].map(([label, passed]) => `${passed ? "✓" : "×"} ${label}`).join(" · ");
    const choices = document.createElement("div");
    choices.className = "provider-eval-decisions";
    for (const [label, value] of [["Aprovar resposta", "approve"], ["Reprovar resposta", "reject"]]) {
      const choice = document.createElement("button");
      choice.type = "button";
      choice.textContent = label;
      choice.dataset.caseId = item.caseId;
      choice.dataset.providerDecision = value;
      choices.append(choice);
    }
    card.append(head, promptLabel, prompt, answerLabel, answer, checks, choices);
    container.append(card);
  }
  $("provider-eval-review").disabled = true;
}

function setProviderEvalDecision(caseId, approved) {
  if (!state.providerEval || !caseId) return;
  state.providerEvalDecisions[caseId] = approved;
  const card = $(`provider-case-${caseId}`);
  if (card) {
    card.querySelectorAll("[data-provider-decision]").forEach(button => {
      const selected = (button.dataset.providerDecision === "approve") === approved;
      button.classList.toggle("selected", selected);
    });
  }
  $("provider-eval-review").disabled = Object.keys(state.providerEvalDecisions).length !== state.providerEval.caseCount;
}

async function submitProviderEvalReview() {
  if (!state.providerEval) return;
  const button = $("provider-eval-review");
  button.disabled = true;
  button.textContent = "Registrando revisão...";
  const decisions = Object.entries(state.providerEvalDecisions).map(([caseId, approved]) => ({
    caseId,
    decision: approved ? "approved" : "rejected"
  }));
  try {
    const result = await api("/api/evals/provider/review", {
      method: "POST",
      body: JSON.stringify({ runId: state.providerEval.runId, decisions })
    });
    const approved = result.status === "approved";
    $("provider-eval-review-status").textContent = approved
      ? `Revisão concluída: ${result.approved} respostas aprovadas.`
      : `Revisão concluída com reprovação: ${result.rejected} resposta(s) precisam de correção.`;
    $("provider-eval-status").textContent = approved ? "Aprovado por revisão humana" : "Reprovado por revisão humana";
    document.querySelectorAll("[data-provider-decision]").forEach(choice => { choice.disabled = true; });
    button.textContent = "Revisão concluída";
  } catch (error) {
    $("provider-eval-review-status").textContent = error.message;
    button.disabled = false;
    button.textContent = "Concluir revisão humana";
  }
}

async function refreshSetupState() {
  try {
    const data = await api("/api/setup-state");
    state.setupState = data;
    applyReleaseMetadata(data);
  } catch (error) {
    setCatalogSyncStatus(true, error.message);
  }
}

function applyReleaseMetadata(data) {
  if (data.setupVersion) {
    state.setupVersion = data.setupVersion;
    $("setup-version").textContent = data.setupVersion === "indisponível" ? "indisponível" : `v${data.setupVersion}`;
  }
  if (data.controlVersion) {
    state.controlVersion = data.controlVersion;
    $("control-version").textContent = `v${data.controlVersion}`;
  }
  if (data.installationType) {
    $("installation-type").textContent = data.installationType === "CLOUDFLARE_TUNNEL"
      ? "Cloudflare Tunnel"
      : "Tradicional (Traefik)";
  }
  applyTerminalAccessState();
  if (data.plan) {
    state.setupPlan = data.plan;
    state.llmAllowed = data.llmAllowed === true;
    state.maintainerAccess = data.plan === "pro-master" && data.capabilities?.maintainer === true;
    $("setup-plan").textContent = data.plan === "pro-master" ? "PRO MASTER" : data.plan;
    if (!state.llmAllowed) {
      state.assistantMode = "basic";
      state.assistantModel = "";
      renderAssistantMode();
    }
  }
  applyMaintainerAccessState();
  if (Object.prototype.hasOwnProperty.call(data, "homologationRunnerAvailable")) {
    renderHomologationRunner(data);
  }
  if (Object.prototype.hasOwnProperty.call(data, "supplyChainAvailable")) {
    renderSupplyChainStatus(data);
  }
  setCatalogSyncStatus(Boolean(data.stale), data.warning, data);
}

function renderSupplyChainStatus(data) {
  const target = $("supply-chain-status");
  if (!target) return;
  const available = data.supplyChainAvailable === true;
  target.className = `sync-status ${available ? "current" : "stale"}`;
  if (!available) {
    target.textContent = "SBOM e evidências de supply chain ainda não estão disponíveis nesta instalação.";
    return;
  }
  const references = Number(data.supplyChainImageReferences || 0);
  const digestPinned = Number(data.supplyChainDigestPinnedImages || 0);
  const unresolved = Number(data.supplyChainUnresolvedReferences || 0);
  target.textContent = `Supply chain validada · CycloneDX 1.6 · ${references} referências de imagem (${digestPinned} por digest) · ${unresolved} expressões não resolvidas · atestação vinculada por SHA-256, ainda sem assinatura independente`;
}

function renderHomologationRunner(data) {
  const card = $("homologation-runner-card");
  const status = $("homologation-runner-status");
  if (!card || !status) return;
  const available = data.homologationRunnerAvailable === true;
  state.homologationRunnerAvailable = available;
  card.className = `homologation-runner-card ${available ? "available" : "pending"}`;
  status.textContent = available
    ? `Runner v${data.homologationRunnerVersion} disponível · homologação essencial automática por arquitetura`
    : "Runner ainda não foi confirmado no runtime desta instalação";
  applyTerminalAccessState();
}

function terminalAccessAllowed() {
  return state.setupState?.installationType === "CLOUDFLARE_TUNNEL" && state.setupState?.capabilities?.remoteTerminal === true;
}

function applyMaintainerAccessState() {
  document.querySelectorAll("[data-maintainer-only]").forEach(element => {
    element.hidden = !state.maintainerAccess;
  });
  if (!state.maintainerAccess) {
    state.homologation = null;
    state.homologationItems = [];
    if (state.view === "homologation") navigate("dashboard");
  }
  applyTerminalAccessState();
}

function applyTerminalAccessState() {
  const allowed = terminalAccessAllowed();
  const note = "Recurso disponível apenas quando é usado Cloudflare Tunnel.";
  document.querySelectorAll('[data-action="terminal"], [data-action="settings"], [data-action="homologation"], [data-action="sre"], [data-action="gateway"]').forEach(button => {
    const runnerUnavailable = button.dataset.action === "homologation" && !state.homologationRunnerAvailable;
    const maintainerRequired = button.dataset.action === "homologation" && !state.maintainerAccess;
    button.disabled = !allowed || runnerUnavailable || maintainerRequired;
    button.classList.toggle("terminal-locked", !allowed || runnerUnavailable || maintainerRequired);
    button.title = !allowed ? note : maintainerRequired ? "Recurso exclusivo do plano PRO MASTER." : runnerUnavailable ? "Homologation Runner indisponível nesta release." : "";
  });
  $("terminal-access-notice").hidden = allowed;
}

function setCatalogSyncStatus(stale, warning = "", data = {}) {
  const target = $("catalog-sync-status");
  target.className = `sync-status ${stale ? "stale" : "current"}`;
  if (stale) {
    target.textContent = warning || "Não foi possível confirmar o catálogo instalado.";
    return;
  }
  const architecture = data.architecture ? ` · ${data.architecture}` : "";
  target.textContent = `Sincronizado com o Setup MNO ${data.setupVersion ? `v${data.setupVersion}` : ""}${architecture}`;
}

function renderOverview() {
  const o = state.overview;
  if (!o) return;
  const m = o.metrics;
  setMetric("cpu", m.cpuPercent, `${fmt.format(m.cpuPercent)}%`, `Carga ${fmt.format(m.load1)} · ${fmt.format(m.load5)} · ${fmt.format(m.load15)}`);
  setMetric("ram", m.memoryPercent, `${fmt.format(m.memoryPercent)}%`, `${bytes(m.memoryUsed)} de ${bytes(m.memoryTotal)}`);
  setMetric("disk", m.diskPercent, `${fmt.format(m.diskPercent)}%`, `${bytes(m.diskUsed)} de ${bytes(m.diskTotal)}`);
  $("apps-value").textContent = o.apps;
  $("services-detail").textContent = `${o.services} serviços no Swarm`;
  $("nav-app-count").textContent = o.apps;
  $("mini-host").textContent = o.hostname || "Servidor";
  $("mini-engine").textContent = `Docker ${o.engineVersion || "—"} · ${o.architecture || "—"}`;
  $("last-update").textContent = `Atualizado ${new Date(o.generatedAt).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })}`;
  $("hero-status").textContent = o.degradedServices
    ? `${o.degradedServices} serviço(s) exigem atenção antes do próximo deploy.`
    : `${o.healthyServices} serviços estão operando dentro do esperado.`;
  $("services-state").className = `trend ${o.degradedServices ? "bad" : "good"}`;
  $("services-state").textContent = o.degradedServices ? `${o.degradedServices} alertas` : "Saudável";

  const dots = $("stack-dots");
  dots.innerHTML = "";
  const total = Math.min(22, Math.max(1, o.services));
  const degraded = Math.min(total, o.degradedServices);
  for (let i = 0; i < total; i++) {
    const dot = document.createElement("i");
    if (i < degraded) dot.className = "off";
    dots.append(dot);
  }

  $("health-summary").classList.remove("skeleton-block");
  $("health-summary").innerHTML = `
    <div class="health-item"><span>Serviços saudáveis</span><strong class="good">${o.healthyServices}</strong></div>
    <div class="health-item"><span>Precisam de atenção</span><strong class="${o.degradedServices ? "bad" : "good"}">${o.degradedServices}</strong></div>
    <div class="health-item"><span>Nós no Swarm</span><strong>${o.swarmNodes || 1}</strong></div>`;
}

function setMetric(id, value, display, detail) {
  $(id + "-value").textContent = display;
  $(id + "-detail").textContent = detail;
  $(id + "-meter").style.width = `${Math.max(0, Math.min(100, value || 0))}%`;
  const stateEl = $(id + "-state");
  const level = value >= 85 ? "bad" : value >= 70 ? "warn" : "good";
  stateEl.className = `trend ${level}`;
  stateEl.textContent = value >= 85 ? "Crítico" : value >= 70 ? "Atenção" : "Saudável";
}

function renderRecent() {
  const target = $("recent-apps");
  const apps = state.apps.slice(0, 5);
  target.innerHTML = apps.length ? apps.map(app => `
    <div class="recent-row">
      <strong class="recent-name">${escapeHTML(app.name)}</strong>
      <span class="status-dot ${app.status}">${app.status === "online" ? "Online" : "Atenção"}</span>
      <span>${app.running}/${app.desired} réplicas</span>
    </div>`).join("") : `<div class="empty-state">Nenhuma stack encontrada no Swarm.</div>`;
}

function renderInstalled() {
  const query = ($("installed-search")?.value || "").trim().toLowerCase();
  const status = $("installed-filter")?.value || "";
  const apps = state.apps.filter(app => {
    const searchable = `${app.name} ${app.services.map(s => s.name).join(" ")}`.toLowerCase();
    return (!query || searchable.includes(query)) && (!status || app.status === status);
  });
  $("installed-summary").textContent = `${apps.length} de ${state.apps.length} aplicações encontradas`;
  $("installed-grid").innerHTML = apps.length ? apps.map(app => {
    const ratio = app.desired ? Math.min(100, app.running / app.desired * 100) : 0;
    return `<article class="installed-card">
      <div class="installed-card-head">
        <span class="app-avatar">${escapeHTML(app.name.slice(0,1).toUpperCase())}</span>
        <span class="trend ${app.status === "online" ? "good" : "bad"}">${app.status === "online" ? "Online" : "Atenção"}</span>
      </div>
      <h3 title="${escapeHTML(app.name)}">${escapeHTML(app.name)}</h3>
      <p>${app.services.length} serviço(s) · ${app.running}/${app.desired} réplicas</p>
      <div class="replica-bar"><i style="width:${ratio}%"></i></div>
      <div class="service-list">${app.services.map(service => `
        <div class="service-line"><span title="${escapeHTML(service.name)}">${escapeHTML(service.name)}</span><span>${service.replicas}</span></div>`).join("")}
      </div>
    </article>`;
  }).join("") : `<div class="empty-state">Nenhuma aplicação corresponde aos filtros.</div>`;
}

function populateCategories() {
  const select = $("catalog-category");
  const selected = select.value;
  const categories = [...new Set(state.catalog.flatMap(item => String(item.cats || "").split(",").map(v => v.trim()).filter(Boolean)))].sort((a,b) => a.localeCompare(b, "pt-BR"));
  select.innerHTML = `<option value="">Todas as categorias</option>` + categories.map(category => `<option>${escapeHTML(category)}</option>`).join("");
  if (categories.includes(selected)) select.value = selected;
}

function renderCatalog() {
  const query = ($("catalog-search")?.value || "").trim().toLowerCase();
  const category = $("catalog-category")?.value || "";
  const arch = $("catalog-arch")?.value || "";
  const items = state.catalog.filter(item => {
    const searchable = `${item.name} ${item.cats} ${item.desc} ${item.search || ""}`.toLowerCase();
    return (!query || searchable.includes(query))
      && (!category || String(item.cats).split(",").map(v => v.trim()).includes(category))
      && (!arch || item.arch === arch);
  });
  $("catalog-total").textContent = state.catalog.length;
  $("catalog-result").textContent = `${items.length} de ${state.catalog.length} setups encontrados`;
  $("catalog-grid").innerHTML = items.length ? items.map(item => {
    const quality = state.qualityByCatalog[item.name] || {};
    const maturity = [
      "structural", "source-reviewed", "script-reviewed",
      "operational-reviewed", "homologated"
    ].includes(quality.maturity) ? quality.maturity : "structural";
    const architectureLabels = (quality.operationalArchitectures || []).map(value =>
      value === "amd64" ? "X86" : value === "arm64" ? "ARM" : value
    );
    const maturityLabel = ({
      structural: "Catalogado",
      "source-reviewed": "Fontes revisadas",
      "script-reviewed": "Instalador revisado",
      "operational-reviewed": quality.operationalCoverage === "partial"
        ? `Validado em ${architectureLabels.join(" + ") || "arquitetura registrada"}`
        : "Validado operacionalmente",
      homologated: "Selo oficial homologado"
    })[maturity];
    const evidenceTitle = maturity === "homologated"
      ? `Selo oficial validado pela governança canônica · ${quality.operationalEvidenceIds?.length || 0} evidência(s) · cobertura ${architectureLabels.join(" + ") || "completa"}`
      : quality.operationalEvidence
      ? `${quality.operationalEvidenceIds?.length || 0} evidência(s) validada(s) · última verificação ${quality.lastOperationalVerification?.slice(0, 10) || "N/I"}`
      : "Ainda sem evidência operacional anexada.";
    return `
    <article class="catalog-card">
      <div class="catalog-card-top"><h3>${escapeHTML(item.name)}</h3><span class="type-label">${escapeHTML(item.type || "Setup")}</span></div>
      <span class="homologation-badge maturity-${maturity}" title="${escapeHTML(evidenceTitle)}">${escapeHTML(maturityLabel)}</span>
      <div class="catalog-tags">${String(item.cats || "").split(",").slice(0,4).map(tag => `<span>${escapeHTML(tag.trim())}</span>`).join("")}</div>
      <p class="catalog-description">${escapeHTML(item.desc || "Setup disponível no catálogo MNO.")}</p>
      <div class="catalog-facts"><span><b>RAM</b> ${escapeHTML(item.ramLabel || "N/I")}</span><span><b>Arquitetura</b> ${item.arch === "x86-arm" ? "X86 + ARM" : "X86"}</span></div>
      <button class="light-button" data-action="terminal">Abrir no instalador <b>→</b></button>
    </article>`;
  }).join("") : `<div class="empty-state">Nenhum setup corresponde aos filtros selecionados.</div>`;
  applyTerminalAccessState();
}

function renderBlueprintSyncStatus() {
  const data = state.blueprintCatalog;
  const target = $("blueprint-sync-status");
  if (!data) return;
  const versionMismatch = state.setupVersion && state.setupVersion !== "indisponível"
    && data.setupVersion !== state.setupVersion;
  target.className = `sync-status ${versionMismatch ? "stale" : "current"}`;
  target.textContent = versionMismatch
    ? `O índice pertence ao Setup MNO v${data.setupVersion}, mas o runtime confirmou v${state.setupVersion}. Atualize o Control Center antes de usar o catálogo.`
    : `Índice canônico validado · fábrica v${data.factoryVersion} · conhecimento v${data.knowledgeVersion} · somente leitura`;
}

function blueprintGroup(status) {
  if (status === "homologated") return "homologated";
  if (status === "reviewed") return "beta";
  return "review";
}

function blueprintStatusLabel(item) {
  return ({
    homologated: "Homologado",
    example: "Legado editorial",
    draft: "Rascunho",
    reviewed: "Blueprint Beta",
    deprecated: "Descontinuado"
  })[item.status] || "Não homologado";
}

function blueprintRiskLabel(risk) {
  return ({ low: "Baixo", medium: "Médio", high: "Alto" })[risk] || "Não informado";
}

function blueprintEditorialStageLabel(stage) {
  return ({
    example: "Exemplo editorial",
    draft: "Rascunho",
    reviewed: "Revisado",
    homologated: "Homologado",
    deprecated: "Descontinuado"
  })[stage] || "Estado desconhecido";
}

function renderBlueprints() {
  const query = ($("blueprint-search")?.value || "").trim().toLowerCase();
  const status = $("blueprint-status")?.value || "";
  const architecture = $("blueprint-arch")?.value || "";
  const risk = $("blueprint-risk")?.value || "";
  const items = state.blueprints.filter(item => {
    const searchable = [
      item.blueprintId, item.title, item.summary, item.objective,
      ...(Array.isArray(item.aliases) ? item.aliases : []),
      ...(Array.isArray(item.components) ? item.components : []),
      ...(Array.isArray(item.tags) ? item.tags : [])
    ].join(" ").toLowerCase();
    return (!query || searchable.includes(query))
      && (!status || blueprintGroup(item.status) === status)
      && (!architecture || (Array.isArray(item.architectures) && item.architectures.includes(architecture)))
      && (!risk || item.risk === risk);
  });

  const catalog = state.blueprintCatalog || {};
  $("blueprint-total").textContent = catalog.blueprintCount ?? state.blueprints.length;
  $("blueprint-homologated-total").textContent = catalog.homologatedCount ?? 0;
  $("blueprint-example-total").textContent = catalog.betaCount ?? 0;
  $("nav-blueprint-count").textContent = catalog.blueprintCount ?? state.blueprints.length;
  $("blueprint-result").textContent = `${items.length} de ${state.blueprints.length} Blueprints encontrados`;

  const groups = {
    homologated: items.filter(item => blueprintGroup(item.status) === "homologated"),
    beta: items.filter(item => blueprintGroup(item.status) === "beta"),
    review: items.filter(item => blueprintGroup(item.status) === "review")
  };
  renderBlueprintGroup("blueprint-homologated-grid", groups.homologated, "Nenhum Blueprint homologado disponível nesta versão.");
  renderBlueprintGroup("blueprint-example-grid", groups.beta, "Nenhum guia Beta corresponde aos filtros.");
  renderBlueprintGroup("blueprint-review-grid", groups.review, "Nenhum Blueprint em revisão ou descontinuado corresponde aos filtros.");
}

function renderBlueprintGroup(targetId, items, emptyMessage) {
  $(targetId).innerHTML = items.length ? items.map(item => {
    const group = blueprintGroup(item.status);
    const architectures = (Array.isArray(item.architectures) ? item.architectures : [])
      .map(value => value === "amd64" ? "X86" : value === "arm64" ? "ARM" : value)
      .join(" + ");
    const tags = (Array.isArray(item.tags) ? item.tags : []).slice(0, 4);
    const editorial = item.editorial || {};
    return `<article class="blueprint-card ${group}">
      <div class="blueprint-card-top"><span class="blueprint-status-badge ${group}">${escapeHTML(blueprintStatusLabel(item))}</span><span class="blueprint-risk risk-${escapeHTML(item.risk)}">Risco ${escapeHTML(blueprintRiskLabel(item.risk))}</span></div>
      <p class="blueprint-id">${escapeHTML(item.blueprintId)}</p>
      <h3>${escapeHTML(item.title)}</h3>
      <p class="blueprint-summary">${escapeHTML(item.summary)}</p>
      <div class="catalog-tags">${tags.map(tag => `<span>${escapeHTML(tag)}</span>`).join("")}</div>
      <div class="blueprint-card-facts"><span><b>${Array.isArray(item.components) ? item.components.length : 0}</b> componentes</span><span><b>${escapeHTML(architectures || "N/I")}</b> arquitetura</span><span><b>${escapeHTML(editorial.passedGates ?? 0)}/${escapeHTML(editorial.totalGates ?? 0)}</b> gates</span></div>
      <button class="light-button" data-action="blueprint" data-blueprint-id="${escapeHTML(item.blueprintId)}">Visualizar Blueprint <b>→</b></button>
    </article>`;
  }).join("") : `<div class="empty-state compact">${escapeHTML(emptyMessage)}</div>`;
}

// Mantido somente para compatibilidade estrutural com registros editoriais antigos.
// A interface atual usa openBlueprint() abaixo, com o guia operacional Beta.
function openBlueprintLegacyEditorial(blueprintId) {
  const item = state.blueprints.find(candidate => candidate.blueprintId === blueprintId);
  if (!item) return;
  const group = blueprintGroup(item.status);
  const dialog = $("blueprint-dialog");
  $("blueprint-detail-title").textContent = item.title || "Blueprint";
  const alert = $("blueprint-detail-alert");
  alert.className = `blueprint-detail-alert ${group}`;
  alert.innerHTML = group === "homologated"
    ? `<strong>Conteúdo homologado</strong><span>O registro concluiu o fluxo editorial. Esta tela permanece consultiva e não executa deploy.</span>`
    : group === "example"
      ? `<strong>Blueprint Beta</strong><span>Guia manual em evolução; valide cada etapa e não o trate como conteúdo homologado.</span>`
      : `<strong>Conteúdo não homologado</strong><span>Este registro permanece separado do catálogo homologado e não deve orientar uma implantação.</span>`;

  const architectures = (Array.isArray(item.architectures) ? item.architectures : [])
    .map(value => value === "amd64" ? "X86 / amd64" : value === "arm64" ? "ARM / arm64" : value);
  const components = Array.isArray(item.components) ? item.components : [];
  const aliases = Array.isArray(item.aliases) ? item.aliases : [];
  const tags = Array.isArray(item.tags) ? item.tags : [];
  const media = Array.isArray(item.media) ? item.media : [];
  const editorial = item.editorial || {};
  const history = Array.isArray(editorial.history) ? editorial.history : [];
  const gates = Array.isArray(editorial.gates) ? editorial.gates : [];
  const homologation = editorial.homologation || {};
  const evidence = Array.isArray(homologation.evidence) ? homologation.evidence : [];
  const review = editorial.review || {};
  const versionSeal = editorial.versionSeal || {};
  $("blueprint-detail-content").innerHTML = `
    <section class="blueprint-detail-lead"><p>${escapeHTML(item.summary)}</p><div class="catalog-tags">${tags.map(tag => `<span>${escapeHTML(tag)}</span>`).join("")}</div></section>
    <div class="blueprint-detail-facts">
      <span><small>Status</small><strong>${escapeHTML(blueprintStatusLabel(item))}</strong></span>
      <span><small>Versão</small><strong>v${escapeHTML(item.blueprintVersion)}</strong></span>
      <span><small>Risco</small><strong>${escapeHTML(blueprintRiskLabel(item.risk))}</strong></span>
      <span><small>Atualizado</small><strong>${escapeHTML(item.updatedAt || "N/I")}</strong></span>
    </div>
    <section class="blueprint-editorial-panel">
      <div class="blueprint-editorial-head"><div><p class="eyebrow">Fluxo editorial verificável</p><h3>${escapeHTML(blueprintEditorialStageLabel(editorial.currentStage))}</h3></div><span class="${editorial.promotionReady ? "ready" : "blocked"}">${editorial.promotionReady ? "Promoção liberada" : "Promoção bloqueada"}</span></div>
      <div class="blueprint-editorial-progress"><span class="${editorial.currentStage === "draft" || ["reviewed", "homologated", "deprecated"].includes(editorial.currentStage) ? "complete" : ""}"><b>1</b>Rascunho</span><i></i><span class="${["reviewed", "homologated", "deprecated"].includes(editorial.currentStage) ? "complete" : ""}"><b>2</b>Revisão</span><i></i><span class="${editorial.currentStage === "homologated" ? "complete" : ""}"><b>3</b>Homologação</span></div>
      ${editorial.currentStage === "example" ? `<p class="blueprint-example-flow">Exemplos ficam fora da trilha de promoção até serem convertidos em rascunhos reais.</p>` : ""}
      <div class="blueprint-editorial-gates">${gates.map(gate => `<span class="${gate.passed ? "passed" : "pending"}"><b>${gate.passed ? "✓" : "○"}</b>${escapeHTML(gate.title)}</span>`).join("")}</div>
      <div class="blueprint-editorial-summary"><span><small>Gates concluídos</small><strong>${escapeHTML(editorial.passedGates ?? 0)} de ${escapeHTML(editorial.totalGates ?? 0)}</strong></span><span><small>Revisão</small><strong>${escapeHTML(review.decision === "approved" ? "Aprovada" : review.decision === "rejected" ? "Rejeitada" : "Pendente")}</strong></span><span><small>Ambiente</small><strong>${escapeHTML(homologation.environment === "isolated-temporary" ? "Isolado temporário" : "Não iniciado")}</strong></span></div>
    </section>
    <section><p class="eyebrow">Histórico editorial</p><ol class="blueprint-editorial-history">${history.map(entry => `<li><span>${escapeHTML(entry.changedAt)}</span><div><strong>${escapeHTML(blueprintEditorialStageLabel(entry.stage))}</strong><p>${escapeHTML(entry.note)}</p><small>${escapeHTML(entry.actor)}</small></div></li>`).join("")}</ol></section>
    <section><p class="eyebrow">Evidências de homologação</p>${evidence.length ? `<ul class="blueprint-evidence-list">${evidence.map(entry => `<li><div><strong>${escapeHTML(entry.title)}</strong><span>${escapeHTML(entry.type)} · ${escapeHTML(entry.architecture)} · ${escapeHTML(entry.verifiedAt)}</span></div><code>${escapeHTML(entry.sha256)}</code></li>`).join("")}</ul>` : `<p class="muted">Nenhuma evidência de homologação declarada. A promoção permanece bloqueada.</p>`}</section>
    <section class="blueprint-version-seal"><p class="eyebrow">Selo determinístico da versão</p><dl><div><dt>Algoritmo</dt><dd>${escapeHTML(versionSeal.algorithm || "N/I")}</dd></div><div><dt>Manifesto</dt><dd>${escapeHTML(versionSeal.manifestSHA256 || "N/I")}</dd></div><div><dt>Payload editorial</dt><dd>${escapeHTML(versionSeal.payloadSHA256 || "N/I")}</dd></div></dl><p>O selo vincula versão, manifesto, bundle e hashes das evidências. Caminhos internos não são expostos.</p></section>
    <section><p class="eyebrow">Objetivo</p><p>${escapeHTML(item.objective)}</p></section>
    <section><p class="eyebrow">Componentes canônicos</p><ol class="blueprint-component-list">${components.map(component => `<li>${escapeHTML(component)}</li>`).join("")}</ol></section>
    <div class="blueprint-detail-columns">
      <section><p class="eyebrow">Compatibilidade</p><ul>${architectures.map(value => `<li>${escapeHTML(value)}</li>`).join("")}</ul></section>
      <section><p class="eyebrow">Aliases editoriais</p><ul>${aliases.map(value => `<li>${escapeHTML(value)}</li>`).join("")}</ul></section>
    </div>
    <section><p class="eyebrow">Mídia declarada</p>${media.length ? `<ul class="blueprint-media-list">${media.map(entry => `<li><strong>${escapeHTML(entry.title)}</strong><span>${escapeHTML(entry.type)} · ${escapeHTML(entry.status)}${entry.hasTranscript ? " · transcrição disponível" : ""}</span></li>`).join("")}</ul>` : `<p class="muted">Nenhuma mídia declarada.</p>`}</section>
    <section class="blueprint-provenance"><p class="eyebrow">Procedência verificável</p><dl><div><dt>Blueprint ID</dt><dd>${escapeHTML(item.blueprintId)}</dd></div><div><dt>Autor</dt><dd>${escapeHTML(item.author)}</dd></div><div><dt>Bundle</dt><dd>${escapeHTML(bytes(item.bundleBytes))}</dd></div><div><dt>SHA-256</dt><dd>${escapeHTML(item.bundleSHA256)}</dd></div></dl><p>O bundle foi validado durante a geração do pacote. Downloads e caminhos internos não são expostos pelo painel.</p></section>`;
  dialog.showModal();
}

function openBlueprint(blueprintId) {
  const item = state.blueprints.find(candidate => candidate.blueprintId === blueprintId);
  if (!item) return;
  const dialog = $("blueprint-dialog");
  $("blueprint-detail-title").textContent = item.title || "Blueprint";
  const alert = $("blueprint-detail-alert");
  const isHomologated = item.status === "homologated";
  alert.className = `blueprint-detail-alert ${isHomologated ? "homologated" : "review"}`;
  alert.innerHTML = isHomologated
    ? `<strong>Blueprint homologado</strong><span>Guia consultivo validado. A instalação continua exigindo confirmação humana no Instalador Seguro.</span>`
    : `<strong>Blueprint Beta</strong><span>Este guia pode ser seguido manualmente, mas ainda não concluiu a homologação técnica de ponta a ponta. Valide cada etapa antes de avançar.</span>`;

  const tags = Array.isArray(item.tags) ? item.tags : [];
  const components = Array.isArray(item.componentDetails) ? item.componentDetails : [];
  const installation = item.installation || {};
  const steps = Array.isArray(installation.steps) ? installation.steps : [];
  const validation = item.validation || {};
  const checks = Array.isArray(validation.checks) ? validation.checks : [];
  const rollback = item.rollback || {};
  const rollbackSteps = Array.isArray(rollback.steps) ? rollback.steps : [];
  const media = Array.isArray(item.media) ? item.media : [];
  const editorial = item.editorial || {};
  const gates = Array.isArray(editorial.gates) ? editorial.gates : [];
  const architectures = (Array.isArray(item.architectures) ? item.architectures : [])
    .map(value => value === "amd64" ? "X86 / amd64" : value === "arm64" ? "ARM / arm64" : value)
    .join(" + ");
  const downloadURL = `/api/blueprints/${encodeURIComponent(item.blueprintId)}/download`;

  $("blueprint-detail-content").innerHTML = `
    <section class="blueprint-guide-intro">
      <div><p class="eyebrow">Resultado esperado</p><p>${escapeHTML(item.objective)}</p></div>
      ${item.downloadAvailable ? `<a class="primary-button blueprint-download" href="${downloadURL}" download>Baixar Blueprint em ZIP <b>↓</b></a>` : ""}
      <div class="catalog-tags">${tags.map(tag => `<span>${escapeHTML(tag)}</span>`).join("")}</div>
    </section>
    <div class="blueprint-detail-facts">
      <span><small>Status</small><strong>${escapeHTML(blueprintStatusLabel(item))}</strong></span>
      <span><small>Versão</small><strong>v${escapeHTML(item.blueprintVersion)}</strong></span>
      <span><small>RAM mínima</small><strong>${escapeHTML(item.resourceProfile?.minimumRamGB ?? "N/I")} GB</strong></span>
      <span><small>Arquitetura</small><strong>${escapeHTML(architectures || "N/I")}</strong></span>
    </div>
    <section>
      <p class="eyebrow">Antes de começar</p>
      <p>${escapeHTML(item.summary)}</p>
      <div class="blueprint-component-roles">${components.map(component => `<article><span>${escapeHTML(component.installOrder)}</span><div><strong>${escapeHTML(component.catalogName)}</strong><p>${escapeHTML(component.role)}</p></div></article>`).join("")}</div>
      <p class="blueprint-resource-note"><strong>Dimensionamento:</strong> ${escapeHTML(item.resourceProfile?.basis || "Valide a capacidade antes da instalação.")}</p>
    </section>
    <section>
      <div class="blueprint-section-heading"><div><p class="eyebrow">Checklist orientado</p><h3>Passo a passo de instalação e integração</h3></div><button class="light-button" data-action="terminal">Abrir Instalador Seguro <b>→</b></button></div>
      <ol class="blueprint-guide-steps">${steps.map(step => `<li><span>${escapeHTML(step.step)}</span><div><small>${escapeHTML(step.component)}</small><strong>${escapeHTML(step.title)}</strong><p>${escapeHTML(step.description)}</p><em>Confirme esta etapa antes de continuar</em></div></li>`).join("")}</ol>
    </section>
    <section>
      <p class="eyebrow">Validação final</p>
      <h3>Confirme que o ecossistema funciona</h3>
      <div class="blueprint-checklist">${checks.map(check => `<label><input type="checkbox"><span><strong>${escapeHTML(check.description)}</strong><small>Resultado esperado: ${escapeHTML(check.expected)}</small></span></label>`).join("")}</div>
    </section>
    <section>
      <p class="eyebrow">Downloads, vídeos e PDFs</p>
      <div class="blueprint-materials">
        ${item.downloadAvailable ? `<a href="${downloadURL}" download><span>ZIP</span><div><strong>Pacote deste Blueprint</strong><small>Checklist e manifesto da versão v${escapeHTML(item.blueprintVersion)}</small></div><b>Baixar ↓</b></a>` : ""}
        ${media.map(entry => entry.url
          ? `<a href="${escapeHTML(entry.url)}" target="_blank" rel="noopener noreferrer"><span>${escapeHTML(entry.type)}</span><div><strong>${escapeHTML(entry.title)}</strong><small>Material revisado</small></div><b>Abrir ↗</b></a>`
          : `<div class="pending"><span>${escapeHTML(entry.type)}</span><div><strong>${escapeHTML(entry.title)}</strong><small>Link em preparação</small></div><b>Em breve</b></div>`).join("")}
      </div>
    </section>
    <section class="blueprint-rollback-guide">
      <p class="eyebrow">Se algo der errado</p><h3>Plano de rollback</h3><p>${escapeHTML(rollback.strategy || "Interrompa o fluxo e retorne à configuração anterior.")}</p>
      <ol>${rollbackSteps.map(step => `<li>${escapeHTML(step)}</li>`).join("")}</ol>
    </section>
    <details class="blueprint-technical-details">
      <summary>Informações técnicas e procedência</summary>
      <div><span><small>Autor</small><strong>${escapeHTML(item.author)}</strong></span><span><small>Risco</small><strong>${escapeHTML(blueprintRiskLabel(item.risk))}</strong></span><span><small>Gates editoriais</small><strong>${escapeHTML(editorial.passedGates ?? 0)} de ${escapeHTML(editorial.totalGates ?? 0)}</strong></span><span><small>SHA-256 do ZIP</small><code>${escapeHTML(item.bundleSHA256)}</code></span></div>
      <ul>${gates.map(gate => `<li>${gate.passed ? "✓" : "○"} ${escapeHTML(gate.title)}</li>`).join("")}</ul>
    </details>`;
  applyTerminalAccessState();
  dialog.showModal();
}

function closeBlueprint() {
  const dialog = $("blueprint-dialog");
  if (dialog.open) dialog.close();
  $("blueprint-detail-content").replaceChildren();
}

async function requestBlueprintRecommendation(event) {
  event.preventDefault();
  const objective = $("blueprint-objective").value.trim();
  if (!objective) return;
  const button = event.currentTarget.querySelector("button[type=submit]");
  const result = $("blueprint-recommendation-result");
  button.disabled = true;
  button.querySelector("span").textContent = "Analisando...";
  result.hidden = false;
  result.className = "blueprint-recommendation-result loading";
  result.textContent = "Validando arquitetura, capacidade e evidências canônicas...";
  try {
    const data = await api("/api/blueprints/recommend", {
      method: "POST",
      body: JSON.stringify({ objective })
    });
    state.blueprintRecommendation = data;
    renderBlueprintRecommendation(data);
  } catch (error) {
    result.className = "blueprint-recommendation-result error";
    result.textContent = error.message;
  } finally {
    button.disabled = false;
    button.querySelector("span").textContent = "Recomendar";
  }
}

function renderBlueprintRecommendation(data) {
  const target = $("blueprint-recommendation-result");
  const context = data.context || {};
  const recommendations = Array.isArray(data.recommendations) ? data.recommendations : [];
  const rejected = Array.isArray(data.rejected) ? data.rejected : [];
  target.className = "blueprint-recommendation-result";
  target.hidden = false;
  const architecture = context.architecture === "amd64" ? "X86 / amd64"
    : context.architecture === "arm64" ? "ARM / arm64" : context.architecture || "N/I";
  const recommendationCards = recommendations.length ? recommendations.map(item => `
    <article class="blueprint-match-card ${item.compatible ? (item.capacityFit === "minimum" ? "limited" : "ready") : "blocked"}">
      <div class="blueprint-match-rank"><span>#${escapeHTML(item.rank)}</span><div><small>${escapeHTML(item.confidence === "high" ? "Alta aderência" : item.confidence === "medium" ? "Aderência média" : "Aderência baixa")}</small><strong>${escapeHTML(item.title)}</strong></div></div>
      <div class="blueprint-match-badges"><span>${escapeHTML(item.status === "reviewed" ? "Blueprint Beta" : "Homologado")}</span><span>${escapeHTML(item.capacityFit === "recommended" ? "RAM recomendada atendida" : item.capacityFit === "minimum" ? "RAM mínima atendida" : "Capacidade insuficiente")}</span></div>
      <ul>${(Array.isArray(item.reasons) ? item.reasons : []).map(reason => `<li>${escapeHTML(reason)}</li>`).join("")}</ul>
      ${(Array.isArray(item.blockers) && item.blockers.length) ? `<div class="blueprint-match-blockers"><strong>Não instale neste servidor ainda</strong>${item.blockers.map(reason => `<span>${escapeHTML(reason)}</span>`).join("")}</div>` : ""}
      <div class="blueprint-match-resources"><span><small>Mínima</small><strong>${escapeHTML(item.minimumRamGB)} GB</strong></span><span><small>Recomendada</small><strong>${escapeHTML(item.recommendedRamGB)} GB</strong></span><span><small>Risco</small><strong>${escapeHTML(blueprintRiskLabel(item.risk))}</strong></span></div>
      <p>${escapeHTML(item.resourceBasis)}</p>
      <button class="light-button" data-action="blueprint" data-blueprint-id="${escapeHTML(item.blueprintId)}">Visualizar Blueprint <b>→</b></button>
    </article>`).join("") : `<div class="blueprint-no-match"><strong>Nenhum Blueprint compatível</strong><span>${escapeHTML(data.noMatchReason || "Não há evidência suficiente para recomendar com segurança.")}</span></div>`;
  const rejectedBlock = rejected.length ? `<details class="blueprint-rejected"><summary>${rejected.length} candidato(s) recusado(s) pelos gates</summary><ul>${rejected.map(item => `<li><strong>${escapeHTML(item.title)}</strong><span>${(Array.isArray(item.reasons) ? item.reasons : []).map(escapeHTML).join(" · ")}</span></li>`).join("")}</ul></details>` : "";
  target.innerHTML = `
    <div class="blueprint-recommendation-head"><div><p class="eyebrow">Resultado por objetivo</p><h3>${recommendations.length} Blueprint(s) relacionado(s)</h3></div><div class="blueprint-runtime-facts"><span>${escapeHTML(architecture)}</span><span>${escapeHTML(context.memoryAvailableGB ?? "N/I")} GB livres</span><span>Setup v${escapeHTML(context.setupVersion || "N/I")}</span></div></div>
    <div class="blueprint-match-grid">${recommendationCards}</div>
    ${rejectedBlock}
    <div class="blueprint-recommendation-guardrails">${(Array.isArray(data.guardrails) ? data.guardrails : []).map(value => `<span>◎ ${escapeHTML(value)}</span>`).join("")}</div>`;
}

async function askAssistant(event) {
  event.preventDefault();
  const input = $("assistant-input");
  const question = input.value.trim();
  if (!question) return;
  const button = event.currentTarget.querySelector("button[type=submit]");
  const history = state.assistantHistory.slice(-10);
  addMessage(question, "user");
  input.value = "";
  input.disabled = true;
  button.disabled = true;
  const pending = addMessage("Analisando o snapshot seguro atual...", "assistant", true);
  try {
    let answer;
    try {
      answer = await streamAssistant(question, history, pending, false);
    } catch {
      const fallbackReason = pending.dataset.fallbackReason || "connector";
      const fallbackMessage = fallbackReason === "provider"
        ? "O provedor de IA não concluiu a resposta. Ativando o diagnóstico básico..."
        : fallbackReason === "context"
          ? "O contexto operacional ficou indisponível. Ativando o diagnóstico básico..."
          : "O conector de IA ficou indisponível. Ativando o diagnóstico básico...";
      pending.querySelector(".message-content").textContent = fallbackMessage;
      answer = await streamAssistant(question, history, pending, true, fallbackReason);
    }
    const historyAnswer = pending.dataset.responseMode === "catalog"
      ? `O catálogo completo do Setup MNO v${pending.dataset.setupVersion || state.setupVersion || "atual"} foi listado localmente com ${pending.dataset.catalogEntries || state.catalog.length} setups.`
      : answer;
    state.assistantHistory.push(
      { role: "user", content: question },
      { role: "assistant", content: historyAnswer }
    );
    state.assistantHistory = state.assistantHistory.slice(-10);
  } catch (error) {
    setAssistantMessageRouteUnavailable(pending);
    pending.querySelector(".message-content").textContent = `Não consegui concluir a análise: ${error.message}`;
  } finally {
    renderMessageFeedback(pending);
    input.disabled = false;
    button.disabled = false;
    input.focus();
  }
}

async function runLocalDiagnostic() {
  const button = $("assistant-diagnostic-run");
  const target = $("assistant-diagnostic-result");
  const content = target.querySelector(".message-content");
  const originalLabel = button.innerHTML;
  target.hidden = false;
  target.dataset.feedbackToken = "";
  content.textContent = "Criando uma fotografia sanitizada e somente leitura...";
  button.disabled = true;
  button.textContent = "Coletando fatos sem alterar o servidor...";
  try {
    await streamAssistant(
      "Execute um diagnóstico geral do sistema, incluindo memória, disco, serviços e réplicas.",
      [],
      target,
      true
    );
  } catch (error) {
    setAssistantMessageRouteUnavailable(target);
    content.textContent = `Não foi possível concluir o diagnóstico local: ${error.message}`;
  } finally {
    button.disabled = false;
    button.innerHTML = originalLabel;
    renderAssistantMode();
  }
}

async function streamAssistant(question, history, target, basic, fallbackReason = "") {
  clearRetrievalInspection(target);
  clearBlueprintSimulation(target);
  clearConsultativePlan(target);
  setAssistantMessageRoutePending(target, basic ? "Classificando contingência local..." : "Classificando especialista...");
  updateAssistantRoute(null, "Classificando a intenção localmente...");
  updateRetrievalSummary(null, basic
    ? "Resposta local: o RAG não foi executado."
    : "Recuperando candidatos canônicos...");
  const response = await fetch("/api/assistant", {
    method: "POST",
    credentials: "same-origin",
    headers: {
      Accept: "text/event-stream",
      "Content-Type": "application/json",
      "X-CSRF-Token": state.csrf
    },
    body: JSON.stringify({ question, history, basic, fallbackReason })
  });
  if (response.status === 401) {
    state.csrf = "";
    showLogin();
  }
  if (!response.ok) {
    const contentType = response.headers.get("content-type") || "";
    const data = contentType.includes("application/json") ? await response.json() : {};
    throw new Error(data.error || `Falha HTTP ${response.status}`);
  }
  if (!response.body) throw new Error("streaming não suportado pelo navegador");

  const content = target.querySelector(".message-content");
  content.textContent = "";
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let answer = "";
  while (true) {
    const { value, done } = await reader.read();
    buffer += decoder.decode(value || new Uint8Array(), { stream: !done });
    let separator;
    while ((separator = buffer.indexOf("\n\n")) >= 0) {
      const block = buffer.slice(0, separator);
      buffer = buffer.slice(separator + 2);
      const event = parseSSEBlock(block);
      if (!event) continue;
      if (event.type === "meta") {
        target.dataset.responseMode = event.data.mode || "";
        target.dataset.setupVersion = event.data.setupVersion || "";
        target.dataset.catalogEntries = String(event.data.catalogEntries || "");
        target.dataset.fallbackReason = event.data.fallbackReason || "";
        updateAssistantRuntime(event.data);
      } else if (event.type === "feedback") {
        target.dataset.feedbackToken = event.data.token || "";
        target.dataset.feedbackPolicyVersion = event.data.policyVersion || "";
      } else if (event.type === "route") {
        updateAssistantRoute(event.data);
        attachAssistantMessageRoute(target, event.data);
      } else if (event.type === "retrieval") {
        renderRetrievalInspection(target, event.data);
      } else if (event.type === "quality") {
        renderAnswerQuality(target, event.data);
      } else if (event.type === "blueprint_simulation") {
        renderBlueprintSimulation(target, event.data);
      } else if (event.type === "grounding") {
        applyGroundingAudit(target, event.data);
      } else if (event.type === "plan") {
        renderConsultativePlan(target, event.data);
      } else if (event.type === "runbook") {
        renderRunbookRecommendation(target, event.data);
      } else if (event.type === "delta") {
        answer += event.data.delta || "";
        renderAssistantContent(content, answer);
        $("assistant-conversation").scrollTop = $("assistant-conversation").scrollHeight;
      } else if (event.type === "error") {
        target.dataset.fallbackReason = event.data.reason || "provider";
        throw new Error(event.data.error || "provedor de IA indisponível");
      }
    }
    if (done) break;
  }
  if (!answer.trim()) throw new Error("o assistente não retornou texto");
  return answer.trim();
}

function clearRetrievalInspection(target) {
  target.querySelector(".retrieval-inspection")?.remove();
}

function clearBlueprintSimulation(target) {
  target.querySelector(".blueprint-simulation-banner")?.remove();
}

function clearConsultativePlan(target) {
  target?.querySelector(".consultative-plan")?.remove();
  target?.querySelector(".runbook-recommendation")?.remove();
  updateConsultativePlanSummary(null);
  updateRunbookSummary(null);
}

function consultativePlanStatusLabel(value) {
  return {
    "informational": "Informativo",
    "needs-evidence": "Coletar evidências",
    "human-review": "Revisão humana",
    "review-ready": "Pronto para revisão"
  }[value] || "Plano indisponível";
}

function consultativeEvidenceStatusLabel(value) {
  return {
    "not-applicable": "Não se aplica",
    "insufficient": "Evidência insuficiente",
    "validated": "Evidência validada"
  }[value] || "Evidência não informada";
}

function consultativeConfidenceLabel(value) {
  return { high: "alta", medium: "média", low: "baixa" }[value] || "não informada";
}

function consultativeList(title, values, emptyLabel) {
  const section = document.createElement("section");
  const heading = document.createElement("strong");
  heading.textContent = title;
  section.append(heading);
  const safeValues = Array.isArray(values)
    ? values.filter(value => typeof value === "string" && value.trim()).slice(0, 20)
    : [];
  if (!safeValues.length) {
    const paragraph = document.createElement("p");
    paragraph.textContent = emptyLabel;
    section.append(paragraph);
    return section;
  }
  const list = document.createElement("ul");
  for (const value of safeValues) {
    const item = document.createElement("li");
    item.textContent = value;
    list.append(item);
  }
  section.append(list);
  return section;
}

function consultativeText(title, value) {
  const section = document.createElement("section");
  const heading = document.createElement("strong");
  const paragraph = document.createElement("p");
  heading.textContent = title;
  paragraph.textContent = typeof value === "string" && value.trim() ? value : "Não informado.";
  section.append(heading, paragraph);
  return section;
}

function renderConsultativePlan(target, plan) {
  if (!target || plan?.schemaVersion !== 1 || plan?.maturity !== "beta" ||
      plan?.executed !== false || plan?.executable !== false) return;
  clearConsultativePlan(target);
  const card = document.createElement("article");
  card.className = `consultative-plan plan-${String(plan.status || "unknown")}`;
  card.setAttribute("aria-label", "Plano consultivo SRE-4 BETA");

  const header = document.createElement("div");
  header.className = "consultative-plan-head";
  const identity = document.createElement("div");
  const kicker = document.createElement("small");
  const title = document.createElement("strong");
  kicker.textContent = `SRE-4 · BETA · contrato ${plan.version || "N/I"}`;
  title.textContent = "Plano de ação consultivo";
  identity.append(kicker, title);
  const badge = document.createElement("span");
  badge.textContent = consultativePlanStatusLabel(plan.status);
  header.append(identity, badge);

  const facts = document.createElement("div");
  facts.className = "consultative-plan-facts";
  for (const value of [
    consultativeEvidenceStatusLabel(plan.evidenceStatus),
    `Confiança ${consultativeConfidenceLabel(plan.confidence)}`,
    `Risco ${riskLabel(plan.riskLevel)}`
  ]) {
    const item = document.createElement("span");
    item.textContent = value;
    facts.append(item);
  }

  const grid = document.createElement("div");
  grid.className = "consultative-plan-grid";
  grid.append(
    consultativeText(plan.hypothesis === true ? "Hipótese de diagnóstico" : "Diagnóstico", plan.diagnosis),
    consultativeText("Impacto", plan.impact),
    consultativeList("Evidências observadas", plan.observedEvidence, "Nenhuma evidência observada foi declarada."),
    consultativeList("Evidências pendentes", plan.missingEvidence, "Nenhuma evidência obrigatória está pendente."),
    consultativeList("Pré-condições", plan.preconditions, "Pré-condições não informadas."),
    consultativeText("Rollback", plan.rollback),
    consultativeText("Validação posterior", plan.validation),
    consultativeText("Próximo passo seguro", plan.nextSafeStep)
  );

  const footer = document.createElement("p");
  footer.className = "consultative-plan-footer";
  footer.textContent = "Nenhuma ação foi executada. Este plano não contém comandos nem autorização de mudança.";
  card.append(header, facts, grid, footer);
  target.querySelector(".message-content")?.parentElement.append(card);
  updateConsultativePlanSummary(plan);
}

function updateConsultativePlanSummary(plan) {
  const status = $("assistant-plan-status");
  const title = $("assistant-plan-title");
  const summary = $("assistant-plan-summary");
  const metadata = $("assistant-plan-metadata");
  if (!status || !title || !summary || !metadata) return;
  if (!plan) {
    status.textContent = "Em espera";
    status.className = "secure-pill";
    title.textContent = "Aguardando resposta";
    summary.textContent = "O servidor acrescentará diagnóstico, evidência, confiança, impacto, pré-condições e rollback.";
    metadata.textContent = "Nenhuma ação pode ser executada pelo plano.";
    return;
  }
  status.textContent = consultativePlanStatusLabel(plan.status);
  status.className = `secure-pill plan-status-${String(plan.status || "unknown")}`;
  title.textContent = plan.hypothesis === true ? "Hipótese visível" : "Contrato consultivo validado";
  summary.textContent = `${consultativeEvidenceStatusLabel(plan.evidenceStatus)} · confiança ${consultativeConfidenceLabel(plan.confidence)} · risco ${riskLabel(plan.riskLevel)}.`;
  metadata.textContent = `SRE-4 ${plan.version || "N/I"} · BETA · executed=false · executable=false.`;
}

function runbookStatusLabel(value) {
  return {
    recommended: "Disponível",
    unavailable: "Sem runbook",
    "not-applicable": "Não se aplica"
  }[value] || "Bloqueado";
}

function renderRunbookRecommendation(target, recommendation) {
  if (!target || recommendation?.schemaVersion !== 1 || recommendation?.maturity !== "beta" ||
      recommendation?.automaticExecution !== false || recommendation?.freeCommandAllowed !== false) return;
  target.querySelector(".runbook-recommendation")?.remove();
  const card = document.createElement("article");
  card.className = `runbook-recommendation runbook-${String(recommendation.status || "unknown")}`;
  card.setAttribute("aria-label", "Runbook homologado SRE-5 BETA");

  const header = document.createElement("div");
  header.className = "consultative-plan-head";
  const identity = document.createElement("div");
  const kicker = document.createElement("small");
  const title = document.createElement("strong");
  kicker.textContent = `SRE-5 · BETA · registro ${recommendation.registryVersion || "N/I"}`;
  title.textContent = recommendation.runbook?.title || "Nenhuma operação homologada selecionada";
  identity.append(kicker, title);
  const badge = document.createElement("span");
  badge.textContent = runbookStatusLabel(recommendation.status);
  header.append(identity, badge);
  const reason = document.createElement("p");
  reason.textContent = recommendation.reason || "Seleção indisponível.";
  card.append(header, reason);

  const runbook = recommendation.runbook;
  const safeReadOnly = recommendation.status === "recommended" && runbook?.executionMode === "secure-terminal-handoff" &&
    runbook?.handoffAction === "sre" && runbook?.mutatesState === false && runbook?.allowsParameters === false &&
    runbook?.automaticExecution === false && runbook?.homologationStatus === "homologated";
  if (safeReadOnly) {
    const grid = document.createElement("div");
    grid.className = "consultative-plan-grid";
    grid.append(
      consultativeText("Escopo", runbook.scope),
      consultativeText("Confirmação humana", runbook.humanConfirmation),
      consultativeList("Pré-checks", runbook.preChecks, "Nenhum pré-check informado."),
      consultativeList("Pós-checks", runbook.postChecks, "Nenhum pós-check informado."),
      consultativeText("Dry-run", runbook.dryRun),
      consultativeText("Rollback", runbook.rollback)
    );
    const action = document.createElement("button");
    action.type = "button";
    action.className = "light-button";
    action.dataset.action = "sre";
    action.textContent = "Abrir coleta segura →";
    card.append(grid, action);
  }
  const footer = document.createElement("p");
  footer.className = "consultative-plan-footer";
  footer.textContent = "A IA não executou o runbook. Comandos livres e parâmetros arbitrários permanecem proibidos.";
  card.append(footer);
  target.querySelector(".message-content")?.parentElement.append(card);
  updateRunbookSummary(recommendation);
}

function updateRunbookSummary(recommendation) {
  const status = $("assistant-runbook-status");
  const title = $("assistant-runbook-title");
  const summary = $("assistant-runbook-summary");
  const metadata = $("assistant-runbook-metadata");
  if (!status || !title || !summary || !metadata) return;
  if (!recommendation) {
    status.textContent = "Em espera";
    status.className = "secure-pill";
    title.textContent = "Aguardando plano consultivo";
    summary.textContent = "O servidor poderá recomendar somente operações fechadas, versionadas e homologadas.";
    metadata.textContent = "Sem comandos livres e sem execução automática.";
    return;
  }
  status.textContent = runbookStatusLabel(recommendation.status);
  status.className = `secure-pill runbook-status-${String(recommendation.status || "unknown")}`;
  title.textContent = recommendation.runbook?.title || "Nenhum runbook aplicável";
  summary.textContent = recommendation.reason || "Seleção indisponível.";
  metadata.textContent = `SRE-5 · registro ${recommendation.registryVersion || "N/I"} · automaticExecution=false · freeCommandAllowed=false.`;
}

function renderAnswerQuality(target, quality) {
  if (!target || quality?.active !== true) return;
  const header = target.querySelector(".message-route");
  if (!header) return;
  const ensureBadge = className => {
    let badge = header.querySelector(`.${className}`);
    if (!badge) {
      badge = document.createElement("span");
      header.append(badge);
    }
    return badge;
  };
  const installation = ensureBadge("message-route-installation");
  installation.className = "message-route-chip message-route-installation assurance-homologated";
  installation.textContent = quality.installationLabel || "Instalador homologado";
  installation.title = `Testado pelo mantenedor em ${(quality.testedArchitectures || []).join(" e ") || "arquiteturas declaradas"}.`;
  installation.hidden = false;

  const badge = ensureBadge("message-route-quality");
  const accepted = new Set([
    "structural", "source-reviewed", "script-reviewed",
    "operational-reviewed", "homologated"
  ]);
  const maturity = accepted.has(quality.maturity) ? quality.maturity : "structural";
  badge.className = `message-route-chip message-route-quality maturity-${maturity}`;
  badge.textContent = quality.maturityLabel || "Conhecimento básico";
  badge.hidden = false;
  const issues = Array.isArray(quality.issueLabels)
    ? quality.issueLabels.filter(value => typeof value === "string" && value).slice(0, 8)
    : [];
  badge.title = issues.length
    ? `Maturidade do conhecimento. Pontos em revisão: ${issues.join("; ")}`
    : quality.operationalCoverage === "partial"
      ? `Evidência operacional parcial: ${(quality.operationalArchitectures || []).join(" e ") || "arquitetura informada"}.`
      : "Maturidade do conhecimento canônico usado nesta resposta.";

  const integration = ensureBadge("message-route-integration");
  const integrationMaturity = ["not-mapped", "suggested", "documented", "validated"]
    .includes(quality.integrationMaturity) ? quality.integrationMaturity : "not-mapped";
  integration.className = `message-route-chip message-route-integration integration-${integrationMaturity}`;
  integration.textContent = quality.integrationLabel || "Integrações em expansão";
  integration.title = "Maturidade dos guias de combinação e integração desta ferramenta.";
  integration.hidden = false;
}

function renderBlueprintSimulation(target, simulation) {
  if (!target || simulation?.active !== true || simulation?.deployable !== false) return;
  clearBlueprintSimulation(target);
  const ids = Array.isArray(simulation.blueprintIds)
    ? simulation.blueprintIds.filter(value => typeof value === "string" && value).slice(0, 5)
    : [];
  const banner = document.createElement("div");
  banner.className = "blueprint-simulation-banner";
  banner.setAttribute("role", "status");
  const title = document.createElement("strong");
  title.textContent = "Simulação de homologação";
  const description = document.createElement("span");
  description.textContent = "Blueprint fictício e não implantável. O fluxo RAG é equivalente ao de produção, mas esta resposta não autoriza deploy.";
  banner.append(title, description);
  if (ids.length) {
    const metadata = document.createElement("small");
    metadata.textContent = ids.join(" · ");
    banner.append(metadata);
  }
  target.querySelector(".message-content")?.parentElement.prepend(banner);
}

function updateAssistantRoute(route, message = "") {
  const specialist = $("assistant-route-specialist");
  const summary = $("assistant-route-summary");
  const status = $("assistant-route-status");
  const metadata = $("assistant-route-metadata");
  if (!specialist || !summary || !status || !metadata) return;
  state.assistantRoute = route || null;
  if (!route) {
    specialist.textContent = "Aguardando consulta";
    summary.textContent = message || "A intenção será classificada sem usar uma segunda LLM.";
    status.textContent = "Em espera";
    metadata.textContent = "Roteamento local e determinístico.";
    return;
  }
  specialist.textContent = specialistLabel(route.specialist);
  status.textContent = `Risco ${riskLabel(route.riskLevel)}`;
  const setups = Array.isArray(route.setups) && route.setups.length
    ? ` · ${route.setups.join(", ")}`
    : "";
  summary.textContent = `${intentLabel(route.intent)} · ${responseProfileLabel(route.responseProfile)} · confiança ${route.confidence === "high" ? "alta" : "média"}${setups}`;
  const evidence = Array.isArray(route.requiredEvidence) && route.requiredEvidence.length
    ? route.requiredEvidence.map(evidenceLabel).join(", ")
    : "redirecionamento de escopo";
  const promptHash = typeof route.promptSHA256 === "string" && route.promptSHA256.length >= 12
    ? route.promptSHA256.slice(0, 12)
    : "N/I";
  metadata.textContent = `Roteador ${route.routerVersion || "N/I"} · registro ${route.promptRegistryVersion || "N/I"} · prompt ${route.promptVersion || "N/I"} · contrato ${route.responseContractVersion || "N/I"} · perfil ${route.responseProfile || "N/I"} · SHA ${promptHash} · exige: ${evidence}.`;
}

function assistantMessageRouteSnapshot(route) {
  const contract = globalThis.SetupMNOAssistantRoute;
  return contract && typeof contract.snapshot === "function" ? contract.snapshot(route) : null;
}

function setAssistantMessageRoutePending(target, label = "Classificando especialista...") {
  if (!target) return;
  target._assistantMessageRoute = null;
  const header = target.querySelector(".message-route");
  const specialist = target.querySelector(".message-route-specialist");
  const risk = target.querySelector(".message-route-risk");
  const prompt = target.querySelector(".message-route-prompt");
  if (!header || !specialist || !risk || !prompt) return;
  specialist.textContent = label;
  risk.hidden = true;
  prompt.hidden = true;
  header.setAttribute("aria-label", label);
}

function setAssistantMessageRouteUnavailable(target) {
  setAssistantMessageRoutePending(target, "Assistente MNO · resposta não concluída");
}

function attachAssistantMessageRoute(target, route) {
  const snapshot = assistantMessageRouteSnapshot(route);
  if (!target || !snapshot) {
    setAssistantMessageRouteUnavailable(target);
    return;
  }
  target._assistantMessageRoute = snapshot;
  const header = target.querySelector(".message-route");
  const specialist = target.querySelector(".message-route-specialist");
  const risk = target.querySelector(".message-route-risk");
  const prompt = target.querySelector(".message-route-prompt");
  if (!header || !specialist || !risk || !prompt) return;
  specialist.textContent = `${snapshot.specialistName} · ${snapshot.responseProfileName}`;
  risk.textContent = `Risco ${snapshot.riskName}`;
  risk.className = `message-route-chip message-route-risk risk-${snapshot.risk}`;
  risk.hidden = false;
  prompt.textContent = `Prompt ${snapshot.promptVersion}`;
  prompt.hidden = false;
  header.setAttribute(
    "aria-label",
    `${snapshot.specialistName}, ${snapshot.responseProfileName}, risco ${snapshot.riskName}, prompt ${snapshot.promptVersion}, contrato ${snapshot.responseContractVersion}`
  );
}

function specialistLabel(value) {
  return globalThis.SetupMNOAssistantRoute?.specialistLabel(value) || "Especialista não identificado";
}

function intentLabel(value) {
  return {
    security_review: "revisão de segurança",
    troubleshooting: "diagnóstico de falha",
    capacity_planning: "planejamento de capacidade",
    blueprint_recommendation: "recomendação de Blueprint",
    integration_design: "projeto de integração",
    setup_guidance: "orientação de setup",
    knowledge_status: "estado da base de conhecimento",
    infrastructure_diagnosis: "diagnóstico de infraestrutura",
    scope_redirect: "consulta fora do escopo"
  }[value] || "intenção não identificada";
}

function responseProfileLabel(value) {
  return {
    direct_overview: "explicação direta",
    guided_decision: "decisão guiada",
    catalog_inventory: "inventário canônico",
    technical_diagnosis: "análise técnica",
    guided_architecture: "arquitetura guiada",
    risk_review: "revisão de risco",
    safe_redirect: "redirecionamento seguro"
  }[value] || "apresentação adaptativa";
}

function riskLabel(value) {
  return globalThis.SetupMNOAssistantRoute?.riskLabel(value) || "não informado";
}

function evidenceLabel(value) {
  return {
    runtime_state: "estado runtime",
    security_controls: "controles de segurança",
    risks: "riscos",
    rollback: "rollback",
    diagnostics: "diagnóstico",
    setup_documentation: "documentação do setup",
    resources: "recursos",
    setup_requirements: "requisitos do setup",
    architecture: "arquitetura",
    blueprint: "Blueprint homologado",
    dependencies: "dependências",
    network: "rede",
    catalog_entry: "catálogo",
    infrastructure_documentation: "documentação de infraestrutura"
  }[value] || value;
}

function updateRetrievalSummary(inspection, message = "") {
  const summary = $("rag-inspection-summary");
  const status = $("rag-inspection-status");
  const title = $("rag-inspection-title");
  if (!summary || !status || !title) return;
  if (!inspection) {
    title.textContent = "Validação de fundamentação";
    summary.textContent = message || "Aguardando uma consulta ao Copiloto.";
    status.innerHTML = "<i></i> Em espera";
    return;
  }
  const promptSent = Number(inspection.promptSourceCount) > 0;
  const sources = promptSent
    ? Number(inspection.promptSourceCount)
    : Array.isArray(inspection.evidence) ? inspection.evidence.length : 0;
  const confidence = confidenceLabel(inspection.confidence);
  summary.textContent = `${confidence} · ${sources} fonte${sources === 1 ? "" : "s"} · ${Number(inspection.durationMs) || 0} ms`;
  if (inspection.usedInAnswer) {
    title.textContent = "Resposta fundamentada";
    status.innerHTML = "<i></i> RAG validado";
  } else if (inspection.promptStatus === "citation-pending") {
    title.textContent = "Validando fundamentação";
    status.innerHTML = "<i></i> RAG analisando";
  } else if (["citation-missing", "citation-invalid"].includes(inspection.promptStatus)) {
    title.textContent = "Resposta não validada";
    status.innerHTML = "<i></i> RAG não validado";
  } else {
    title.textContent = "Evidências em inspeção";
    status.innerHTML = `<i></i> ${inspection.knowledgeStale ? "Contingência" : "Inspeção"}`;
  }
}

function confidenceLabel(value) {
  return { high: "Confiança alta", medium: "Confiança média", low: "Confiança baixa", none: "Sem correspondência" }[value] || "Confiança não informada";
}

function renderRetrievalInspection(target, inspection) {
  if (!inspection || inspection.mode !== "shadow" || typeof inspection.usedInAnswer !== "boolean") return;
  target._retrievalInspection = { ...inspection };
  clearRetrievalInspection(target);
  updateRetrievalSummary(inspection);
  const promptSent = Number(inspection.promptSourceCount) > 0;
  const evidenceLimit = promptSent ? Number(inspection.promptSourceCount) : 6;
  const evidence = Array.isArray(inspection.evidence) ? inspection.evidence.slice(0, evidenceLimit) : [];
  const details = document.createElement("details");
  details.className = "retrieval-inspection";
  const simulation = inspection.simulation === true;
  const sourceLabel = `${evidence.length} evidência${evidence.length === 1 ? "" : "s"}${simulation ? " · simulação" : ""}`;
  const items = evidence.map(item => {
    const hash = String(item.contentSHA256 || "").slice(0, 12);
    const fixture = item.fictitious === true && item.deployable === false ? " · FIXTURE NÃO IMPLANTÁVEL" : "";
    return `<li><strong>${Number(item.rank) || "—"}. ${escapeHTML(item.title || item.documentId || "Documento canônico")}</strong><span>${escapeHTML(item.heading || "Seção geral")}</span><p>${escapeHTML(item.excerpt || "Trecho não disponível.")}</p><small>${escapeHTML(item.documentId || "documento")} · v${escapeHTML(item.documentVersion || "N/I")} · ${escapeHTML(item.targetArchitecture || "geral")} · ${escapeHTML(item.status || "N/I")}${escapeHTML(fixture)}${hash ? ` · SHA ${escapeHTML(hash)}` : ""}</small></li>`;
  }).join("");
  const grounded = inspection.usedInAnswer === true;
  const activationLabel = grounded
    ? "Citações validadas · resposta fundamentada"
    : inspection.promptStatus === "citation-pending"
      ? "Evidências relevantes enviadas · validação pendente"
      : ["citation-missing", "citation-invalid"].includes(inspection.promptStatus)
        ? `Resposta não fundamentada · ${promptStatusLabel(inspection.promptStatus)}`
        : `Inspeção apenas · ${promptStatusLabel(inspection.promptStatus)}`;
  details.innerHTML = `<summary>Evidências RAG · ${escapeHTML(confidenceLabel(inspection.confidence))} · ${sourceLabel}</summary><div class="retrieval-notice${grounded ? " grounded" : ""}"><strong>${escapeHTML(activationLabel)}</strong><span>Ranking ${escapeHTML(inspection.version || "N/I")} · conhecimento ${escapeHTML(inspection.knowledgeVersion || "N/I")} · filtro ${escapeHTML(inspection.filterType || "N/I")} · ${Number(inspection.candidateCount) || 0} candidatos</span></div>${items ? `<ol>${items}</ol>` : `<p class="retrieval-empty">Nenhuma evidência canônica foi selecionada para esta consulta.</p>`}`;
  target.querySelector(".message-content")?.parentElement.append(details);
}

function applyGroundingAudit(target, audit) {
  const inspection = target?._retrievalInspection;
  if (!inspection || !audit) return;
  inspection.usedInAnswer = audit.grounded === true;
  inspection.promptStatus = audit.status || "citation-missing";
  inspection.citedSourceCount = Number(audit.citedSources) || 0;
  renderRetrievalInspection(target, inspection);
}

function promptStatusLabel(value) {
  return {
    "confidence-insufficient": "confiança insuficiente",
    "legacy-fallback": "índice legado",
    "invalid-evidence": "evidência recusada",
    "invalid-blueprint-evidence": "evidência de Blueprint recusada",
    "blueprint-homologation-blocked": "fixture bloqueada fora do Arquiteto de Blueprints",
    "setup-mismatch": "fonte de outro setup recusada",
    "catalog-evidence-missing": "catálogo exato ausente",
    "citation-pending": "citações em validação",
    "citation-missing": "nenhuma citação válida",
    "citation-invalid": "citação inexistente",
    "no-evidence": "sem evidência",
    "feature-disabled": "ativação desabilitada"
  }[value] || "não usada na resposta";
}

function parseSSEBlock(block) {
  let type = "message";
  const data = [];
  for (const line of block.split("\n")) {
    if (line.startsWith("event:")) type = line.slice(6).trim();
    if (line.startsWith("data:")) data.push(line.slice(5).trimStart());
  }
  if (!data.length) return null;
  try {
    return { type, data: JSON.parse(data.join("\n")) };
  } catch {
    return null;
  }
}

function renderAssistantMode() {
  updateAssistantRuntime({
    mode: state.assistantMode,
    model: state.assistantModel,
    configured: true
  });
  renderAssistantAvailability();
}

function assistantModeUsesLLM(mode) {
  return ["openai", "openrouter", "deepseek", "ollama"].includes(mode);
}

function renderAssistantAvailability() {
  const enabled = assistantModeUsesLLM(state.assistantMode);
  $("assistant-chat").hidden = !enabled;
  $("assistant-disabled").hidden = enabled;
  $("assistant-route-card").hidden = !enabled;
  $("assistant-rag-card").hidden = !enabled;
  if (enabled) return;
  const deferred = state.assistantMode === "later";
  const planLimited = Boolean(state.setupPlan) && !state.llmAllowed;
  $("assistant-disabled-text").textContent = deferred
    ? "A configuração do conector de IA foi adiada durante a instalação. Nenhuma LLM está conectada e o chat permanecerá desativado até que um provedor seja escolhido."
    : planLimited
      ? `O plano ${state.setupPlan} mantém o Assistente com IA desativado. O diagnóstico básico local continua disponível sem LLM.`
      : "O modo Básico foi selecionado. Nenhuma LLM está conectada e, por isso, o campo de conversa permanece desativado.";
  $("assistant-disabled-help").textContent = deferred
    ? "Quando desejar ativar o chat, abra Configurações e escolha Alterar Provedor."
    : planLimited
      ? "O chat com LLM é um recurso do plano PRO. Use o botão abaixo para analisar a saúde do servidor localmente."
      : "Para habilitar o chat, abra Configurações e escolha Alterar Provedor.";
}

function updateAssistantRuntime(runtime = {}) {
  const mode = runtime.mode || state.assistantMode || "basic";
  const model = runtime.model || state.assistantModel || "";
  const fallback = Boolean(runtime.fallback);
  const operationalContextAvailable = runtime.operationalContextAvailable !== false;
  const operationalContextWarning = String(runtime.operationalContextWarning || "").trim();
  const operationalContextPartial = operationalContextAvailable && operationalContextWarning !== "";
  const fallbackReason = runtime.fallbackReason || "";
  const fallbackLabel = fallbackReason === "provider"
    ? "Provedor de IA indisponível"
    : fallbackReason === "context"
      ? "Contexto local indisponível"
      : "Conector interno indisponível";
  const badge = $("assistant-mode");
  const provider = providerLabel(mode);
  badge.textContent = mode === "catalog" ? "Catálogo local" : fallback ? "Básico · contingência" : provider;
  $("assistant-provider").textContent = mode === "catalog" ? "Catálogo validado" : fallback ? fallbackLabel : provider;
  $("settings-provider").textContent = mode === "catalog" ? providerLabel(state.assistantMode) : provider;
  $("settings-model").textContent = model ? `Modelo: ${model}` : "Sem consumo de API ou modelo local.";
  $("assistant-model").textContent = mode === "catalog"
    ? "Resposta exata gerada localmente, sem consumo de tokens."
    : model
      ? `Modelo: ${model}`
      : fallback
        ? "Contingência local ativa. O conector será testado novamente na próxima pergunta."
        : "Sem consumo de API ou modelo local.";
  const modelQualityNote = $("assistant-model-quality-note");
  modelQualityNote.classList.remove("warning");
  if (fallback) {
    modelQualityNote.textContent = "A contingência local respondeu sem usar a LLM configurada. O conector será testado novamente na próxima pergunta.";
  } else if (mode === "openrouter" && model.endsWith(":free")) {
    modelQualityNote.classList.add("warning");
    modelQualityNote.textContent = "Modelo gratuito: recomendado somente para testes. Limites e disponibilidade podem reduzir a consistência; execute o canário e revise a resposta.";
  } else if (assistantModeUsesLLM(mode) && model) {
    modelQualityNote.textContent = "A qualidade final depende também deste modelo. Execute o canário de 4 testes após configurar ou trocar a LLM.";
  } else {
    modelQualityNote.textContent = "Modo determinístico local; nenhuma LLM participa desta resposta.";
  }
  if (!fallback && assistantModeUsesLLM(mode) && !operationalContextAvailable) {
    $("assistant-provider").textContent = `${provider} · conhecimento ativo`;
    $("assistant-model").textContent = model
      ? `Modelo: ${model} · métricas locais temporariamente indisponíveis`
      : "Conhecimento canônico ativo · métricas locais temporariamente indisponíveis";
  }
  if (!fallback && assistantModeUsesLLM(mode) && operationalContextPartial) {
    $("assistant-provider").textContent = `${provider} · métricas ativas`;
    $("assistant-model").textContent = model
      ? `Modelo: ${model} · contexto operacional parcial`
      : "Métricas locais ativas · contexto operacional parcial";
  }
  if (mode === "catalog") {
    $("assistant-welcome-title").textContent = "Catálogo runtime validado.";
    $("assistant-welcome-text").textContent = "Listagens completas são geradas localmente para garantir todos os setups, sem omissões ou alucinações.";
    $("assistant-privacy").textContent = "A listagem usa o catálogo validado instalado no servidor e não envia os 151 registros à LLM.";
  } else if (mode === "openai" || mode === "openrouter" || mode === "deepseek") {
    $("assistant-welcome-title").textContent = `Olá! O Copiloto MNO está conectado à ${provider}.`;
    $("assistant-welcome-text").textContent = "Sou especializado em Setup MNO e infraestrutura. Uso uma fotografia sanitizada, sem hostname, credenciais, comandos, nomes reais de serviços ou logs brutos.";
    $("assistant-privacy").textContent = "A consulta usa uma LLM externa. O Setup envia somente o snapshot SRE BETA minimizado e o conhecimento necessário para responder.";
    if (!operationalContextAvailable) {
      $("assistant-welcome-text").textContent = "A base canônica continua disponível para explicar aplicações, requisitos e integrações. A leitura de métricas deste servidor está temporariamente indisponível.";
      $("assistant-privacy").textContent = "A resposta usa o conhecimento canônico; nenhuma métrica local foi enviada nesta consulta.";
    } else if (operationalContextPartial) {
      $("assistant-welcome-text").textContent = operationalContextWarning;
      $("assistant-privacy").textContent = "Os fatos sanitizados disponíveis são combinados com o conhecimento canônico; dados ausentes não são inventados.";
    }
  } else if (mode === "ollama") {
    $("assistant-welcome-title").textContent = "Olá! O Copiloto MNO está conectado ao Ollama.";
    $("assistant-welcome-text").textContent = "Sou especializado em Setup MNO e infraestrutura. Posso combinar o catálogo com a leitura segura do ambiente para orientar seus próximos passos.";
    $("assistant-privacy").textContent = "O processamento ocorre no endpoint Ollama configurado, sem acesso da IA ao Docker, shell ou terminal.";
    if (!operationalContextAvailable) {
      $("assistant-welcome-text").textContent = "A base canônica continua disponível para explicar aplicações, requisitos e integrações. A leitura de métricas deste servidor está temporariamente indisponível.";
      $("assistant-privacy").textContent = "O processamento usa o conhecimento canônico no endpoint Ollama configurado; nenhuma métrica local foi enviada nesta consulta.";
    } else if (operationalContextPartial) {
      $("assistant-welcome-text").textContent = operationalContextWarning;
      $("assistant-privacy").textContent = "O Ollama recebe somente o snapshot sanitizado disponível e o conhecimento canônico necessário à consulta.";
    }
  } else if (fallback) {
    $("assistant-welcome-title").textContent = `${fallbackLabel}.`;
    $("assistant-welcome-text").textContent = "O diagnóstico básico assumiu esta resposta. O Copiloto tentará restabelecer o modo configurado automaticamente na próxima pergunta.";
    $("assistant-privacy").textContent = "A contingência interpreta o snapshot sanitizado localmente e não envia dados para terceiros.";
  } else if (mode === "later") {
    $("assistant-model").textContent = "Conector de IA ainda não configurado.";
    $("settings-model").textContent = "Conector de IA ainda não configurado.";
    $("assistant-welcome-title").textContent = "Configuração de IA adiada.";
    $("assistant-welcome-text").textContent = "O chat permanece desativado até que um provedor de IA seja configurado.";
    $("assistant-privacy").textContent = "Nenhuma LLM está conectada e nenhum dado é enviado para terceiros.";
  } else {
    $("assistant-welcome-title").textContent = "Olá! O diagnóstico básico está pronto.";
    $("assistant-welcome-text").textContent = "Sou especializado em Setup MNO e infraestrutura. Posso avaliar capacidade, réplicas e sinais agregados sem alterar o servidor.";
    $("assistant-privacy").textContent = "O modo básico interpreta o snapshot SRE sanitizado localmente e não envia dados para terceiros.";
  }
  renderProviderEvalAvailability();
}

function providerLabel(mode) {
  return {
    openai: "OpenAI",
    openrouter: "OpenRouter",
    deepseek: "DeepSeek",
    ollama: "Ollama",
    catalog: "Catálogo local",
    basic: "Diagnóstico básico",
    later: "IA não configurada"
  }[mode] || "Diagnóstico básico";
}

function addMessage(text, type, pending = false) {
  const row = document.createElement("div");
  row.className = `message ${type === "user" ? "user-message" : "assistant-message"}`;
  const assistantHeader = `<div class="message-route" aria-live="polite" aria-label="Classificando especialista"><strong class="message-route-specialist">${pending ? "Classificando especialista..." : "MNO Insights"}</strong><span class="message-route-chip message-route-risk" hidden></span><span class="message-route-chip message-route-prompt" hidden></span><span class="message-route-chip message-route-quality" hidden></span></div>`;
  row.innerHTML = `<span class="message-avatar">${type === "user" ? escapeHTML(state.user.slice(0,1).toUpperCase()) : "M"}</span><div>${type === "assistant" ? assistantHeader : `<strong>Você</strong>`}<p class="message-content"></p></div>`;
  const content = row.querySelector(".message-content");
  if (type === "assistant") {
    renderAssistantContent(content, text);
  } else {
    content.textContent = text;
  }
  $("assistant-conversation").append(row);
  $("assistant-conversation").scrollTop = $("assistant-conversation").scrollHeight;
  return row;
}

function renderAssistantContent(element, markdown) {
  const renderer = window.SetupMNOMarkdown;
  if (!renderer || typeof renderer.render !== "function") {
    element.textContent = markdown;
    return;
  }
  element.innerHTML = renderer.render(markdown);
}

const feedbackReasonLabels = {
  helpful: {
    accurate: "Informação correta",
    clear: "Explicação clara",
    useful: "Orientação útil"
  },
  unhelpful: {
    incorrect: "Informação incorreta",
    incomplete: "Resposta incompleta",
    unclear: "Explicação confusa",
    outdated: "Informação desatualizada",
    unsafe: "Orientação potencialmente insegura",
    insufficient_evidence: "Faltaram evidências"
  }
};

const feedbackAreaLabels = {
  setup: "Setup ou aplicação",
  infrastructure: "Infraestrutura",
  capacity: "Capacidade e recursos",
  security: "Segurança",
  blueprint: "Blueprint",
  troubleshooting: "Diagnóstico de falha",
  integration: "Integração",
  other: "Outro tema técnico"
};

function renderMessageFeedback(target) {
  if (!target?.dataset.feedbackToken || target.querySelector(".message-feedback")) return;
  const container = document.createElement("div");
  container.className = "message-feedback";
  const label = document.createElement("small");
  label.textContent = "Esta resposta ajudou?";
  container.append(label);
  for (const [rating, text] of [["helpful", "Sim"], ["unhelpful", "Precisa melhorar"]]) {
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.feedbackRating = rating;
    button.textContent = text;
    container.append(button);
  }
  target.querySelector(".message-content")?.parentElement.append(container);
}

function openFeedbackDialog(target, rating) {
  if (!target?.dataset.feedbackToken || !feedbackReasonLabels[rating]) return;
  state.feedbackTarget = target;
  state.feedbackRating = rating;
  $("feedback-dialog-title").textContent = rating === "helpful" ? "Registrar resposta útil" : "Indicar o que precisa melhorar";
  $("feedback-dialog-summary").textContent = rating === "helpful"
    ? "Sua classificação ajuda a preservar respostas úteis sem armazenar a conversa."
    : "Escolha o motivo da falha. Um administrador decidirá se ela deve originar um teste de qualidade sintético.";
  const reason = $("feedback-reason");
  reason.replaceChildren();
  for (const [value, label] of Object.entries(feedbackReasonLabels[rating])) {
    const option = document.createElement("option");
    option.value = value;
    option.textContent = label;
    reason.append(option);
  }
  $("feedback-area").value = "setup";
  $("feedback-consent").checked = false;
  $("feedback-error").textContent = "";
  $("feedback-dialog").showModal();
}

function closeFeedbackDialog() {
  $("feedback-dialog").close();
  state.feedbackTarget = null;
  state.feedbackRating = "";
}

async function submitAssistantFeedback(event) {
  event.preventDefault();
  const target = state.feedbackTarget;
  const token = target?.dataset.feedbackToken || "";
  const button = event.currentTarget.querySelector("button[type=submit]");
  if (!token || !state.feedbackRating || !$("feedback-consent").checked) {
    $("feedback-error").textContent = "Confirme o consentimento para enviar apenas as classificações.";
    return;
  }
  button.disabled = true;
  try {
    await api("/api/feedback", {
      method: "POST",
      body: JSON.stringify({
        token,
        rating: state.feedbackRating,
        area: $("feedback-area").value,
        reason: $("feedback-reason").value,
        consent: true
      })
    });
    const controls = target.querySelector(".message-feedback");
    if (controls) {
      controls.replaceChildren();
      const status = document.createElement("small");
      status.textContent = "Feedback estruturado enviado para revisão humana.";
      controls.append(status);
    }
    target.dataset.feedbackToken = "";
    closeFeedbackDialog();
  } catch (error) {
    $("feedback-error").textContent = error.message;
  } finally {
    button.disabled = false;
  }
}

async function loadAudit(before = 0, append = false) {
  try {
    const auditPath = before ? `/api/audit?limit=50&before=${encodeURIComponent(before)}` : "/api/audit?limit=50";
    const [data, feedback] = await Promise.all([api(auditPath), api("/api/feedback")]);
    const events = Array.isArray(data.events) ? data.events : [];
    state.auditEvents = append ? [...state.auditEvents, ...events] : events;
    state.auditNextBefore = Number(data.pagination?.nextBefore) || 0;
    const integrity = data.integrity || {};
    const verified = integrity.status === "verified" && integrity.persistenceStatus === "healthy";
    $("audit-integrity").classList.toggle("warning", !verified);
    $("audit-integrity").textContent = verified ? "✓ Íntegra" : "! Atenção";
    $("audit-policy").textContent = verified
      ? `Cadeia local verificada · retenção máxima: ${Number(integrity.retentionDays) || 0} dias · ${Number(integrity.retainedEvents) || 0} eventos retidos.`
      : "A persistência ou a integridade da auditoria exige verificação administrativa antes de novas operações.";
    $("audit-list").innerHTML = state.auditEvents.length ? state.auditEvents.map(event => `
      <div class="audit-row">
        <span>${new Date(event.time).toLocaleString("pt-BR")}</span>
        <strong>${escapeHTML(event.action)}</strong>
        <small>${escapeHTML(event.actor || "admin")} · ${escapeHTML(event.outcome || "success")}</small>
        <span>${escapeHTML(event.detail)}</span>
        <span>${escapeHTML(event.address)}</span>
      </div>`).join("") : `<div class="empty-state">Nenhum evento retido na trilha local.</div>`;
    $("audit-load-more").hidden = !data.pagination?.hasMore;
    renderFeedbackReview(feedback);
  } catch (error) {
    showAlert(error.message);
  }
}

function renderFeedbackReview(data = {}) {
  const report = data.report || {};
  $("feedback-total").textContent = String(report.total || 0);
  $("feedback-helpful").textContent = String(report.helpful || 0);
  $("feedback-unhelpful").textContent = String(report.unhelpful || 0);
  $("feedback-pending").textContent = String(report.pending || 0);
  $("feedback-accepted").textContent = String(report.accepted || 0);
  const versionCounts = report.versionCounts && typeof report.versionCounts === "object" ? report.versionCounts : {};
  const versionSummary = Object.entries(versionCounts)
    .sort(([left], [right]) => right.localeCompare(left, undefined, { numeric: true }))
    .map(([version, count]) => `Control v${version}: ${count}`);
  $("feedback-versions").textContent = versionSummary.length
    ? `Registros por versão: ${versionSummary.join(" · ")}`
    : "Nenhum registro nesta versão.";
  const container = $("feedback-review-list");
  container.replaceChildren();
  const records = Array.isArray(data.records) ? data.records : [];
  if (!records.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "Nenhum feedback estruturado aguardando revisão.";
    container.append(empty);
    return;
  }
  for (const record of records) {
    const card = document.createElement("article");
    card.className = "feedback-review-card";
    const heading = document.createElement("div");
    const title = document.createElement("strong");
    title.textContent = record.rating === "helpful" ? "Resposta útil" : "Resposta precisa melhorar";
    const status = document.createElement("span");
    status.textContent = {
      pending_review: "Aguardando revisão",
      accepted_for_eval: "Candidato a teste",
      dismissed: "Descartado"
    }[record.status] || "Estado inválido";
    heading.append(title, status);
    const metadata = document.createElement("p");
    const fallback = record.fallbackReason ? ` · contingência: ${record.fallbackReason}` : "";
    metadata.textContent = `${feedbackAreaLabels[record.area] || "Área técnica"} · ${feedbackReasonLabels[record.rating]?.[record.reason] || "Motivo estruturado"} · ${providerLabel(record.assistantMode)}${fallback} · Control v${record.controlVersion}`;
    const date = document.createElement("small");
    date.textContent = new Date(record.createdAt).toLocaleString("pt-BR");
    const actions = document.createElement("div");
    actions.className = "feedback-review-actions";
    if (record.status === "pending_review") {
      for (const [action, label] of [["accept_for_eval", "Aceitar para melhoria"], ["dismiss", "Descartar"]]) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "light-button";
        button.dataset.feedbackAction = action;
        button.dataset.feedbackId = record.feedbackId;
        button.textContent = label;
        actions.append(button);
      }
    }
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "feedback-delete-button";
    remove.dataset.feedbackAction = "delete";
    remove.dataset.feedbackId = record.feedbackId;
    remove.textContent = "Excluir";
    actions.append(remove);
    card.append(heading, metadata, date, actions);
    container.append(card);
  }
}

async function reviewFeedbackRecord(feedbackId, decision) {
  try {
    await api("/api/feedback/review", {
      method: "POST",
      body: JSON.stringify({ feedbackId, decision })
    });
    await loadAudit();
  } catch (error) {
    showAlert(error.message);
  }
}

async function deleteFeedbackRecord(feedbackId) {
  if (!window.confirm("Excluir permanentemente este feedback estruturado?")) return;
  try {
    await api("/api/feedback/delete", {
      method: "POST",
      body: JSON.stringify({ feedbackId })
    });
    await loadAudit();
  } catch (error) {
    showAlert(error.message);
  }
}

function navigate(view) {
  if (view === "homologation" && !state.maintainerAccess) {
    showAlert("🔒 A Central de Revisão é exclusiva do plano PRO MASTER.");
    view = "dashboard";
  }
  state.view = view;
  document.querySelectorAll(".view").forEach(element => element.classList.toggle("active", element.id === `view-${view}`));
  document.querySelectorAll(".nav-item").forEach(element => element.classList.toggle("active", element.dataset.view === view));
  $("page-kicker").textContent = titles[view][0];
  $("page-title").textContent = titles[view][1];
  if (view === "audit") loadAudit();
  if (view === "homologation") refreshHomologation();
  if (view === "evals" && !state.evals) refreshEvals();
  closeSidebar();
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function openTerminal(intent = "installer") {
  intent = typeof intent === "string" ? intent : "installer";
  if (!["installer", "settings", "homologation", "sre", "gateway"].includes(intent)) intent = "gateway";
  if (!terminalAccessAllowed()) {
    showAlert("🔒 Recurso disponível apenas quando é usado Cloudflare Tunnel.");
    return;
  }
  if (intent === "homologation" && !state.homologationRunnerAvailable) {
    showAlert("O Homologation Runner ainda não foi confirmado no runtime desta instalação.");
    return;
  }
  if (intent === "homologation" && !state.maintainerAccess) {
    showAlert("🔒 O Homologation Runner é exclusivo do plano PRO MASTER.");
    return;
  }
  pendingTerminalIntent = intent;
  const dialog = $("terminal-reauth-dialog");
  $("terminal-reauth-error").textContent = "";
  $("terminal-reauth-password").value = "";
  if (!dialog.open) dialog.showModal();
  window.requestAnimationFrame(() => $("terminal-reauth-password").focus());
}

async function confirmTerminalAccess(event) {
  event.preventDefault();
  const passwordInput = $("terminal-reauth-password");
  const submit = $("terminal-reauth-submit");
  const password = passwordInput.value;
  if (!password) {
    $("terminal-reauth-error").textContent = "Informe sua senha administrativa.";
    passwordInput.focus();
    return;
  }
  submit.disabled = true;
  $("terminal-reauth-error").textContent = "";
  try {
    await api("/api/terminal/reauth", { method: "POST", body: JSON.stringify({ password, intent: pendingTerminalIntent || "installer" }) });
    passwordInput.value = "";
    const intent = pendingTerminalIntent || "installer";
    pendingTerminalIntent = "";
    $("terminal-reauth-dialog").close();
    openAuthorizedTerminal(intent);
  } catch (error) {
    passwordInput.value = "";
    $("terminal-reauth-error").textContent = error.message;
    passwordInput.focus();
  } finally {
    submit.disabled = false;
  }
}

function closeTerminalReauth() {
  pendingTerminalIntent = "";
  $("terminal-reauth-password").value = "";
  $("terminal-reauth-error").textContent = "";
  const dialog = $("terminal-reauth-dialog");
  if (dialog.open) dialog.close();
}

function openAuthorizedTerminal(intent) {
  const dialog = $("terminal-dialog");
  const mobile = window.matchMedia("(max-width: 650px), (pointer: coarse)").matches;
  const presentation = {
    installer: {
      title: "Instalador Seguro",
      subtitle: "Setup MNO · deploy com confirmação humana",
      warning: "O Instalador Setup MNO será aberto diretamente. Whiptails, planos e confirmações permanecem ativos."
    },
    settings: {
      title: "Configurações Seguras",
      subtitle: "Conta e provedores · confirmação obrigatória",
      warning: "O menu de configurações será aberto diretamente. Senhas e chaves nunca passam pelo navegador."
    },
    homologation: {
      title: "Central do Mantenedor",
      subtitle: "Homologação, validação e selo · PRO MASTER",
      warning: "A Central PRO MASTER exige dry-runs e confirmações humanas. Ela nunca publica commit, tag ou release automaticamente."
    },
    sre: {
      title: "Auditoria SRE-3 · BETA",
      subtitle: "Trivy, Lynis e Docker Bench · somente leitura",
      warning: "A execução exige confirmação humana, pode baixar ferramentas fixadas e salva apenas contagens sanitizadas válidas por 24 horas. Nenhuma correção será aplicada."
    },
    gateway: {
      title: "Terminal Seguro",
      subtitle: "Setup MNO · sessão administrativa",
      warning: "Escolha entre Instalador, Configurações, Auditoria SRE-3 BETA, Central do Mantenedor ou encerrar a sessão no menu protegido."
    }
  }[intent] || {
    title: "Terminal Seguro",
    subtitle: "Setup MNO · sessão administrativa",
    warning: "A intenção visual não foi reconhecida. O menu seguro será aberto sem executar comandos automaticamente."
  };
  $("terminal-title").textContent = presentation.title;
  $("terminal-subtitle").textContent = presentation.subtitle;
  $("terminal-warning").innerHTML = `<span>◎</span> ${presentation.warning}`;
  const parameters = new URLSearchParams({
    arg: intent,
    rendererType: "dom",
    disableResizeOverlay: "true",
    disableLeaveAlert: "true",
    setupmnoTouch: "7"
  });
  if (mobile) {
    parameters.set("fontSize", "10");
    parameters.set("lineHeight", "1.05");
  }
  const frame = $("terminal-frame");
  const terminalURL = `/terminal/?${parameters.toString()}`;
  const loadSequence = ++terminalLoadSequence;
  frame.src = "about:blank";
  if (!dialog.open) dialog.showModal();
  syncTerminalDialogViewport();
  loadTerminalAfterDialogLayout(dialog, frame, terminalURL, loadSequence);
}

function loadTerminalAfterDialogLayout(dialog, frame, terminalURL, loadSequence) {
  window.requestAnimationFrame(() => {
    window.requestAnimationFrame(() => {
      if (!dialog.open || loadSequence !== terminalLoadSequence) return;
      frame.src = terminalURL;
    });
  });
}

function syncTerminalDialogViewport() {
  const dialog = $("terminal-dialog");
  if (!dialog?.open) return;
  const height = Math.round(window.visualViewport?.height || window.innerHeight);
  dialog.style.setProperty("--terminal-viewport-height", `${height}px`);
}

function closeTerminal() {
  const dialog = $("terminal-dialog");
  terminalLoadSequence += 1;
  $("terminal-frame").src = "about:blank";
  dialog.style.removeProperty("--terminal-viewport-height");
  if (dialog.open) dialog.close();
}

function openSidebar() {
  $("sidebar").classList.add("open");
  $("sidebar-backdrop").classList.add("open");
}

function closeSidebar() {
  $("sidebar").classList.remove("open");
  $("sidebar-backdrop").classList.remove("open");
}

function showAlert(message) {
  $("global-alert").textContent = message;
  $("global-alert").classList.remove("hidden");
}

function clearAlert() {
  $("global-alert").classList.add("hidden");
}

async function api(endpoint, options = {}) {
  const headers = { Accept: "application/json", ...(options.headers || {}) };
  if (options.body) headers["Content-Type"] = "application/json";
  if (state.csrf && options.method && options.method !== "GET") headers["X-CSRF-Token"] = state.csrf;
  const response = await fetch(endpoint, { credentials: "same-origin", ...options, headers });
  if (response.status === 401 && endpoint !== "/api/login" && endpoint !== "/api/terminal/reauth") {
    state.csrf = "";
    showLogin();
  }
  const contentType = response.headers.get("content-type") || "";
  const data = contentType.includes("application/json") ? await response.json() : {};
  if (!response.ok) throw new Error(data.error || `Falha HTTP ${response.status}`);
  return data;
}

function bytes(value) {
  if (!value) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const index = Math.min(units.length - 1, Math.floor(Math.log(value) / Math.log(1024)));
  return `${fmt.format(value / Math.pow(1024, index))} ${units[index]}`;
}

function escapeHTML(value) {
  return String(value ?? "").replace(/[&<>"']/g, character => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;"
  })[character]);
}
