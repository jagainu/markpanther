/*
 * MarkPanther preview.js
 *
 * クラシックスクリプトとして書く（ES module ではない）。ブラウザでは
 * <script src="preview.js"> として読み込まれ window.MarkPanther を公開する。
 * bun test からは `require("./preview.js")` として読み込まれ、
 * ファイル末尾の module.exports 経由で内部の純粋関数群にアクセスできる。
 *
 * 依存ライブラリ（markdown-it 本体・各プラグイン・katex・js-yaml・DOMPurify・
 * highlight.js・Idiomorph・mermaid）はすべて vendor/ 以下にグローバル公開
 * （UMD）ビルドとして置かれていて、preview.html が <script> タグで
 * このファイルより先に読み込む想定。getGlobal() でそれらを参照する。
 * ただしテスト環境などグローバルに無い場合は tryRequire() で
 * 同じディレクトリ構成の vendor/ から直接 require するフォールバックを持つ
 * （ブラウザでは `require` が存在しないため常に no-op）。
 */

/* ------------------------------------------------------------------ *
 * 小さなユーティリティ
 * ------------------------------------------------------------------ */

function getGlobal(name) {
  if (typeof window !== "undefined" && typeof window[name] !== "undefined") {
    return window[name];
  }
  if (
    typeof globalThis !== "undefined" &&
    typeof globalThis[name] !== "undefined"
  ) {
    return globalThis[name];
  }
  return undefined;
}

function tryRequire(relativePath) {
  if (typeof require !== "function") return undefined;
  try {
    return require(relativePath);
  } catch (e) {
    return undefined;
  }
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function escapeAttr(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function decodeHtmlEntities(s) {
  return String(s)
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'");
}

/* ------------------------------------------------------------------ *
 * options
 * ------------------------------------------------------------------ */

function normalizeOptions(options) {
  options = options || {};
  function withDefault(key, def) {
    return options[key] === undefined ? def : !!options[key];
  }
  return {
    smartypants: withDefault("smartypants", false),
    superscript: withDefault("superscript", false),
    highlightMark: withDefault("highlightMark", true),
    hardLineBreaks: withDefault("hardLineBreaks", true),
    syntaxHighlighting: withDefault("syntaxHighlighting", true),
    codeLineNumbers: withDefault("codeLineNumbers", false),
    math: withDefault("math", true),
    frontmatter: withDefault("frontmatter", true),
    tocToken: withDefault("tocToken", true),
    taskList: withDefault("taskList", true),
    mermaid: withDefault("mermaid", true),
    markChanges: withDefault("markChanges", false),
    lineNumbers: withDefault("lineNumbers", false),
    changeBand: withDefault("changeBand", false),
  };
}

/* ------------------------------------------------------------------ *
 * frontmatter
 * ------------------------------------------------------------------ */

function splitFrontmatter(markdown, enabled) {
  var result = {
    hasFrontmatter: false,
    frontmatterRaw: null,
    body: markdown == null ? "" : markdown,
    lineOffset: 0,
  };
  if (!enabled || typeof markdown !== "string") return result;

  var lines = markdown.split(/\r\n|\r|\n/);
  if (lines.length === 0 || lines[0].replace(/^﻿/, "").trim() !== "---")
    return result;

  var closingIndex = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() === "---") {
      closingIndex = i;
      break;
    }
  }
  if (closingIndex === -1) return result;

  result.hasFrontmatter = true;
  result.frontmatterRaw = lines.slice(1, closingIndex).join("\n");
  result.body = lines.slice(closingIndex + 1).join("\n");
  result.lineOffset = closingIndex + 1;
  return result;
}

function formatFrontmatterValue(v) {
  if (v === null || v === undefined) return "";
  if (typeof v === "object") return escapeHtml(JSON.stringify(v));
  return escapeHtml(String(v));
}

function renderFrontmatterTable(data) {
  var rows = "";
  if (data && typeof data === "object" && !Array.isArray(data)) {
    Object.keys(data).forEach(function (key) {
      rows +=
        "<tr><th>" +
        escapeHtml(key) +
        "</th><td>" +
        formatFrontmatterValue(data[key]) +
        "</td></tr>";
    });
  } else {
    rows = '<tr><td colspan="2">' + formatFrontmatterValue(data) + "</td></tr>";
  }
  return (
    '<table class="frontmatter-table" data-line="0"><tbody>' +
    rows +
    "</tbody></table>\n"
  );
}

function renderFrontmatterBlock(raw) {
  var jsyaml =
    getGlobal("jsyaml") || tryRequire("./vendor/js-yaml/js-yaml.min.js");
  var data;
  var ok = !!jsyaml;
  if (ok) {
    try {
      data = jsyaml.load(raw);
    } catch (e) {
      ok = false;
    }
  }
  if (!ok) {
    return (
      '<pre class="frontmatter-raw" data-line="0">' +
      escapeHtml(raw) +
      "</pre>\n"
    );
  }
  return renderFrontmatterTable(data);
}

/* ------------------------------------------------------------------ *
 * heading slug / TOC
 * ------------------------------------------------------------------ */

function slugify(text) {
  var s = String(text == null ? "" : text)
    .toLowerCase()
    .trim();
  // Unicode の文字・数字・結合文字・アンダースコア・空白・ハイフン以外を除去
  s = s.replace(/[^\p{L}\p{N}\p{M}_\s-]/gu, "");
  s = s.replace(/\s+/g, "-");
  return s;
}

function createSlugger() {
  var counts = Object.create(null);
  return function (text) {
    var base = slugify(text);
    if (base === "") base = "section";
    if (!(base in counts)) {
      counts[base] = 0;
      return base;
    }
    counts[base] += 1;
    return base + "-" + counts[base];
  };
}

/**
 * headings: [{level, id, text}, ...] -> ネストした <ul><li> の TOC HTML
 */
function buildTocHtml(headings) {
  if (!headings || !headings.length) return '<ul class="toc-list"></ul>';
  var html = "";
  var levels = [];
  headings.forEach(function (h, idx) {
    if (idx === 0) {
      html += '<ul class="toc-list"><li>';
      levels.push(h.level);
    } else {
      var prev = levels[levels.length - 1];
      if (h.level > prev) {
        html += '<ul class="toc-list"><li>';
        levels.push(h.level);
      } else if (h.level === prev) {
        html += "</li><li>";
      } else {
        while (levels.length > 1 && levels[levels.length - 1] > h.level) {
          html += "</li></ul>";
          levels.pop();
        }
        html += "</li><li>";
        levels[levels.length - 1] = h.level;
      }
    }
    html +=
      '<a href="#' + escapeAttr(h.id) + '">' + escapeHtml(h.text) + "</a>";
  });
  while (levels.length) {
    html += "</li></ul>";
    levels.pop();
  }
  return html;
}

function computeInlineText(inlineToken) {
  if (!inlineToken || !inlineToken.children) return "";
  var text = "";
  for (var i = 0; i < inlineToken.children.length; i++) {
    var c = inlineToken.children[i];
    if (c.type === "text" || c.type === "code_inline") {
      text += c.content;
    } else if (c.type === "softbreak" || c.type === "hardbreak") {
      text += " ";
    }
  }
  return text;
}

function isTocPlaceholder(tokens, i) {
  return (
    !!tokens[i] &&
    tokens[i].type === "paragraph_open" &&
    !!tokens[i + 1] &&
    tokens[i + 1].type === "inline" &&
    tokens[i + 1].content.trim() === "[TOC]" &&
    !!tokens[i + 2] &&
    tokens[i + 2].type === "paragraph_close"
  );
}

function addHeadingIdAndTocRule(md) {
  md.core.ruler.push("markpanther_heading_toc", function (state) {
    var tokens = state.tokens;
    var slugger = createSlugger();
    var headings = [];
    var i;
    for (i = 0; i < tokens.length; i++) {
      if (tokens[i].type === "heading_open") {
        var level = parseInt(tokens[i].tag.slice(1), 10) || 1;
        var inline = tokens[i + 1];
        var text = computeInlineText(inline);
        var id = slugger(text);
        tokens[i].attrSet("id", id);
        headings.push({ level: level, id: id, text: text });
      }
    }

    var offset =
      state.env && typeof state.env.lineOffset === "number"
        ? state.env.lineOffset
        : 0;
    var tocHtml = null;
    for (i = 0; i < tokens.length; i++) {
      if (isTocPlaceholder(tokens, i)) {
        if (tocHtml === null) tocHtml = buildTocHtml(headings);
        var line = tokens[i].map ? tokens[i].map[0] + offset : offset;
        var htmlToken = new state.Token("html_block", "", 0);
        htmlToken.content =
          '<nav class="toc" data-line="' + line + '">' + tocHtml + "</nav>\n";
        htmlToken.map = tokens[i].map;
        htmlToken.block = true;
        tokens.splice(i, 3, htmlToken);
      }
    }
  });
}

/* ------------------------------------------------------------------ *
 * data-line 付与（frontmatter/TOC/fence を除く通常のブロックトークン）
 * ------------------------------------------------------------------ */

function addDataLineRule(md) {
  md.core.ruler.push("markpanther_data_line", function (state) {
    var offset =
      state.env && typeof state.env.lineOffset === "number"
        ? state.env.lineOffset
        : 0;
    var tokens = state.tokens;
    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i];
      if (t.map && t.block) {
        t.attrSet("data-line", String(t.map[0] + offset));
      }
    }
  });
}

/* ------------------------------------------------------------------ *
 * 画像パスの書き換え（markp://file/...）
 * ------------------------------------------------------------------ */

function normalizePath(p) {
  var isAbsolute = p.indexOf("/") === 0;
  var parts = p.split("/");
  var out = [];
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i];
    if (part === "" || part === ".") continue;
    if (part === "..") {
      if (out.length && out[out.length - 1] !== "..") {
        out.pop();
      } else if (!isAbsolute) {
        out.push("..");
      }
      // 絶対パスでルートより上に出ようとした場合は無視する
    } else {
      out.push(part);
    }
  }
  return (isAbsolute ? "/" : "") + out.join("/");
}

function joinPath(baseDir, rel) {
  if (rel.indexOf("/") === 0) return normalizePath(rel);
  var combined = String(baseDir).replace(/\/+$/, "") + "/" + rel;
  return normalizePath(combined);
}

var ABSOLUTE_URL_RE = /^[a-zA-Z][a-zA-Z0-9+.-]*:/;

/**
 * 画像 src の書き換え。docDir が null/undefined、または既に絶対URL
 * （http(s): / data: / その他スキーム付き）の場合は書き換えない。
 * 戻り値: { src, original } — original は書き換えた場合のみ元の値、
 * 書き換え不要な場合は null。
 */
function rewriteImageSrc(src, docDir) {
  if (typeof src !== "string" || src === "")
    return { src: src, original: null };
  if (docDir === null || docDir === undefined)
    return { src: src, original: null };
  if (ABSOLUTE_URL_RE.test(src)) return { src: src, original: null };

  // 他のツールが書き出した md は %E6%97%A5... のようにエンコード済みのことがある。
  // いったんデコードしてから組み立てないと二重エンコードになり、ファイルが見つからない。
  var decoded = safeDecodeURI(src);
  var normalized =
    decoded.indexOf("/") === 0 ? normalizePath(decoded) : joinPath(docDir, decoded);
  var rewritten = "markp://file/" + encodeURI(normalized);
  if (imageVersion > 0) rewritten += "?v=" + imageVersion;
  return { src: rewritten, original: src };
}

/** 不正なエスケープ（"100%.png" など）を含む場合は元の文字列のまま返す。 */
function safeDecodeURI(s) {
  try {
    return decodeURI(s);
  } catch (e) {
    return s;
  }
}

/**
 * ローカル画像の再取得用。⌘R（Reload from Disk）のたびに Swift 側が呼ぶ。
 * URL が変わるので、次の render の差分更新で <img> が読み直される。
 */
var imageVersion = 0;
function bumpImageVersion() {
  imageVersion += 1;
  brokenImageSources = {};
  return imageVersion;
}

var IMG_TAG_RE = /<img\b[^>]*>/gi;
var SRC_ATTR_RE = /\ssrc\s*=\s*("[^"]*"|'[^']*')/i;

/**
 * 完成済み HTML 文字列中の <img> タグの src をすべて書き換える。
 * markdown 記法の画像・生 HTML の画像の両方に効く（markdown-it 側では
 * normalizeLink を無効化して生パスを通しているため、ここで一元的に扱う）。
 */
function rewriteImagesInHtml(html, docDir) {
  if (docDir === null || docDir === undefined) return html;
  return html.replace(IMG_TAG_RE, function (imgTag) {
    var m = SRC_ATTR_RE.exec(imgTag);
    if (!m) return imgTag;
    var quote = m[1].charAt(0);
    var rawSrc = m[1].slice(1, -1);
    var decodedSrc = decodeHtmlEntities(rawSrc);
    var result = rewriteImageSrc(decodedSrc, docDir);
    if (result.original === null) return imgTag;

    var withNewSrc = imgTag.replace(
      SRC_ATTR_RE,
      " src=" + quote + escapeAttr(result.src) + quote,
    );
    var selfClosing = /\/\s*>$/.test(withNewSrc);
    var body = withNewSrc.slice(0, withNewSrc.length - (selfClosing ? 2 : 1));
    body += " data-original-src=" + quote + escapeAttr(decodedSrc) + quote;
    return body + (selfClosing ? " />" : ">");
  });
}

/* ------------------------------------------------------------------ *
 * シンタックスハイライト + 行番号
 * ------------------------------------------------------------------ */

/**
 * hljs が出力する <span class="...">...</span> だけからなる HTML を前提に、
 * 改行のたびにタグを閉じて再度開き直すことで、各行を独立した
 * <span class="line">...</span> に安全に分割する（複数行コメント等で
 * span がまたがっていても壊れない）。
 */
function wrapCodeLines(html) {
  var openTags = [];
  var lines = [];
  var currentLine = "";
  var i = 0;
  var n = html.length;
  while (i < n) {
    var ch = html.charAt(i);
    if (ch === "<") {
      var close = html.indexOf(">", i);
      if (close === -1) {
        currentLine += html.slice(i);
        break;
      }
      var tag = html.slice(i, close + 1);
      currentLine += tag;
      if (/^<\/span>/i.test(tag)) {
        openTags.pop();
      } else if (/^<span\b/i.test(tag)) {
        openTags.push(tag);
      }
      i = close + 1;
    } else if (ch === "\n") {
      for (var k = openTags.length - 1; k >= 0; k--) currentLine += "</span>";
      lines.push(currentLine);
      currentLine = openTags.join("");
      i++;
    } else {
      var next = i;
      while (
        next < n &&
        html.charAt(next) !== "<" &&
        html.charAt(next) !== "\n"
      )
        next++;
      currentLine += html.slice(i, next);
      i = next;
    }
  }
  lines.push(currentLine);
  return lines
    .map(function (line) {
      return '<span class="line">' + line + "</span>";
    })
    .join("\n");
}

function highlightCode(code, lang, options, line) {
  var attrLine = typeof line === "number" ? ' data-line="' + line + '"' : "";
  var langClass = lang ? " language-" + escapeAttr(lang) : "";
  var bodyHtml = null;

  if (options.syntaxHighlighting && lang) {
    var hljs =
      getGlobal("hljs") || tryRequire("./vendor/highlightjs/highlight.min.js");
    if (hljs) {
      try {
        if (hljs.getLanguage(lang)) {
          bodyHtml = hljs.highlight(code, {
            language: lang,
            ignoreIllegals: true,
          }).value;
        }
      } catch (e) {
        bodyHtml = null;
      }
    }
  }
  if (bodyHtml === null) {
    bodyHtml = escapeHtml(code);
  }
  if (options.codeLineNumbers) {
    bodyHtml = wrapCodeLines(bodyHtml);
  }
  var preClass =
    "code-block" + (options.codeLineNumbers ? " line-numbers" : "");
  return (
    '<pre class="' +
    preClass +
    '"' +
    attrLine +
    '><code class="hljs' +
    langClass +
    '">' +
    bodyHtml +
    "</code></pre>\n"
  );
}

/* ------------------------------------------------------------------ *
 * mermaid（遅延ロード + キャッシュ）
 * ------------------------------------------------------------------ */

var mermaidCache = Object.create(null);
var mermaidScriptPromise = null;
var mermaidSeq = 0;

/**
 * mermaid のソースは複数行のテキストなので、そのまま HTML 属性値へ埋め込むと
 * 属性値中の生の改行がサニタイズ/パース経路（DOMPurify + happy-dom や
 * WKWebView の HTML パーサ）でラップ要素ごと落とされる事故につながる
 * （実機検証で確認済み）。1行のセーフな文字集合（base64）にエンコードして
 * 属性へ格納し、読み出し側でデコードすることでこれを避ける。
 */
function base64EncodeUtf8(str) {
  var bytes = new TextEncoder().encode(str);
  var binary = "";
  for (var i = 0; i < bytes.length; i++)
    binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

function base64DecodeUtf8(b64) {
  var binary = atob(b64);
  var bytes = new Uint8Array(binary.length);
  for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

function renderMermaidBlock(source, line) {
  var trimmed = String(source).replace(/\n+$/, "");
  var attrLine = typeof line === "number" ? ' data-line="' + line + '"' : "";
  var encoded = base64EncodeUtf8(trimmed);
  var cached = mermaidCache[trimmed];
  if (cached !== undefined) {
    return (
      '<div class="mermaid-diagram" data-mermaid-source-b64="' +
      encoded +
      '"' +
      attrLine +
      ">" +
      cached +
      "</div>\n"
    );
  }
  return (
    '<div class="mermaid-diagram" data-mermaid-pending="true" data-mermaid-source-b64="' +
    encoded +
    '"' +
    attrLine +
    '><pre class="mermaid-source">' +
    escapeHtml(trimmed) +
    "</pre></div>\n"
  );
}

function prefersDark() {
  return (
    typeof window !== "undefined" &&
    !!window.matchMedia &&
    window.matchMedia("(prefers-color-scheme: dark)").matches
  );
}

function mermaidThemeVariables(dark) {
  var c = dark
    ? { fill: "#1c2128", border: "#444c56", line: "#768390", text: "#e6edf3", alt: "#22272e", note: "#2d333b", bg: "#0d1117" }
    : { fill: "#f6f8fa", border: "#c4ccd4", line: "#57606a", text: "#1f2328", alt: "#eef1f4", note: "#fff8c5", bg: "#ffffff" };
  return {
    darkMode: dark,
    background: c.bg,
    fontFamily: '-apple-system, BlinkMacSystemFont, "Hiragino Sans", "Helvetica Neue", sans-serif',
    fontSize: "14px",
    primaryColor: c.fill,
    primaryBorderColor: c.border,
    primaryTextColor: c.text,
    secondaryColor: c.alt,
    secondaryBorderColor: c.border,
    secondaryTextColor: c.text,
    tertiaryColor: c.alt,
    tertiaryBorderColor: c.border,
    tertiaryTextColor: c.text,
    lineColor: c.line,
    textColor: c.text,
    mainBkg: c.fill,
    nodeBorder: c.border,
    clusterBkg: c.alt,
    clusterBorder: c.border,
    edgeLabelBackground: c.bg,
    titleColor: c.text,
    actorBkg: c.fill,
    actorBorder: c.border,
    actorTextColor: c.text,
    actorLineColor: c.line,
    signalColor: c.line,
    signalTextColor: c.text,
    labelBoxBkgColor: c.fill,
    labelBoxBorderColor: c.border,
    labelTextColor: c.text,
    loopTextColor: c.text,
    noteBkgColor: c.note,
    noteBorderColor: c.border,
    noteTextColor: c.text,
    activationBkgColor: c.alt,
    activationBorderColor: c.border,
  };
}

function loadMermaidScript() {
  if (mermaidScriptPromise) return mermaidScriptPromise;
  mermaidScriptPromise = new Promise(function (resolve) {
    var existing = getGlobal("mermaid");
    if (existing) {
      resolve(existing);
      return;
    }
    var script = document.createElement("script");
    script.src = "vendor/mermaid/mermaid.min.js";
    script.onload = function () {
      var m = getGlobal("mermaid");
      if (m) {
        try {
          m.initialize({
            startOnLoad: false,
            securityLevel: "strict",
            // 既定テーマ（薄紫の塗り + 紫の枠）は本文の配色から浮くので、GitHub 風の本文に合わせた
            // ニュートラルな配色を base テーマの変数で与える。
            theme: "base",
            themeVariables: mermaidThemeVariables(prefersDark()),
          });
        } catch (e) {
          /* initialize failure is non-fatal; individual render() calls will surface errors */
        }
      }
      resolve(m || null);
    };
    script.onerror = function () {
      resolve(null);
    };
    document.head.appendChild(script);
  });
  return mermaidScriptPromise;
}

function renderOneMermaid(el, mermaid) {
  var encoded = el.getAttribute("data-mermaid-source-b64") || "";
  var source = "";
  try {
    source = base64DecodeUtf8(encoded);
  } catch (e) {
    source = "";
  }
  var id = "markpanther-mermaid-" + ++mermaidSeq;
  var renderResult;
  try {
    renderResult = mermaid.render(id, source);
  } catch (e) {
    renderResult = Promise.reject(e);
  }
  return Promise.resolve(renderResult)
    .then(function (result) {
      var svg = result && result.svg ? result.svg : "";
      mermaidCache[source] = svg;
      el.innerHTML = svg;
      el.removeAttribute("data-mermaid-pending");
    })
    .catch(function (err) {
      var msg = err && err.message ? err.message : String(err);
      el.innerHTML =
        '<div class="mermaid-error"><p class="mermaid-error-message">' +
        escapeHtml(msg) +
        '</p><pre class="mermaid-source">' +
        escapeHtml(source) +
        "</pre></div>";
      el.removeAttribute("data-mermaid-pending");
    });
}

function processMermaidBlocks(contentEl) {
  var pendingEls = contentEl.querySelectorAll('[data-mermaid-pending="true"]');
  if (!pendingEls.length) return Promise.resolve();
  return loadMermaidScript().then(function (mermaid) {
    if (!mermaid) return;
    var tasks = [];
    for (var i = 0; i < pendingEls.length; i++) {
      tasks.push(renderOneMermaid(pendingEls[i], mermaid));
    }
    return Promise.all(tasks);
  });
}

/* ------------------------------------------------------------------ *
 * markdown-it の組み立て
 * ------------------------------------------------------------------ */

function buildMarkdownIt(options) {
  var markdownItFactory =
    getGlobal("markdownit") ||
    tryRequire("./vendor/markdown-it/markdown-it.min.js");
  var md = markdownItFactory({
    html: true,
    linkify: true,
    typographer: options.smartypants,
    breaks: options.hardLineBreaks,
  });

  // リンク/画像パスの正規化は markdown-it に任せず、自前の
  // rewriteImagesInHtml に一元化する（mdurl の二重エンコード事故を避けるため）。
  md.normalizeLink = function (url) {
    return url;
  };
  md.validateLink = function () {
    return true;
  };

  if (options.taskList) {
    var taskLists =
      getGlobal("markdownitTaskLists") ||
      tryRequire(
        "./vendor/markdown-it-task-lists/markdown-it-task-lists.min.js",
      );
    if (taskLists) md.use(taskLists, { enabled: false });
  }

  var footnote =
    getGlobal("markdownitFootnote") ||
    tryRequire("./vendor/markdown-it-footnote/markdown-it-footnote.min.js");
  if (footnote) md.use(footnote);

  if (options.superscript) {
    var sup =
      getGlobal("markdownitSup") ||
      tryRequire("./vendor/markdown-it-sup/markdown-it-sup.min.js");
    if (sup) md.use(sup);
  }

  if (options.highlightMark) {
    var mark =
      getGlobal("markdownitMark") ||
      tryRequire("./vendor/markdown-it-mark/markdown-it-mark.min.js");
    if (mark) md.use(mark);
  }

  if (options.math) {
    var texmath =
      getGlobal("texmath") ||
      tryRequire("./vendor/markdown-it-texmath/texmath.js");
    var katex = getGlobal("katex") || tryRequire("./vendor/katex/katex.min.js");
    if (texmath && katex) {
      md.use(texmath, {
        engine: katex,
        delimiters: "dollars",
        katexOptions: { throwOnError: false },
      });
    }
  }

  addDataLineRule(md);
  if (options.tocToken) {
    addHeadingIdAndTocRule(md);
  }

  md.renderer.rules.fence = function (tokens, idx, _opts, env) {
    var token = tokens[idx];
    var info = (token.info || "").trim();
    var langName = info.split(/\s+/)[0] || "";
    var offset = env && typeof env.lineOffset === "number" ? env.lineOffset : 0;
    var line = token.map ? token.map[0] + offset : offset;
    if (options.mermaid && langName.toLowerCase() === "mermaid") {
      return renderMermaidBlock(token.content, line);
    }
    return highlightCode(token.content, langName, options, line);
  };

  return md;
}

/* ------------------------------------------------------------------ *
 * markdown -> HTML（DOM 不要、純粋な文字列処理）
 * ------------------------------------------------------------------ */

function buildHtmlFromMarkdown(markdown, options, docDir) {
  var fm = splitFrontmatter(markdown, options.frontmatter);
  var frontmatterHtml = fm.hasFrontmatter
    ? renderFrontmatterBlock(fm.frontmatterRaw)
    : "";

  var md = buildMarkdownIt(options);
  var env = { docDir: docDir, lineOffset: fm.lineOffset };
  var bodyHtml = md.render(fm.body, env);
  bodyHtml = rewriteImagesInHtml(bodyHtml, docDir);

  return frontmatterHtml + bodyHtml;
}

/* ------------------------------------------------------------------ *
 * sanitize
 * ------------------------------------------------------------------ */

// DOMPurify のデフォルト ALLOWED_URI_REGEXP に markp: スキームを足したもの。
var MARKPANTHER_URI_REGEXP =
  /^(?:(?:(?:f|ht)tps?|mailto|tel|callto|sms|cid|xmpp|markp|data):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i;

function sanitizeHtml(html) {
  var DOMPurify =
    getGlobal("DOMPurify") || tryRequire("./vendor/dompurify/purify.min.js");
  if (!DOMPurify || typeof DOMPurify.sanitize !== "function") {
    // DOMPurify が使えない状況（本来起こらない）では安全側に倒して丸ごとエスケープする。
    return escapeHtml(html);
  }
  return DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true, svg: true, svgFilters: true, mathMl: true },
    ALLOWED_URI_REGEXP: MARKPANTHER_URI_REGEXP,
    ADD_TAGS: ["input"],
    ADD_ATTR: [
      "type",
      "checked",
      "disabled",
      "target",
      "data-line",
      "data-original-src",
      "data-mermaid-source-b64",
      "data-mermaid-pending",
    ],
  });
}

/* ------------------------------------------------------------------ *
 * 変更箇所ハイライト（markChanges）
 * ------------------------------------------------------------------ */

var CHANGE_MARK_ATTR = "data-markpanther-changed-pending";
var CHANGE_FADE_MS = 4000;
// 直前の render() で #content に反映された内容の「比較単位」署名一覧。
// markChanges の値に関わらず毎回更新し、markChanges=true のときだけ
// これと比較して新規/変更ユニットを検出する（そうしないと、false の
// レンダーを挟んだ後に true が来たときの比較対象が古くなってしまうため）。
/**
 * 変更の印は「基準の版」との差分として積み上げる。Claude Code は同じファイルを
 * 何度も上書きするので、毎回「直前の版との差分」に置き換えると、いつ何が変わったのか
 * 追えなくなる。基準を据え置けば、リセットするまでの変更がすべて残る。
 *
 * 基準を引き直すのは3つ: × で消したとき／自分で編集したとき／開き直したとき。
 */
var baselineSignatures = null;
var baselineRecords = null;
/** 直前の描画。自分の編集を見分けるのと、今回ぶんだけ光らせるのに使う */
var previousUnitSignatures = null;
var previousUnitRecords = null;

/**
 * 「比較単位」の粒度規則: ul/ol は li 単位、table は tr 単位、
 * blockquote は直下の子単位まで降りる。それ以外の要素はそのまま
 * 単体の単位として扱う（再帰的に適用されるので、blockquote の直下の子が
 * さらに ul であればそれも li 単位まで分解される）。
 */
function decomposeIntoUnits(el) {
  var tag = el.tagName;
  if (tag === "UL" || tag === "OL") {
    var items = [];
    for (var i = 0; i < el.children.length; i++) {
      if (el.children[i].tagName === "LI") {
        items = items.concat(decomposeIntoUnits(el.children[i]));
      }
    }
    return items.length ? items : [el];
  }
  if (tag === "TABLE") {
    var rows = el.querySelectorAll("tr");
    if (rows.length) {
      var out = [];
      for (var r = 0; r < rows.length; r++) out.push(rows[r]);
      return out;
    }
    return [el];
  }
  if (tag === "BLOCKQUOTE") {
    var children = [];
    for (var c = 0; c < el.children.length; c++) {
      children = children.concat(decomposeIntoUnits(el.children[c]));
    }
    return children.length ? children : [el];
  }
  return [el];
}

/** container（#content または detached な複製）直下の子を比較単位へ分解する。 */
function collectUnits(containerEl) {
  var units = [];
  for (var i = 0; i < containerEl.children.length; i++) {
    units = units.concat(decomposeIntoUnits(containerEl.children[i]));
  }
  return units;
}

/**
 * 1つの比較単位の「内容の同一性」を表す署名を作る。
 * - data-line（行番号由来。行がずれただけの無関係な変更を無視するため）は
 *   自分自身にも子孫にも残さない。
 * - mermaid の図は、highlight.js とは違い非同期に「pending -> 解決済み
 *   SVG」へ後から書き換わるため、DOM の見た目ではなく
 *   data-mermaid-source-b64（fence の中身そのもの）だけを署名にする
 *   （そうしないと mermaid が解決しただけで「変更」扱いになってしまう）。
 */
function computeUnitSignature(el) {
  if (el.classList && el.classList.contains("mermaid-diagram")) {
    return "mermaid:" + (el.getAttribute("data-mermaid-source-b64") || "");
  }
  var clone = el.cloneNode(true);
  clone.removeAttribute("data-line");
  var lineAttrEls = clone.querySelectorAll("[data-line]");
  for (var i = 0; i < lineAttrEls.length; i++) {
    lineAttrEls[i].removeAttribute("data-line");
  }
  return clone.outerHTML;
}

/**
 * containerEl（sanitize 後・morph 前の detached な要素）を走査して比較単位の
 * 署名一覧を作る。markChanges が有効かつ前回の署名があるときは、前回の
 * 署名の多重集合に無い単位へ一時マーカー属性（CHANGE_MARK_ATTR）を付ける。
 *
 * 戻り値: { signatures: string[], changedCount: number }
 */
/**
 * 直近の外部更新で変わったユニットの署名（多重集合）。外部更新ではない再描画（モード切替・設定変更）でも
 * 印を付け直せるように覚えておき、次の外部更新で置き換える。
 */
/**
 * 直近の外部更新で変わったユニットの一覧 [{sig, added}]。added は、そのユニットのテキスト内で「前の版から
 * 追加された部分」の範囲 [[start, end], ...]（対応する前の版が見つからない新規ブロックは空）。
 * 外部更新ではない再描画（モード切替・設定変更）でも印を付け直せるように覚えておき、次の外部更新で置き換える。
 */
var persistentChanges = null;
/** 直近の描画で印が付いた場所のソース行（サイドバー用） */
var lastChangedLines = [];
/** ブロックごと消えた箇所。次の外部更新まで持ち越す（persistentChanges と対） */
var persistentGaps = null;
var CHANGE_KEEP_ATTR = "data-markpanther-changed-keep";

/** 行内の差分用のトークン分割。和文は 1 文字ずつ、英数字は単語単位、空白は連続でひとまとめ。 */
var DIFF_TOKEN_RE = /[\u3040-\u30ff\u3400-\u9fff\uff00-\uffef]|[A-Za-z0-9_]+|\s+|[^\sA-Za-z0-9_]/g;
var DIFF_MAX_CELLS = 1000000;

function tokenizeForDiff(text) {
  var tokens = [];
  var m;
  DIFF_TOKEN_RE.lastIndex = 0;
  while ((m = DIFF_TOKEN_RE.exec(text)) !== null) {
    tokens.push({ text: m[0], start: m.index, end: m.index + m[0].length });
  }
  return tokens;
}

/**
 * oldText → newText で「追加された部分」を newText 上の範囲で返す。{ranges, similarity}。
 * similarity は 0〜1（トークンの一致率）。ブロックの対応付けに使う。
 */
/** 削除の記録。同じ位置に続く削除はひとつにまとめる。空白だけのものは捨てる。 */
function pushRemoval(removals, at, text) {
  if (!text) return;
  var last = removals[removals.length - 1];
  if (last && last.at === at) last.text += text;
  else removals.push({ at: at, text: text });
}

function trimRemovals(removals) {
  return removals.filter(function (r) {
    return /\S/.test(r.text);
  });
}

function diffTexts(oldText, newText) {
  if (oldText === newText) return { ranges: [], similarity: 1, removals: [] };
  var a = tokenizeForDiff(oldText);
  var b = tokenizeForDiff(newText);
  if (!a.length || !b.length) {
    // 片方が空。新しい方が空なら全部消えたことになる
    var gone = b.length ? [] : trimRemovals([{ at: 0, text: oldText }]);
    return { ranges: [], similarity: 0, removals: gone };
  }

  if (a.length * b.length > DIFF_MAX_CELLS) {
    // 大きすぎるときは、共通の先頭・末尾を除いた中間だけを「追加」とみなす
    var prefix = 0;
    var maxPrefix = Math.min(oldText.length, newText.length);
    while (prefix < maxPrefix && oldText.charCodeAt(prefix) === newText.charCodeAt(prefix)) prefix++;
    var suffix = 0;
    var maxSuffix = maxPrefix - prefix;
    while (
      suffix < maxSuffix &&
      oldText.charCodeAt(oldText.length - 1 - suffix) === newText.charCodeAt(newText.length - 1 - suffix)
    ) suffix++;
    var end = newText.length - suffix;
    var droppedMiddle = oldText.slice(prefix, oldText.length - suffix);
    return {
      ranges: end > prefix ? [[prefix, end]] : [],
      similarity: (prefix + suffix) / Math.max(oldText.length, newText.length),
      removals: trimRemovals([{ at: prefix, text: droppedMiddle }]),
    };
  }

  // dp[i][j] = a[i:] と b[j:] の LCS 長。先頭から辿ることで、同じトークンが複数あるとき手前を優先して対応させる
  var n = a.length;
  var m = b.length;
  var width = m + 1;
  var dp = new Uint32Array((n + 1) * width);
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i * width + j] =
        a[i].text === b[j].text
          ? dp[(i + 1) * width + j + 1] + 1
          : Math.max(dp[(i + 1) * width + j], dp[i * width + j + 1]);
    }
  }
  var ranges = [];
  var removals = [];
  var matchedChars = 0;
  var x = 0;
  var y = 0;
  while (y < m) {
    if (x < n && a[x].text === b[y].text) {
      matchedChars += b[y].text.length;
      x++;
      y++;
    } else if (x < n && dp[(x + 1) * width + y] >= dp[x * width + y + 1]) {
      // a[x] は消えた。印は新しい本文側の「ここにあった」位置に置く
      pushRemoval(removals, b[y].start, a[x].text);
      x++;
    } else {
      var last = ranges[ranges.length - 1];
      if (last && last[1] === b[y].start) last[1] = b[y].end;
      else ranges.push([b[y].start, b[y].end]);
      y++;
    }
  }
  // 新しい本文を使い切った後に残った古いトークンは、末尾から消えたぶん
  while (x < n) {
    pushRemoval(removals, newText.length, a[x].text);
    x++;
  }
  // 類似度は一致した文字数で測る。トークン数で測ると、短い行に長めの追記をしただけで別物と判定されてしまう
  return {
    ranges: ranges,
    similarity: (2 * matchedChars) / (oldText.length + newText.length),
    removals: trimRemovals(moveRemovalsPastAdditions(removals, ranges)),
  };
}

/**
 * 同じ場所で「消えて、足された」とき（3 → 4 など）、削除の印を足された文字の
 * 後ろへ回す。「▲4」ではなく「4▲」の順にして、いま在る姿を先に読ませる。
 */
function moveRemovalsPastAdditions(removals, ranges) {
  if (!removals.length || !ranges.length) return removals;
  removals.forEach(function (removal) {
    var moved = true;
    while (moved) {
      moved = false;
      for (var i = 0; i < ranges.length; i++) {
        if (ranges[i][0] === removal.at) {
          removal.at = ranges[i][1];
          moved = true;
          break;
        }
      }
    }
  });
  // 動かした結果、同じ位置に重なったものはまとめ直す
  removals.sort(function (a, b) { return a.at - b.at; });
  var merged = [];
  removals.forEach(function (removal) {
    var last = merged[merged.length - 1];
    if (last && last.at === removal.at) last.text += removal.text;
    else merged.push(removal);
  });
  return merged;
}

function diffAddedRanges(oldText, newText) {
  return diffTexts(oldText, newText).ranges;
}

var DIFF_PAIR_MIN_SIMILARITY = 0.4;

/**
 * previousSignatures / previousRecords: 直前の render のユニット。自分の編集を
 * 見分けるのに使う。差分の相手は直前ではなく baselineSignatures（据え置きの基準）。
 */
/** 並びも含めて同じか。基準を引き直すべきか判断するのに使う。 */
function sameSignatures(a, b) {
  if (!a || !b || a.length !== b.length) return false;
  for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function markChangedUnits(containerEl, previousSignatures, markChanges, previousRecords) {
  var units = collectUnits(containerEl);
  var signatures = units.map(computeUnitSignature);
  var records = units.map(function (unit, idx) {
    return { sig: signatures[idx], tag: unit.tagName, text: collectUnitSearchText(unit).text };
  });

  // 外からの更新ではないのに中身が変わった = 自分で編集した。そこを新しい基準にする
  if (!markChanges && previousSignatures && !sameSignatures(signatures, previousSignatures)) {
    baselineSignatures = null;
    baselineRecords = null;
    persistentChanges = null;
    persistentGaps = null;
  }
  if (!baselineSignatures) {
    baselineSignatures = signatures;
    baselineRecords = records;
  }

  var changedCount = 0;
  if (!markChanges && persistentChanges) {
    // 外部更新ではない再描画: 前回の変更箇所に、光らせずに印だけ付け直す
    var used = Object.create(null);
    units.forEach(function (unit, idx) {
      for (var k = 0; k < persistentChanges.length; k++) {
        if (!used[k] && persistentChanges[k].sig === signatures[idx]) {
          used[k] = true;
          unit.setAttribute(CHANGE_KEEP_ATTR, String(k));
          break;
        }
      }
    });
  }
  if (!markChanges && persistentGaps) {
    insertGapMarkers(containerEl, units, signatures, persistentGaps);
  }
  if (markChanges) {
    persistentChanges = null;
    persistentGaps = null;
  }
  if (markChanges && baselineSignatures !== signatures) {
    var baseSignatures = baselineSignatures;
    var baseRecords = baselineRecords;
    var remaining = Object.create(null);
    baseSignatures.forEach(function (sig) {
      remaining[sig] = (remaining[sig] || 0) + 1;
    });
    var changedIndexes = [];
    units.forEach(function (unit, idx) {
      var sig = signatures[idx];
      if (remaining[sig] > 0) remaining[sig] -= 1;
      else changedIndexes.push(idx);
    });

    // 前の版にあって今回なくなったユニット = 変更前の姿の候補
    var removed = [];
    var removedOf = [];  // baseRecords の添字 -> removed の添字（残っていれば -1）
    if (baseRecords) {
      var stillThere = Object.create(null);
      signatures.forEach(function (sig) {
        stillThere[sig] = (stillThere[sig] || 0) + 1;
      });
      baseRecords.forEach(function (record, i) {
        if (stillThere[record.sig] > 0) {
          stillThere[record.sig] -= 1;
          removedOf[i] = -1;
          return;
        }
        removedOf[i] = removed.length;
        removed.push({ record: record, used: false, pairedWith: -1 });
      });
    }

    var changes = [];
    changedIndexes.forEach(function (idx) {
      var added = null;
      var removals = [];
      for (var r = 0; r < removed.length; r++) {
        if (removed[r].used || removed[r].record.tag !== records[idx].tag) continue;
        var diff = diffTexts(removed[r].record.text, records[idx].text);
        if (diff.similarity >= DIFF_PAIR_MIN_SIMILARITY) {
          removed[r].used = true;
          removed[r].pairedWith = idx;
          added = diff.ranges;
          removals = diff.removals || [];
          break;
        }
      }
      // 前の版に対応する姿が無い = 行ごと足された。語単位ではなくブロックごと塗る
      // （箇条書きの点まで含めたいので、範囲ハイライトではなく要素の背景で塗る）
      var whole = added === null && records[idx].text.length > 0;
      if (added === null) added = [];
      units[idx].setAttribute(CHANGE_MARK_ATTR, String(changes.length));
      changes.push({ sig: signatures[idx], added: added, removals: removals, whole: whole });
    });

    // どの変更ブロックとも対応が付かなかったもの = ブロックごと消えた。
    // 置き場所は「前の版で直前にいたブロックの、今の姿」。書き換えられて残った
    // ブロックもアンカーになる（署名だけで見ると別物になり、印が前に寄ってしまう）。
    var gaps = [];
    if (baseRecords) {
      var anchorSig = null;
      baseRecords.forEach(function (record, i) {
        var entryIdx = removedOf[i];
        if (entryIdx === -1) {
          anchorSig = record.sig;  // そのまま残っている
          return;
        }
        var entry = removed[entryIdx];
        if (entry.pairedWith >= 0) {
          anchorSig = signatures[entry.pairedWith];  // 書き換えられて残っている
          return;
        }
        if (!/\S/.test(entry.record.text)) return;
        gaps.push({ anchorSig: anchorSig, text: entry.record.text, tag: entry.record.tag });
      });
    }
    insertGapMarkers(containerEl, units, signatures, gaps);

    changedCount = changes.length + gaps.length;
    if (changes.length > 0) persistentChanges = changes;
    persistentGaps = gaps.length > 0 ? gaps : null;
  }

  return { signatures: signatures, records: records, changedCount: changedCount };
}

/**
 * 変更の印をすべて取り払う。ヘッダの「非表示」から呼ぶ。
 * 本文そのものには触らない。次の外部更新では新しい印が付く。
 */
function clearChangeMarks() {
  persistentChanges = null;
  persistentGaps = null;
  // ここから積み直す。今の姿が新しい基準
  baselineSignatures = previousUnitSignatures;
  baselineRecords = previousUnitRecords;
  var contentEl = document.getElementById("content");
  if (!contentEl) return;

  // ブロックの印
  var flagged = contentEl.querySelectorAll(
    "." + "markpanther-changed" + ", ." + CHANGE_RECENT_CLASS + ", ." + REMOVAL_ONLY_CLASS +
      ", ." + ADDED_WHOLE_CLASS,
  );
  for (var i = 0; i < flagged.length; i++) {
    flagged[i].classList.remove("markpanther-changed");
    flagged[i].classList.remove(CHANGE_RECENT_CLASS);
    flagged[i].classList.remove(REMOVAL_ONLY_CLASS);
    flagged[i].classList.remove(ADDED_WHOLE_CLASS);
  }
  // 行内の ▲ とブロックごとの破線は要素そのものを外す
  var inserted = contentEl.querySelectorAll("." + REMOVED_CLASS + ", ." + GAP_CLASS);
  for (var j = 0; j < inserted.length; j++) {
    if (inserted[j].parentNode) inserted[j].parentNode.removeChild(inserted[j]);
  }
  // 追加部分の塗り
  setHighlightGroup("markpanther-added", [], 0);
}

function prefersReducedMotion() {
  return (
    typeof window !== "undefined" &&
    !!window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  );
}

function isElementFullyOutsideViewport(el) {
  var rect = el.getBoundingClientRect();
  var viewportHeight =
    (typeof window !== "undefined" && window.innerHeight) ||
    (document.documentElement && document.documentElement.clientHeight) ||
    0;
  return rect.bottom <= 0 || rect.top >= viewportHeight;
}

function scrollToFirstChangeIfNeeded(el) {
  if (!el) return;
  if (!isElementFullyOutsideViewport(el)) return;
  if (typeof el.scrollIntoView !== "function") return;
  try {
    el.scrollIntoView({
      block: "center",
      behavior: prefersReducedMotion() ? "auto" : "smooth",
    });
  } catch (e) {
    el.scrollIntoView();
  }
}

/**
 * 光り終わった変更ブロックを、落ち着いた印（淡い背景 + 左の帯）へ切り替える。時間では消さず、
 * 次の外部更新まで残す。あとから画面を見た人にも、どこが変わったかが分かるようにするため。
 */
var CHANGE_RECENT_CLASS = "markpanther-changed-recent";

function demoteChangeHighlight(el) {
  if (!el.classList.contains("markpanther-changed")) return;
  el.classList.remove("markpanther-changed");
  el.classList.add(CHANGE_RECENT_CLASS);
}

function scheduleChangeFadeOut(el) {
  setTimeout(function () {
    demoteChangeHighlight(el);
  }, CHANGE_FADE_MS);
}

/** 更新トーストのクリック用。印の付いた最初のブロックへ移動し、あったかどうかを返す。 */
function scrollToFirstChange() {
  var contentEl = document.getElementById("content");
  var el = contentEl && contentEl.querySelector(".markpanther-changed, ." + CHANGE_RECENT_CLASS);
  if (!el) return false;
  if (typeof el.scrollIntoView === "function") {
    try {
      el.scrollIntoView({ block: "center", behavior: prefersReducedMotion() ? "auto" : "smooth" });
    } catch (e) {
      el.scrollIntoView();
    }
  }
  return true;
}

/**
 * 変更マーカーの付いたユニットに markpanther-changed クラスを付け、フェードアウトの
 * タイマーを仕込み、最初の変更箇所がビューポート外なら（中央寄せで）
 * スクロールする。
 */
var REMOVED_CLASS = "markpanther-removed";

/**
 * 消えた箇所に印を置く。最新版の表示を動かさないことが要件なので、幅も文字も持たない
 * 空の span を挟み、見える楔は CSS の疑似要素（絶対配置）で描く。消えた本文は
 * data-removed に載せ、ホバーで読めるようにする。
 */
function insertRemovalMarkers(el, removals) {
  if (!removals || !removals.length) return;
  var collected = collectUnitSearchText(el);
  var segments = [{ base: 0, map: collected.map }];
  // Range は DOM の変化に追従するので、先に全部作ってから挿す
  var points = [];
  removals.forEach(function (removal) {
    var at = Math.min(removal.at, collected.text.length);
    var range = buildRangeForMatch(segments, { start: at, end: at });
    if (range) points.push({ range: range, text: removal.text });
  });
  points.forEach(function (point) {
    point.range = moveRangeIntoCell(point.range);
  });
  points.forEach(function (point) {
    var marker = document.createElement("span");
    marker.className = REMOVED_CLASS;
    marker.setAttribute("data-removed", point.text);
    marker.setAttribute("aria-label", "Removed: " + point.text);
    try {
      point.range.insertNode(marker);
    } catch (e) {
      /* 位置が解決できなければ黙って諦める（本文の表示を壊さない方を優先） */
    }
  });
}

var TABLE_STRUCTURE_TAGS = { TABLE: 1, THEAD: 1, TBODY: 1, TFOOT: 1, TR: 1 };

/**
 * セルの境目は tr 直下の改行ノードに当たることがある。そこへ印を挿すと tr の子になり、
 * ブラウザが匿名セルとして描くので列が1つずれる。改行の後ろ側なら次のセルの先頭、
 * 手前側なら前のセルの末尾へ寄せる。
 */
function moveRangeIntoCell(range) {
  var node = range.startContainer;
  var parent = node.nodeType === 3 ? node.parentNode : node;
  if (!parent || !TABLE_STRUCTURE_TAGS[parent.tagName]) return range;
  var isCell = function (n) { return n && (n.tagName === "TD" || n.tagName === "TH"); };
  var next = node.nextSibling;
  while (next && !isCell(next)) next = next.nextSibling;
  var prev = node.previousSibling;
  while (prev && !isCell(prev)) prev = prev.previousSibling;
  var moved = document.createRange();
  if (next && (range.startOffset > 0 || !prev)) {
    moved.setStart(next, 0);
  } else if (prev) {
    moved.selectNodeContents(prev);
    moved.collapse(false);
  } else {
    return range;
  }
  moved.collapse(true);
  return moved;
}

var REMOVAL_ONLY_CLASS = "markpanther-removal-only";
var ADDED_WHOLE_CLASS = "markpanther-added-whole";
var GAP_CLASS = "markpanther-removed-block";

var REVEAL_CLASS = "markpanther-removed-reveal";

/**
 * ブロックごと消えた箇所に置く印。破線と ▲ は疑似要素で描くので、この要素自体は
 * 文字を持たない。消えた本文は data-removed に持ち、マウスを乗せたあいだだけ
 * 本文の流れに差し戻す。
 *
 * 親がリストなら li、表の行なら表の後ろ、それ以外は div。入れる場所の文法を
 * 壊さないため。
 */
function makeGapMarker(anchorEl, text, removedTag) {
  var tag = anchorEl && anchorEl.tagName === "LI" ? "li" : "div";
  var el = document.createElement(tag);
  el.className = GAP_CLASS;
  el.setAttribute("data-removed", text);
  if (removedTag) el.setAttribute("data-removed-tag", String(removedTag).toLowerCase());
  el.setAttribute("aria-label", "Removed: " + text);
  return el;
}

/** 戻すときの器。消えていたのが見出しなら見出しとして出す（元の姿を再現する）。 */
var REVEAL_TAGS = {
  p: 1, h1: 1, h2: 1, h3: 1, h4: 1, h5: 1, h6: 1, blockquote: 1, pre: 1,
};

function makeRevealElement(markerEl) {
  var isBlock = markerEl.classList.contains(GAP_CLASS);
  if (!isBlock) return document.createElement("span");
  // 印そのものが li なら、点はその li が描くので中身は span でよい
  if (markerEl.tagName === "LI") return document.createElement("span");
  var tag = markerEl.getAttribute("data-removed-tag");
  return document.createElement(tag && REVEAL_TAGS[tag] ? tag : "div");
}

/** gaps: [{anchorSig, text}]。anchorSig が null なら本文の先頭に置く。 */
function insertGapMarkers(containerEl, units, signatures, gaps) {
  if (!gaps || !gaps.length) return;
  // 同じ場所に続けて入れるとき、次は「直前に入れた印の後ろ」へ置く。
  // 毎回アンカーの直後に入れると、消えた順と逆に並んでしまう。
  var lastAt = Object.create(null);
  gaps.forEach(function (gap) {
    var key = gap.anchorSig == null ? "\u0000top" : "sig:" + gap.anchorSig;
    var anchorEl = null;
    if (gap.anchorSig != null) {
      for (var i = 0; i < signatures.length; i++) {
        if (signatures[i] !== gap.anchorSig) continue;
        anchorEl = units[i];
        break;
      }
      // 同じ署名のブロックが複数あっても最初の1つを使う（取り違えても位置が
      // 1ブロックずれるだけで、見落とすよりはよい）
      if (!anchorEl) return;
    }
    var marker = makeGapMarker(anchorEl, gap.text, gap.tag);

    var after = lastAt[key];
    if (!after && !anchorEl) {
      containerEl.insertBefore(marker, containerEl.firstChild);
      lastAt[key] = marker;
      return;
    }
    // 表の行の後ろには div を置けないので、表そのものの後ろへ逃がす
    var target = after || anchorEl;
    if (target.tagName === "TR") {
      while (target.parentNode && target.tagName !== "TABLE") target = target.parentNode;
    }
    if (!target.parentNode) return;
    target.parentNode.insertBefore(marker, target.nextSibling);
    lastAt[key] = marker;
  });
}

function hideRemovedReveal() {
  if (typeof document === "undefined") return;
  var shown = document.querySelectorAll("." + REVEAL_CLASS);
  for (var i = 0; i < shown.length; i++) {
    if (shown[i].parentNode) shown[i].parentNode.removeChild(shown[i]);
  }
  var open = document.querySelectorAll(".is-open." + GAP_CLASS + ", .is-open." + REMOVED_CLASS);
  for (var j = 0; j < open.length; j++) open[j].classList.remove("is-open");
}

/**
 * マウスを乗せているあいだ、消えた本文をその場に戻して見せる。
 * 吹き出しではなく本文の流れに差し込むので、「変更前はこう書いてあった」が
 * そのまま読める。取り消し線とグレーで、いま在るものと取り違えないようにする。
 */
function showRemovedReveal(markerEl) {
  if (markerEl.classList.contains("is-open")) return;
  hideRemovedReveal();
  var text = markerEl.getAttribute("data-removed") || "";
  if (!text) return;

  var isBlock = markerEl.classList.contains(GAP_CLASS);
  var reveal = makeRevealElement(markerEl);
  reveal.className = REVEAL_CLASS;
  reveal.textContent = text;
  markerEl.classList.add("is-open");

  if (isBlock) {
    markerEl.appendChild(reveal);
    return;
  }
  // 行内は、印のすぐ後ろ = 消えた文字があった位置へ差し込む
  if (markerEl.parentNode) markerEl.parentNode.insertBefore(reveal, markerEl.nextSibling);
}

if (typeof document !== "undefined" && document.addEventListener && !document.__markpantherRemovedHoverBound) {
  document.__markpantherRemovedHoverBound = true;
  // 戻した本文の上に入ってもそのままにする（出入りで点滅させない）
  var hoverSelector = "." + GAP_CLASS + ", ." + REMOVED_CLASS + ", ." + REVEAL_CLASS;
  document.addEventListener("mouseover", function (event) {
    var target = event.target;
    if (!target || !target.closest) return;
    var hit = target.closest(hoverSelector);
    if (!hit) {
      hideRemovedReveal();
      return;
    }
    if (hit.classList.contains(REVEAL_CLASS)) return;
    showRemovedReveal(hit);
  });
}

/**
 * 印の付いた場所のソース行。サイドバーのどの見出しに変更があったかを
 * 呼び出し側（Swift）が決められるように返す。
 * 消えたブロックには行が無いので、直前に残っているブロックの行を使う。
 */
function collectChangedLines(contentEl) {
  var lines = [];
  function push(el) {
    if (!el || typeof el.getAttribute !== "function") return;
    var raw = el.getAttribute("data-line");
    var line = raw == null ? NaN : parseInt(raw, 10);
    if (!isFinite(line)) {
      var owner = el.closest ? el.closest("[data-line]") : null;
      line = owner ? parseInt(owner.getAttribute("data-line"), 10) : NaN;
    }
    if (isFinite(line)) lines.push(line);
  }
  var marked = contentEl.querySelectorAll(
    ".markpanther-changed, ." + CHANGE_RECENT_CLASS);
  for (var i = 0; i < marked.length; i++) push(marked[i]);

  var gapMarks = contentEl.querySelectorAll("." + GAP_CLASS);
  for (var g = 0; g < gapMarks.length; g++) {
    // 消えた場所そのものには行が無い。手前に残っているブロックを指す
    var prev = gapMarks[g].previousElementSibling;
    while (prev && !prev.hasAttribute("data-line")) prev = prev.previousElementSibling;
    push(prev || gapMarks[g].parentElement);
  }
  var unique = [];
  lines.sort(function (a, b) { return a - b; }).forEach(function (line) {
    if (unique[unique.length - 1] !== line) unique.push(line);
  });
  return unique;
}

function applyChangeHighlights(contentEl, shouldScroll) {
  var addedRanges = [];
  function collectAdded(el, attr) {
    var change = persistentChanges && persistentChanges[parseInt(el.getAttribute(attr), 10)];
    if (!change) return;
    insertRemovalMarkers(el, change.removals);
    // 行ごと足されたブロックは、箇条書きの点まで含めて塗る
    el.classList.toggle(ADDED_WHOLE_CLASS, !!change.whole);
    // 消えただけのブロックは控えめに見せる（左余白の ● を出さない）
    var removalsOnly = !change.whole && !change.added.length &&
      !!(change.removals && change.removals.length);
    el.classList.toggle(REMOVAL_ONLY_CLASS, removalsOnly);
    if (!change.added.length) return;
    var collected = collectUnitSearchText(el);
    var segments = [{ base: 0, map: collected.map }];
    change.added.forEach(function (range) {
      var r = buildRangeForMatch(segments, { start: range[0], end: range[1] });
      if (r) addedRanges.push(r);
    });
  }

  // 再描画で引き継ぐ印（光らせない）
  var kept = contentEl.querySelectorAll("[" + CHANGE_KEEP_ATTR + "]");
  for (var k = 0; k < kept.length; k++) {
    collectAdded(kept[k], CHANGE_KEEP_ATTR);
    kept[k].removeAttribute(CHANGE_KEEP_ATTR);
    kept[k].classList.add(CHANGE_RECENT_CLASS);
  }
  var marked = contentEl.querySelectorAll("[" + CHANGE_MARK_ATTR + "]");
  var changedEls = [];
  for (var i = 0; i < marked.length; i++) {
    var el = marked[i];
    collectAdded(el, CHANGE_MARK_ATTR);
    el.removeAttribute(CHANGE_MARK_ATTR);
    el.classList.add("markpanther-changed");
    changedEls.push(el);
    scheduleChangeFadeOut(el);
  }
  // 行内で追加された部分。DOM は書き換えず CSS Custom Highlight で塗る（検索のハイライトより下の優先度）
  setHighlightGroup("markpanther-added", addedRanges, 0);
  lastChangedLines = collectChangedLines(contentEl);
  if (changedEls.length && shouldScroll) {
    scrollToFirstChangeIfNeeded(changedEls[0]);
  }
}

/* ------------------------------------------------------------------ *
 * render() 本体（DOM 必須）
 * ------------------------------------------------------------------ */

var renderCounter = 0;

function render(markdown, docDir, options) {
  var myToken = ++renderCounter;
  var normalized = normalizeOptions(options);
  var resolvedDocDir = docDir === undefined ? null : docDir;

  return Promise.resolve()
    .then(function () {
      var html;
      try {
        html = buildHtmlFromMarkdown(
          markdown == null ? "" : markdown,
          normalized,
          resolvedDocDir,
        );
      } catch (e) {
        html =
          '<pre class="render-error">' +
          escapeHtml((e && e.message) || String(e)) +
          "</pre>";
      }
      return html;
    })
    .then(function (html) {
      if (myToken !== renderCounter) return { changed: 0, changedLines: lastChangedLines };
      var clean = sanitizeHtml(html);
      if (myToken !== renderCounter) return { changed: 0, changedLines: lastChangedLines };

      var contentEl = document.getElementById("content");
      if (!contentEl) return { changed: 0, changedLines: [] };

      // sanitize 後・morph 前の detached ツリー上で比較単位の署名を作り、
      // markChanges が有効なら新規/変更ユニットへ一時マーカーを振ってから
      // 文字列に戻して morph する（マーカーはこの後 DOMPurify を通さないので
      // 属性許可リストの心配は不要）。
      var detached = document.createElement("div");
      detached.innerHTML = clean;
      var changeResult = markChangedUnits(
        detached,
        previousUnitSignatures,
        normalized.markChanges,
        previousUnitRecords,
      );
      previousUnitSignatures = changeResult.signatures;
      previousUnitRecords = changeResult.records;
      var cleanForMorph = detached.innerHTML;

      var Idiomorph = getGlobal("Idiomorph");
      if (Idiomorph && typeof Idiomorph.morph === "function") {
        Idiomorph.morph(contentEl, cleanForMorph, { morphStyle: "innerHTML" });
      } else {
        contentEl.innerHTML = cleanForMorph;
      }

      reapplyBrokenImages(contentEl);
      applyLineNumbers(contentEl, normalized.lineNumbers);
      updateContentLeft();
      // 変更箇所の見せ方: 既定は左余白の ●、changeBand なら diff 風の帯
      document.body.classList.toggle("markpanther-change-band", normalized.changeBand);
      rebuildCopyButtons();

      applyChangeHighlights(contentEl, normalized.markChanges);

      var afterMermaid = normalized.mermaid
        ? processMermaidBlocks(contentEl).then(function () {
            if (myToken !== renderCounter) return;
          })
        : Promise.resolve();

      return afterMermaid.then(function () {
        if (myToken === renderCounter) {
          applyZoomToDiagrams();
          repositionCopyButtons();
        }
        if (myToken === renderCounter && searchState) {
          reapplyFindAfterRender();
        }
        return { changed: changeResult.changedCount, changedLines: lastChangedLines };
      });
    });
}

/* ------------------------------------------------------------------ *
 * getTopLine / scrollToLine
 * ------------------------------------------------------------------ */

/**
 * ウィンドウ上下に浮いているクローム（ガラスのカプセル）のぶんの余白。Swift 側が setInsets で渡す。
 * CSS 変数にして、本文の padding と scroll-padding に使う。
 */
var topInset = 0;
var bottomInset = 0;

/**
 * 表示倍率。WKWebView のページズームは使わない（WebKit はページズーム中に SVG の foreignObject の位置を誤り、
 * mermaid のラベルが箱からずれる）。文字は CSS 変数で基準サイズを拡大し、図は幅を変えて viewBox で拡縮する。
 */
var zoomFactor = 1;

function setZoom(value) {
  var z = Number(value);
  if (!isFinite(z) || z <= 0) z = 1;
  zoomFactor = Math.min(3, Math.max(0.5, z));
  document.documentElement.style.setProperty("--markpanther-zoom", String(zoomFactor));
  applyZoomToDiagrams();
  if (typeof repositionCopyButtons === "function") repositionCopyButtons();
}

function applyZoomToDiagrams() {
  var contentEl = document.getElementById("content");
  if (!contentEl) return;
  var svgs = contentEl.querySelectorAll(".mermaid-diagram svg");
  for (var i = 0; i < svgs.length; i++) {
    var svg = svgs[i];
    var natural = parseFloat(svg.getAttribute("data-markpanther-natural-width"));
    if (!natural) {
      natural = parseFloat(svg.style.maxWidth);
      if (!natural) continue;
      svg.setAttribute("data-markpanther-natural-width", String(natural));
    }
    svg.style.maxWidth = natural * zoomFactor + "px";
  }
}

/**
 * プレビューの左余白に出すソースの行番号（1 始まり）。data-line（0 始まり、frontmatter ぶんは加算済み）から
 * 表示用の属性を作る。morph の後で付けるので、変更検出の署名には影響しない。
 */
/** 行番号の欄を表示領域の左端に固定するため、中央寄せされた #content の左端の位置を CSS へ渡す。 */
function updateContentLeft() {
  var contentEl = document.getElementById("content");
  if (!contentEl || typeof contentEl.getBoundingClientRect !== "function") return;
  var left = contentEl.getBoundingClientRect().left + (window.scrollX || 0);
  document.documentElement.style.setProperty("--markpanther-content-left", Math.max(0, left) + "px");
  // 余白の ● は #content の padding box を基準に置かれる。本文の並びにいる印から
  // 同じ位置を指せるよう、その padding 幅も渡しておく（テーマごとに違う）。
  if (typeof window.getComputedStyle === "function") {
    var pad = parseFloat(window.getComputedStyle(contentEl).paddingLeft);
    document.documentElement.style.setProperty(
      "--markpanther-content-pad", (isFinite(pad) ? pad : 0) + "px");
  }
}

function applyLineNumbers(contentEl, enabled) {
  document.body.classList.toggle("markpanther-line-numbers", !!enabled);
  if (!enabled) return;
  var els = contentEl.querySelectorAll("[data-line]");
  for (var i = 0; i < els.length; i++) {
    var line = parseInt(els[i].getAttribute("data-line"), 10);
    if (isNaN(line)) continue;
    var label = String(line + 1);
    els[i].setAttribute("data-lno", label);
    // 変更マーカーの丸を番号の左隣へ置くために、桁数を CSS から参照できるようにする
    els[i].setAttribute("data-lno-digits", String(label.length));
  }
}

function setInsets(top, bottom) {
  topInset = Math.max(0, Number(top) || 0);
  bottomInset = Math.max(0, Number(bottom) || 0);
  var style = document.documentElement.style;
  style.setProperty("--markpanther-top-inset", topInset + "px");
  style.setProperty("--markpanther-bottom-inset", bottomInset + "px");
  if (typeof repositionCopyButtons === "function") repositionCopyButtons();
}

/** rects: [{line, top, bottom}]。上の余白の線に最も近い（まだ見えている）要素の行を返す。 */
function pickTopLine(rects, inset) {
  var best = null;
  var bestDelta = Infinity;
  for (var i = 0; i < rects.length; i++) {
    if (rects[i].bottom < inset) continue;
    var delta = Math.abs(rects[i].top - inset);
    if (delta < bestDelta) {
      bestDelta = delta;
      best = rects[i];
    }
  }
  if (!best) best = rects[0];
  return best && !isNaN(best.line) ? best.line : 0;
}

function getTopLine() {
  var contentEl = document.getElementById("content");
  if (!contentEl) return 0;
  var candidates = contentEl.querySelectorAll("[data-line]");
  var rects = [];
  for (var i = 0; i < candidates.length; i++) {
    var rect = candidates[i].getBoundingClientRect();
    rects.push({
      line: parseInt(candidates[i].getAttribute("data-line"), 10),
      top: rect.top,
      bottom: rect.bottom,
    });
  }
  return pickTopLine(rects, topInset);
}

function scrollToLine(line) {
  var contentEl = document.getElementById("content");
  if (!contentEl) return;
  var candidates = contentEl.querySelectorAll("[data-line]");
  var best = null;
  var bestLine = -1;
  for (var i = 0; i < candidates.length; i++) {
    var l = parseInt(candidates[i].getAttribute("data-line"), 10);
    if (!isNaN(l) && l <= line && l > bestLine) {
      bestLine = l;
      best = candidates[i];
    }
  }
  if (!best && candidates.length) best = candidates[0];
  if (best && typeof best.scrollIntoView === "function") {
    best.scrollIntoView({ block: "start" });
  }
}

/* ------------------------------------------------------------------ *
 * getBodyHTML
 * ------------------------------------------------------------------ */

function getBodyHTML() {
  var contentEl = document.getElementById("content");
  if (!contentEl) return "";
  var clone = contentEl.cloneNode(true);
  var imgs = clone.querySelectorAll("img[data-original-src]");
  for (var i = 0; i < imgs.length; i++) {
    var orig = imgs[i].getAttribute("data-original-src");
    imgs[i].setAttribute("src", orig);
    imgs[i].removeAttribute("data-original-src");
  }
  var broken = clone.querySelectorAll("." + BROKEN_IMAGE_CLASS);
  for (var b = 0; b < broken.length; b++) {
    broken[b].classList.remove(BROKEN_IMAGE_CLASS);
    if (!broken[b].getAttribute("class")) broken[b].removeAttribute("class");
    broken[b].removeAttribute("title");
  }
  // 行番号や mermaid の元ソースなど、アプリ内部でしか使わない属性は貼り付け先に持ち出さない。
  var INTERNAL_ATTRS = ["data-line", "data-mermaid-source-b64", "data-mermaid-pending", "data-markpanther-natural-width", "data-lno", "data-lno-digits"];
  for (var a = 0; a < INTERNAL_ATTRS.length; a++) {
    var tagged = clone.querySelectorAll("[" + INTERNAL_ATTRS[a] + "]");
    for (var t = 0; t < tagged.length; t++) tagged[t].removeAttribute(INTERNAL_ATTRS[a]);
  }
  // 変更ハイライトは一時的な表示状態であり、コピー結果/エクスポートには含めない。
  var revealed = clone.querySelectorAll("." + REVEAL_CLASS);
  for (var rv = 0; rv < revealed.length; rv++) {
    if (revealed[rv].parentNode) revealed[rv].parentNode.removeChild(revealed[rv]);
  }
  var gapMarks = clone.querySelectorAll("." + GAP_CLASS);
  for (var gm = 0; gm < gapMarks.length; gm++) {
    if (gapMarks[gm].parentNode) gapMarks[gm].parentNode.removeChild(gapMarks[gm]);
  }
  var removalOnly = clone.querySelectorAll("." + REMOVAL_ONLY_CLASS + ", ." + ADDED_WHOLE_CLASS);
  for (var ro = 0; ro < removalOnly.length; ro++) {
    removalOnly[ro].classList.remove(REMOVAL_ONLY_CLASS);
    removalOnly[ro].classList.remove(ADDED_WHOLE_CLASS);
  }
  var removedMarks = clone.querySelectorAll("." + REMOVED_CLASS);
  for (var rm = 0; rm < removedMarks.length; rm++) {
    if (removedMarks[rm].parentNode) removedMarks[rm].parentNode.removeChild(removedMarks[rm]);
  }
  var changed = clone.querySelectorAll(".markpanther-changed, ." + CHANGE_RECENT_CLASS);
  for (var j = 0; j < changed.length; j++) {
    changed[j].classList.remove("markpanther-changed");
    changed[j].classList.remove(CHANGE_RECENT_CLASS);
    if (!changed[j].getAttribute("class")) changed[j].removeAttribute("class");
  }
  var keepMarks = clone.querySelectorAll("[" + CHANGE_KEEP_ATTR + "]");
  for (var m = 0; m < keepMarks.length; m++) keepMarks[m].removeAttribute(CHANGE_KEEP_ATTR);
  var pending = clone.querySelectorAll("[" + CHANGE_MARK_ATTR + "]");
  for (var k = 0; k < pending.length; k++) {
    pending[k].removeAttribute(CHANGE_MARK_ATTR);
  }
  return clone.innerHTML;
}

/* ------------------------------------------------------------------ *
 * setStyle
 * ------------------------------------------------------------------ */

var BUILTIN_STYLES = ["GitHub", "Clearness"];

function setStyle(name) {
  var link = document.getElementById("markpanther-style-link");
  if (!link) return;
  if (BUILTIN_STYLES.indexOf(name) !== -1) {
    link.setAttribute("href", "styles/" + name + ".css");
  } else {
    link.setAttribute("href", "markp://style/" + name + ".css");
  }
}

function getCurrentStyleHref() {
  var link = document.getElementById("markpanther-style-link");
  return link ? link.getAttribute("href") : "styles/GitHub.css";
}

/* ------------------------------------------------------------------ *
 * exportHTML
 * ------------------------------------------------------------------ */

function fetchText(url) {
  return fetch(url).then(function (res) {
    if (!res.ok)
      throw new Error("failed to fetch " + url + " (" + res.status + ")");
    return res.text();
  });
}

function arrayBufferToBase64(buffer) {
  var bytes = new Uint8Array(buffer);
  var binary = "";
  for (var i = 0; i < bytes.length; i++)
    binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

function inlineKatexFonts(css) {
  var urlRe = /url\((fonts\/[^)]+\.woff2)\)/g;
  var paths = [];
  var m;
  while ((m = urlRe.exec(css))) {
    if (paths.indexOf(m[1]) === -1) paths.push(m[1]);
  }
  if (!paths.length) return Promise.resolve(css);
  return Promise.all(
    paths.map(function (p) {
      return fetch("vendor/katex/" + p)
        .then(function (res) {
          return res.arrayBuffer();
        })
        .then(function (buf) {
          return {
            path: p,
            dataUri: "data:font/woff2;base64," + arrayBufferToBase64(buf),
          };
        });
    }),
  ).then(function (list) {
    var out = css;
    list.forEach(function (item) {
      var escaped = item.path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      var re = new RegExp("url\\(" + escaped + "\\)", "g");
      out = out.replace(re, "url(" + item.dataUri + ")");
    });
    return out;
  });
}

function exportHTML(opts) {
  opts = opts || {};
  var includeStyles = !!opts.includeStyles;
  var includeHighlight = !!opts.includeHighlight;
  var title = opts.title || "";

  var bodyHtml = getBodyHTML();
  var hasMath = /class="[^"]*\bkatex\b/.test(bodyHtml);

  var cssPromises = [];
  if (includeStyles) {
    cssPromises.push(fetchText(getCurrentStyleHref()));
    cssPromises.push(fetchText("preview.css"));
  }
  if (includeHighlight) {
    cssPromises.push(
      fetchText(
        prefersDark()
          ? "vendor/highlightjs/styles/github-dark.min.css"
          : "vendor/highlightjs/styles/github.min.css",
      ),
    );
  }
  var katexCssPromise = hasMath
    ? fetchText("vendor/katex/katex.min.css").then(inlineKatexFonts)
    : Promise.resolve("");

  return Promise.all([Promise.all(cssPromises), katexCssPromise]).then(
    function (results) {
      var otherCss = results[0].join("\n");
      var katexCss = results[1];
      var styleTag = "";
      if (otherCss || katexCss) {
        styleTag = "<style>\n" + otherCss + "\n" + katexCss + "\n</style>\n";
      }
      return (
        '<!doctype html>\n<html>\n<head>\n<meta charset="utf-8">\n<title>' +
        escapeHtml(title) +
        "</title>\n" +
        styleTag +
        '</head>\n<body>\n<article class="markdown-body">' +
        bodyHtml +
        "</article>\n</body>\n</html>\n"
      );
    },
  );
}

/* ------------------------------------------------------------------ *
 * プレビュー内検索（find / clearFind）
 *
 * CSS Custom Highlight API（CSS.highlights / Highlight / ::highlight()）で
 * 実装し、DOM は一切書き換えない（Idiomorph の差分更新と干渉させないため）。
 * 対象は #content のテキストで、mermaid の <svg> と .katex の中身は除外する。
 * 比較単位（decomposeIntoUnits と同じ粒度: ul/ol は li、table は tr、
 * blockquote は直下の子）ごとにテキストを取り出し、単位間は改行1文字で
 * つないで1本の文字列にする。これにより要素をまたぐ一致（**foo**bar の
 * "foobar" 等）は拾いつつ、ブロックをまたぐ一致は拾わない。
 * ------------------------------------------------------------------ */

var searchState = null; // { query, matches: [{start,end}], currentIndex, segments } | null

function isSearchExcludedElement(el) {
  return (
    el.tagName === "SVG" || (el.classList && el.classList.contains("katex"))
  );
}

/**
 * unitEl 配下のテキストを（除外サブツリーを飛ばして）連結し、グローバル文字
 * オフセットから元のテキストノード＋ノード内オフセットへ引けるマップを作る。
 */
function collectUnitSearchText(unitEl) {
  var text = "";
  var map = [];
  function walk(node) {
    if (node.nodeType === 1) {
      if (isSearchExcludedElement(node)) return;
      for (var i = 0; i < node.childNodes.length; i++) walk(node.childNodes[i]);
      return;
    }
    if (node.nodeType === 3) {
      var content = node.nodeValue || "";
      if (content.length) {
        map.push({
          node: node,
          start: text.length,
          end: text.length + content.length,
        });
        text += content;
      }
    }
  }
  walk(unitEl);
  return { text: text, map: map };
}

/**
 * contentEl（実 DOM の #content）全体の検索インデックスを作る。
 * 戻り値: { text, segments: [{ base: number, map: [{node,start,end}] }] }
 */
function buildSearchIndex(contentEl) {
  var units = collectUnits(contentEl);
  var fullText = "";
  var segments = [];
  units.forEach(function (unit, idx) {
    if (idx > 0) fullText += "\n";
    var u = collectUnitSearchText(unit);
    segments.push({ base: fullText.length, map: u.map });
    fullText += u.text;
  });
  return { text: fullText, segments: segments };
}

/** 大文字小文字を無視して、重複しない一致区間 [start, end) をすべて探す。 */
function findMatches(text, query) {
  var matches = [];
  if (!query) return matches;
  var needle = String(query).toLowerCase();
  if (!needle.length) return matches;
  var haystack = String(text).toLowerCase();
  var from = 0;
  while (true) {
    var found = haystack.indexOf(needle, from);
    if (found === -1) break;
    matches.push({ start: found, end: found + needle.length });
    from = found + needle.length;
  }
  return matches;
}

function resolveOffsetToNodeOffset(segments, globalOffset) {
  for (var i = 0; i < segments.length; i++) {
    var seg = segments[i];
    for (var j = 0; j < seg.map.length; j++) {
      var entry = seg.map[j];
      var segStart = seg.base + entry.start;
      var segEnd = seg.base + entry.end;
      if (globalOffset >= segStart && globalOffset <= segEnd) {
        return { node: entry.node, offset: globalOffset - segStart };
      }
    }
  }
  return null;
}

function buildRangeForMatch(segments, match) {
  var startPos = resolveOffsetToNodeOffset(segments, match.start);
  var endPos = resolveOffsetToNodeOffset(segments, match.end);
  if (!startPos || !endPos) return null;
  try {
    var range = document.createRange();
    range.setStart(startPos.node, startPos.offset);
    range.setEnd(endPos.node, endPos.offset);
    return range;
  } catch (e) {
    return null;
  }
}

function isCustomHighlightApiSupported() {
  return (
    typeof CSS !== "undefined" &&
    !!CSS.highlights &&
    typeof Highlight === "function"
  );
}

function setHighlightGroup(name, ranges, priority) {
  if (!isCustomHighlightApiSupported()) return;
  if (!ranges.length) {
    CSS.highlights.delete(name);
    return;
  }
  var hl = new Highlight();
  hl.priority = typeof priority === "number" ? priority : 0;
  ranges.forEach(function (r) {
    hl.add(r);
  });
  CSS.highlights.set(name, hl);
}

/** searchState の内容に基づいて ::highlight() 用のレンジ群を張り直す。 */
function applyFindHighlights() {
  if (!isCustomHighlightApiSupported()) return;
  if (!searchState || !searchState.matches.length) {
    CSS.highlights.delete("markpanther-find");
    CSS.highlights.delete("markpanther-find-current");
    return;
  }
  var allRanges = [];
  var currentRanges = [];
  searchState.matches.forEach(function (m, i) {
    var range = buildRangeForMatch(searchState.segments, m);
    if (!range) return;
    if (i === searchState.currentIndex) {
      currentRanges.push(range);
    } else {
      allRanges.push(range);
    }
  });
  // 変更箇所の「追加された部分」（優先度 0）より上に描く
  setHighlightGroup("markpanther-find", allRanges, 1);
  setHighlightGroup("markpanther-find-current", currentRanges, 2);
}

/** current の一致がビューポート中央付近に来るようスクロールする。 */
function scrollToCurrentMatch() {
  if (!searchState || !searchState.matches.length) return;
  var range = buildRangeForMatch(
    searchState.segments,
    searchState.matches[searchState.currentIndex],
  );
  if (!range || typeof range.getBoundingClientRect !== "function") return;
  var rect = range.getBoundingClientRect();
  if (!rect || (rect.top === 0 && rect.bottom === 0 && rect.height === 0)) {
    // レイアウトが取れない環境（テスト等）では何もしない
    return;
  }
  var viewportHeight =
    (typeof window !== "undefined" && window.innerHeight) ||
    (document.documentElement && document.documentElement.clientHeight) ||
    0;
  var delta = rect.top - viewportHeight / 2 + rect.height / 2;
  var behavior = prefersReducedMotion() ? "auto" : "smooth";
  try {
    window.scrollBy({ top: delta, left: 0, behavior: behavior });
  } catch (e) {
    if (typeof window.scrollBy === "function") window.scrollBy(0, delta);
  }
}

/** 現在のスクロール位置以降で最初に見つかる一致のインデックスを選ぶ。 */
function pickInitialCurrentIndex(segments, matches) {
  for (var i = 0; i < matches.length; i++) {
    var range = buildRangeForMatch(segments, matches[i]);
    if (!range || typeof range.getBoundingClientRect !== "function") continue;
    var rect = range.getBoundingClientRect();
    if (rect && rect.top >= 0) return i;
  }
  return 0;
}

function find(query, opts) {
  opts = opts || {};
  var backwards = !!opts.backwards;
  query = query == null ? "" : String(query);
  var contentEl = document.getElementById("content");

  if (!contentEl || !query) {
    clearFind();
    return { current: 0, total: 0 };
  }

  var index = buildSearchIndex(contentEl);
  var matches = findMatches(index.text, query);

  if (!matches.length) {
    searchState = {
      query: query,
      matches: [],
      currentIndex: 0,
      segments: index.segments,
    };
    applyFindHighlights();
    return { current: 0, total: 0 };
  }

  var currentIndex;
  if (searchState && searchState.query === query) {
    currentIndex = searchState.currentIndex + (backwards ? -1 : 1);
    if (currentIndex < 0) currentIndex = matches.length - 1;
    if (currentIndex >= matches.length) currentIndex = 0;
  } else {
    currentIndex = pickInitialCurrentIndex(index.segments, matches);
  }

  searchState = {
    query: query,
    matches: matches,
    currentIndex: currentIndex,
    segments: index.segments,
  };
  applyFindHighlights();
  scrollToCurrentMatch();
  return { current: currentIndex + 1, total: matches.length };
}

function clearFind() {
  searchState = null;
  if (isCustomHighlightApiSupported()) {
    CSS.highlights.delete("markpanther-find");
    CSS.highlights.delete("markpanther-find-current");
  }
}

/**
 * render() 完了後、検索がアクティブなら同じ query でハイライトを張り直す。
 * current はできるだけ近い位置（旧 current 一致の開始オフセットに一番近い
 * 新しい一致）を維持し、件数が減ったら範囲内に丸める。
 */
function reapplyFindAfterRender() {
  if (!searchState) return;
  var contentEl = document.getElementById("content");
  if (!contentEl) return;

  var index = buildSearchIndex(contentEl);
  var matches = findMatches(index.text, searchState.query);

  var newCurrent = 0;
  if (matches.length) {
    if (
      searchState.matches.length &&
      searchState.currentIndex < searchState.matches.length
    ) {
      var oldStart = searchState.matches[searchState.currentIndex].start;
      var bestIdx = 0;
      var bestDelta = Infinity;
      matches.forEach(function (m, i) {
        var d = Math.abs(m.start - oldStart);
        if (d < bestDelta) {
          bestDelta = d;
          bestIdx = i;
        }
      });
      newCurrent = bestIdx;
    }
    if (newCurrent >= matches.length) newCurrent = matches.length - 1;
  }

  searchState = {
    query: searchState.query,
    matches: matches,
    currentIndex: newCurrent,
    segments: index.segments,
  };
  applyFindHighlights();
  if (matches.length) scrollToCurrentMatch();
}

/* ------------------------------------------------------------------ *
 * 読み込めなかった画像
 *
 * <img> の error を拾って class と title（どのパスが無いのか）を付ける。
 * morph で class が落ちても戻せるよう、失敗した src を覚えておく。
 * ------------------------------------------------------------------ */

var BROKEN_IMAGE_CLASS = "markpanther-broken-image";
var brokenImageSources = {};

function markBrokenImage(img) {
  img.classList.add(BROKEN_IMAGE_CLASS);
  var original = img.getAttribute("data-original-src") || img.getAttribute("src") || "";
  img.setAttribute("title", "Image not found: " + original);
}

function reapplyBrokenImages(contentEl) {
  var imgs = contentEl.querySelectorAll("img");
  for (var i = 0; i < imgs.length; i++) {
    if (brokenImageSources[imgs[i].getAttribute("src")]) markBrokenImage(imgs[i]);
  }
}

function installBrokenImageTracking() {
  // error / load はバブリングしないので capture で拾う
  document.addEventListener("error", function (event) {
    var el = event.target;
    if (!el || el.tagName !== "IMG") return;
    brokenImageSources[el.getAttribute("src")] = true;
    markBrokenImage(el);
  }, true);
  document.addEventListener("load", function (event) {
    var el = event.target;
    if (!el || el.tagName !== "IMG") return;
    delete brokenImageSources[el.getAttribute("src")];
    if (el.classList.contains(BROKEN_IMAGE_CLASS)) {
      el.classList.remove(BROKEN_IMAGE_CLASS);
      el.removeAttribute("title");
    }
  }, true);
}

if (typeof document !== "undefined") installBrokenImageTracking();

/* ------------------------------------------------------------------ *
 * コードブロックの Copy ボタン
 *
 * ボタンは #content の外のオーバーレイ層に置き、各 <pre> の右上へ重ねる。
 * 本文の DOM を書き換えないので、Idiomorph の差分更新・変更検出・検索・
 * getBodyHTML/exportHTML のどれにも影響しない。位置は render 後と、
 * 本文のサイズが変わったとき（ウィンドウ幅・画像の読み込み・mermaid の描画）に取り直す。
 * ------------------------------------------------------------------ */

var OVERLAY_ID = "markpanther-overlays";
var COPY_BUTTON_CLASS = "markpanther-copy-button";
var copyLayoutObserver = null;

function codeTextForCopy(pre) {
  var code = pre.querySelector("code") || pre;
  return code.textContent || "";
}

function copyablePres(contentEl) {
  var result = [];
  var pres = contentEl.querySelectorAll("pre");
  for (var i = 0; i < pres.length; i++) {
    if (!pres[i].closest("[data-mermaid-source-b64]")) result.push(pres[i]);
  }
  return result;
}

function ensureOverlayLayer() {
  var layer = document.getElementById(OVERLAY_ID);
  if (layer) return layer;
  layer = document.createElement("div");
  layer.id = OVERLAY_ID;
  document.body.appendChild(layer);
  return layer;
}

function sendToClipboard(text) {
  var handlers = window.webkit && window.webkit.messageHandlers;
  if (handlers && handlers.markpantherCopy) {
    handlers.markpantherCopy.postMessage(text);
  } else if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).catch(function () {});
  }
}

function makeCopyButton(pre) {
  var button = document.createElement("button");
  button.type = "button";
  button.className = COPY_BUTTON_CLASS;
  button.setAttribute("aria-label", "Copy code");
  button.addEventListener("click", function () {
    sendToClipboard(codeTextForCopy(pre));
    button.classList.add("is-copied");
    setTimeout(function () {
      button.classList.remove("is-copied");
    }, 1400);
  });
  return button;
}

function positionCopyButton(button, pre) {
  var rect = pre.getBoundingClientRect();
  button.style.top = rect.top + window.scrollY + 6 + "px";
  button.style.right =
    document.documentElement.clientWidth - (rect.right + window.scrollX) + 6 + "px";
}

/** コードブロックごとにボタンを作り直す（render のたびに呼ぶ）。 */
function rebuildCopyButtons() {
  var contentEl = document.getElementById("content");
  if (!contentEl) return;
  var layer = ensureOverlayLayer();
  while (layer.firstChild) layer.removeChild(layer.firstChild);
  var pres = copyablePres(contentEl);
  for (var i = 0; i < pres.length; i++) {
    var button = makeCopyButton(pres[i]);
    button._markpantherPre = pres[i];
    layer.appendChild(button);
    positionCopyButton(button, pres[i]);
  }
  observeLayoutForCopyButtons(contentEl);
}

function repositionCopyButtons() {
  updateContentLeft(); // 幅が変わると #content の左端も動く
  var layer = document.getElementById(OVERLAY_ID);
  if (!layer) return;
  for (var i = 0; i < layer.children.length; i++) {
    var button = layer.children[i];
    if (button._markpantherPre && button._markpantherPre.isConnected) {
      positionCopyButton(button, button._markpantherPre);
    }
  }
}

function observeLayoutForCopyButtons(contentEl) {
  if (copyLayoutObserver || typeof ResizeObserver === "undefined") return;
  copyLayoutObserver = new ResizeObserver(repositionCopyButtons);
  copyLayoutObserver.observe(contentEl);
  window.addEventListener("resize", repositionCopyButtons);
}

/* ------------------------------------------------------------------ *
 * vi 風のキー送り（プレビューのみ）
 *
 * プレビューは読み取り専用なので j/k をスクロールに使える。エディタ側は
 * 文字入力が最優先なので、この仕掛けはプレビューのページにしか載せない。
 * ------------------------------------------------------------------ */

var viPendingG = false;

function isTypingTarget(el) {
  if (!el) return false;
  var tag = String(el.tagName || "").toLowerCase();
  return tag === "input" || tag === "textarea" || el.isContentEditable === true;
}

/**
 * キーイベントを送り量に翻訳する。扱わないキーなら null。
 * 実際のスクロールは applyViCommand が行う（DOM に触らないので単体で試せる）。
 */
function viCommand(event) {
  // ⌘ はメニューのショートカット、⌥ は文字入力。どちらも横取りしない
  if (!event || event.metaKey || event.altKey || isTypingTarget(event.target)) {
    viPendingG = false;
    return null;
  }
  var key = event.key;

  if (event.ctrlKey) {
    viPendingG = false;
    if (key === "d") return { kind: "pages", amount: 0.5 };
    if (key === "u") return { kind: "pages", amount: -0.5 };
    if (key === "f") return { kind: "pages", amount: 1 };
    if (key === "b") return { kind: "pages", amount: -1 };
    return null;
  }

  // gg で先頭へ。1つ目の g は何もせずに待つ
  if (key === "g" && !event.shiftKey) {
    if (viPendingG) {
      viPendingG = false;
      return { kind: "top" };
    }
    viPendingG = true;
    return null;
  }
  viPendingG = false;

  if (key === "G") return { kind: "bottom" };
  if (key === "j") return { kind: "lines", amount: 1 };
  if (key === "k") return { kind: "lines", amount: -1 };
  return null;
}

/** 本文の行の高さ。取れないときは文字サイズから見積もる。 */
function viLineStep() {
  var style = window.getComputedStyle ? window.getComputedStyle(document.body) : null;
  var lineHeight = style ? parseFloat(style.lineHeight) : NaN;
  if (isFinite(lineHeight) && lineHeight > 0) return lineHeight;
  var fontSize = style ? parseFloat(style.fontSize) : NaN;
  return (isFinite(fontSize) && fontSize > 0 ? fontSize : 16) * 1.6;
}

function viDocumentHeight() {
  var el = document.documentElement || {};
  var body = document.body || {};
  return Math.max(el.scrollHeight || 0, body.scrollHeight || 0, el.offsetHeight || 0);
}

function applyViCommand(command) {
  if (!command) return;
  switch (command.kind) {
    case "lines":
      window.scrollBy({ top: viLineStep() * command.amount, behavior: "auto" });
      return;
    case "pages":
      window.scrollBy({ top: (window.innerHeight || 0) * command.amount, behavior: "auto" });
      return;
    case "top":
      window.scrollTo({ top: 0, behavior: "auto" });
      return;
    case "bottom":
      window.scrollTo({ top: viDocumentHeight(), behavior: "auto" });
      return;
    default:
      return;
  }
}

if (typeof document !== "undefined" && document.addEventListener && !document.__markpantherViKeysBound) {
  document.__markpantherViKeysBound = true;
  document.addEventListener("keydown", function (event) {
    var command = viCommand(event);
    if (!command) return;
    event.preventDefault();
    applyViCommand(command);
  });
}

/* ------------------------------------------------------------------ *
 * 公開
 * ------------------------------------------------------------------ */

if (typeof window !== "undefined") {
  window.MarkPanther = {
    render: render,
    getTopLine: getTopLine,
    scrollToLine: scrollToLine,
    getBodyHTML: getBodyHTML,
    exportHTML: exportHTML,
    setStyle: setStyle,
    find: find,
    clearFind: clearFind,
    bumpImageVersion: bumpImageVersion,
    setInsets: setInsets,
    setZoom: setZoom,
    scrollToFirstChange: scrollToFirstChange,
    clearChangeMarks: clearChangeMarks,
  };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    // options
    normalizeOptions: normalizeOptions,
    // frontmatter
    splitFrontmatter: splitFrontmatter,
    formatFrontmatterValue: formatFrontmatterValue,
    renderFrontmatterTable: renderFrontmatterTable,
    renderFrontmatterBlock: renderFrontmatterBlock,
    // heading / toc
    slugify: slugify,
    createSlugger: createSlugger,
    buildTocHtml: buildTocHtml,
    computeInlineText: computeInlineText,
    isTocPlaceholder: isTocPlaceholder,
    addHeadingIdAndTocRule: addHeadingIdAndTocRule,
    addDataLineRule: addDataLineRule,
    // image path
    normalizePath: normalizePath,
    joinPath: joinPath,
    rewriteImageSrc: rewriteImageSrc,
    rewriteImagesInHtml: rewriteImagesInHtml,
    bumpImageVersion: bumpImageVersion,
    // code
    wrapCodeLines: wrapCodeLines,
    highlightCode: highlightCode,
    // mermaid
    renderMermaidBlock: renderMermaidBlock,
    mermaidThemeVariables: mermaidThemeVariables,
    mermaidCache: mermaidCache,
    // 変更ハイライト
    decomposeIntoUnits: decomposeIntoUnits,
    collectUnits: collectUnits,
    computeUnitSignature: computeUnitSignature,
    markChangedUnits: markChangedUnits,
    demoteChangeHighlight: demoteChangeHighlight,
    diffAddedRanges: diffAddedRanges,
    diffTexts: diffTexts,
    collectChangedLines: collectChangedLines,
    insertRemovalMarkers: insertRemovalMarkers,
    insertGapMarkers: insertGapMarkers,
    showRemovedReveal: showRemovedReveal,
    hideRemovedReveal: hideRemovedReveal,
    clearChangeMarks: clearChangeMarks,
    scrollToFirstChange: scrollToFirstChange,
    // vi 風のキー送り
    viCommand: viCommand,
    applyViCommand: applyViCommand,
    viLineStep: viLineStep,
    // 検索
    findMatches: findMatches,
    buildSearchIndex: buildSearchIndex,
    resolveOffsetToNodeOffset: resolveOffsetToNodeOffset,
    buildRangeForMatch: buildRangeForMatch,
    find: find,
    clearFind: clearFind,
    // copy button
    codeTextForCopy: codeTextForCopy,
    // pipeline
    buildMarkdownIt: buildMarkdownIt,
    buildHtmlFromMarkdown: buildHtmlFromMarkdown,
    sanitizeHtml: sanitizeHtml,
    render: render,
    getTopLine: getTopLine,
    pickTopLine: pickTopLine,
    setInsets: setInsets,
    setZoom: setZoom,
    scrollToLine: scrollToLine,
    getBodyHTML: getBodyHTML,
    exportHTML: exportHTML,
    setStyle: setStyle,
    // misc
    escapeHtml: escapeHtml,
    escapeAttr: escapeAttr,
    decodeHtmlEntities: decodeHtmlEntities,
    getGlobal: getGlobal,
  };
}
