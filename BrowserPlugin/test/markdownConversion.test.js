import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

import {
  convertHtmlStringToMarkdown,
  convertPdfArrayBufferToMarkdown,
  convertWordArrayBufferToMarkdown
} from "../src/markdownConversion.js";

function normalizeForAssertion(markdown) {
  return markdown
    .replace(/\\([\\`*_[\]().!:-])/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

function asArrayBuffer(buffer) {
  return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
}

async function readFixtureMarkdown(filename) {
  const html = await readFile(new URL(`./fixtures/${filename}`, import.meta.url), "utf8");
  return convertHtmlStringToMarkdown(html);
}

test("html pages convert into markdown", () => {
  const html = `
    <html>
      <body>
        <article>
          <h1>TaskTrace Browser Plugin</h1>
          <p>Hello <strong>world</strong> and <a href="https://example.com/docs">docs</a>.</p>
          <ul>
            <li>Alpha</li>
            <li>Beta</li>
          </ul>
          <table>
            <tr><th>Name</th><th>Value</th></tr>
            <tr><td>Gamma</td><td>42</td></tr>
          </table>
        </article>
      </body>
    </html>
  `;
  const markdown = convertHtmlStringToMarkdown(html);

  assert.equal(
    markdown,
    [
      "# TaskTrace Browser Plugin",
      "",
      "Hello **world** and [docs](https://example.com/docs).",
      "",
      "- Alpha",
      "- Beta",
      "",
      "| Name | Value |",
      "| --- | --- |",
      "| Gamma | 42 |"
    ].join("\n")
  );
});

test("sample pdf converts into markdown with expected paper content", async () => {
  const pdfFile = await readFile(new URL("../2404.16130v2.pdf", import.meta.url));
  const markdown = await convertPdfArrayBufferToMarkdown(asArrayBuffer(pdfFile));
  const normalizedMarkdown = normalizeForAssertion(markdown);

  assert.match(
    normalizedMarkdown,
    /From Local to Global: A GraphRAG Approach to Query-Focused Summarization/
  );
  assert.match(normalizedMarkdown, /The use of retrieval-augmented generation \(RAG\)/);
  assert.match(normalizedMarkdown, /GraphRAG leads to substantial improvements over a conventional RAG baseline/);
});

test("sample docx content converts into markdown", async () => {
  const docxFile = await readFile(new URL("../file-sample_500kB.docx", import.meta.url));
  const markdown = await convertWordArrayBufferToMarkdown(asArrayBuffer(docxFile));
  const normalizedMarkdown = normalizeForAssertion(markdown);

  assert.match(normalizedMarkdown, /Lorem ipsum dolor sit amet, consectetur adipiscing elit\. Nunc ac faucibus odio\./);
  assert.match(normalizedMarkdown, /Aenean congue fringilla justo ut aliquam\./);
  assert.match(normalizedMarkdown, /Cras fringilla ipsum magna, in fringilla dui commodo a\./);
  assert.match(normalizedMarkdown, /In eleifend velit vitae libero sollicitudin euismod\./);
});

test("tweet fixture converts into focused tweet markdown", async () => {
  const html = await readFile(new URL("./fixtures/x-tweet.html", import.meta.url), "utf8");
  const markdown = convertHtmlStringToMarkdown(html);
  const normalizedMarkdown = normalizeForAssertion(markdown);

  assert.match(
    normalizedMarkdown,
    /GENUINELY what are you even doing with your openclaws\?\?\?\? i have legitimately not seen a single good use case/
  );
  assert.match(
    normalizedMarkdown,
    /I know OpenClaw isn't part of OpenAI but this feels like a mini-crisis for OpenAI if the GPT integration doesn't improve soon\./
  );
  assert.match(normalizedMarkdown, /@justalexoki/);
  assert.doesNotMatch(normalizedMarkdown, /Share post/);
  assert.doesNotMatch(normalizedMarkdown, /Reply/);
  assert.doesNotMatch(normalizedMarkdown, /Relevant/);
});

test("twitter article fixture converts into focused article markdown", async () => {
  const html = await readFile(new URL("./fixtures/x-article.html", import.meta.url), "utf8");
  const markdown = convertHtmlStringToMarkdown(html);
  const normalizedMarkdown = normalizeForAssertion(markdown);

  assert.match(normalizedMarkdown, /GPU Memory Math for LLMs \(2026 Edition\)/);
  assert.match(
    normalizedMarkdown,
    /If you’re running models locally, thinking “model → VRAM” falls apart once you account for how the weights were trained and quantized in the first place\./
  );
  assert.match(normalizedMarkdown, /The Only Conversion You Actually Need/);
  assert.match(normalizedMarkdown, /FP16 \/ BF16 → 16 bits → ~2 GB per 1B params/);
  assert.match(normalizedMarkdown, /GGUF Is Not Magic/);
  assert.doesNotMatch(normalizedMarkdown, /Summarize/);
  assert.doesNotMatch(normalizedMarkdown, /Share post/);
  assert.doesNotMatch(normalizedMarkdown, /Reply/);
});

test("palladium article fixture converts into focused article markdown", async () => {
  const html = await readFile(new URL("./fixtures/palladium-article.html", import.meta.url), "utf8");
  const markdown = convertHtmlStringToMarkdown(html);
  const normalizedMarkdown = normalizeForAssertion(markdown);

  assert.match(markdown, /^# Think Tanks Have Defeated Democracy/m);
  assert.match(normalizedMarkdown, /Samuel Hammond, April 2, 2026/);
  assert.match(
    normalizedMarkdown,
    /As a Canadian, studying the output of American think tanks has become something of an obsession for me\./
  );
  assert.match(normalizedMarkdown, /transaction costs and \[the game theory that pulls electoral democracies towards a two party system, termed Duverger’s law\]/);
  assert.match(normalizedMarkdown, /## Associations Without Members/);
  assert.match(normalizedMarkdown, /## The Anti-Social Impact of Nonprofits/);
  assert.doesNotMatch(normalizedMarkdown, /Posted in Articles/);
  assert.doesNotMatch(normalizedMarkdown, /Bookmark the permalink/);
  assert.doesNotMatch(normalizedMarkdown, /Related/);
  assert.doesNotMatch(normalizedMarkdown, /@hamandcheese/);
});

test("structured article metadata, figures, and relative URLs convert cleanly", () => {
  const html = `
    <html>
      <head>
        <base href="https://example.com/articles/story/">
        <title>Fallback Title</title>
        <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "NewsArticle",
            "headline": "Structured Story",
            "author": [{ "name": "Jane Doe" }],
            "datePublished": "2026-04-16"
          }
        </script>
      </head>
      <body>
        <div class="sidebar related-posts">
          <a href="/one">one</a>
          <a href="/two">two</a>
          <a href="/three">three</a>
        </div>
        <article class="story">
          <div class="story-body">
            <p>This is the main article body with enough text to outrank the sidebar and exercise the article scoring logic for markdown extraction. It keeps going because short snippets often look like marketing blurbs or navigation copy, and the whole point of the extraction pass is to avoid treating those scraps as the primary article.</p>
            <figure>
              <img src="/images/lead.jpg" alt="Lead">
              <figcaption>Lead image caption.</figcaption>
            </figure>
            <p>Read <a href="/docs/reference">the reference</a> for more detail on how this should work in practice across arbitrary websites. The parser should keep the body, preserve the figure caption, and resolve the relative links into absolute URLs so the captured markdown still makes sense when opened later outside the source site.</p>
          </div>
        </article>
      </body>
    </html>
  `;
  const markdown = convertHtmlStringToMarkdown(html);
  const normalizedMarkdown = normalizeForAssertion(markdown);

  assert.match(markdown, /^# Structured Story/m);
  assert.match(normalizedMarkdown, /Jane Doe, 2026-04-16/);
  assert.match(normalizedMarkdown, /!\[Lead\]\(https:\/\/example\.com\/images\/lead\.jpg\)/);
  assert.match(normalizedMarkdown, /\*Lead image caption\.\*/);
  assert.match(normalizedMarkdown, /\[the reference\]\(https:\/\/example\.com\/docs\/reference\)/);
  assert.doesNotMatch(normalizedMarkdown, /one two three/);
});

test("live palladium article fixture parses into focused markdown", async () => {
  const markdown = await readFixtureMarkdown("palladium-think-tanks-live.html");
  const normalizedMarkdown = normalizeForAssertion(markdown);

  assert.ok(markdown.length > 10000);
  assert.match(markdown, /^# Think Tanks Have Defeated Democracy/m);
  assert.match(normalizedMarkdown, /Samuel Hammond, April 2, 2026/);
  assert.match(normalizedMarkdown, /\*Sam Jotham Sutharson\/Washington, D\.C\. metro station\*/);
  assert.match(normalizedMarkdown, /### Associations Without Members/);
  assert.doesNotMatch(normalizedMarkdown, /Posted in Articles/);
  assert.doesNotMatch(normalizedMarkdown, /Bookmark the permalink/);
  assert.doesNotMatch(normalizedMarkdown, /Related/);
});

test("live MDN reference fixture parses into structured docs markdown", async () => {
  const markdown = await readFixtureMarkdown("mdn-article-element-live.html");
  const normalizedMarkdown = normalizeForAssertion(markdown);

  assert.ok(markdown.length > 4000);
  assert.match(markdown, /^# <article>: The Article Contents element/m);
  assert.match(normalizedMarkdown, /## Try it/);
  assert.match(normalizedMarkdown, /Weather forecast for Seattle/);
  assert.match(normalizedMarkdown, /## Technical summary/);
  assert.doesNotMatch(normalizedMarkdown, /Your blueprint for a better internet/);
  assert.doesNotMatch(markdown, /^# <article>: The Article Contents element\n\n# <article>: The Article Contents element/m);
});

test("live Wikipedia fixture parses into sensible article markdown", async () => {
  const markdown = await readFixtureMarkdown("wikipedia-markdown-live.html");
  const normalizedMarkdown = normalizeForAssertion(markdown);

  assert.ok(markdown.length > 12000);
  assert.match(markdown, /^# Markdown/m);
  assert.match(normalizedMarkdown, /lightweight markup language/);
  assert.match(normalizedMarkdown, /## History/);
  assert.match(normalizedMarkdown, /## External links/);
  assert.doesNotMatch(normalizedMarkdown, /From Wikipedia, the free encyclopedia/);
  assert.doesNotMatch(normalizedMarkdown, /Categories:/);
  assert.doesNotMatch(normalizedMarkdown, /This article relies excessively on references to primary sources/);
});

test("live Go tutorial fixture parses into tutorial markdown", async () => {
  const markdown = await readFixtureMarkdown("go-tutorial-getting-started-live.html");
  const normalizedMarkdown = normalizeForAssertion(markdown);

  assert.ok(markdown.length > 5000);
  assert.match(markdown, /^# Tutorial: Get started with Go/m);
  assert.match(normalizedMarkdown, /## Prerequisites/);
  assert.match(normalizedMarkdown, /## Write some code/);
  assert.match(normalizedMarkdown, /Hello, world/);
  assert.match(normalizedMarkdown, /## Call code in an external package/);
  assert.doesNotMatch(normalizedMarkdown, /Why Go/);
});

test("live CDC page fixture parses into clean health guidance markdown", async () => {
  const markdown = await readFixtureMarkdown("cdc-measles-about-live.html");
  const normalizedMarkdown = normalizeForAssertion(markdown);

  assert.ok(markdown.length > 3000);
  assert.match(markdown, /^# About Measles/m);
  assert.match(normalizedMarkdown, /## Key points/);
  assert.match(normalizedMarkdown, /## Signs and symptoms/);
  assert.match(normalizedMarkdown, /## Resources/);
  assert.doesNotMatch(normalizedMarkdown, /Skip directly to site content/);
  assert.doesNotMatch(normalizedMarkdown, /Sources Print Share/);
  assert.doesNotMatch(normalizedMarkdown, /May 29, 2024$/);
});
