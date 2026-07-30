(function (global) {
  "use strict";

  function escapeHTML(value) {
    return String(value ?? "").replace(/[&<>"']/g, character => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;"
    })[character]);
  }

  function renderInline(line) {
    let output = "";
    let plain = "";

    function flushPlain() {
      if (!plain) return;
      output += escapeHTML(plain);
      plain = "";
    }

    for (let index = 0; index < line.length;) {
      if (line.startsWith("**", index)) {
        const end = line.indexOf("**", index + 2);
        if (end > index + 2) {
          flushPlain();
          output += `<strong>${escapeHTML(line.slice(index + 2, end))}</strong>`;
          index = end + 2;
          continue;
        }
      }
      if (line[index] === "`") {
        const end = line.indexOf("`", index + 1);
        if (end > index + 1) {
          flushPlain();
          output += `<code>${escapeHTML(line.slice(index + 1, end))}</code>`;
          index = end + 1;
          continue;
        }
      }
      plain += line[index];
      index++;
    }
    flushPlain();
    return output;
  }

  function render(markdown) {
    return String(markdown ?? "")
      .replace(/\r\n?/g, "\n")
      .split("\n")
      .map(renderInline)
      .join("\n");
  }

  global.SetupMNOMarkdown = Object.freeze({ render });
})(typeof window !== "undefined" ? window : globalThis);
