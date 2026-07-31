const state = {
  csrf: "",
  user: "",
  controlVersion: "",
  setupVersion: "",
  setupState: null,
  overview: null,
  apps: [],
  catalog: [],
  assistantMode: "basic",
  assistantModel: "",
  assistantHistory: [],
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
  assistant: ["Diagnóstico assistido", "Assistente MNO"],
  audit: ["Rastreabilidade da sessão", "Auditoria"]
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
  state.assistantMode = session.assistantMode || "basic";
  state.assistantModel = session.assistantModel || "";
  state.assistantHistory = [];
  $("current-user").textContent = state.user;
  $("hero-user").textContent = state.user;
  $("user-initial").textContent = state.user.slice(0, 1).toUpperCase();
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
  await refreshCatalog();
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
    pending.querySelector(".message-content").textContent = `Não consegui concluir a análise: ${error.message}`;
  } finally {
    input.disabled = false;
    button.disabled = false;
    input.focus();
  }
}

async function streamAssistant(question, history, target, basic, fallbackReason = "") {
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
  badge.textContent = mode === "openai" ? "OpenAI" : mode === "ollama" ? "Ollama" : mode === "catalog" ? "Catálogo local" : fallback ? "Básico · contingência" : "Básico";
  $("assistant-provider").textContent = mode === "openai" ? "OpenAI" : mode === "ollama" ? "Ollama" : mode === "catalog" ? "Catálogo validado" : fallback ? fallbackLabel : "Diagnóstico básico";
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
  } else if (mode === "openai") {
    $("assistant-welcome-title").textContent = "Olá! O Copiloto MNO está conectado à OpenAI.";
    $("assistant-welcome-text").textContent = "Envio somente contexto operacional minimizado, sem hostname, credenciais, comandos ou acesso direto ao Docker.";
    $("assistant-privacy").textContent = "A consulta usa uma LLM externa. O Setup envia apenas métricas e dados mínimos necessários para responder.";
  } else if (mode === "ollama") {
    $("assistant-welcome-title").textContent = "Olá! O Copiloto MNO está conectado ao Ollama.";
    $("assistant-welcome-text").textContent = "Posso combinar o catálogo do Setup MNO com a leitura segura do ambiente para orientar seus próximos passos.";
    $("assistant-privacy").textContent = "O processamento ocorre no endpoint Ollama configurado, sem acesso da IA ao Docker, shell ou terminal.";
  } else if (fallback) {
    $("assistant-welcome-title").textContent = `${fallbackLabel}.`;
    $("assistant-welcome-text").textContent = "O diagnóstico básico assumiu esta resposta. O Copiloto tentará restabelecer o modo configurado automaticamente na próxima pergunta.";
    $("assistant-privacy").textContent = "A contingência interpreta métricas localmente e não envia dados para terceiros.";
  } else {
    $("assistant-welcome-title").textContent = "Olá! O diagnóstico básico está pronto.";
    $("assistant-welcome-text").textContent = "Posso avaliar capacidade, serviços degradados e prontidão para novos deploys. Ações críticas continuam dependendo da sua confirmação.";
    $("assistant-privacy").textContent = "O modo básico interpreta métricas localmente e não envia dados para terceiros.";
  }
}

function addMessage(text, type, pending = false) {
  const row = document.createElement("div");
  row.className = `message ${type === "user" ? "user-message" : "assistant-message"}`;
  row.innerHTML = `<span class="message-avatar">${type === "user" ? escapeHTML(state.user.slice(0,1).toUpperCase()) : "M"}</span><div>${pending ? "" : `<strong>${type === "user" ? "Você" : "MNO Insights"}</strong>`}<p class="message-content"></p></div>`;
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

function openTerminal() {
  const dialog = $("terminal-dialog");
  const mobile = window.matchMedia("(max-width: 650px), (pointer: coarse)").matches;
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
