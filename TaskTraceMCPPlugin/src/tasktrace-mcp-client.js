import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const DEFAULT_SERVER_NAME = "tasktrace";
let mcpSdkPromise;

function resolveTaskTraceServerConfig(cfg) {
  const server = cfg?.mcp?.servers?.[DEFAULT_SERVER_NAME];

  if (!server || typeof server !== "object") {
    throw new Error(`OpenClaw MCP server "${DEFAULT_SERVER_NAME}" is not configured.`);
  }

  if (typeof server.command !== "string" || server.command.trim().length === 0) {
    throw new Error(`OpenClaw MCP server "${DEFAULT_SERVER_NAME}" is missing its command.`);
  }

  return {
    command: server.command,
    args: Array.isArray(server.args) ? server.args.filter((value) => typeof value === "string") : [],
    cwd: typeof server.cwd === "string" && server.cwd.trim().length > 0
      ? server.cwd
      : (typeof server.workingDirectory === "string" && server.workingDirectory.trim().length > 0
          ? server.workingDirectory
          : undefined),
    env: server.env && typeof server.env === "object" ? server.env : undefined
  };
}

function resolveOpenClawRoot() {
  const argvEntry = typeof process.argv[1] === "string" && process.argv[1].trim().length > 0
    ? (() => {
        try {
          return fs.realpathSync(process.argv[1]);
        } catch {
          return process.argv[1];
        }
      })()
    : undefined;
  const execDir = path.dirname(process.execPath);
  const distSegment = `${path.sep}dist${path.sep}`;
  const candidates = [
    typeof process.env.OPENCLAW_ROOT === "string" ? process.env.OPENCLAW_ROOT.trim() : "",
    argvEntry ? path.dirname(argvEntry) : "",
    argvEntry && argvEntry.includes(distSegment)
      ? argvEntry.slice(0, argvEntry.indexOf(distSegment))
      : "",
    argvEntry ? path.resolve(path.dirname(argvEntry), "..") : "",
    path.resolve(execDir, "..", "lib", "node_modules", "openclaw"),
    path.resolve(execDir, "..", "..", "lib", "node_modules", "openclaw")
  ]
    .map((value) => value.trim())
    .filter(Boolean);

  const resolvedRoot = candidates.find((candidate) => (
    fs.existsSync(path.join(candidate, "package.json"))
    && fs.existsSync(path.join(candidate, "node_modules", "@modelcontextprotocol", "sdk", "dist", "esm", "client", "index.js"))
    && fs.existsSync(path.join(candidate, "node_modules", "@modelcontextprotocol", "sdk", "dist", "esm", "client", "stdio.js"))
  ));

  if (!resolvedRoot) {
    throw new Error(`Could not resolve the OpenClaw install root from process.argv[1]=${process.argv[1] ?? "<missing>"} process.execPath=${process.execPath}`);
  }

  return resolvedRoot;
}

async function loadMcpSdk(logger) {
  if (!mcpSdkPromise) {
    mcpSdkPromise = (async () => {
      const openClawRoot = resolveOpenClawRoot();
      const clientModuleURL = pathToFileURL(
        path.join(openClawRoot, "node_modules", "@modelcontextprotocol", "sdk", "dist", "esm", "client", "index.js")
      ).href;
      const stdioModuleURL = pathToFileURL(
        path.join(openClawRoot, "node_modules", "@modelcontextprotocol", "sdk", "dist", "esm", "client", "stdio.js")
      ).href;
      const [{ Client }, { StdioClientTransport }] = await Promise.all([
        import(clientModuleURL),
        import(stdioModuleURL)
      ]);

      logger?.info?.(`[tasktrace-mcp-client] loaded bundled MCP SDK from ${openClawRoot}`);
      return { Client, StdioClientTransport };
    })();
  }

  return await mcpSdkPromise;
}

export async function callTaskTraceMcp(cfg, logger, operation) {
  const server = resolveTaskTraceServerConfig(cfg);
  const { Client, StdioClientTransport } = await loadMcpSdk(logger);
  const transport = new StdioClientTransport({
    command: server.command,
    args: server.args,
    cwd: server.cwd,
    env: {
      ...process.env,
      ...(server.env ?? {})
    }
  });
  const client = new Client(
    {
      name: "tasktrace-openclaw-resource-bridge",
      version: "1.0.0"
    },
    {
      capabilities: {}
    }
  );

  try {
    await client.connect(transport);
    return await operation({ client });
  } finally {
    await Promise.allSettled([
      client.close(),
      transport.close()
    ]);
  }
}
