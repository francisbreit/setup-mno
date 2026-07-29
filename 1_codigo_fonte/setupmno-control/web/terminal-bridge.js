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

  function terminal() {
    return window.term && typeof window.term.input === "function" ? window.term : null;
  }

  function reconnectOverlayVisible() {
    return Array.from(document.querySelectorAll(".xterm div")).some(element =>
      /Press.+Reconnect/i.test(element.textContent || "")
    );
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

  function mountTouchbar() {
    if (!window.matchMedia("(max-width: 650px), (pointer: coarse)").matches) return;

    const style = document.createElement("style");
    style.textContent = `
      body.setupmno-touch-terminal #terminal-container {
        height: calc(100% - 58px);
        margin: 58px auto 0;
      }
      #setupmno-terminal-touchbar {
        position: fixed;
        z-index: 2147483647;
        top: 0;
        right: 0;
        left: 0;
        display: flex;
        align-items: center;
        gap: 6px;
        height: 58px;
        box-sizing: border-box;
        padding: max(7px, env(safe-area-inset-top)) 8px 7px;
        overflow-x: auto;
        border-top: 1px solid rgba(255,255,255,.14);
        background: #10141a;
        scrollbar-width: none;
      }
      #setupmno-terminal-touchbar::-webkit-scrollbar { display: none; }
      #setupmno-terminal-touchbar button {
        min-width: 48px;
        min-height: 42px;
        flex: 1 0 48px;
        padding: 0 10px;
        border: 1px solid rgba(255,255,255,.15);
        border-radius: 9px;
        color: #f2f4f7;
        background: #1b212a;
        font: 800 13px system-ui, sans-serif;
        touch-action: manipulation;
      }
      #setupmno-terminal-touchbar button:active {
        border-color: rgba(255,122,26,.75);
        background: #ff7a1a;
      }
      #setupmno-terminal-touch-status {
        min-width: 72px;
        color: #f5c451;
        font: 800 9px system-ui, sans-serif;
        white-space: nowrap;
      }
      #setupmno-terminal-touch-status.ready { color: #31d98b; }
      @media (max-width: 480px) and (orientation: portrait) {
        body.setupmno-touch-terminal #terminal-container {
          height: calc(100% - 52px);
          margin-top: 52px;
        }
        #setupmno-terminal-touchbar {
          gap: 3px;
          height: 52px;
          padding: max(5px, env(safe-area-inset-top)) 4px 5px;
          overflow-x: hidden;
        }
        #setupmno-terminal-touchbar button {
          min-width: 30px;
          min-height: 40px;
          flex: 1 1 30px;
          padding: 0 3px;
          border-radius: 7px;
          font-size: 11px;
        }
        #setupmno-terminal-touchbar button[data-key="Enter"] {
          min-width: 43px;
          flex-grow: 1.35;
          font-size: 10px;
        }
        #setupmno-terminal-touch-status {
          min-width: 14px;
          width: 14px;
          max-width: 14px;
          overflow: hidden;
          color: #f5c451;
          font-size: 0;
        }
        #setupmno-terminal-touch-status::before {
          content: "●";
          font-size: 10px;
        }
      }
    `;
    document.head.append(style);

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
    });
    document.body.append(touchbar);
    document.body.classList.add("setupmno-touch-terminal");
  }

  function updateStatus(ready, label = "") {
    const status = document.getElementById("setupmno-terminal-touch-status");
    if (!status) return;
    status.classList.toggle("ready", ready);
    status.textContent = label || (ready ? "Touch pronto" : "Aguardando…");
  }

  mountTouchbar();

  let attempts = 0;
  const readyTimer = window.setInterval(() => {
    attempts += 1;
    if (terminal()) {
      window.clearInterval(readyTimer);
      updateStatus(true);
      window.term.fit?.();
    } else if (attempts >= 120) {
      window.clearInterval(readyTimer);
      updateStatus(false);
    }
  }, 250);

  window.setInterval(() => {
    if (reconnectOverlayVisible()) {
      updateStatus(false, "Enter para reconectar");
    }
  }, 500);

  let resizeTimer = 0;
  window.addEventListener("resize", () => {
    window.clearTimeout(resizeTimer);
    resizeTimer = window.setTimeout(() => window.term?.fit?.(), 120);
  });
})();
