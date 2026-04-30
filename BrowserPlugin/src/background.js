import {
  convertHtmlStringToMarkdown,
  convertPdfArrayBufferToMarkdown,
  convertWordArrayBufferToMarkdown
} from "./markdownConversion.js";

const hostName = "com.tasktrace.browser_plugin";

export function describeNativeHostFailure(error) {
  const message = error instanceof Error ? error.message : "TaskTrace browser plugin failed";

  if (
    message.includes("Native host has exited") ||
    message.includes("message port closed before a response was received")
  ) {
    return "TaskTrace browser service is not running.";
  }

  return message;
}

function isPdfURL(url) {
  return /\.pdf([?#].*)?$/i.test(url);
}

function isDocxURL(url) {
  return /\.docx([?#].*)?$/i.test(url);
}

function isLegacyWordURL(url) {
  return /\.doc([?#].*)?$/i.test(url) && !isDocxURL(url);
}

function resolveFetchableURL(url) {
  try {
    const parsedURL = new URL(url);

    return (
      parsedURL.searchParams.get("file") ||
      parsedURL.searchParams.get("src") ||
      parsedURL.searchParams.get("url") ||
      url
    );
  } catch {
    return url;
  }
}

function captureHtmlFragment(fragment) {
  if (!fragment?.html) {
    throw new Error("TaskTrace browser plugin could not read the selected tweet.");
  }

  return {
    title: fragment.title || null,
    url: fragment.url || null,
    markdown: convertHtmlStringToMarkdown(fragment.html),
    contentType: "text/markdown",
    sourceContentType: fragment.sourceContentType || fragment.contentType || "text/html"
  };
}

async function captureHTMLSnapshot(tabId) {
  const [{ result }] = await chrome.scripting.executeScript({
    target: { tabId },
    func: () => ({
      title: document.title || null,
      url: window.location.href || null,
      html: document.documentElement.outerHTML,
      contentType: document.contentType || null
    })
  });

  return result;
}

async function fetchDocumentBytes(url) {
  const response = await fetch(resolveFetchableURL(url));

  if (!response.ok) {
    throw new Error(`Unable to fetch ${url}: ${response.status}`);
  }

  return response.arrayBuffer();
}

async function capturePage(tab) {
  const url = tab.url || "";
  const title = tab.title || null;

  if (isPdfURL(url)) {
    return {
      title,
      url,
      markdown: await convertPdfArrayBufferToMarkdown(await fetchDocumentBytes(url)),
      contentType: "text/markdown",
      sourceContentType: "application/pdf"
    };
  }

  if (isLegacyWordURL(url)) {
    throw new Error("Legacy .doc files are not supported. Convert the file to .docx.");
  }

  if (isDocxURL(url)) {
    return {
      title,
      url,
      markdown: await convertWordArrayBufferToMarkdown(await fetchDocumentBytes(url)),
      contentType: "text/markdown",
      sourceContentType:
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    };
  }

  const snapshot = await captureHTMLSnapshot(tab.id);

  if (snapshot.contentType === "application/pdf" || isPdfURL(snapshot.url || "")) {
    return {
      title: snapshot.title || title,
      url: snapshot.url || url,
      markdown: await convertPdfArrayBufferToMarkdown(
        await fetchDocumentBytes(snapshot.url || url)
      ),
      contentType: "text/markdown",
      sourceContentType: "application/pdf"
    };
  }

  if (isLegacyWordURL(snapshot.url || "")) {
    throw new Error("Legacy .doc files are not supported. Convert the file to .docx.");
  }

  if (
    snapshot.contentType ===
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
    isDocxURL(snapshot.url || "")
  ) {
    return {
      title: snapshot.title || title,
      url: snapshot.url || url,
      markdown: await convertWordArrayBufferToMarkdown(
        await fetchDocumentBytes(snapshot.url || url)
      ),
      contentType: "text/markdown",
      sourceContentType:
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    };
  }

  return {
    title: snapshot.title || title,
    url: snapshot.url || url,
    markdown: convertHtmlStringToMarkdown(snapshot.html),
    contentType: "text/markdown",
    sourceContentType: snapshot.contentType || "text/html"
  };
}

function sendRequestToNativeHost(tabId, request) {
  return new Promise((resolve, reject) => {
    const port = chrome.runtime.connectNative(hostName);
    let isSettled = false;

    port.onMessage.addListener((response) => {
      if (isSettled) {
        return;
      }

      isSettled = true;
      port.disconnect();

      if (response?.kind === "error") {
        reject(new Error(response?.message || "TaskTrace browser plugin failed"));
        return;
      }

      chrome.action.setBadgeText({ tabId, text: "OK" });
      chrome.action.setTitle({
        tabId,
        title: response?.message || "TaskTrace replied"
      });
      resolve(response);
    });

    port.onDisconnect.addListener(() => {
      if (isSettled) {
        return;
      }

      isSettled = true;

      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
        return;
      }

      reject(new Error("TaskTrace browser plugin failed"));
    });

    port.postMessage(request);
  });
}

function reportCaptureFailure(tabId, error) {
  console.error("TaskTrace browser plugin failed:", error);
  chrome.action.setBadgeText({ tabId, text: "ERR" });
  chrome.action.setTitle({
    tabId,
    title: describeNativeHostFailure(error)
  });
}

chrome.action.onClicked.addListener(async (tab) => {
  if (!tab.id) {
    return;
  }

  try {
    const page = await capturePage(tab);
    await sendRequestToNativeHost(tab.id, {
      kind: "capture_page_text",
      page
    });
  } catch (error) {
    reportCaptureFailure(tab.id, error);
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.kind !== "capture_html_fragment" || !sender.tab?.id) {
    return undefined;
  }

  (async () => {
    try {
      const page = captureHtmlFragment(message.fragment);
      await sendRequestToNativeHost(sender.tab.id, {
        kind: "capture_page_text",
        page
      });
      sendResponse({ ok: true });
    } catch (error) {
      reportCaptureFailure(sender.tab.id, error);
      sendResponse({
        ok: false,
        error: describeNativeHostFailure(error)
      });
    }
  })();

  return true;
});
