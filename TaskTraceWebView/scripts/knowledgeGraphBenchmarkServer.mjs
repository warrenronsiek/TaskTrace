import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const distDirectory = path.resolve(__dirname, "../dist");
const host = process.env.HOST ?? "127.0.0.1";
const port = Number.parseInt(process.env.PORT ?? "4173", 10);

const contentTypeByExtension = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8"
};

const benchmarkURL = (params) => `http://${host}:${port}/index.html?${new URLSearchParams(params).toString()}`;

const sendResponse = async (response, requestPathname) => {
  const relativePath = requestPathname === "/" ? "/index.html" : requestPathname;
  const resolvedPath = path.resolve(distDirectory, `.${relativePath}`);
  const fallbackPath = path.resolve(distDirectory, "./index.html");
  const filePath = resolvedPath.startsWith(distDirectory) ? resolvedPath : fallbackPath;

  try {
    const fileContents = await readFile(filePath);
    response.writeHead(200, { "content-type": contentTypeByExtension[path.extname(filePath)] ?? "application/octet-stream" });
    response.end(fileContents);
  } catch {
    const fallbackContents = await readFile(fallbackPath);
    response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    response.end(fallbackContents);
  }
};

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? "/", `http://${host}:${port}`);
    await sendResponse(response, url.pathname);
  } catch (error) {
    response.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
    response.end(error instanceof Error ? error.message : String(error));
  }
});

server.listen(port, host, () => {
  console.log(`Knowledge graph benchmark server listening on http://${host}:${port}`);
  console.log("Open one of these URLs in a real browser, not jsdom:");
  console.log(`  default:  ${benchmarkURL({
    benchmark: "knowledge-graph",
    seed: "7",
    knowledgeNodes: "1200",
    communities: "48",
    files: "180",
    overviews: "36",
    activities: "240",
    knowledgeEdges: "7200",
    fileLinksPerFile: "3",
    knowledgeThreshold: "450",
    fileThreshold: "125",
    activityThreshold: "150",
    overviewThreshold: "60",
    panDurationMs: "5000",
    selection: "none"
  })}`);
  console.log(`  selected: ${benchmarkURL({
    benchmark: "knowledge-graph",
    seed: "7",
    knowledgeNodes: "1200",
    communities: "48",
    files: "180",
    overviews: "36",
    activities: "240",
    knowledgeEdges: "7200",
    fileLinksPerFile: "3",
    knowledgeThreshold: "450",
    fileThreshold: "125",
    activityThreshold: "150",
    overviewThreshold: "60",
    panDurationMs: "5000",
    selection: "densest"
  })}`);
});
