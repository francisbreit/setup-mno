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
  auditScope: "all",
  vibeOpsActiveTab: "tools",
  assistantMode: "basic",
  assistantModel: "",
  setupPlan: "",
  llmAllowed: false,
  strixDiagnosticsAccess: false,
  maintainerAccess: false,
  homologationRunnerAvailable: false,
  homologation: null,
  homologationItems: [],
  assistantHistory: [],
  assistantRoute: null,
  fleetStatus: null,
  fleetNodes: [],
  fleetMode: "disabled",
  fleetAllowed: false,
  fleetNodeId: "",
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
const THEME_STORAGE_KEY = "setupmno-control-theme";
const titles = {
  dashboard: ["Infraestrutura em tempo real", "Visão geral"],
  installed: ["Inventário do Docker Swarm", "Aplicações instaladas"],
  catalog: ["Deploys e instalações", "Catálogo de setups"],
  blueprints: ["Arquiteturas compostas", "Blueprints MNO"],
  assistant: ["Diagnóstico assistido", "Assistente MNO"],
  evals: ["Relatório técnico", "Qualidade do Assistente"],
  homologation: ["Evidências operacionais", "Revisão de Homologação"],
  resilience: ["Proteção e continuidade", "Resiliência Operacional"],
  fleet: ["Federação Multi-VPS Segura", "MNO Fleet Hub [BETA]"],
  audit: ["Rastreabilidade da sessão", "Auditoria"],
  settings: ["Administração protegida", "Configurações"],
  help: ["Aprenda no seu ritmo", "Help · Instruções de uso"]
};

let helpFilter = "all";

document.addEventListener("DOMContentLoaded", init);

async function init() {
  initializeTheme();
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
  $("theme-toggle").addEventListener("click", toggleTheme);
  bindHelpCenter();
  $("navigation").addEventListener("click", event => {
    const button = event.target.closest("[data-view]");
    if (button) navigate(button.dataset.view);
  });
  document.body.addEventListener("click", event => {
    const nav = event.target.closest("[data-nav]");
    if (nav) {
      if (event.target.closest("#onboarding-dialog")) {
        closeOnboarding();
      }
      navigate(nav.dataset.nav);
    }
    const action = event.target.closest("[data-action]");
    if (!action) return;
    if (action.dataset.action === "terminal") {
      if (event.target.closest("#onboarding-dialog")) closeOnboarding();
      openTerminal();
    }
    if (action.dataset.action === "assistant") {
      if (event.target.closest("#onboarding-dialog")) closeOnboarding();
      navigate("assistant");
    }
    if (action.dataset.action === "settings") {
      if (event.target.closest("#onboarding-dialog")) closeOnboarding();
      openTerminal("settings");
    }
    if (action.dataset.action === "homologation") openTerminal("homologation");
    if (action.dataset.action === "sre") openTerminal("sre");
    if (action.dataset.action === "strix") openTerminal("strix");
    if (action.dataset.action === "gateway") openTerminal("gateway");
    if (action.dataset.action === "blueprint") openBlueprint(action.dataset.blueprintId);
    if (action.dataset.action === "quality-report") navigate("evals");
    if (action.dataset.action === "quality-return") navigate("assistant");
    if (action.dataset.action === "onboarding") openOnboarding();
    if (action.dataset.action === "fleet-mode") openFleetModeDialog();
    if (action.dataset.action === "fleet-help") {
      navigate("help");
      setHelpFilter("vibeops");
      const hero = $("help-vibeops-hero");
      if (hero) hero.scrollIntoView({ behavior: "smooth", block: "start" });
    }
    if (action.dataset.action === "help-vibeops-guide") {
      navigate("help");
      setHelpFilter("vibeops");
      const guide = $("help-guide-vibeops");
      if (guide) {
        guide.open = true;
        guide.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    }
    if (action.dataset.action === "help-fleet-clone-guide") {
      navigate("help");
      setHelpFilter("vibeops");
      const guide = $("help-guide-fleet-clone");
      if (guide) {
        guide.open = true;
        guide.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    }
  });
  $("open-terminal-top").addEventListener("click", openTerminal);
  $("terminal-close").addEventListener("click", closeTerminal);
  $("terminal-dialog").addEventListener("cancel", event => {
    event.preventDefault();
    closeTerminal();
  });
  $("onboarding-close").addEventListener("click", closeOnboarding);
  $("onboarding-finish").addEventListener("click", finishOnboarding);
  $("onboarding-dialog").addEventListener("cancel", closeOnboarding);
  $("onboarding-dialog").addEventListener("click", event => {
    if (event.target === $("onboarding-dialog")) {
      closeOnboarding();
    }
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
  $("resilience-search").addEventListener("input", renderResilience);
  $("resilience-filter").addEventListener("change", renderResilience);
  $("resilience-risk").addEventListener("change", renderResilience);
  $("fleet-search")?.addEventListener("input", renderFleetNodes);
  $("fleet-filter-status")?.addEventListener("change", renderFleetNodes);
  $("fleet-filter-role")?.addEventListener("change", renderFleetNodes);
  $("fleet-sync-button")?.addEventListener("click", syncFleet);
  $("fleet-add-node-button")?.addEventListener("click", openFleetAddDialog);
  $("fleet-add-dialog-close")?.addEventListener("click", closeFleetAddDialog);
  $("fleet-add-cancel")?.addEventListener("click", closeFleetAddDialog);
  $("fleet-add-form")?.addEventListener("submit", submitFleetAddNode);
  $("fleet-add-dialog")?.addEventListener("cancel", closeFleetAddDialog);
  $("fleet-change-mode-btn")?.addEventListener("click", openFleetModeDialog);
  $("fleet-mode-dialog-close")?.addEventListener("click", closeFleetModeDialog);
  $("fleet-mode-dialog-ok")?.addEventListener("click", closeFleetModeDialog);
  $("fleet-mode-dialog")?.addEventListener("cancel", closeFleetModeDialog);
  $("fleet-worker-token-toggle")?.addEventListener("click", toggleWorkerTokenVisibility);
  $("fleet-worker-token-copy")?.addEventListener("click", copyWorkerToken);
  $("fleet-worker-url-copy")?.addEventListener("click", copyWorkerURL);
  $("sentinel-config-btn")?.addEventListener("click", openSentinelConfigDialog);
  $("sentinel-dialog-close")?.addEventListener("click", closeSentinelConfigDialog);
  $("sentinel-dialog-cancel")?.addEventListener("click", closeSentinelConfigDialog);
  $("sentinel-config-dialog")?.addEventListener("cancel", closeSentinelConfigDialog);
  $("sentinel-config-form")?.addEventListener("submit", submitSentinelConfig);
  $("sentinel-test-btn")?.addEventListener("click", testSentinelAlert);
  $("vibeops-tab-group")?.addEventListener("click", event => {
    const tabBtn = event.target.closest("[data-vibeops-tab]");
    if (!tabBtn) return;
    const tab = tabBtn.dataset.vibeopsTab;
    state.vibeOpsActiveTab = tab;
    document.querySelectorAll("#vibeops-tab-group .vibeops-tab").forEach(b => {
      b.classList.toggle("active", b.dataset.vibeopsTab === tab);
    });
    if ($("vibeops-tools-list")) $("vibeops-tools-list").classList.toggle("hidden", tab !== "tools");
    if ($("vibeops-sentinel-list")) $("vibeops-sentinel-list").classList.toggle("hidden", tab !== "sentinel");
  });
  $("vibeops-refresh-btn")?.addEventListener("click", loadVibeOpsAudit);
  $("vibeops-view-all-btn")?.addEventListener("click", () => {
    state.auditScope = "vibe_ops";
    setView("audit");
  });
  $("audit-scope-pills")?.addEventListener("click", event => {
    const pill = event.target.closest("[data-audit-scope]");
    if (!pill) return;
    const scope = pill.dataset.auditScope || "all";
    if (state.auditScope === scope) return;
    state.auditScope = scope;
    state.auditEvents = [];
    state.auditNextBefore = 0;
    loadAudit();
  });
  $("fleet-nodes-grid")?.addEventListener("click", handleFleetGridAction);
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

function storedTheme() {
  try {
    const theme = window.localStorage?.getItem(THEME_STORAGE_KEY);
    return theme === "light" || theme === "dark" ? theme : "dark";
  } catch {
    return "dark";
  }
}

function applyTheme(theme, persist = false) {
  const selected = theme === "light" ? "light" : "dark";
  document.documentElement.dataset.theme = selected;
  const toggle = $("theme-toggle");
  const light = selected === "light";
  if (toggle) {
    toggle.setAttribute("aria-label", light ? "Ativar modo escuro" : "Ativar modo claro");
    toggle.setAttribute("aria-pressed", String(light));
    toggle.title = light ? "Ativar modo escuro" : "Ativar modo claro";
    const icon = toggle.querySelector("span");
    if (icon) icon.textContent = light ? "☾" : "☀";
  }
  const themeColor = $("theme-color");
  if (themeColor) themeColor.setAttribute("content", light ? "#f4f6f9" : "#07090d");
  if (!persist) return;
  try {
    window.localStorage?.setItem(THEME_STORAGE_KEY, selected);
  } catch {
    // A preferência é opcional; o painel continua funcional sem armazenamento local.
  }
}

function initializeTheme() {
  applyTheme(storedTheme());
}

function toggleTheme() {
  const current = document.documentElement.dataset.theme === "light" ? "light" : "dark";
  applyTheme(current === "light" ? "dark" : "light", true);
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

function setHelpFilter(targetFilter) {
  const search = $("help-search");
  if (search) search.value = "";
  helpFilter = targetFilter || "all";
  document.querySelectorAll("[data-help-filter]").forEach(item => {
    item.classList.toggle("active", item.dataset.helpFilter === helpFilter);
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
  state.auditScope = "all";
  state.vibeOpsActiveTab = "tools";
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
  checkFirstRunOnboarding();
  checkDeepLinkAction();
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
  closeOnboarding();
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
  await Promise.allSettled([refreshOverview(), refreshApps(), refreshReleaseData(), refreshEvals(), refreshHomologation(), loadFleet()]);
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
    if (state.view === "fleet") loadFleet();
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
    expired: "Selo expirado",
    drift: "Drift detectado",
    revoked: "Selo revogado",
    rejected: "Recusado",
    draft: "Checklist em andamento",
    incompatible: "Artefato incompatível",
    quarantine: "Quarentena"
  })[status] || "Estado desconhecido";
}

function renderHomologation() {
  const summary = state.homologation?.summary || {};
  ["pending", "approved", "sealed", "expired", "drift", "revoked", "rejected", "draft", "incompatible", "quarantine"].forEach(key => {
    const target = $(`homologation-${key}`);
    if (target) target.textContent = Number(summary[key]) || 0;
  });
  const reviewCount = (Number(summary.pending) || 0) + (Number(summary.expired) || 0) + (Number(summary.drift) || 0) + (Number(summary.incompatible) || 0) + (Number(summary.quarantine) || 0);
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
    const revocation = item.revocation ? `<div class="homologation-decision homologation-revocation" style="border-color:rgba(255,92,114,.3);background:rgba(255,92,114,.08)"><strong>Revogação do Selo</strong><span>${escapeHTML(item.revocation.revokedBy)} · ${escapeHTML(String(item.revocation.revokedAt || "").slice(0, 10))}</span><p>${escapeHTML(item.revocation.reason)}</p></div>` : "";
    return `<article class="homologation-review-card status-${escapeHTML(item.status)}">
      <div class="homologation-review-head"><div><span class="type-label">${item.kind === "candidate" ? "Candidato" : "Sessão"}</span><h3>${escapeHTML(item.setupId || item.id)}</h3></div><span class="homologation-state">${escapeHTML(homologationStatusLabel(item.status))}</span></div>
      <div class="homologation-metadata"><span><b>Execução</b>${escapeHTML(item.runId || "—")}</span><span><b>Arquitetura</b>${item.architecture === "arm64" ? "ARM64" : item.architecture === "amd64" ? "X86_64" : "—"}</span><span><b>Setup / Runner</b>${escapeHTML(item.setupVersion || "—")} / ${escapeHTML(item.runnerVersion || "—")}</span><span><b>Compatibilidade</b>${escapeHTML(item.compatibility || "—")}</span></div>
      ${item.warning ? `<p class="homologation-warning">${escapeHTML(item.warning)}</p>` : ""}${decision}${revocation}
      <details><summary>Ver evidências e checks</summary>${checkMarkup || "<p class=\"muted\">O checklist ainda está em elaboração.</p>"}<p class="homologation-seal-boundary">${item.officialSeal ? `Selo Essencial: concedido · Escopo: instalação e inicialização · ID: ${escapeHTML(item.sealId || "—")}${item.status === "revoked" ? " (revogado)" : item.status === "expired" ? " (expirado)" : item.status === "drift" ? " (drift detectado)" : " (válido)"}${item.validUntil ? ` · Validade: ${escapeHTML(item.validUntil.slice(0, 10))}` : ""}` : "Selo Essencial: ainda não concedido"} · Publicação automática: não</p></details>
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
    state.strixDiagnosticsAccess = ["pro", "pro-master"].includes(data.plan) && data.capabilities?.strixDiagnostics === true;
    state.maintainerAccess = data.plan === "pro-master" && data.capabilities?.maintainer === true;
    $("setup-plan").textContent = data.plan === "pro-master" ? "PRO MASTER" : data.plan;
    if (!state.llmAllowed) {
      state.assistantMode = "basic";
      state.assistantModel = "";
      renderAssistantMode();
    }
  }
  if (data.fleetMode) {
    state.fleetMode = data.fleetMode;
  }
  if (typeof data.fleetAllowed === "boolean") {
    state.fleetAllowed = data.fleetAllowed;
  }
  if (data.fleetNodeId) {
    state.fleetNodeId = data.fleetNodeId;
  }
  updateFleetNavigationBadge();
  applyMaintainerAccessState();
  if (Object.prototype.hasOwnProperty.call(data, "homologationRunnerAvailable")) {
    renderHomologationRunner(data);
  }
  if (Object.prototype.hasOwnProperty.call(data, "supplyChainAvailable")) {
    renderSupplyChainStatus(data);
  }
  setCatalogSyncStatus(Boolean(data.stale), data.warning, data);
  checkDeepLinkAction();
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
  document.querySelectorAll('[data-action="terminal"], [data-action="settings"], [data-action="homologation"], [data-action="sre"], [data-action="strix"], [data-action="gateway"]').forEach(button => {
    const runnerUnavailable = button.dataset.action === "homologation" && !state.homologationRunnerAvailable;
    const maintainerRequired = button.dataset.action === "homologation" && !state.maintainerAccess;
    const strixRequired = button.dataset.action === "strix" && !state.strixDiagnosticsAccess;
    button.disabled = !allowed || runnerUnavailable || maintainerRequired || strixRequired;
    button.classList.toggle("terminal-locked", !allowed || runnerUnavailable || maintainerRequired || strixRequired);
    button.title = !allowed ? note : maintainerRequired ? "Recurso exclusivo do plano PRO MASTER." : strixRequired ? "Diagnóstico disponível nos planos PRO e PRO MASTER." : runnerUnavailable ? "Homologation Runner indisponível nesta release." : "";
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
  clearAssistantOutputGate(target);
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
      } else if (event.type === "output_gate") {
        renderAssistantOutputGate(target, event.data);
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

function clearAssistantOutputGate(target) {
  target?.querySelector(".assistant-output-gate")?.remove();
}

function renderAssistantOutputGate(target, decision) {
  clearAssistantOutputGate(target);
  if (!target || decision?.status !== "rejected") return;
  const banner = document.createElement("div");
  banner.className = "assistant-output-gate";
  const title = document.createElement("strong");
  title.textContent = "Gate de qualidade BETA acionado";
  const text = document.createElement("span");
  text.textContent = "A resposta externa não passou pelas verificações locais e foi substituída por um diagnóstico seguro, determinístico e somente leitura.";
  banner.append(title, text);
  target.querySelector(".message-content")?.before(banner);
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
    const scopeParam = state.auditScope && state.auditScope !== "all" ? `&scope=${encodeURIComponent(state.auditScope)}` : "";
    const auditPath = before ? `/api/audit?limit=50&before=${encodeURIComponent(before)}${scopeParam}` : `/api/audit?limit=50${scopeParam}`;
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

    document.querySelectorAll("#audit-scope-pills .audit-pill").forEach(btn => {
      btn.classList.toggle("active", btn.dataset.auditScope === (state.auditScope || "all"));
    });

    $("audit-list").innerHTML = state.auditEvents.length ? state.auditEvents.map(event => {
      const actor = event.actor || "admin";
      let actorBadgeClass = "admin";
      let actorLabel = "ADMIN";
      if (actor === "vibe_ops_agent") {
        actorBadgeClass = "vibe-ops";
        actorLabel = "🤖 VIBE OPS";
      } else if (actor === "mno_sentinel") {
        actorBadgeClass = "sentinel";
        actorLabel = "🛡️ SENTINEL";
      } else if (actor === "fleet_controller") {
        actorBadgeClass = "vibe-ops";
        actorLabel = "⎇ FROTA";
      } else if (actor === "anonymous") {
        actorBadgeClass = "anonymous";
        actorLabel = "🔒 ANÔNIMO";
      }
      return `
      <div class="audit-row">
        <span>${new Date(event.time).toLocaleString("pt-BR")}</span>
        <div>
          <strong>${escapeHTML(event.action)}</strong>
          <small class="audit-actor-badge ${actorBadgeClass}">${actorLabel}</small>
        </div>
        <small>${escapeHTML(event.resource || "system")} · ${escapeHTML(event.outcome || "success")}</small>
        <span>${escapeHTML(event.detail)}</span>
        <span>${escapeHTML(event.address)}</span>
      </div>`;
    }).join("") : `<div class="empty-state">Nenhum evento retido na trilha local para o escopo selecionado.</div>`;
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
  if (view === "resilience") loadResilience();
  if (view === "evals" && !state.evals) refreshEvals();
  if (view === "fleet") loadFleet();
  closeSidebar();
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function openTerminal(intent = "installer") {
  intent = typeof intent === "string" ? intent : "installer";
  if (!["installer", "settings", "homologation", "sre", "strix", "gateway"].includes(intent)) intent = "gateway";
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
  if (intent === "strix" && !state.strixDiagnosticsAccess) {
    showAlert("🔒 O diagnóstico Strix SRE-6 está disponível nos planos PRO e PRO MASTER.");
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
      title: "Diagnóstico de Segurança · BETA",
      subtitle: "Servidor e aplicações · somente leitura",
      warning: "A análise verifica o servidor e as imagens usadas pelas aplicações. Ela pode levar alguns minutos, salva somente um resumo por 24 horas e não aplica correções."
    },
    strix: {
      title: "Análise avançada de código · BETA",
      subtitle: "Strix SRE-6 · opcional para PRO e PRO MASTER",
      warning: "Analisa somente uma cópia compactada do código escolhida por você. O modo guiado usa limites seguros automáticos. O executor não recebe acesso ao servidor, às aplicações ou aos dados de produção."
    },
    gateway: {
      title: "Terminal Seguro",
      subtitle: "Setup MNO · sessão administrativa",
      warning: "Escolha entre Instalador, Configurações, diagnóstico de segurança, análise avançada de código, Central do Mantenedor ou encerrar a sessão no menu protegido."
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

async function loadResilience() {
  const status = $("resilience-status");
  if (status) status.textContent = "Carregando matriz determinística de resiliência...";
  try {
    const data = await api("/api/resilience");
    state.resilience = data;
    renderResilience();
    if (status) status.textContent = `Auditoria determinística atualizada · ${data.summary.totalSetups} setups mapeados.`;
  } catch (error) {
    if (status) status.textContent = "Falha ao carregar matriz de resiliência: " + error.message;
  }
}

function renderResilience() {
  if (!state.resilience) return;
  const { summary, items } = state.resilience;

  if ($("resilience-resilient")) $("resilience-resilient").textContent = summary.resilientCount ?? "0";
  if ($("resilience-attention")) $("resilience-attention").textContent = summary.attentionCount ?? "0";
  if ($("resilience-critical")) $("resilience-critical").textContent = summary.criticalCount ?? "0";
  if ($("resilience-avg")) $("resilience-avg").textContent = (summary.averageScore ? summary.averageScore.toFixed(1) : "0") + " / 100";
  if ($("resilience-hybrid")) $("resilience-hybrid").textContent = summary.hybridCount ?? "0";
  if ($("resilience-database")) $("resilience-database").textContent = summary.databaseCount ?? "0";
  if ($("resilience-volume")) $("resilience-volume").textContent = summary.volumeCount ?? "0";
  if ($("resilience-stateless")) $("resilience-stateless").textContent = summary.statelessCount ?? "0";

  const search = ($("resilience-search")?.value || "").toLowerCase().trim();
  const filterType = $("resilience-filter")?.value || "";
  const filterRisk = $("resilience-risk")?.value || "";

  const filtered = items.filter(item => {
    if (filterType && item.persistenceType !== filterType) return false;
    if (filterRisk && item.riskLevel !== filterRisk) return false;
    if (search) {
      const matchName = item.catalogName.toLowerCase().includes(search);
      const matchID = item.setupId.toLowerCase().includes(search);
      const matchStorage = (item.storageLocations || []).some(s => s.toLowerCase().includes(search));
      if (!matchName && !matchID && !matchStorage) return false;
    }
    return true;
  });

  const resultCount = $("resilience-result");
  if (resultCount) resultCount.textContent = `${filtered.length} de ${items.length} aplicações listadas`;
  const container = $("resilience-list");
  if (!container) return;

  if (filtered.length === 0) {
    container.innerHTML = `<div class="empty-state">Nenhuma aplicação corresponde aos filtros selecionados.</div>`;
    return;
  }

  container.innerHTML = filtered.map(item => {
    const riskClass = item.riskLevel === "critical" ? "down" : item.riskLevel === "high" ? "down" : item.riskLevel === "medium" ? "warn" : "up";
    const scoreClass = item.score >= 80 ? "up" : item.score >= 60 ? "warn" : "down";
    const typeLabel = {
      "stateless": "Stateless (Efêmero)",
      "database-backed": "Database-Backed (Banco SQL/NoSQL)",
      "volume-backed": "Volume-Backed (Disco Local)",
      "hybrid": "Híbrido (Banco + Storage S3)"
    }[item.persistenceType] || item.persistenceType;

    const checklistHTML = `
      <div class="resilience-checklist">
        <div><strong>Backup:</strong> <span>${escapeHTML(item.checklist.backupReadiness)}</span></div>
        <div><strong>Restore:</strong> <span>${escapeHTML(item.checklist.restoreVerifiability)}</span></div>
        <div><strong>Update:</strong> <span>${escapeHTML(item.checklist.updateSafety)}</span></div>
        <div><strong>Rollback:</strong> <span>${escapeHTML(item.checklist.rollbackStrategy)}</span></div>
      </div>
    `;

    const recsHTML = (item.recommendations || []).map(r => `<li>${escapeHTML(r)}</li>`).join("");

    return `
      <article class="homologation-card resilience-card">
        <div class="homologation-review-head">
          <div>
            <h3>${escapeHTML(item.catalogName)}</h3>
            <p class="muted"><code>${escapeHTML(item.setupId)}</code> · <strong>${escapeHTML(typeLabel)}</strong></p>
          </div>
          <div class="resilience-badges-row">
            <span class="trend ${riskClass}">Risco ${escapeHTML(item.riskLevel.toUpperCase())}</span>
            <span class="trend ${scoreClass}">Score: ${item.score}/100</span>
          </div>
        </div>
        ${checklistHTML}
        <div class="resilience-storage-note">
          <strong>Armazenamento:</strong> ${escapeHTML((item.storageLocations || []).join(", "))}
        </div>
        <ul class="resilience-recs">${recsHTML}</ul>
      </article>
    `;
  }).join("");
}

async function loadFleet() {
  const statusEl = $("fleet-status");
  try {
    const statusData = await api("/api/fleet/status");
    state.fleetStatus = statusData;
    state.fleetMode = statusData.mode || "disabled";
    state.fleetAllowed = statusData.fleetAllowed === true;
    state.fleetNodeId = statusData.nodeId || "";

    if (state.fleetMode === "master") {
      try {
        const nodesData = await api("/api/fleet/nodes");
        state.fleetNodes = nodesData.nodes || [];
      } catch {
        state.fleetNodes = [];
      }
    } else if (state.fleetMode === "worker") {
      state.fleetNodes = [{
        id: statusData.nodeId || "worker-local",
        name: "Nó de Frota (Worker Local)",
        mode: "worker",
        status: "online",
        role: "worker",
        tunnelHealthy: true,
        telemetry: statusData.localTelemetry
      }];
    } else {
      state.fleetNodes = [];
    }

    renderFleet();
    updateFleetNavigationBadge();
    await loadSentinel();
    await loadVibeOpsAudit();
  } catch (error) {
    if (statusEl) statusEl.textContent = "Falha ao consultar MNO Fleet Hub: " + error.message;
  }
}

function updateFleetNavigationBadge() {
  const countBadge = $("nav-fleet-count");
  if (countBadge) {
    if (state.fleetMode === "master") {
      countBadge.textContent = String(state.fleetStatus?.totalNodes || state.fleetNodes.length || 0);
    } else if (state.fleetMode === "worker") {
      countBadge.textContent = "1";
    } else {
      countBadge.textContent = "0";
    }
  }
  const overviewBadge = $("fleet-overview-badge");
  if (overviewBadge) {
    if (state.fleetMode === "master") {
      const count = state.fleetStatus?.totalNodes || state.fleetNodes.length || 1;
      overviewBadge.textContent = `Torre Master (${count} ${count === 1 ? "nó" : "nós"})`;
    } else if (state.fleetMode === "worker") {
      overviewBadge.textContent = "Nó Worker";
    } else {
      overviewBadge.textContent = "Standalone (0 MB)";
    }
  }
}

function renderFleet() {
  const statusData = state.fleetStatus || {};
  const mode = state.fleetMode || "disabled";
  const badge = $("fleet-mode-badge");
  const statusEl = $("fleet-status");

  if (badge) {
    badge.className = `mode-pill mode-${mode}`;
    if (mode === "master") {
      badge.textContent = "Torre Master (Controlador)";
    } else if (mode === "worker") {
      badge.textContent = "Nó Operário (Worker)";
    } else {
      badge.textContent = "Modo Simples (Desativado)";
    }
  }

  if (statusEl) {
    if (mode === "master") {
      const total = statusData.totalNodes || state.fleetNodes.length || 0;
      const online = statusData.onlineNodes || 0;
      statusEl.className = "sync-status current";
      statusEl.textContent = `Torre Master conectada · ${online} de ${total} nós online · Malha Zero-Trust ativa · Co-piloto de prontidão`;
    } else if (mode === "worker") {
      statusEl.className = "sync-status current";
      statusEl.textContent = "Nó Operário ativo · Respondendo exclusivamente à Torre Master autorizada pelo token";
    } else {
      statusEl.className = "sync-status";
      statusEl.textContent = "MNO Fleet Hub desativado neste nó · Consumo ocioso: 0 MB de RAM";
    }
  }

  const isAllowed = state.fleetAllowed === true;

  // Atualizar botões de alteração de modo
  const changeModeBtn = $("fleet-change-mode-btn");
  if (changeModeBtn) {
    if (!isAllowed) {
      changeModeBtn.disabled = true;
      changeModeBtn.classList.add("disabled", "btn-pro-locked");
      changeModeBtn.title = "Recurso exclusivo para planos PRO e PRO MASTER no modo Cloudflare Tunnel";
      changeModeBtn.innerHTML = 'Alterar Modo <b class="badge-lock-tag">🔒 PRO</b>';
    } else {
      changeModeBtn.disabled = false;
      changeModeBtn.classList.remove("disabled", "btn-pro-locked");
      changeModeBtn.title = "Alterar modo de operação do servidor";
      changeModeBtn.innerHTML = 'Alterar Modo <b>⚙</b>';
    }
  }

  const ctaModeBtn = $("fleet-cta-mode-btn");
  if (ctaModeBtn) {
    if (!isAllowed) {
      ctaModeBtn.disabled = true;
      ctaModeBtn.classList.add("disabled", "btn-pro-locked");
      ctaModeBtn.title = "Recurso exclusivo para planos PRO e PRO MASTER no modo Cloudflare Tunnel";
      ctaModeBtn.innerHTML = 'Configuração Bloqueada <b class="badge-lock-tag">🔒 PRO</b>';
    } else {
      ctaModeBtn.disabled = false;
      ctaModeBtn.classList.remove("disabled", "btn-pro-locked");
      ctaModeBtn.title = "Configurar papel e modo da frota";
      ctaModeBtn.innerHTML = 'Configurar Modo da Frota <b>→</b>';
    }
  }

  const ctaTitle = $("fleet-cta-title");
  const ctaDesc = $("fleet-cta-desc");
  if (ctaTitle && ctaDesc) {
    if (!isAllowed) {
      ctaTitle.textContent = "Configuração do Fleet Hub Bloqueada";
      ctaDesc.textContent = "O gerenciamento de frota multi-servidor (Vibe Ops) é exclusivo para instalações no modo Cloudflare Tunnel (Zero Portas Abertas) no WSL2 ou VPS para assinantes dos planos PRO e PRO MASTER. Nos planos Free ou modo Tradicional, a configuração permanece bloqueada.";
    } else {
      ctaTitle.textContent = "Deseja ativar o MNO Fleet Hub neste servidor?";
      ctaDesc.textContent = "Acesse o terminal do servidor ou utilize o instalador seguro e execute a opção ⎇ MNO FLEET HUB para escolher o papel desta máquina.";
    }
  }

  const addNodeBtn = $("fleet-add-node-button");
  if (addNodeBtn) {
    if (!isAllowed) {
      addNodeBtn.disabled = true;
      addNodeBtn.classList.add("disabled", "btn-pro-locked");
      addNodeBtn.title = "Recurso exclusivo para planos PRO e PRO MASTER no modo Cloudflare Tunnel";
    } else {
      addNodeBtn.disabled = false;
      addNodeBtn.classList.remove("disabled", "btn-pro-locked");
      addNodeBtn.title = "";
    }
  }

  const disabledPanel = $("fleet-disabled-panel");
  const masterPanel = $("fleet-master-panel");
  const workerPanel = $("fleet-worker-panel");

  if (disabledPanel) disabledPanel.classList.toggle("hidden", mode !== "disabled");
  if (masterPanel) masterPanel.classList.toggle("hidden", mode !== "master");
  if (workerPanel) workerPanel.classList.toggle("hidden", mode !== "worker");

  if (mode === "master") {
    renderFleetMasterSummary();
    renderFleetNodes();
  } else if (mode === "worker") {
    renderFleetWorker();
  }
}

function renderFleetMasterSummary() {
  const nodes = state.fleetNodes || [];
  const statusData = state.fleetStatus || {};

  const total = statusData.totalNodes || nodes.length;
  let online = 0;
  let offline = 0;
  let totalMemMB = 0;
  let totalServices = 0;

  nodes.forEach(node => {
    if (node.status === "online") online++;
    else offline++;

    const mem = node.memoryTotalMB || node.telemetry?.memoryTotalMB || 0;
    totalMemMB += mem;

    const srv = node.serviceCount || ((node.telemetry?.healthyApps || 0) + (node.telemetry?.unhealthyApps || 0));
    totalServices += srv;
  });

  if ($("fleet-stat-total")) $("fleet-stat-total").textContent = String(total);
  if ($("fleet-stat-online")) $("fleet-stat-online").textContent = String(online);
  if ($("fleet-stat-offline")) $("fleet-stat-offline").textContent = String(offline);
  if ($("fleet-stat-memory")) $("fleet-stat-memory").textContent = totalMemMB > 0 ? bytes(totalMemMB * 1024 * 1024) : "—";
  if ($("fleet-stat-services")) $("fleet-stat-services").textContent = String(totalServices);
}

function renderFleetNodes() {
  const container = $("fleet-nodes-grid");
  if (!container) return;

  const search = ($("fleet-search")?.value || "").toLowerCase().trim();
  const filterStatus = $("fleet-filter-status")?.value || "";
  const filterRole = $("fleet-filter-role")?.value || "";

  const filtered = (state.fleetNodes || []).filter(node => {
    if (filterStatus && node.status !== filterStatus) return false;
    if (filterRole && node.role !== filterRole && node.mode !== filterRole) return false;
    if (search) {
      const matchName = (node.name || "").toLowerCase().includes(search);
      const matchEndpoint = (node.endpoint || "").toLowerCase().includes(search);
      const matchRole = (node.role || node.mode || "").toLowerCase().includes(search);
      const matchArch = (node.architecture || "").toLowerCase().includes(search);
      const matchId = (node.id || "").toLowerCase().includes(search);
      if (!matchName && !matchEndpoint && !matchRole && !matchArch && !matchId) return false;
    }
    return true;
  });

  const resultCount = $("fleet-result-count");
  if (resultCount) {
    resultCount.textContent = `${filtered.length} de ${(state.fleetNodes || []).length} servidores listados`;
  }

  if (filtered.length === 0) {
    container.innerHTML = `<div class="empty-state">Nenhum servidor corresponde aos filtros da frota.</div>`;
    return;
  }

  container.innerHTML = filtered.map(node => {
    const isMaster = node.mode === "master" || (node.id && node.id.startsWith("node-master"));
    const statusClass = node.status === "online" ? "online" : node.status === "degraded" ? "warning" : "offline";
    const statusLabel = node.status === "online" ? "Online" : node.status === "degraded" ? "Degradado" : "Offline";
    const roleLabel = isMaster ? "Master" : (node.role || "Worker");
    const roleClass = isMaster ? "master" : "worker";

    const memTotalMB = node.memoryTotalMB || node.telemetry?.memoryTotalMB || 0;
    const memUsedMB = node.memoryUsedMB || node.telemetry?.memoryUsedMB || 0;
    const memPct = memTotalMB > 0 ? Math.round((memUsedMB / memTotalMB) * 100) : 0;
    const memBarClass = memPct > 85 ? "danger" : memPct > 70 ? "warn" : "";

    const cpuPct = node.cpuUsagePercent || (node.telemetry?.loadAverage1m ? Math.min(100, Math.round(node.telemetry.loadAverage1m * 25)) : 0);
    const cpuBarClass = cpuPct > 85 ? "danger" : cpuPct > 70 ? "warn" : "";

    const serviceCount = node.serviceCount || ((node.telemetry?.healthyApps || 0) + (node.telemetry?.unhealthyApps || 0));
    const endpointLabel = node.endpoint || (isMaster ? "Localhost (Loopback)" : "—");
    const archLabel = node.architecture ? (node.architecture === "amd64" ? "x86-64" : node.architecture) : "x86-64";
    const setupVer = node.setupVersion ? `v${node.setupVersion}` : "Setup MNO";

    const lockClass = !state.fleetAllowed ? " disabled btn-pro-locked" : "";
    const disabledAttr = !state.fleetAllowed ? " disabled" : "";

    const openBtnHTML = (!isMaster && node.endpoint && (node.endpoint.startsWith("http://") || node.endpoint.startsWith("https://")))
      ? `<a href="${escapeHTML(node.endpoint)}" target="_blank" rel="noopener noreferrer" class="light-button small" title="Abrir Control Center deste servidor em nova aba">Abrir Painel ↗</a>`
      : "";

    const removeBtnHTML = isMaster
      ? ""
      : `<button type="button" class="ghost-button small${lockClass}" data-fleet-action="remove" data-node-id="${escapeHTML(node.id)}" data-node-name="${escapeHTML(node.name)}" title="Remover nó da frota"${disabledAttr}>Excluir 🗑️</button>`;

    return `
      <article class="fleet-card ${isMaster ? "is-master" : ""}" data-node-id="${escapeHTML(node.id)}">
        <div class="fleet-card-top">
          <div>
            <h4 class="fleet-card-title">${escapeHTML(node.name || node.id)}</h4>
            <div class="fleet-card-sub"><code>${escapeHTML(node.id)}</code> · ${escapeHTML(setupVer)}</div>
          </div>
          <div class="fleet-card-badges">
            <span class="fleet-role-badge ${roleClass}">${escapeHTML(roleLabel)}</span>
            <span class="secure-pill status-${statusClass}"><i></i> ${escapeHTML(statusLabel)}</span>
          </div>
        </div>

        <div class="fleet-card-metrics">
          <div>
            <div class="fleet-metric-row">
              <span>Memória RAM (${memPct}%)</span>
              <strong>${memTotalMB > 0 ? `${fmt.format(memUsedMB)} / ${fmt.format(memTotalMB)} MB` : "—"}</strong>
            </div>
            <div class="fleet-bar-wrap">
              <div class="fleet-bar-fill ${memBarClass}" style="width:${Math.min(100, memPct)}%"></div>
            </div>
          </div>
          <div>
            <div class="fleet-metric-row">
              <span>Carga de CPU</span>
              <strong>${cpuPct}%</strong>
            </div>
            <div class="fleet-bar-wrap">
              <div class="fleet-bar-fill ${cpuBarClass}" style="width:${Math.min(100, cpuPct)}%"></div>
            </div>
          </div>
        </div>

        <div class="fleet-card-facts">
          <div>
            <small>Endpoint / Conexão</small>
            <span>${escapeHTML(endpointLabel)}</span>
          </div>
          <div>
            <small>Arquitetura</small>
            <span>${escapeHTML(archLabel)}</span>
          </div>
          <div>
            <small>Aplicações Ativas</small>
            <span>${node.status === "offline" ? "Inacessível (Offline)" : `${serviceCount} serviços`}</span>
          </div>
          <div>
            <small>Rede Mesh</small>
            <span>${node.status === "online" && node.tunnelHealthy !== false ? "✓ Zero-Trust" : "⚠ Offline / Inacessível"}</span>
          </div>
        </div>

        <div class="fleet-card-actions">
          <button type="button" class="light-button small${lockClass}" data-fleet-action="ping" data-node-id="${escapeHTML(node.id)}"${disabledAttr}>Testar Conexão ⚡</button>
          ${openBtnHTML}
          ${removeBtnHTML}
        </div>
      </article>
    `;
  }).join("");
}

async function syncFleet() {
  const btn = $("fleet-sync-button");
  const originalText = btn ? btn.textContent : "";
  if (btn) {
    btn.disabled = true;
    btn.textContent = "Sincronizando...";
  }

  try {
    const res = await api("/api/fleet/sync", { method: "POST" });
    showToast(`⚡ Frota sincronizada: ${res.onlineNodes || 0} online, ${res.offlineNodes || 0} offline.`);
    await loadFleet();
  } catch (error) {
    showToast(`⚠ Falha na sincronização: ${error.message}`);
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = originalText;
    }
  }
}

function renderFleetWorker() {
  const statusData = state.fleetStatus || {};
  const telem = statusData.localTelemetry || {};
  const currentOrigin = (typeof window !== "undefined" && window.location && window.location.origin) ? window.location.origin : "http://127.0.0.1:8080";

  if ($("fleet-worker-id")) $("fleet-worker-id").textContent = statusData.nodeId || "worker-local";
  if ($("fleet-worker-endpoint")) $("fleet-worker-endpoint").textContent = currentOrigin;
  if ($("fleet-worker-url")) $("fleet-worker-url").value = currentOrigin;
  if ($("fleet-worker-swarm")) $("fleet-worker-swarm").textContent = telem.activeSwarm ? "Ativo (Docker Swarm OK)" : "Inativo";

  const healthy = telem.healthyApps || 0;
  const unhealthy = telem.unhealthyApps || 0;
  if ($("fleet-worker-apps")) $("fleet-worker-apps").textContent = `${healthy} saudáveis (${healthy + unhealthy} total)`;

  const tokenInput = $("fleet-worker-token");
  if (tokenInput) {
    const rawToken = statusData.fleetToken || state.setupState?.fleetToken || "";
    tokenInput.value = rawToken;
    if (!rawToken) {
      tokenInput.placeholder = "Token configurado no nó indisponível";
    }
  }
}

async function handleFleetGridAction(event) {
  const button = event.target.closest("[data-fleet-action]");
  if (!button) return;

  if (!state.fleetAllowed) {
    showToast("Ação bloqueada: exclusivo para planos PRO e PRO MASTER com Cloudflare Tunnel.");
    return;
  }

  const action = button.dataset.fleetAction;
  const nodeId = button.dataset.nodeId;
  const nodeName = button.dataset.nodeName || nodeId;

  if (action === "ping") {
    await pingFleetNode(nodeId, button);
  } else if (action === "remove") {
    await removeFleetNode(nodeId, nodeName);
  }
}

async function pingFleetNode(nodeId, buttonEl) {
  const originalText = buttonEl ? buttonEl.textContent : "";
  if (buttonEl) {
    buttonEl.disabled = true;
    buttonEl.textContent = "Testando...";
  }

  try {
    const res = await api(`/api/fleet/nodes/${encodeURIComponent(nodeId)}/ping`, {
      method: "POST"
    });

    if (res.pong) {
      showToast(`⚡ Nó respondeu em ${res.latencyMs}ms (Status: ${res.status})`);
      if (buttonEl) buttonEl.textContent = `✓ ${res.latencyMs}ms`;
    } else {
      showToast(`⚠ Falha no ping: ${res.error || "sem resposta"}`);
      if (buttonEl) buttonEl.textContent = "Falha ⚠";
    }

    try {
      const nodesData = await api("/api/fleet/nodes");
      state.fleetNodes = nodesData.nodes || [];
      renderFleetMasterSummary();
      renderFleetNodes();
    } catch {}
  } catch (error) {
    showToast(`Erro ao enviar ping: ${error.message}`);
    if (buttonEl) buttonEl.textContent = "Erro";
  } finally {
    if (buttonEl) {
      setTimeout(() => {
        buttonEl.disabled = false;
        buttonEl.textContent = originalText;
      }, 3000);
    }
  }
}

async function removeFleetNode(nodeId, nodeName) {
  if (!confirm(`Deseja realmente remover o servidor "${nodeName}" da frota?`)) {
    return;
  }

  try {
    await api(`/api/fleet/nodes/${encodeURIComponent(nodeId)}`, {
      method: "DELETE"
    });
    showToast(`Servidor "${nodeName}" removido da frota com sucesso.`);
    await loadFleet();
  } catch (error) {
    showAlert(`Erro ao remover servidor: ${error.message}`);
  }
}

function openFleetAddDialog() {
  if (!state.fleetAllowed) {
    showToast("Configuração bloqueada: exclusivo para planos PRO e PRO MASTER com Cloudflare Tunnel.");
    return;
  }
  const dialog = $("fleet-add-dialog");
  if (!dialog) return;
  $("fleet-add-error").textContent = "";
  $("fleet-new-name").value = "";
  $("fleet-new-endpoint").value = "";
  $("fleet-new-token").value = "";
  $("fleet-new-role").value = "worker";
  if (!dialog.open) dialog.showModal();
}

function closeFleetAddDialog() {
  const dialog = $("fleet-add-dialog");
  if (dialog?.open) dialog.close();
}

async function submitFleetAddNode(event) {
  event.preventDefault();
  const errorEl = $("fleet-add-error");
  const submitBtn = $("fleet-add-submit");
  errorEl.textContent = "";

  const name = $("fleet-new-name").value.trim();
  const endpoint = $("fleet-new-endpoint").value.trim();
  const token = $("fleet-new-token").value.trim();
  const role = $("fleet-new-role").value;

  if (!name || !endpoint || !token) {
    errorEl.textContent = "Preencha todos os campos obrigatórios (*).";
    return;
  }

  submitBtn.disabled = true;
  submitBtn.textContent = "Pareando nó...";

  try {
    await api("/api/fleet/nodes", {
      method: "POST",
      body: JSON.stringify({ name, endpoint, token, role })
    });

    closeFleetAddDialog();
    showToast(`✓ Nó "${name}" pareado e adicionado à frota com sucesso!`);
    await loadFleet();
  } catch (error) {
    errorEl.textContent = error.message;
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = "Parear e Adicionar Nó ＋";
  }
}

function openFleetModeDialog() {
  if (!state.fleetAllowed) {
    showToast("Configuração bloqueada: exclusivo para planos PRO e PRO MASTER com Cloudflare Tunnel.");
    return;
  }
  const dialog = $("fleet-mode-dialog");
  if (dialog && !dialog.open) dialog.showModal();
}

function closeFleetModeDialog() {
  const dialog = $("fleet-mode-dialog");
  if (dialog?.open) dialog.close();
}

function toggleWorkerTokenVisibility() {
  const input = $("fleet-worker-token");
  const btn = $("fleet-worker-token-toggle");
  if (!input || !btn) return;
  const isPass = input.type === "password";
  input.type = isPass ? "text" : "password";
  btn.textContent = isPass ? "Ocultar" : "Mostrar";
}

async function copyWorkerToken() {
  const input = $("fleet-worker-token");
  if (!input || !input.value) {
    showToast("Nenhum token disponível para copiar.");
    return;
  }
  try {
    await navigator.clipboard.writeText(input.value);
    showToast("Token de pareamento copiado com sucesso!");
  } catch {
    input.select();
    document.execCommand("copy");
    showToast("Token de pareamento copiado!");
  }
}

async function copyWorkerURL() {
  const input = $("fleet-worker-url");
  if (!input || !input.value) return;
  try {
    await navigator.clipboard.writeText(input.value);
    showToast("URL do Endpoint copiada!");
  } catch {
    input.select();
    document.execCommand("copy");
    showToast("URL copiada!");
  }
}

async function loadSentinel() {
  if (!state.fleetAllowed) return;
  try {
    const status = await api("/api/sentinel/status");
    renderSentinel(status);
  } catch (err) {
    console.warn("Sentinel status indisponível:", err);
  }
}

function renderSentinel(status) {
  const badge = $("sentinel-status-badge");
  const runningEl = $("sentinel-stat-running");
  const lastEl = $("sentinel-stat-last");
  const incidentsEl = $("sentinel-stat-incidents");
  const listContainer = $("sentinel-incidents-container");

  if (!status) return;

  if (badge) {
    if (status.enabled) {
      badge.className = "mode-pill mode-master";
      badge.textContent = status.running ? "Vigilância Ativa" : "Ativado";
    } else {
      badge.className = "mode-pill mode-disabled";
      badge.textContent = "Sentinel Inativo";
    }
  }

  if (runningEl) {
    runningEl.textContent = status.enabled ? "Ativo (24/7)" : "Desativado";
  }

  if (lastEl) {
    lastEl.textContent = status.lastCheck ? new Date(status.lastCheck).toLocaleTimeString() : "Aguardando";
  }

  if (incidentsEl) {
    incidentsEl.textContent = String(status.activeCount || 0);
    incidentsEl.className = status.activeCount > 0 ? "trend warn" : "trend up";
  }

  if (listContainer) {
    if (status.activeIncidents && status.activeIncidents.length > 0) {
      listContainer.classList.remove("hidden");
      listContainer.innerHTML = status.activeIncidents.map(inc => `
        <div class="sentinel-incident-item ${escapeHTML(inc.severity || 'warning')}">
          <div>
            <strong>${inc.severity === "critical" ? "🚨" : "⚠️"} ${escapeHTML(inc.nodeName)}:</strong>
            <span>${escapeHTML(inc.message)}</span>
          </div>
          <small class="muted">${new Date(inc.startedAt).toLocaleTimeString()}</small>
        </div>
      `).join("");
    } else {
      listContainer.classList.add("hidden");
      listContainer.innerHTML = "";
    }
  }
}

async function loadVibeOpsAudit() {
  if (!state.fleetAllowed || state.fleetMode !== "master") return;
  try {
    const [auditData, sentinelStatus] = await Promise.all([
      api("/api/audit?scope=vibe_ops&limit=50"),
      api("/api/sentinel/status").catch(() => ({}))
    ]);
    renderVibeOpsAudit(auditData, sentinelStatus);
  } catch (err) {
    console.warn("Vibe Ops audit indisponível:", err);
  }
}

function renderVibeOpsAudit(auditData = {}, sentinelStatus = {}) {
  const allEvents = Array.isArray(auditData.events) ? auditData.events : [];
  const toolEvents = allEvents.filter(e => e.action === "fleet_tool_call" || e.action.startsWith("fleet_tool_") || e.actor === "vibe_ops_agent");
  const sentinelEvents = allEvents.filter(e => e.action.startsWith("sentinel_") || e.actor === "mno_sentinel" || e.resource === "sentinel");
  const recentAlerts = Array.isArray(sentinelStatus.recentAlerts) ? sentinelStatus.recentAlerts : [];
  const integrity = auditData.integrity || {};

  if ($("vibeops-stat-calls")) $("vibeops-stat-calls").textContent = String(toolEvents.length);
  if ($("vibeops-stat-incidents")) $("vibeops-stat-incidents").textContent = String(sentinelStatus.activeCount || 0);
  if ($("vibeops-stat-alerts")) $("vibeops-stat-alerts").textContent = String(sentinelEvents.length + recentAlerts.length);
  if ($("vibeops-stat-integrity")) {
    const ok = integrity.status === "verified" && integrity.persistenceStatus === "healthy";
    $("vibeops-stat-integrity").textContent = ok ? "✓ SHA-256 Íntegra" : "! Degradação";
    $("vibeops-stat-integrity").className = ok ? "trend up" : "trend warn";
  }
  if ($("vibeops-tools-count")) $("vibeops-tools-count").textContent = String(toolEvents.length);
  if ($("vibeops-sentinel-count")) $("vibeops-sentinel-count").textContent = String(sentinelEvents.length + recentAlerts.length);

  const toolsContainer = $("vibeops-tools-list");
  if (toolsContainer) {
    if (!toolEvents.length) {
      toolsContainer.innerHTML = `<div class="empty-state">Nenhuma chamada de ferramenta registrada ainda. Conecte o Hermes Agent ou n8n via API de ferramentas.</div>`;
    } else {
      toolsContainer.innerHTML = toolEvents.map(ev => {
        let toolName = "fleet_tool_call";
        const match = (ev.detail || "").match(/Tool\s+([a-zA-Z0-9_-]+)/i);
        if (match) toolName = match[1];
        const isSuccess = ev.outcome === "success";
        return `
          <div class="vibeops-feed-item">
            <div class="vibeops-feed-header">
              <div class="vibeops-feed-tags">
                <span class="vibeops-tool-tag">${escapeHTML(toolName)}</span>
                <span class="vibeops-actor-tag">${escapeHTML(ev.actor || "vibe_ops_agent")}</span>
                <span class="vibeops-outcome-tag ${isSuccess ? 'success' : 'denied'}">${isSuccess ? 'Sucesso' : 'Falha/Rejeição'}</span>
              </div>
              <span class="vibeops-feed-time">${new Date(ev.time).toLocaleString("pt-BR")}</span>
            </div>
            <div class="vibeops-feed-detail">${escapeHTML(ev.detail)}</div>
            <div class="vibeops-feed-meta">
              <span>Origem: <code>${escapeHTML(ev.address || "local")}</code></span>
              <span>Hash: <code>${escapeHTML((ev.eventHash || "").slice(0, 12))}...</code></span>
            </div>
          </div>
        `;
      }).join("");
    }
  }

  const sentinelContainer = $("vibeops-sentinel-list");
  if (sentinelContainer) {
    const combinedSentinel = [...sentinelEvents];
    for (const alt of recentAlerts) {
      if (!combinedSentinel.some(e => (e.detail && e.detail.includes(alt.incidentId)) || e.time === alt.sentAt)) {
        combinedSentinel.push({
          time: alt.sentAt,
          action: "sentinel_alert_dispatched",
          actor: "mno_sentinel",
          resource: "sentinel",
          outcome: alt.success ? "success" : "failure",
          detail: `Alerta para incidente ${alt.incidentId} enviado via ${alt.channel} (HTTP ${alt.httpStatus})`,
          address: "sentinel-daemon"
        });
      }
    }
    combinedSentinel.sort((a, b) => new Date(b.time) - new Date(a.time));

    if (!combinedSentinel.length) {
      sentinelContainer.innerHTML = `<div class="empty-state">Nenhum alerta emitido pelo Sentinel nas últimas horas. Servidores operando dentro dos parâmetros normais.</div>`;
    } else {
      sentinelContainer.innerHTML = combinedSentinel.map(ev => {
        const isSuccess = ev.outcome === "success";
        return `
          <div class="vibeops-feed-item">
            <div class="vibeops-feed-header">
              <div class="vibeops-feed-tags">
                <span class="vibeops-tool-tag" style="background:rgba(168,85,247,.18);color:#c084fc;border-color:rgba(168,85,247,.3);">${escapeHTML(ev.action)}</span>
                <span class="vibeops-actor-tag">${escapeHTML(ev.actor || "mno_sentinel")}</span>
                <span class="vibeops-outcome-tag ${isSuccess ? 'success' : 'denied'}">${isSuccess ? 'Disparado' : 'Falha'}</span>
              </div>
              <span class="vibeops-feed-time">${new Date(ev.time).toLocaleString("pt-BR")}</span>
            </div>
            <div class="vibeops-feed-detail">${escapeHTML(ev.detail)}</div>
            <div class="vibeops-feed-meta">
              <span>Canal/Origem: <code>${escapeHTML(ev.address || "sentinel")}</code></span>
            </div>
          </div>
        `;
      }).join("");
    }
  }
}

async function openSentinelConfigDialog() {
  if (!state.fleetAllowed) {
    showToast("Configuração bloqueada: exclusivo para planos PRO e PRO MASTER.");
    return;
  }
  const dialog = $("sentinel-config-dialog");
  const feedbackEl = $("sentinel-test-feedback");
  if (feedbackEl) feedbackEl.classList.add("hidden");

  try {
    const cfg = await api("/api/sentinel/config");
    if ($("sentinel-enabled-input")) $("sentinel-enabled-input").checked = cfg.enabled === true;
    if ($("sentinel-ram-threshold")) $("sentinel-ram-threshold").value = cfg.ramThresholdPct || 85;
    if ($("sentinel-disk-threshold")) $("sentinel-disk-threshold").value = cfg.diskThresholdPct || 90;
    if ($("sentinel-notify-degraded")) $("sentinel-notify-degraded").checked = cfg.notifyDegradedApp !== false;
    if ($("sentinel-notify-node-down")) $("sentinel-notify-node-down").checked = cfg.notifyNodeDown !== false;
    if ($("sentinel-webhook-url")) $("sentinel-webhook-url").value = cfg.webhookURL || "";
    if ($("sentinel-telegram-token")) $("sentinel-telegram-token").value = cfg.telegramBotToken || "";
    if ($("sentinel-telegram-chat")) $("sentinel-telegram-chat").value = cfg.telegramChatID || "";
    if ($("sentinel-cooldown")) $("sentinel-cooldown").value = cfg.cooldownMinutes || 15;
  } catch (err) {
    showToast("Erro ao carregar configurações do Sentinel: " + err.message);
  }

  if (dialog && !dialog.open) dialog.showModal();
}

function closeSentinelConfigDialog() {
  const dialog = $("sentinel-config-dialog");
  if (dialog?.open) dialog.close();
}

async function submitSentinelConfig(event) {
  event.preventDefault();
  const submitBtn = $("sentinel-save-btn");
  const feedbackEl = $("sentinel-test-feedback");
  if (feedbackEl) feedbackEl.classList.add("hidden");

  const payload = {
    enabled: $("sentinel-enabled-input")?.checked || false,
    ramThresholdPct: parseInt($("sentinel-ram-threshold")?.value, 10) || 85,
    diskThresholdPct: parseInt($("sentinel-disk-threshold")?.value, 10) || 90,
    notifyDegradedApp: $("sentinel-notify-degraded")?.checked || false,
    notifyNodeDown: $("sentinel-notify-node-down")?.checked || false,
    webhookURL: $("sentinel-webhook-url")?.value?.trim() || "",
    telegramBotToken: $("sentinel-telegram-token")?.value?.trim() || "",
    telegramChatID: $("sentinel-telegram-chat")?.value?.trim() || "",
    cooldownMinutes: parseInt($("sentinel-cooldown")?.value, 10) || 15
  };

  try {
    if (submitBtn) {
      submitBtn.disabled = true;
      submitBtn.textContent = "Salvando...";
    }
    await api("/api/sentinel/config", {
      method: "POST",
      body: JSON.stringify(payload)
    });
    showToast("✓ Configurações do MNO Sentinel salvas com sucesso!");
    closeSentinelConfigDialog();
    await loadSentinel();
  } catch (err) {
    if (feedbackEl) {
      feedbackEl.textContent = "Erro ao salvar: " + err.message;
      feedbackEl.className = "form-feedback error";
      feedbackEl.classList.remove("hidden");
    } else {
      showToast("Erro: " + err.message);
    }
  } finally {
    if (submitBtn) {
      submitBtn.disabled = false;
      submitBtn.textContent = "Salvar Configurações";
    }
  }
}

async function testSentinelAlert() {
  const testBtn = $("sentinel-test-btn");
  const feedbackEl = $("sentinel-test-feedback");
  if (!feedbackEl) return;

  const testPayload = {
    webhookURL: $("sentinel-webhook-url")?.value?.trim() || "",
    telegramBotToken: $("sentinel-telegram-token")?.value?.trim() || "",
    telegramChatID: $("sentinel-telegram-chat")?.value?.trim() || ""
  };

  try {
    if (testBtn) {
      testBtn.disabled = true;
      testBtn.textContent = "Enviando teste...";
    }
    feedbackEl.textContent = "Disparando teste de notificação...";
    feedbackEl.className = "form-feedback info";
    feedbackEl.classList.remove("hidden");

    const res = await api("/api/sentinel/test", {
      method: "POST",
      body: JSON.stringify(testPayload)
    });

    const failed = (res.records || []).filter(r => !r.success);
    if (failed.length > 0) {
      feedbackEl.textContent = `Aviso: Falha em ${failed.map(f => f.target + " (" + f.error + ")").join(", ")}`;
      feedbackEl.className = "form-feedback warn";
    } else {
      feedbackEl.textContent = "✓ Teste de alerta enviado e entregue com sucesso nos canais configurados!";
      feedbackEl.className = "form-feedback success";
    }
  } catch (err) {
    feedbackEl.textContent = "Erro ao enviar teste: " + err.message;
    feedbackEl.className = "form-feedback error";
  } finally {
    if (testBtn) {
      testBtn.disabled = false;
      testBtn.textContent = "Testar Envio Agora 🧪";
    }
  }
}

function showToast(message) {
  const toast = $("toast");
  if (!toast) return;
  toast.textContent = message;
  toast.classList.add("show");
  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => {
    toast.classList.remove("show");
  }, 3500);
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
const escapeHtml = escapeHTML;

const ONBOARDING_KEY = "setupmno-onboarding-dismissed";

function checkFirstRunOnboarding() {
  const dismissed = localStorage.getItem(ONBOARDING_KEY) === "true";
  if (!dismissed) {
    setTimeout(openOnboarding, 600);
  }
}

function openOnboarding() {
  if (!$("app-view") || $("app-view").classList.contains("hidden")) return;
  const dialog = $("onboarding-dialog");
  if (!dialog) return;
  const dismissed = localStorage.getItem(ONBOARDING_KEY) === "true";
  const dontShow = $("onboarding-dont-show");
  if (dontShow) dontShow.checked = dismissed;
  if (!dialog.open) dialog.showModal();
}

function closeOnboarding() {
  const dialog = $("onboarding-dialog");
  if (!dialog) return;
  const dontShow = $("onboarding-dont-show");
  if (dontShow && dontShow.checked) {
    localStorage.setItem(ONBOARDING_KEY, "true");
  }
  if (dialog.open) dialog.close();
}

function finishOnboarding() {
  const dontShow = $("onboarding-dont-show");
  if (!dontShow || dontShow.checked) {
    localStorage.setItem(ONBOARDING_KEY, "true");
  }
  closeOnboarding();
}

function checkDeepLinkAction() {
  if (state.deepLinkHandled) return;
  try {
    const urlParams = new URLSearchParams(window.location.search);
    const action = urlParams.get("action");
    const nav = urlParams.get("nav") || (window.location.hash ? window.location.hash.replace("#", "") : "");
    if (nav && ["dashboard", "installed", "catalog", "blueprints", "assistant", "resilience", "fleet", "homologation", "audit", "settings", "help"].includes(nav)) {
      navigate(nav);
    }
    if (action === "terminal" || window.location.hash === "#terminal" || urlParams.get("install") === "1") {
      if (terminalAccessAllowed()) {
        state.deepLinkHandled = true;
        setTimeout(() => {
          openTerminal("installer");
        }, 150);
      }
    }
  } catch {}
}

