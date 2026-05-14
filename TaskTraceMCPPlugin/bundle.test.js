import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";

const packageJson = JSON.parse(await readFile(new URL("./package.json", import.meta.url), "utf8"));
const mcpConfig = JSON.parse(await readFile(new URL("./.mcp.json", import.meta.url), "utf8"));
const codexPlugin = JSON.parse(await readFile(new URL("./.codex-plugin/plugin.json", import.meta.url), "utf8"));
const claudePlugin = JSON.parse(await readFile(new URL("./.claude-plugin/plugin.json", import.meta.url), "utf8"));
const openclawPlugin = JSON.parse(await readFile(new URL("./openclaw.plugin.json", import.meta.url), "utf8"));
const taskTraceResourceToolNames = [
  "tasktrace_list_resources",
  "tasktrace_list_resource_templates",
  "tasktrace_get_active_day_overviews",
  "tasktrace_get_high_level_activities",
  "tasktrace_get_detailed_activities",
  "tasktrace_read_resource",
];

test("package exposes the OpenClaw resource-tool runtime alongside the shared MCP bundle metadata", () => {
  assert.deepEqual(packageJson.openclaw, {
    extensions: ["./index.js"],
  });
  assert.equal(packageJson.files.includes("openclaw.plugin.json"), true);
  assert.equal(packageJson.files.includes("index.js"), true);
  assert.equal(packageJson.files.includes("src"), true);
});

test("shared mcp config points at the canonical TaskTrace stdio command", () => {
  assert.deepEqual(mcpConfig, {
    mcpServers: {
      tasktrace: {
        command: "/Applications/TaskTrace.app/Contents/MacOS/TaskTrace",
        args: ["--mcp-stdio"],
      },
    },
  });
});

test("native OpenClaw manifest keeps the official plugin identity and resource tool contracts", () => {
  assert.equal(openclawPlugin.id, "tasktrace-mcp");
  assert.equal(openclawPlugin.name, "TaskTrace MCP");
  assert.equal(openclawPlugin.version, packageJson.version);
  assert.deepEqual(openclawPlugin.activation, { onStartup: true });
  assert.deepEqual(openclawPlugin.contracts.tools, taskTraceResourceToolNames);
  assert.equal(Object.hasOwn(openclawPlugin, "channels"), false);
  assert.equal(Object.hasOwn(openclawPlugin, "channelConfigs"), false);
});

test("bundle manifests keep the TaskTrace MCP wiring", () => {
  assert.equal(codexPlugin.mcpServers, "./.mcp.json");
  assert.deepEqual(claudePlugin.mcpServers, {
    tasktrace: {
      command: "/Applications/TaskTrace.app/Contents/MacOS/TaskTrace",
      args: ["--mcp-stdio"],
    },
  });
});
