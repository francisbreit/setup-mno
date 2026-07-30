"use strict";

const assert = require("node:assert/strict");

require("./web/markdown.js");

const { render } = globalThis.SetupMNOMarkdown;

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

const malicious = render('**seguro** <img src=x onerror="alert(1)"> <script>alert(2)</script>');
assert.match(malicious, /<strong>seguro<\/strong>/);
assert.doesNotMatch(malicious, /<img|<script|onerror="/);
assert.match(malicious, /&lt;img/);

console.log("Markdown seguro validado.");
