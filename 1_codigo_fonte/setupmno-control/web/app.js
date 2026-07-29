const state = {
  csrf: "",
  user: "",
  version: "",
  overview: null,
  apps: [],
  catalog: [],
  view: "dashboard",
  timer: null
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
  closeTerminal();
  showLogin();
}

function setAuthenticated(session) {
  state.csrf = session.csrfToken;
  state.user = session.user;
  state.version = session.version;
  $("current-user").textContent = state.user;
  $("hero-user").textContent = state.user;
  $("user-initial").textContent = state.user.slice(0, 1).toUpperCase();
  $("app-version").textContent = `v${state.version}`;
  $("login-view").classList.add("hidden");
  $("app-view").classList.remove("hidden");
  refreshAll();
  clearInterval(state.timer);
  state.timer = setInterval(refreshOverview, 30000);
}

function showLogin() {
  $("app-view").classList.add("hidden");
  $("login-view").classList.remove("hidden");
  setTimeout(() => $("login-user").focus(), 80);
}

async function refreshAll() {
  $("refresh-button").classList.add("spinning");
  await Promise.allSettled([refreshOverview(), refreshApps(), refreshCatalog()]);
  $("refresh-button").classList.remove("spinning");
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
  if (state.catalog.length) return;
  try {
    state.catalog = await api("/api/catalog");
    populateCategories();
    renderCatalog();
  } catch (error) {
    showAlert(error.message);
  }
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
  const categories = [...new Set(state.catalog.flatMap(item => String(item.cats || "").split(",").map(v => v.trim()).filter(Boolean)))].sort((a,b) => a.localeCompare(b, "pt-BR"));
  select.innerHTML = `<option value="">Todas as categorias</option>` + categories.map(category => `<option>${escapeHTML(category)}</option>`).join("");
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
  addMessage(question, "user");
  input.value = "";
  const pending = addMessage("Analisando métricas atuais...", "assistant", true);
  try {
    const result = await api("/api/assistant", {
      method: "POST",
      body: JSON.stringify({ question })
    });
    pending.querySelector("p").textContent = result.answer;
  } catch (error) {
    pending.querySelector("p").textContent = `Não consegui concluir a análise: ${error.message}`;
  }
}

function addMessage(text, type, pending = false) {
  const row = document.createElement("div");
  row.className = `message ${type === "user" ? "user-message" : "assistant-message"}`;
  row.innerHTML = `<span class="message-avatar">${type === "user" ? escapeHTML(state.user.slice(0,1).toUpperCase()) : "M"}</span><div>${pending ? "" : `<strong>${type === "user" ? "Você" : "MNO Insights"}</strong>`}<p>${escapeHTML(text)}</p></div>`;
  $("assistant-conversation").append(row);
  $("assistant-conversation").scrollTop = $("assistant-conversation").scrollHeight;
  return row;
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
  $("terminal-frame").src = "/terminal/";
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
