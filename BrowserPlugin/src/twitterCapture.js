const taskTraceButtonAttribute = "data-tasktrace-tweet-button";

function normalizeText(text) {
  return text.replace(/\s+/g, " ").trim();
}

export function createTweetCapturePayload(
  tweetElement,
  runtime = {
    locationHref:
      typeof window !== "undefined" ? (window.location?.href ?? "https://x.com") : "https://x.com",
    origin:
      typeof window !== "undefined"
        ? (window.location?.origin ?? "https://x.com")
        : "https://x.com"
  }
) {
  const articleTitle = normalizeText(
    tweetElement.querySelector('[data-testid="twitter-article-title"]')?.textContent || ""
  );
  const displayName = normalizeText(
    tweetElement.querySelector('[data-testid="User-Name"]')?.textContent || ""
  );
  const handle = Array.from(tweetElement.querySelectorAll("span"))
    .map((node) => normalizeText(node.textContent || ""))
    .find((text) => /^@[A-Za-z0-9_]+$/.test(text));
  const summaryText = normalizeText(
    tweetElement.querySelector('[data-testid="tweetText"]')?.textContent || ""
  );
  const statusURL =
    Array.from(tweetElement.querySelectorAll('a[href*="/status/"]'))
      .map((node) => node.getAttribute("href") || "")
      .filter((href) => href.length > 0)
      .filter((href) => !/\/(analytics|quotes)(\/|$)/.test(href))
      .filter((href) => !/\/(photo|video)\//.test(href))
      .at(-1) || runtime.locationHref;
  const absoluteStatusURL = /^https?:\/\//.test(statusURL)
    ? statusURL
    : new URL(statusURL, runtime.origin).toString();
  const title =
    articleTitle ||
    normalizeText(
      [displayName, handle].filter((value) => value && value.length > 0).join(" ")
    ) ||
    summaryText.slice(0, 120) ||
    "Tweet";

  return {
    title,
    url: absoluteStatusURL,
    html: tweetElement.outerHTML,
    contentType: "text/html",
    sourceContentType: "text/html"
  };
}

export async function handleTweetCapture(tweetElement, button, runtime = chrome.runtime) {
  if (button.disabled) {
    return;
  }

  button.disabled = true;
  button.style.opacity = "0.7";
  button.setAttribute("title", "Sending tweet to TaskTrace…");

  try {
    const response = await runtime.sendMessage({
      kind: "capture_html_fragment",
      fragment: createTweetCapturePayload(tweetElement)
    });

    if (!response?.ok) {
      throw new Error(response?.error || "TaskTrace browser plugin failed");
    }

    button.setAttribute("title", "Tweet sent to TaskTrace.");
  } catch (error) {
    button.setAttribute(
      "title",
      error instanceof Error ? error.message : "TaskTrace browser plugin failed"
    );
  } finally {
    button.disabled = false;
    button.style.opacity = "";
  }
}

export function decorateTweet(tweetElement, runtime = chrome.runtime) {
  if (tweetElement.querySelector(`[${taskTraceButtonAttribute}]`)) {
    return false;
  }

  const grokButton =
    tweetElement.querySelector('button[aria-label="Grok actions"]') ||
    tweetElement.querySelector('button[aria-label="Summarize"]');
  const moreButton =
    tweetElement.querySelector('button[data-testid="caret"]') ||
    tweetElement.querySelector('button[aria-label="More"]');
  const anchorButton = grokButton || moreButton;

  if (!anchorButton) {
    return false;
  }

  const button = anchorButton.cloneNode(true);
  const svg = button.querySelector("svg");

  button.setAttribute(taskTraceButtonAttribute, "true");
  button.setAttribute("aria-label", "Send tweet to TaskTrace");
  button.setAttribute("title", "Send tweet to TaskTrace");
  button.removeAttribute("aria-expanded");
  button.removeAttribute("aria-haspopup");
  button.removeAttribute("data-testid");

  Array.from(button.querySelectorAll("[data-testid]")).forEach((node) =>
    node.removeAttribute("data-testid")
  );

  if (svg) {
    const image = button.ownerDocument.createElement("img");
    image.src = runtime.getURL("icons/favicon-32x32.png");
    image.alt = "";
    image.width = 18;
    image.height = 18;
    image.style.display = "block";
    image.style.width = "18px";
    image.style.height = "18px";
    svg.replaceWith(image);
  }

  button.addEventListener("click", async (event) => {
    event.preventDefault();
    event.stopPropagation();

    await handleTweetCapture(tweetElement, button, runtime);
  });

  const anchorContainer =
    anchorButton.parentElement?.tagName === "DIV" ? anchorButton.parentElement : anchorButton;
  const wrapper =
    anchorContainer === anchorButton ? button : anchorContainer.cloneNode(false);

  if (wrapper !== button) {
    wrapper.append(button);
  }

  if (grokButton) {
    anchorContainer.after(wrapper);
  } else {
    anchorContainer.before(wrapper);
  }

  return true;
}

export function decorateTweetDocument(root = document, runtime = chrome.runtime) {
  return Array.from(root.querySelectorAll('article[data-testid="tweet"]')).map((tweetElement) =>
    decorateTweet(tweetElement, runtime)
  );
}

export function startTwitterCapture(
  root = document,
  runtime = chrome.runtime,
  location = window.location
) {
  if (!["x.com", "www.x.com", "twitter.com", "www.twitter.com"].includes(location.hostname)) {
    return false;
  }

  const start = () => {
    decorateTweetDocument(root, runtime);

    new MutationObserver(() => {
      decorateTweetDocument(root, runtime);
    }).observe(root.body, {
      childList: true,
      subtree: true
    });
  };

  if (root.readyState === "loading") {
    root.addEventListener("DOMContentLoaded", start, { once: true });
    return true;
  }

  start();
  return true;
}

if (
  typeof window !== "undefined" &&
  typeof document !== "undefined" &&
  typeof chrome !== "undefined" &&
  chrome.runtime?.sendMessage
) {
  startTwitterCapture();
}
