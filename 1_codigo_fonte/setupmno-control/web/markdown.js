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
      if (line[index] === "[") {
        const closeBracket = line.indexOf("](", index + 1);
        if (closeBracket > index + 1) {
          const closeParen = line.indexOf(")", closeBracket + 2);
          if (closeParen > closeBracket + 2) {
            const label = line.slice(index + 1, closeBracket);
            const target = line.slice(closeBracket + 2, closeParen).trim();
            if (/^(?:https?:\/\/|#|\/)/i.test(target)) {
              flushPlain();
              const isExternal = /^https?:\/\//i.test(target);
              const extraAttrs = isExternal ? ' target="_blank" rel="noopener noreferrer"' : '';
              output += `<a href="${escapeHTML(target)}" class="assistant-action-link"${extraAttrs}>${escapeHTML(label)}</a>`;
              index = closeParen + 1;
              continue;
            }
          }
        }
      }
      plain += line[index];
      index++;
    }
    flushPlain();
    return output;
  }

  function render(markdown) {
    const lines = String(markdown ?? "").replace(/\r\n?/g, "\n").split("\n");
    const output = [];
    let listOpen = false;
    function closeList() {
      if (!listOpen) return;
      output.push("</ul>");
      listOpen = false;
    }
    for (const line of lines) {
      const heading = /^(#{1,3})\s+(.+)$/.exec(line);
      const listItem = /^\s*(?:[-*•])\s+(.+)$/.exec(line);
      if (heading) {
        closeList();
        const level = Math.min(heading[1].length + 2, 5);
        output.push(`<h${level}>${renderInline(heading[2])}</h${level}>`);
      } else if (listItem) {
        if (!listOpen) {
          output.push("<ul>");
          listOpen = true;
        }
        output.push(`<li>${renderInline(listItem[1])}</li>`);
      } else {
        closeList();
        output.push(line.trim() ? renderInline(line) : "");
      }
    }
    closeList();
    return output.join("\n");
  }

  global.SetupMNOMarkdown = Object.freeze({ render });
})(typeof window !== "undefined" ? window : globalThis);
