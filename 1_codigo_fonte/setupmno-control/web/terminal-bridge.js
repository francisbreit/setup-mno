(() => {
  "use strict";

  const allowedSequences = Object.freeze({
    Escape: "\u001b",
    Tab: "\t",
    ArrowLeft: "\u001b[D",
    ArrowUp: "\u001b[A",
    ArrowDown: "\u001b[B",
    ArrowRight: "\u001b[C",
    Enter: "\r"
  });
  const terminalTheme = Object.freeze({
    background: "#000000",
    foreground: "#f5f7fa",
    cursor: "#ff7214",
    cursorAccent: "#000000",
    selectionBackground: "#7a3b18",
    black: "#000000",
    red: "#ff5a67",
    green: "#21d49a",
    yellow: "#f5c451",
    blue: "#64a8ff",
    magenta: "#d18cff",
    cyan: "#55d8e8",
    white: "#dce3ed",
    brightBlack: "#687384",
    brightRed: "#ff7a84",
    brightGreen: "#58e3b3",
    brightYellow: "#ffdc7b",
    brightBlue: "#8abfff",
    brightMagenta: "#e1adff",
    brightCyan: "#84e9f3",
    brightWhite: "#ffffff"
  });

  let resizeTimer = 0;
  let fitTimers = [];
  let themeApplied = false;

  function terminal() {
    return window.term && typeof window.term.input === "function" ? window.term : null;
  }

  function touchLayout() {
    return window.matchMedia("(max-width: 650px), (pointer: coarse)").matches;
  }

  function reconnectOverlayVisible() {
    return Array.from(document.querySelectorAll(".xterm div")).some(element =>
      /Press.+Reconnect/i.test(element.textContent || "")
    );
  }

  function applyTerminalPresentation(activeTerminal) {
    if (!activeTerminal) return;
    activeTerminal.options.theme = terminalTheme;
    activeTerminal.options.scrollback = 2000;
    activeTerminal.options.scrollOnUserInput = false;
    activeTerminal.options.fontFamily = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace";
    if (touchLayout()) {
      activeTerminal.options.fontSize = window.matchMedia("(orientation: portrait)").matches ? 10 : 11;
      activeTerminal.options.lineHeight = 1.05;
    }
    themeApplied = true;
  }

  function fitTerminal() {
    const activeTerminal = terminal();
    const container = document.getElementById("terminal-container");
    if (!activeTerminal || !container || container.clientWidth < 40 || container.clientHeight < 40) {
      return false;
    }
    applyTerminalPresentation(activeTerminal);
    try {
      activeTerminal.fit?.();
      if (Number.isInteger(activeTerminal.rows) && activeTerminal.rows > 0) {
        activeTerminal.refresh?.(0, activeTerminal.rows - 1);
      }
      return true;
    } catch {
      return false;
    }
  }

  function scheduleFit() {
    window.clearTimeout(resizeTimer);
    resizeTimer = window.setTimeout(fitTerminal, 30);
    fitTimers.forEach(window.clearTimeout);
    fitTimers = [80, 180, 360, 700].map(delay => window.setTimeout(fitTerminal, delay));
  }

  function reconnectTerminal() {
    const activeTerminal = terminal();
    const textarea = document.querySelector(".xterm-helper-textarea");
    if (!activeTerminal || !textarea) return false;
    activeTerminal.focus();
    textarea.focus();
    textarea.dispatchEvent(new KeyboardEvent("keydown", {
      key: "Enter",
      code: "Enter",
      keyCode: 13,
      which: 13,
      bubbles: true,
      cancelable: true
    }));
    window.setTimeout(scheduleFit, 120);
    return true;
  }

  function sendKey(key) {
    const activeTerminal = terminal();
    const sequence = allowedSequences[key];
    if (!sequence || !activeTerminal) return false;
    if (key === "Enter" && reconnectOverlayVisible()) {
      updateStatus(false, "Reconectando…");
      return reconnectTerminal();
    }
    activeTerminal.focus();
    activeTerminal.input(sequence, true);
    return true;
  }

  function updateStatus(ready, label = "") {
    const status = document.getElementById("setupmno-terminal-touch-status");
    if (!status) return;
    status.classList.toggle("ready", ready);
    status.textContent = label || (ready ? "Touch pronto" : "Aguardando…");
  }

  function mountStyles() {
    const style = document.createElement("style");
    style.textContent = `
      :root { color-scheme: dark; background: #000; }
      html, body {
        width: 100%;
        height: 100%;
        margin: 0;
        overflow: hidden;
        overscroll-behavior: none;
        background: #000 !important;
      }
      body #terminal-container {
        position: fixed;
        inset: 0;
        box-sizing: border-box;
        width: auto !important;
        max-width: 100%;
        height: auto !important;
        margin: 0 !important;
        overflow: hidden;
        background: #000 !important;
      }
      #terminal-container .xterm {
        width: 100%;
        height: 100%;
        box-sizing: border-box;
        background: #000 !important;
      }
      #terminal-container .xterm-viewport {
        max-width: 100%;
        overflow-x: hidden !important;
        overflow-y: auto !important;
        overscroll-behavior: contain;
        touch-action: pan-y;
        background: #000 !important;
      }
      body.setupmno-touch-terminal {
        --setupmno-touchbar-height: calc(54px + env(safe-area-inset-top));
      }
      body.setupmno-touch-terminal #terminal-container {
        top: var(--setupmno-touchbar-height);
      }
      #setupmno-terminal-touchbar {
        position: fixed;
        z-index: 2147483647;
        top: 0;
        right: 0;
        left: 0;
        display: grid;
        grid-template-columns: minmax(62px,.9fr) repeat(6,minmax(38px,1fr)) minmax(54px,1.15fr) minmax(42px,.9fr);
        align-items: stretch;
        gap: 5px;
        height: var(--setupmno-touchbar-height);
        box-sizing: border-box;
        padding: max(6px,env(safe-area-inset-top)) max(7px,env(safe-area-inset-right)) 6px max(7px,env(safe-area-inset-left));
        overflow: hidden;
        border-bottom: 1px solid rgba(255,255,255,.16);
        background: #10141b;
      }
      #setupmno-terminal-touchbar button {
        min-width: 0;
        min-height: 40px;
        padding: 0 4px;
        border: 1px solid rgba(255,255,255,.18);
        border-radius: 9px;
        color: #f5f7fa;
        background: #1b222c;
        font: 800 12px system-ui, sans-serif;
        touch-action: manipulation;
      }
      #setupmno-terminal-touchbar button:active {
        border-color: #ff9a52;
        color: #05070a;
        background: #ff7214;
      }
      #setupmno-terminal-touch-status {
        min-width: 0;
        align-self: center;
        overflow: hidden;
        color: #f5c451;
        font: 800 9px system-ui, sans-serif;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      #setupmno-terminal-touch-status.ready { color: #21d49a; }
      @media (max-width: 480px) and (orientation: portrait) {
        body.setupmno-touch-terminal {
          --setupmno-touchbar-height: calc(50px + env(safe-area-inset-top));
        }
        #setupmno-terminal-touchbar {
          grid-template-columns: 14px repeat(6,minmax(0,1fr)) minmax(43px,1.25fr) minmax(34px,.9fr);
          gap: 3px;
          padding-right: max(4px,env(safe-area-inset-right));
          padding-left: max(4px,env(safe-area-inset-left));
        }
        #setupmno-terminal-touchbar button {
          min-height: 38px;
          padding: 0 2px;
          border-radius: 7px;
          font-size: 10px;
        }
        #setupmno-terminal-touch-status {
          width: 14px;
          font-size: 0;
        }
        #setupmno-terminal-touch-status::before {
          content: "●";
          font-size: 9px;
        }
      }
      @media (max-height: 520px) and (orientation: landscape) {
        body.setupmno-touch-terminal {
          --setupmno-touchbar-height: calc(46px + env(safe-area-inset-top));
        }
        #setupmno-terminal-touchbar {
          padding-top: max(4px,env(safe-area-inset-top));
          padding-bottom: 4px;
        }
        #setupmno-terminal-touchbar button { min-height: 34px; }
      }
    `;
    document.head.append(style);
  }

  function mountTouchbar() {
    if (!touchLayout()) return;
    const touchbar = document.createElement("div");
    touchbar.id = "setupmno-terminal-touchbar";
    touchbar.setAttribute("aria-label", "Controles touch do terminal");
    touchbar.innerHTML = `
      <span id="setupmno-terminal-touch-status">Aguardando…</span>
      <button type="button" data-key="Escape">Esc</button>
      <button type="button" data-key="Tab">Tab</button>
      <button type="button" data-key="ArrowLeft" aria-label="Seta para esquerda">←</button>
      <button type="button" data-key="ArrowUp" aria-label="Seta para cima">↑</button>
      <button type="button" data-key="ArrowDown" aria-label="Seta para baixo">↓</button>
      <button type="button" data-key="ArrowRight" aria-label="Seta para direita">→</button>
      <button type="button" data-key="Enter">Enter</button>
      <button type="button" data-action="keyboard" aria-label="Abrir teclado virtual">⌨</button>
    `;
    touchbar.addEventListener("click", event => {
      const button = event.target.closest("button");
      if (!button) return;
      event.preventDefault();
      if (button.dataset.key && !sendKey(button.dataset.key)) {
        updateStatus(false);
        return;
      }
      if (button.dataset.action === "keyboard") {
        terminal()?.focus();
        document.querySelector(".xterm-helper-textarea")?.focus();
      }
      updateStatus(Boolean(terminal()));
      scheduleFit();
    });
    document.body.append(touchbar);
    document.body.classList.add("setupmno-touch-terminal");
  }

  mountStyles();
  mountTouchbar();
  scheduleFit();

  let attempts = 0;
  const readyTimer = window.setInterval(() => {
    attempts += 1;
    if (terminal()) {
      if (!themeApplied) applyTerminalPresentation(terminal());
      window.clearInterval(readyTimer);
      updateStatus(true);
      scheduleFit();
    } else if (attempts >= 240) {
      window.clearInterval(readyTimer);
      updateStatus(false);
    }
  }, 50);

  window.setInterval(() => {
    if (reconnectOverlayVisible()) {
      updateStatus(false, "Enter para reconectar");
    }
  }, 500);

  window.addEventListener("resize", scheduleFit, { passive: true });
  window.addEventListener("orientationchange", scheduleFit, { passive: true });
  window.addEventListener("pageshow", scheduleFit, { passive: true });
  window.visualViewport?.addEventListener("resize", scheduleFit, { passive: true });
  window.visualViewport?.addEventListener("scroll", scheduleFit, { passive: true });
  document.addEventListener("focusin", scheduleFit, { passive: true });
  document.addEventListener("focusout", scheduleFit, { passive: true });
  if (document.fonts?.ready) {
    document.fonts.ready.then(scheduleFit).catch(() => {});
  }

  if (window.ResizeObserver) {
    const observer = new ResizeObserver(scheduleFit);
    observer.observe(document.documentElement);
    const terminalContainer = document.getElementById("terminal-container");
    if (terminalContainer) observer.observe(terminalContainer);
    const touchbar = document.getElementById("setupmno-terminal-touchbar");
    if (touchbar) observer.observe(touchbar);
  }
  window.requestAnimationFrame(scheduleFit);
})();
