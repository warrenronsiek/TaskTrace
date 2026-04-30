import { parseHTML } from "linkedom";
import * as mammoth from "mammoth";
import * as pdfjs from "pdfjs-dist/legacy/build/pdf.mjs";
import { WorkerMessageHandler } from "pdfjs-dist/legacy/build/pdf.worker.mjs";

if (typeof chrome !== "undefined" && chrome.runtime?.getURL) {
  globalThis.pdfjsWorker = { WorkerMessageHandler };
  pdfjs.GlobalWorkerOptions.workerSrc = chrome.runtime.getURL("pdf.worker.mjs");
}

const ignoredTags = new Set([
  "head",
  "meta",
  "script",
  "style",
  "noscript",
  "template",
  "svg",
  "canvas"
]);

const blockContainerTags = new Set([
  "article",
  "aside",
  "body",
  "div",
  "footer",
  "header",
  "main",
  "section"
]);

const focusedArticleBodySelectors = [
  "#mw-content-text .mw-parser-output",
  "[itemprop='articleBody']",
  "main [itemprop='articleBody']",
  "main .main-page-content",
  "main .main-content",
  "#content article",
  "article .entry-content",
  "article [itemprop='articleBody']",
  "article .article-content",
  "article .article-body",
  "article .post-content",
  "article .story-content",
  "article .content",
  "main article .entry-content",
  "main article",
  "article"
];

const removableArticleSelectors = [
  ".entry-header",
  ".author-bio",
  ".ambox",
  ".catlinks",
  ".comments",
  ".comments-area",
  ".contributors",
  ".cdc-page-title",
  ".cdc-page-title-bar",
  ".entry-footer",
  ".feedback",
  ".hatnote",
  ".infobox",
  ".jp-relatedposts",
  ".metadata",
  ".mw-editsection",
  ".navbox",
  ".newsletter-form",
  ".page-content-sources",
  ".post-navigation",
  ".reflist",
  ".related",
  ".related-posts",
  ".sharedaddy",
  ".sharing",
  ".shortdescription",
  ".toc",
  "#jp-relatedposts",
  "#siteSub",
  "aside",
  "footer",
  "form",
  "nav",
  "[data-action='print']",
  "[data-action='share']",
  "[data-action='summary']"
];

const articleLikeTypePattern =
  /Article|NewsArticle|BlogPosting|Report|AnalysisNewsArticle|ScholarlyArticle|WebPage/u;

const noisyContainerPattern =
  /(comment|footer|related|share|social|promo|advert|newsletter|subscribe|outbrain|taboola|sidebar|toolbar|cookie|banner|modal|popup|nav|menu)/iu;

function joinRenderedFragments(fragments) {
  return fragments.filter((fragment) => fragment.length > 0).reduce((joined, fragment) => {
    if (joined.length === 0) {
      return fragment;
    }

    const previousCharacter = joined.at(-1) || "";
    const nextCharacter = fragment[0] || "";
    const needsSpace =
      previousCharacter !== "\n" &&
      nextCharacter !== "\n" &&
      previousCharacter !== " " &&
      nextCharacter !== " " &&
      /[\p{L}\p{N}"'*)\]]/u.test(previousCharacter) &&
      /[\p{L}\p{N}\[(`"'*_]/u.test(nextCharacter);

    return `${joined}${needsSpace ? " " : ""}${fragment}`;
  }, "");
}

function resolveURLAttribute(value, baseURL) {
  if (!value || !baseURL || value.startsWith("#") || /^(data:|mailto:|tel:|javascript:)/i.test(value)) {
    return value || "";
  }

  try {
    return new URL(value, baseURL).href;
  } catch {
    return value;
  }
}

function extractDocumentMetadata(document) {
  const canonicalURL =
    document.querySelector("link[rel='canonical']")?.getAttribute("href") ||
    document.querySelector("meta[property='og:url']")?.getAttribute("content") ||
    document.baseURI ||
    "";
  const parseStructuredData = () =>
    Array.from(document.querySelectorAll("script[type='application/ld+json']"))
      .flatMap((node) => {
        try {
          const parsed = JSON.parse(node.textContent || "null");
          return Array.isArray(parsed)
            ? parsed
            : parsed?.["@graph"]
              ? parsed["@graph"]
              : parsed
                ? [parsed]
                : [];
        } catch {
          return [];
        }
      })
      .filter((entry) => entry && typeof entry === "object");
  const structuredEntries = parseStructuredData();
  const primaryStructuredEntry =
    structuredEntries.find((entry) =>
      `${entry["@type"] || ""}`.split(",").some((value) => articleLikeTypePattern.test(value))
    ) ||
    structuredEntries.find((entry) => `${entry["@type"] || ""}`.includes("WebPage")) ||
    null;
  const normalizeAuthor = (value) =>
    normalizeInlineMarkdown(
      (Array.isArray(value) ? value : [value])
        .flatMap((entry) =>
          typeof entry === "string"
            ? [entry]
            : entry && typeof entry === "object"
              ? [entry.name || entry.alternateName || ""]
              : []
        )
        .filter((entry) => entry.length > 0)
        .join(", ")
    );

  return {
    baseURL: canonicalURL || document.baseURI || "",
    canonicalURL: canonicalURL || "",
    title: normalizeInlineMarkdown(
      primaryStructuredEntry?.headline ||
        primaryStructuredEntry?.name ||
        document.querySelector("meta[property='og:title']")?.getAttribute("content") ||
        document.querySelector("meta[name='twitter:title']")?.getAttribute("content") ||
        document.title ||
        ""
    ),
    author: normalizeAuthor(
      primaryStructuredEntry?.author ||
        document.querySelector("meta[name='author']")?.getAttribute("content") ||
        ""
    ),
    publishedAt: normalizeInlineMarkdown(
      primaryStructuredEntry?.datePublished ||
        document.querySelector("meta[property='article:published_time']")?.getAttribute("content") ||
        document.querySelector("meta[name='pubdate']")?.getAttribute("content") ||
        ""
    )
  };
}

function scoreContentCandidate(node) {
  const textLength = normalizeInlineMarkdown(node.textContent || "").length;

  if (textLength < 280) {
    return Number.NEGATIVE_INFINITY;
  }

  const paragraphCount = node.querySelectorAll("p").length;
  const headingCount = node.querySelectorAll("h1, h2, h3").length;
  const imageCount = node.querySelectorAll("img, figure").length;
  const linkTextLength = Array.from(node.querySelectorAll("a"))
    .map((anchor) => normalizeInlineMarkdown(anchor.textContent || "").length)
    .reduce((sum, length) => sum + length, 0);
  const linkDensity = linkTextLength / Math.max(textLength, 1);
  const markerText = `${node.id || ""} ${node.className || ""} ${node.getAttribute("role") || ""}`;
  const articleBonus =
    (node.localName === "article" ? 800 : 0) +
    (node.localName === "main" ? 500 : 0) +
    (/article|post|story|entry|content|body|main/iu.test(markerText) ? 450 : 0);
  const noisePenalty = noisyContainerPattern.test(markerText) ? 900 : 0;

  return (
    textLength +
    paragraphCount * 420 +
    headingCount * 160 +
    imageCount * 80 +
    articleBonus -
    linkDensity * textLength * 1.6 -
    noisePenalty
  );
}

function cloneAndPrepareContentRoot(node, baseURL) {
  const clone = node.cloneNode(true);
  const noisyElements = Array.from(clone.querySelectorAll("*")).filter((element) => {
    const markerText = `${element.id || ""} ${element.className || ""} ${element.getAttribute("role") || ""}`;
    const textLength = normalizeInlineMarkdown(element.textContent || "").length;

    return (
      element.matches("[hidden], [aria-hidden='true'], [role='navigation'], [role='complementary']") ||
      removableArticleSelectors.some((selector) => element.matches(selector)) ||
      (
        noisyContainerPattern.test(markerText) &&
        ["aside", "div", "section", "ul", "ol"].includes(element.localName.toLowerCase()) &&
        textLength < 700
      )
    );
  });

  noisyElements.forEach((element) => element.remove());
  Array.from(clone.querySelectorAll("[href]")).forEach((element) => {
    element.setAttribute(
      "href",
      resolveURLAttribute(element.getAttribute("href") || "", baseURL)
    );
  });
  Array.from(clone.querySelectorAll("[src]")).forEach((element) => {
    element.setAttribute("src", resolveURLAttribute(element.getAttribute("src") || "", baseURL));
  });
  Array.from(clone.querySelectorAll("[srcset]")).forEach((element) => {
    element.setAttribute(
      "srcset",
      (element.getAttribute("srcset") || "")
        .split(",")
        .map((candidate) => {
          const [url, descriptor] = candidate.trim().split(/\s+/, 2);
          return [resolveURLAttribute(url || "", baseURL), descriptor].filter(Boolean).join(" ");
        })
        .filter((candidate) => candidate.length > 0)
        .join(", ")
    );
  });

  return clone;
}

function normalizeInlineMarkdown(markdown) {
  return markdown
    .replace(/\s+/g, " ")
    .replace(/\s+([,.;:!?])/g, "$1")
    .replace(/\(\s+/g, "(")
    .replace(/\s+\)/g, ")")
    .trim();
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function finalizeMarkdown(markdown) {
  return markdown
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function stripRedundantLeadingContent(markdown, title, publishedAt) {
  let cleanedMarkdown = markdown.trim();

  if (title.length > 0) {
    cleanedMarkdown = cleanedMarkdown.replace(
      new RegExp(`^# ${escapeRegExp(title)}\\n\\n`, "u"),
      ""
    );
  }

  if (publishedAt.length > 0) {
    cleanedMarkdown = cleanedMarkdown.replace(
      new RegExp(`^${escapeRegExp(publishedAt)}\\n\\n`, "u"),
      ""
    );
    cleanedMarkdown = cleanedMarkdown.replace(
      new RegExp(`\\n\\n${escapeRegExp(publishedAt)}$`, "u"),
      ""
    );
  }

  return cleanedMarkdown.trim();
}

function renderNode(node, context = { listDepth: 0 }) {
  if (!node) {
    return "";
  }

  if (node.nodeType === node.TEXT_NODE) {
    const collapsedText = node.textContent.replace(/\s+/g, " ");
    return collapsedText.trim().length === 0 ? "" : collapsedText;
  }

  if (node.nodeType !== node.ELEMENT_NODE) {
    return "";
  }

  const tagName = node.localName.toLowerCase();

  if (ignoredTags.has(tagName)) {
    return "";
  }

  if (tagName === "br") {
    return "\n";
  }

  if (tagName === "hr") {
    return "\n---\n\n";
  }

  if (/^h[1-6]$/.test(tagName)) {
    const level = Number.parseInt(tagName[1], 10);
    const heading = normalizeInlineMarkdown(node.textContent || "");

    return heading.length === 0 ? "" : `${"#".repeat(level)} ${heading}\n\n`;
  }

  if (tagName === "pre") {
    const code = node.textContent.replace(/\n+$/g, "");
    return code.length === 0 ? "" : `\`\`\`\n${code}\n\`\`\`\n\n`;
  }

  if (tagName === "code") {
    if (node.parentElement?.localName.toLowerCase() === "pre") {
      return node.textContent;
    }

    const code = normalizeInlineMarkdown(node.textContent);
    return code.length === 0 ? "" : `\`${code}\``;
  }

  if (tagName === "strong" || tagName === "b") {
    const content = normalizeInlineMarkdown(
      Array.from(node.childNodes)
        .map((childNode) => renderNode(childNode, context))
        .reduce((joined, fragment) => joinRenderedFragments([joined, fragment]), "")
    );

    return content.length === 0 ? "" : `**${content}**`;
  }

  if (tagName === "em" || tagName === "i") {
    const content = normalizeInlineMarkdown(
      Array.from(node.childNodes)
        .map((childNode) => renderNode(childNode, context))
        .reduce((joined, fragment) => joinRenderedFragments([joined, fragment]), "")
    );

    return content.length === 0 ? "" : `*${content}*`;
  }

  if (tagName === "a") {
    const href = node.getAttribute("href");
    const content = normalizeInlineMarkdown(
      Array.from(node.childNodes)
        .map((childNode) => renderNode(childNode, context))
        .reduce((joined, fragment) => joinRenderedFragments([joined, fragment]), "")
    ) || href || "";

    return href ? `[${content}](${href})` : content;
  }

  if (tagName === "img") {
    const alt = node.getAttribute("alt") || "";
    const src = node.getAttribute("src") || "";
    return src.length === 0 ? "" : `![${alt}](${src})`;
  }

  if (
    /caption|credit/iu.test(node.getAttribute("class") || "") &&
    tagName !== "figcaption"
  ) {
    const caption = normalizeInlineMarkdown(node.textContent || "");
    return caption.length === 0 ? "" : `\n\n*${caption}*\n\n`;
  }

  if (tagName === "figure") {
    const figureBody = finalizeMarkdown(
      joinRenderedFragments(
        Array.from(node.childNodes)
          .filter((childNode) => childNode.localName?.toLowerCase() !== "figcaption")
          .map((childNode) => renderNode(childNode, context))
      )
    );
    const caption = normalizeInlineMarkdown(
      node.querySelector("figcaption")?.textContent || ""
    );

    return finalizeMarkdown(
      [figureBody, caption.length > 0 ? `*${caption}*` : ""]
        .filter((section) => section.length > 0)
        .join("\n\n")
    ).concat("\n\n");
  }

  if (tagName === "blockquote") {
    const content = finalizeMarkdown(
      Array.from(node.childNodes)
        .map((childNode) => renderNode(childNode, context))
        .reduce((joined, fragment) => joinRenderedFragments([joined, fragment]), "")
    );

    return content.length === 0
      ? ""
      : `${content
          .split("\n")
          .map((line) => (line.length === 0 ? ">" : `> ${line}`))
          .join("\n")}\n\n`;
  }

  if (tagName === "p") {
    const content = normalizeInlineMarkdown(
      Array.from(node.childNodes)
        .map((childNode) => renderNode(childNode, context))
        .reduce((joined, fragment) => joinRenderedFragments([joined, fragment]), "")
    );

    return content.length === 0 ? "" : `${content}\n\n`;
  }

  if (tagName === "ul" || tagName === "ol") {
    const isOrdered = tagName === "ol";
    const items = Array.from(node.children).filter(
      (childNode) => childNode.localName?.toLowerCase() === "li"
    );

    const markdown = items
      .map((itemNode, index) => {
        const prefix = isOrdered ? `${index + 1}. ` : "- ";
        const inlineNodes = Array.from(itemNode.childNodes).filter((childNode) => {
          const childTagName = childNode.localName?.toLowerCase();
          return childTagName !== "ol" && childTagName !== "ul";
        });
        const nestedLists = Array.from(itemNode.childNodes).filter((childNode) => {
          const childTagName = childNode.localName?.toLowerCase();
          return childTagName === "ol" || childTagName === "ul";
        });
        const inlineContent = normalizeInlineMarkdown(
          joinRenderedFragments(inlineNodes.map((childNode) => renderNode(childNode, context)))
        );
        const baseIndent = "  ".repeat(context.listDepth);
        const nestedContent = nestedLists
          .map((childNode) => renderNode(childNode, { listDepth: context.listDepth + 1 }))
          .join("");

        return `${baseIndent}${prefix}${inlineContent}\n${nestedContent}`;
      })
      .join("");

    return `${markdown}\n`;
  }

  if (tagName === "table") {
    const rows = Array.from(node.querySelectorAll("tr"))
      .map((rowNode) =>
        Array.from(rowNode.children)
          .filter((cellNode) => ["th", "td"].includes(cellNode.localName.toLowerCase()))
          .map((cellNode) =>
            normalizeInlineMarkdown(
              Array.from(cellNode.childNodes)
                .map((childNode) => renderNode(childNode, context))
                .reduce((joined, fragment) => joinRenderedFragments([joined, fragment]), "")
            )
          )
      )
      .filter((row) => row.length > 0);

    if (rows.length === 0) {
      return "";
    }

    const columnCount = Math.max(...rows.map((row) => row.length));
    const normalizedRows = rows.map((row) =>
      Array.from({ length: columnCount }, (_, index) => row[index] || "")
    );
    const header = normalizedRows[0];
    const body = normalizedRows.slice(1);

    return [
      `| ${header.join(" | ")} |`,
      `| ${header.map(() => "---").join(" | ")} |`,
      ...body.map((row) => `| ${row.join(" | ")} |`),
      ""
    ].join("\n");
  }

  const children = joinRenderedFragments(
    Array.from(node.childNodes).map((childNode) => renderNode(childNode, context))
  );

  if (blockContainerTags.has(tagName)) {
    const content = finalizeMarkdown(children);
    return content.length === 0
      ? ""
      : /\n\n/.test(content)
        ? `${content}\n\n`
        : `${content}\n\n`;
  }

  return children;
}

export function convertHtmlStringToMarkdown(html) {
  const { document } = parseHTML(html);
  const metadata = extractDocumentMetadata(document);
  const twitterMarkdown = (() => {
    const tweetTexts = Array.from(document.querySelectorAll('[data-testid="tweetText"]'))
      .map((node) => normalizeInlineMarkdown(node.textContent || ""))
      .filter((text) => text.length > 0);
    const articleTitle = normalizeInlineMarkdown(
      document.querySelector('[data-testid="twitter-article-title"]')?.textContent || ""
    );
    const articleBody = document.querySelector('[data-testid="twitterArticleRichTextView"]');

    if (tweetTexts.length === 0 && articleTitle.length === 0 && !articleBody) {
      return null;
    }

    const displayNames = Array.from(document.querySelectorAll('[data-testid="User-Name"]'))
      .map((node) => normalizeInlineMarkdown(node.textContent || ""))
      .filter((text) => text.length > 0);
    const handles = Array.from(document.querySelectorAll("span"))
      .map((node) => normalizeInlineMarkdown(node.textContent || ""))
      .filter((text) => /^@[A-Za-z0-9_]+$/.test(text))
      .filter((text, index, values) => values.indexOf(text) === index);
    const resolveStatusURL = () =>
      Array.from(document.querySelectorAll('a[href*="/status/"]'))
        .map((node) => node.getAttribute("href") || "")
        .filter((href) => href.length > 0)
        .filter((href) => !/\/(analytics|quotes)(\/|$)/.test(href))
        .filter((href) => !/\/(photo|video)\//.test(href))
        .at(-1) || null;
    const statusURL = resolveStatusURL();
    const absoluteStatusURL =
      statusURL === null
        ? null
        : /^https?:\/\//.test(statusURL)
          ? statusURL
          : `https://x.com${statusURL}`;
    const mediaURLs = Array.from(document.querySelectorAll('[data-testid="tweetPhoto"] img'))
      .map((node) => node.getAttribute("src") || "")
      .filter((src) => src.length > 0)
      .filter((src, index, values) => values.indexOf(src) === index);
    const primaryAuthor = [displayNames[0] || null, handles[0] || null]
      .filter((value) => value !== null)
      .join(" ");
    const quoteAuthor = [displayNames[1] || null, handles[1] || null]
      .filter((value) => value !== null)
      .join(" ");

    if (articleTitle.length > 0 || articleBody) {
      const leadingImage = mediaURLs[0] ? `![Image](${mediaURLs[0]})` : "";
      const articleMarkdown = articleBody ? finalizeMarkdown(renderNode(articleBody)) : "";

      return finalizeMarkdown(
        [
          articleTitle.length > 0 ? `# ${articleTitle}` : "",
          primaryAuthor,
          absoluteStatusURL ? `Source: ${absoluteStatusURL}` : "",
          leadingImage,
          articleMarkdown
        ]
          .filter((section) => section.length > 0)
          .join("\n\n")
      );
    }

    const mainTweet = tweetTexts[0] || "";
    const quoteTweet = tweetTexts[1] || "";
    const quoteBlock =
      quoteTweet.length === 0
        ? ""
        : [
            quoteAuthor,
            quoteTweet,
            ...mediaURLs.map((url) => `![Image](${url})`)
          ]
            .filter((section) => section.length > 0)
            .map((line) => `> ${line}`)
            .join("\n");

    return finalizeMarkdown(
      [
        primaryAuthor.length > 0 ? `# ${primaryAuthor}` : "",
        mainTweet,
        quoteBlock,
        absoluteStatusURL ? `Source: ${absoluteStatusURL}` : ""
      ]
        .filter((section) => section.length > 0)
        .join("\n\n")
    );
  })();

  if (twitterMarkdown !== null) {
    return twitterMarkdown;
  }

  const articleMarkdown = (() => {
    const articleBody = Array.from(
      new Set(
        [
          ...focusedArticleBodySelectors.flatMap((selector) =>
            Array.from(document.querySelectorAll(selector))
          ),
          ...Array.from(document.querySelectorAll("article, main, [role='main'], section, div"))
        ].filter((node) => node !== null)
      )
    )
      .map((node) => ({
        node,
        score: scoreContentCandidate(node)
      }))
      .filter((candidate) => Number.isFinite(candidate.score))
      .sort((left, right) => right.score - left.score)[0]?.node || null;

    if (!articleBody) {
      return null;
    }

    const articleRoot =
      articleBody.closest("article") ||
      document.querySelector("article") ||
      document.querySelector("main") ||
      document.body;
    const extractedBody = cloneAndPrepareContentRoot(articleBody, metadata.baseURL);
    const bodyMarkdown = finalizeMarkdown(renderNode(extractedBody));

    if (bodyMarkdown.length < 280) {
      return null;
    }

    const title = normalizeInlineMarkdown(
      articleRoot?.querySelector(".entry-title, [itemprop='headline'], h1")?.textContent ||
        metadata.title
    );
    const author = normalizeInlineMarkdown(
      articleRoot?.querySelector(".posted-by, .byline, [rel='author'], [itemprop='author']")
        ?.textContent ||
        metadata.author
    );
    const publishedAt = normalizeInlineMarkdown(
      articleRoot?.querySelector(".posted-on time, time[datetime], [itemprop='datePublished']")
        ?.textContent ||
        metadata.publishedAt
    );
    const byline = [author, publishedAt].filter((section) => section.length > 0).join(", ");
    const cleanedBodyMarkdown = stripRedundantLeadingContent(bodyMarkdown, title, publishedAt);

    return finalizeMarkdown(
      [
        title.length > 0 ? `# ${title}` : "",
        byline.length > 0 ? `*${byline}*` : "",
        cleanedBodyMarkdown
      ]
        .filter((section) => section.length > 0)
        .join("\n\n")
    );
  })();

  if (articleMarkdown !== null) {
    return articleMarkdown;
  }

  const root =
    document.querySelector("main") ||
    document.querySelector("article") ||
    document.body ||
    document.documentElement;

  return finalizeMarkdown(renderNode(cloneAndPrepareContentRoot(root, metadata.baseURL)));
}

function collectPageLines(textContent) {
  const lines = [];
  let currentLine = "";

  textContent.items.forEach((item) => {
    const fragment = item.str.replace(/\s+/g, " ").trim();

    if (fragment.length > 0) {
      const needsSpace =
        currentLine.length > 0 &&
        !currentLine.endsWith(" ") &&
        !fragment.startsWith(")") &&
        !fragment.startsWith(",") &&
        !fragment.startsWith(".") &&
        !fragment.startsWith(":") &&
        !fragment.startsWith(";") &&
        !fragment.startsWith("?");

      currentLine += `${needsSpace ? " " : ""}${fragment}`;
    }

    if (item.hasEOL && currentLine.trim().length > 0) {
      lines.push(currentLine.trim());
      currentLine = "";
    }
  });

  if (currentLine.trim().length > 0) {
    lines.push(currentLine.trim());
  }

  return lines;
}

function buildPdfMarkdown(title, pageLines) {
  const flattenedLines = pageLines.flat().filter((line) => line.length > 0);
  let resolvedTitle = title;
  let contentLines = flattenedLines;

  if (!resolvedTitle) {
    const titleLines = [];

    for (const line of flattenedLines.slice(0, 4)) {
      if (
        line.includes("@") ||
        line.includes("†") ||
        line.toLowerCase() === "abstract" ||
        /^(\d+|\*|†)/.test(line) ||
        (titleLines.length > 0 && /\b\d+\b/.test(line))
      ) {
        break;
      }

      titleLines.push(line);

      if (titleLines.join(" ").length > 140) {
        break;
      }
    }

    resolvedTitle = titleLines.join(" ").trim() || null;
    contentLines = flattenedLines.slice(titleLines.length);
  }

  const paragraphs = [];
  let currentParagraph = "";

  contentLines.forEach((line) => {
    if (line.length === 0) {
      if (currentParagraph.length > 0) {
        paragraphs.push(currentParagraph.trim());
        currentParagraph = "";
      }

      return;
    }

    const isHeadingCandidate =
      line.toLowerCase() === "abstract" ||
      /^\d+(\.\d+)*\s+[A-Z]/.test(line) ||
      (
        line.length < 80 &&
        line.split(/\s+/).length <= 8 &&
        !line.endsWith(".") &&
        !line.endsWith(",") &&
        !line.endsWith(";") &&
        !line.includes("@")
      );

    if (isHeadingCandidate) {
      if (currentParagraph.length > 0) {
        paragraphs.push(currentParagraph.trim());
        currentParagraph = "";
      }

      paragraphs.push(`## ${line}`);
      return;
    }

    currentParagraph = currentParagraph.endsWith("-")
      ? `${currentParagraph.slice(0, -1)}${line}`
      : `${currentParagraph}${currentParagraph.length > 0 ? " " : ""}${line}`;
  });

  if (currentParagraph.length > 0) {
    paragraphs.push(currentParagraph.trim());
  }

  return finalizeMarkdown(
    `${resolvedTitle ? `# ${resolvedTitle}\n\n` : ""}${paragraphs.join("\n\n")}`
  );
}

export async function convertPdfArrayBufferToMarkdown(arrayBuffer) {
  const loadingTask = pdfjs.getDocument({
    data: new Uint8Array(arrayBuffer),
    disableWorker: true,
    isEvalSupported: false,
    useWorkerFetch: false
  });
  const pdf = await loadingTask.promise;
  const metadata = await pdf.getMetadata().catch(() => null);
  const title =
    metadata?.info?.Title && metadata.info.Title !== "Untitled"
      ? metadata.info.Title
      : null;
  const pageLines = await Promise.all(
    Array.from({ length: pdf.numPages }, async (_, pageIndex) => {
      const page = await pdf.getPage(pageIndex + 1);
      const textContent = await page.getTextContent();
      return collectPageLines(textContent);
    })
  );

  return buildPdfMarkdown(title, pageLines);
}

export async function convertWordArrayBufferToMarkdown(arrayBuffer) {
  const result = await mammoth.convertToMarkdown(
    typeof Buffer === "function"
      ? { buffer: Buffer.from(arrayBuffer) }
      : { arrayBuffer }
  );
  return finalizeMarkdown(result.value);
}
