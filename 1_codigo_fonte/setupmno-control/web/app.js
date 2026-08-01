const state = {
  csrf: "",
  user: "",
  controlVersion: "",
  setupVersion: "",
  setupState: null,
  overview: null,
  apps: [],
  catalog: [],
  blueprints: [],
  blueprintCatalog: null,
  blueprintRecommendation: null,
  assistantMode: "basic",
  assistantModel: "",
  assistantHistory: [],
  assistantRoute: null,
  view: "dashboard",
  timer: null,
  catalogTimer: null
};

const $ = id => document.getElementById(id);
const fmt = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 1 });
const titles = {
  dashboard: ["Infraestrutura em tempo real", "Visão geral"],
  installed: ["Inventário do Docker Swarm", "Aplicações instaladas"],
  catalog: ["Deploys e instalações", "Catálogo de setups"],
  blueprints: ["Arquiteturas compostas", "Blueprints MNO"],
  assistant: ["Diagnóstico assistido", "Assistente MNO"],
  audit: ["Rastreabilidade da sessão", "Auditoria"],
  settings: ["Administração protegida", "Configurações"]
};

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
    if (action.dataset.action === "blueprint") openBlueprint(action.dataset.blueprintId);
  });
  $("open-terminal-top").addEventListener("click", openTerminal);
  $("terminal-close").addEventListener("click", closeTerminal);
  $("terminal-dialog").addEventListener("cancel", event => {
    event.preventDefault();
    closeTerminal();
  });
  $("installed-search").addEventListener("input", renderInstalled);
  $("installed-filter").addEventListener("change", renderInstalled);
  $("catalog-search").addEventListener("input", renderCatalog);
  $("catalog-category").addEventListener("change", renderCatalog);
  $("catalog-arch").addEventListener("change", renderCatalog);
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
  closeTerminal();
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
  $("blueprint-recommendation-result").hidden = true;
  state.assistantMode = session.assistantMode || "basic";
  state.assistantModel = session.assistantModel || "";
  state.assistantHistory = [];
  $("current-user").textContent = state.user;
  $("hero-user").textContent = state.user;
  $("user-initial").textContent = state.user.slice(0, 1).toUpperCase();
  $("settings-username").textContent = state.user;
  $("control-version").textContent = `v${state.controlVersion}`;
  $("setup-version").textContent = "verificando";
  renderAssistantMode();
  $("login-view").classList.add("hidden");
  $("app-view").classList.remove("hidden");
  refreshAll();
  clearInterval(state.timer);
  clearInterval(state.catalogTimer);
  state.timer = setInterval(refreshOverview, 30000);
  state.catalogTimer = setInterval(refreshReleaseData, 300000);
}

function showLogin() {
  clearInterval(state.timer);
  clearInterval(state.catalogTimer);
  $("app-view").classList.add("hidden");
  $("login-view").classList.remove("hidden");
  setTimeout(() => $("login-user").focus(), 80);
}

async function refreshAll() {
  $("refresh-button").classList.add("spinning");
  await Promise.allSettled([refreshOverview(), refreshApps(), refreshReleaseData()]);
  $("refresh-button").classList.remove("spinning");
}

async function refreshReleaseData() {
  await refreshSetupState();
  await Promise.allSettled([refreshCatalog(), refreshBlueprints()]);
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
  setCatalogSyncStatus(Boolean(data.stale), data.warning, data);
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
  $("catalog-grid").innerHTML = items.length ? items.map(item => `
    <article class="catalog-card">
      <div class="catalog-card-top"><h3>${escapeHTML(item.name)}</h3><span class="type-label">${escapeHTML(item.type || "Setup")}</span></div>
      <div class="catalog-tags">${String(item.cats || "").split(",").slice(0,4).map(tag => `<span>${escapeHTML(tag.trim())}</span>`).join("")}</div>
      <p class="catalog-description">${escapeHTML(item.desc || "Setup disponível no catálogo MNO.")}</p>
      <div class="catalog-facts"><span><b>RAM</b> ${escapeHTML(item.ramLabel || "N/I")}</span><span><b>Arquitetura</b> ${item.arch === "x86-arm" ? "X86 + ARM" : "X86"}</span></div>
      <button class="light-button" data-action="terminal">Abrir no instalador <b>→</b></button>
    </article>`).join("") : `<div class="empty-state">Nenhum setup corresponde aos filtros selecionados.</div>`;
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
  if (status === "example") return "example";
  return "review";
}

function blueprintStatusLabel(item) {
  return ({
    homologated: "Homologado",
    example: "Exemplo fictício",
    draft: "Rascunho",
    reviewed: "Revisado",
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
  $("blueprint-example-total").textContent = catalog.exampleCount ?? 0;
  $("nav-blueprint-count").textContent = catalog.blueprintCount ?? state.blueprints.length;
  $("blueprint-result").textContent = `${items.length} de ${state.blueprints.length} Blueprints encontrados`;

  const groups = {
    homologated: items.filter(item => blueprintGroup(item.status) === "homologated"),
    example: items.filter(item => blueprintGroup(item.status) === "example"),
    review: items.filter(item => blueprintGroup(item.status) === "review")
  };
  renderBlueprintGroup("blueprint-homologated-grid", groups.homologated, "Nenhum Blueprint homologado disponível nesta versão.");
  renderBlueprintGroup("blueprint-example-grid", groups.example, "Nenhum exemplo editorial corresponde aos filtros.");
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
      <button class="light-button" data-action="blueprint" data-blueprint-id="${escapeHTML(item.blueprintId)}">Inspecionar Blueprint <b>→</b></button>
    </article>`;
  }).join("") : `<div class="empty-state compact">${escapeHTML(emptyMessage)}</div>`;
}

function openBlueprint(blueprintId) {
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
      ? `<strong>Exemplo fictício — não implantável</strong><span>Material de simulação para validar schema, RAG e interface. Não representa configuração homologada e não autoriza deploy.</span>`
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
  const simulation = data.simulation
    ? `<div class="blueprint-recommendation-warning"><strong>Simulação com exemplos fictícios</strong><span>Os resultados atuais validam o mecanismo de seleção, mas não são implantáveis e não autorizam deploy.</span></div>`
    : "";
  const recommendationCards = recommendations.length ? recommendations.map(item => `
    <article class="blueprint-match-card ${item.capacityFit === "minimum" ? "limited" : "ready"}">
      <div class="blueprint-match-rank"><span>#${escapeHTML(item.rank)}</span><div><small>${escapeHTML(item.confidence === "high" ? "Alta aderência" : item.confidence === "medium" ? "Aderência média" : "Aderência baixa")}</small><strong>${escapeHTML(item.title)}</strong></div></div>
      <div class="blueprint-match-badges"><span>${escapeHTML(item.status === "example" ? "Exemplo fictício" : "Homologado")}</span><span>${escapeHTML(item.capacityFit === "recommended" ? "RAM recomendada atendida" : "Somente RAM mínima")}</span></div>
      <ul>${(Array.isArray(item.reasons) ? item.reasons : []).map(reason => `<li>${escapeHTML(reason)}</li>`).join("")}</ul>
      <div class="blueprint-match-resources"><span><small>Mínima</small><strong>${escapeHTML(item.minimumRamGB)} GB</strong></span><span><small>Recomendada</small><strong>${escapeHTML(item.recommendedRamGB)} GB</strong></span><span><small>Risco</small><strong>${escapeHTML(blueprintRiskLabel(item.risk))}</strong></span></div>
      <p>${escapeHTML(item.resourceBasis)}</p>
      <button class="light-button" data-action="blueprint" data-blueprint-id="${escapeHTML(item.blueprintId)}">Inspecionar evidências <b>→</b></button>
    </article>`).join("") : `<div class="blueprint-no-match"><strong>Nenhum Blueprint compatível</strong><span>${escapeHTML(data.noMatchReason || "Não há evidência suficiente para recomendar com segurança.")}</span></div>`;
  const rejectedBlock = rejected.length ? `<details class="blueprint-rejected"><summary>${rejected.length} candidato(s) recusado(s) pelos gates</summary><ul>${rejected.map(item => `<li><strong>${escapeHTML(item.title)}</strong><span>${(Array.isArray(item.reasons) ? item.reasons : []).map(escapeHTML).join(" · ")}</span></li>`).join("")}</ul></details>` : "";
  target.innerHTML = `
    <div class="blueprint-recommendation-head"><div><p class="eyebrow">Contexto verificado</p><h3>${recommendations.length} recomendação(ões) compatível(is)</h3></div><div class="blueprint-runtime-facts"><span>${escapeHTML(architecture)}</span><span>${escapeHTML(context.memoryAvailableGB ?? "N/I")} GB livres</span><span>Setup v${escapeHTML(context.setupVersion || "N/I")}</span></div></div>
    ${simulation}
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
  const pending = addMessage("Analisando métricas atuais...", "assistant", true);
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
    input.disabled = false;
    button.disabled = false;
    input.focus();
  }
}

async function streamAssistant(question, history, target, basic, fallbackReason = "") {
  clearRetrievalInspection(target);
  clearBlueprintSimulation(target);
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
      } else if (event.type === "route") {
        updateAssistantRoute(event.data);
        attachAssistantMessageRoute(target, event.data);
      } else if (event.type === "retrieval") {
        renderRetrievalInspection(target, event.data);
      } else if (event.type === "blueprint_simulation") {
        renderBlueprintSimulation(target, event.data);
      } else if (event.type === "grounding") {
        applyGroundingAudit(target, event.data);
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
  summary.textContent = `${intentLabel(route.intent)} · confiança ${route.confidence === "high" ? "alta" : "média"}${setups}`;
  const evidence = Array.isArray(route.requiredEvidence) && route.requiredEvidence.length
    ? route.requiredEvidence.map(evidenceLabel).join(", ")
    : "redirecionamento de escopo";
  const promptHash = typeof route.promptSHA256 === "string" && route.promptSHA256.length >= 12
    ? route.promptSHA256.slice(0, 12)
    : "N/I";
  metadata.textContent = `Roteador ${route.routerVersion || "N/I"} · registro ${route.promptRegistryVersion || "N/I"} · prompt ${route.promptVersion || "N/I"} · contrato ${route.responseContractVersion || "N/I"} · SHA ${promptHash} · exige: ${evidence}.`;
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
  specialist.textContent = snapshot.specialistName;
  risk.textContent = `Risco ${snapshot.riskName}`;
  risk.className = `message-route-chip message-route-risk risk-${snapshot.risk}`;
  risk.hidden = false;
  prompt.textContent = `Prompt ${snapshot.promptVersion}`;
  prompt.hidden = false;
  header.setAttribute(
    "aria-label",
    `${snapshot.specialistName}, risco ${snapshot.riskName}, prompt ${snapshot.promptVersion}, contrato ${snapshot.responseContractVersion}`
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
    infrastructure_diagnosis: "diagnóstico de infraestrutura",
    scope_redirect: "consulta fora do escopo"
  }[value] || "intenção não identificada";
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
}

function updateAssistantRuntime(runtime = {}) {
  const mode = runtime.mode || state.assistantMode || "basic";
  const model = runtime.model || state.assistantModel || "";
  const fallback = Boolean(runtime.fallback);
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
  if (mode === "catalog") {
    $("assistant-welcome-title").textContent = "Catálogo runtime validado.";
    $("assistant-welcome-text").textContent = "Listagens completas são geradas localmente para garantir todos os setups, sem omissões ou alucinações.";
    $("assistant-privacy").textContent = "A listagem usa o catálogo validado instalado no servidor e não envia os 151 registros à LLM.";
  } else if (mode === "openai" || mode === "openrouter" || mode === "deepseek") {
    $("assistant-welcome-title").textContent = `Olá! O Copiloto MNO está conectado à ${provider}.`;
    $("assistant-welcome-text").textContent = "Sou especializado em Setup MNO e infraestrutura. Envio somente contexto operacional minimizado, sem hostname, credenciais, comandos ou acesso direto ao Docker.";
    $("assistant-privacy").textContent = "A consulta usa uma LLM externa. O Setup envia apenas métricas e dados mínimos necessários para responder.";
  } else if (mode === "ollama") {
    $("assistant-welcome-title").textContent = "Olá! O Copiloto MNO está conectado ao Ollama.";
    $("assistant-welcome-text").textContent = "Sou especializado em Setup MNO e infraestrutura. Posso combinar o catálogo com a leitura segura do ambiente para orientar seus próximos passos.";
    $("assistant-privacy").textContent = "O processamento ocorre no endpoint Ollama configurado, sem acesso da IA ao Docker, shell ou terminal.";
  } else if (fallback) {
    $("assistant-welcome-title").textContent = `${fallbackLabel}.`;
    $("assistant-welcome-text").textContent = "O diagnóstico básico assumiu esta resposta. O Copiloto tentará restabelecer o modo configurado automaticamente na próxima pergunta.";
    $("assistant-privacy").textContent = "A contingência interpreta métricas localmente e não envia dados para terceiros.";
  } else {
    $("assistant-welcome-title").textContent = "Olá! O diagnóstico básico está pronto.";
    $("assistant-welcome-text").textContent = "Sou especializado em Setup MNO e infraestrutura. Posso avaliar capacidade, serviços degradados e prontidão para novos deploys.";
    $("assistant-privacy").textContent = "O modo básico interpreta métricas localmente e não envia dados para terceiros.";
  }
}

function providerLabel(mode) {
  return {
    openai: "OpenAI",
    openrouter: "OpenRouter",
    deepseek: "DeepSeek",
    ollama: "Ollama",
    basic: "Diagnóstico básico"
  }[mode] || "Diagnóstico básico";
}

function addMessage(text, type, pending = false) {
  const row = document.createElement("div");
  row.className = `message ${type === "user" ? "user-message" : "assistant-message"}`;
  const assistantHeader = `<div class="message-route" aria-live="polite" aria-label="Classificando especialista"><strong class="message-route-specialist">${pending ? "Classificando especialista..." : "MNO Insights"}</strong><span class="message-route-chip message-route-risk" hidden></span><span class="message-route-chip message-route-prompt" hidden></span></div>`;
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

async function loadAudit() {
  try {
    const data = await api("/api/audit");
    $("audit-list").innerHTML = data.events.length ? data.events.map(event => `
      <div class="audit-row">
        <span>${new Date(event.time).toLocaleString("pt-BR")}</span>
        <strong>${escapeHTML(event.action)}</strong>
        <span>${escapeHTML(event.detail)}</span>
        <span>${escapeHTML(event.address)}</span>
      </div>`).join("") : `<div class="empty-state">Nenhum evento nesta sessão.</div>`;
  } catch (error) {
    showAlert(error.message);
  }
}

function navigate(view) {
  state.view = view;
  document.querySelectorAll(".view").forEach(element => element.classList.toggle("active", element.id === `view-${view}`));
  document.querySelectorAll(".nav-item").forEach(element => element.classList.toggle("active", element.dataset.view === view));
  $("page-kicker").textContent = titles[view][0];
  $("page-title").textContent = titles[view][1];
  if (view === "audit") loadAudit();
  closeSidebar();
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function openTerminal(intent = "installer") {
  intent = typeof intent === "string" ? intent : "installer";
  const dialog = $("terminal-dialog");
  const mobile = window.matchMedia("(max-width: 650px), (pointer: coarse)").matches;
  $("terminal-title").textContent = intent === "settings" ? "Configurações Seguras" : "Terminal Seguro";
  $("terminal-subtitle").textContent = intent === "settings"
    ? "Conta e provedores · confirmação obrigatória"
    : "Setup MNO · sessão administrativa";
  $("terminal-warning").innerHTML = intent === "settings"
    ? "<span>◎</span> No Terminal Seguro, selecione CONFIGURAÇÕES. Senhas e chaves não passam pelo navegador."
    : "<span>◎</span> Selecione INSTALADOR para abrir o Setup MNO original. Whiptails e regras de plano permanecem ativos.";
  $("terminal-frame").src = mobile
    ? "/terminal/?rendererType=dom&fontSize=10&lineHeight=1&disableResizeOverlay=true&disableLeaveAlert=true&setupmnoTouch=5"
    : "/terminal/";
  dialog.showModal();
}

function closeTerminal() {
  const dialog = $("terminal-dialog");
  $("terminal-frame").src = "about:blank";
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
  if (response.status === 401 && endpoint !== "/api/login") {
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
