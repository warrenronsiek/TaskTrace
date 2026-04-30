import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

import { parseHTML } from "linkedom";

import {
  createTweetCapturePayload,
  decorateTweet,
  handleTweetCapture
} from "../src/twitterCapture.js";

test("tweet payload resolves the status permalink for article tweets", async () => {
  const html = await readFile(new URL("./fixtures/x-article.html", import.meta.url), "utf8");
  const { document } = parseHTML(html);
  const tweet = document.querySelector('article[data-testid="tweet"]');
  const payload = createTweetCapturePayload(tweet, {
    locationHref: "https://x.com/home",
    origin: "https://x.com"
  });

  assert.equal(payload.title, "GPU Memory Math for LLMs (2026 Edition)");
  assert.equal(payload.url, "https://x.com/TheAhmadOsman/status/2040103488714068245");
  assert.match(payload.html, /data-testid="twitterArticleRichTextView"/);
});

test("tweet decoration injects a TaskTrace action and sends fragment capture messages", async () => {
  const html = await readFile(new URL("./fixtures/x-article.html", import.meta.url), "utf8");
  const { document, window } = parseHTML(html);
  const tweet = document.querySelector('article[data-testid="tweet"]');
  let message = null;

  globalThis.window = window;
  globalThis.document = document;

  try {
    assert.equal(
      decorateTweet(tweet, {
        getURL(path) {
          return `chrome-extension://tasktrace/${path}`;
        },
        async sendMessage(payload) {
          message = payload;
          return { ok: true };
        }
      }),
      true
    );

    const taskTraceButton = tweet.querySelector('[data-tasktrace-tweet-button="true"]');
    const icon = taskTraceButton?.querySelector("img");

    assert.ok(taskTraceButton);
    assert.equal(taskTraceButton?.getAttribute("aria-label"), "Send tweet to TaskTrace");
    assert.equal(
      icon?.getAttribute("src"),
      "chrome-extension://tasktrace/icons/favicon-32x32.png"
    );

    await handleTweetCapture(tweet, taskTraceButton, {
      getURL(path) {
        return `chrome-extension://tasktrace/${path}`;
      },
      async sendMessage(payload) {
        message = payload;
        return { ok: true };
      }
    });

    assert.equal(message?.kind, "capture_html_fragment");
    assert.equal(
      message?.fragment?.url,
      "https://x.com/TheAhmadOsman/status/2040103488714068245"
    );
    assert.match(message?.fragment?.html || "", /data-testid="tweet"/);
  } finally {
    delete globalThis.window;
    delete globalThis.document;
  }
});
