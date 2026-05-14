import { callTaskTraceMcp } from "./tasktrace-mcp-client.js";

const ACTIVE_DAY_OVERVIEWS_URI = "tasktrace://overviews/active-day";
const HIGH_LEVEL_ACTIVITIES_URI = "tasktrace://activities/high-level";
const DETAILED_ACTIVITIES_URI = "tasktrace://activities/detailed";

const EMPTY_OBJECT_SCHEMA = {
  type: "object",
  properties: {},
  additionalProperties: false
};

const URI_ONLY_SCHEMA = {
  type: "object",
  properties: {
    uri: {
      type: "string",
      description: "Exact TaskTrace MCP resource URI to read, such as tasktrace://overviews/active-day or a screenshot URI returned by the detailed activity feed."
    }
  },
  required: ["uri"],
  additionalProperties: false
};

function toolTextResult(payload) {
  return {
    content: [{
      type: "text",
      text: JSON.stringify(payload, null, 2)
    }],
    details: payload
  };
}

function createTaskTraceTool(definition, executeWithContext) {
  return (ctx) => ({
    ...definition,
    execute: async (toolCallId, params, signal, onUpdate) => (
      await executeWithContext({ ctx, toolCallId, params, signal, onUpdate })
    )
  });
}

function summarizedReadResult(result) {
  if (!Array.isArray(result?.contents)) {
    return result;
  }

  return {
    contents: result.contents.map((content) => {
      if (typeof content?.text === "string") {
        return content;
      }

      if (typeof content?.blob === "string") {
        return {
          ...content,
          blob: undefined,
          blobBase64Length: content.blob.length
        };
      }

      return content;
    })
  };
}

async function withTaskTraceMcp(ctx, logger, operation) {
  const cfg = ctx.runtimeConfig ?? ctx.config;

  if (!cfg) {
    throw new Error("OpenClaw runtime config is unavailable for TaskTrace MCP access.");
  }

  return await callTaskTraceMcp(cfg, logger, operation);
}

export function registerTaskTraceMcpTools(api) {
  api.registerTool(createTaskTraceTool({
    name: "tasktrace_list_resources",
    label: "TaskTrace List Resources",
    description: "List the enabled TaskTrace MCP resources, including active-day overviews and recent activity feeds.",
    parameters: EMPTY_OBJECT_SCHEMA
  }, async ({ ctx }) => toolTextResult(
      await withTaskTraceMcp(ctx, api.logger, async ({ client }) => await client.listResources())
    )
  ), { name: "tasktrace_list_resources" });

  api.registerTool(createTaskTraceTool({
    name: "tasktrace_list_resource_templates",
    label: "TaskTrace List Resource Templates",
    description: "List the enabled TaskTrace MCP resource templates, including screenshot URI templates from the detailed activity feed.",
    parameters: EMPTY_OBJECT_SCHEMA
  }, async ({ ctx }) => toolTextResult(
      await withTaskTraceMcp(ctx, api.logger, async ({ client }) => await client.listResourceTemplates())
    )
  ), { name: "tasktrace_list_resource_templates" });

  api.registerTool(createTaskTraceTool({
    name: "tasktrace_get_active_day_overviews",
    label: "TaskTrace Active Day Overviews",
    description: "Read the TaskTrace active-day overview feed as a tool result. Best starting point for what the user has been working on today.",
    parameters: EMPTY_OBJECT_SCHEMA
  }, async ({ ctx }) => toolTextResult(
      await withTaskTraceMcp(ctx, api.logger, async ({ client }) => await client.readResource({ uri: ACTIVE_DAY_OVERVIEWS_URI }))
    )
  ), { name: "tasktrace_get_active_day_overviews" });

  api.registerTool(createTaskTraceTool({
    name: "tasktrace_get_high_level_activities",
    label: "TaskTrace High Level Activities",
    description: "Read the TaskTrace high-level activity feed as a tool result. Good for chronological recap of recent completed work.",
    parameters: EMPTY_OBJECT_SCHEMA
  }, async ({ ctx }) => toolTextResult(
      await withTaskTraceMcp(ctx, api.logger, async ({ client }) => await client.readResource({ uri: HIGH_LEVEL_ACTIVITIES_URI }))
    )
  ), { name: "tasktrace_get_high_level_activities" });

  api.registerTool(createTaskTraceTool({
    name: "tasktrace_get_detailed_activities",
    label: "TaskTrace Detailed Activities",
    description: "Read the TaskTrace detailed activity feed as a tool result. Use for current or very recent activity details, including transcripts, keystrokes, and screenshot metadata.",
    parameters: EMPTY_OBJECT_SCHEMA
  }, async ({ ctx }) => toolTextResult(
      await withTaskTraceMcp(ctx, api.logger, async ({ client }) => await client.readResource({ uri: DETAILED_ACTIVITIES_URI }))
    )
  ), { name: "tasktrace_get_detailed_activities" });

  api.registerTool(createTaskTraceTool({
    name: "tasktrace_read_resource",
    label: "TaskTrace Read Resource",
    description: "Read any TaskTrace MCP resource by URI, including screenshot URIs discovered from the detailed activity feed.",
    parameters: URI_ONLY_SCHEMA
  }, async ({ params, ctx }) => {
      const uri = typeof params?.uri === "string" ? params.uri.trim() : "";

      if (!uri) {
        throw new Error("tasktrace_read_resource requires a non-empty uri.");
      }

      if (!uri.startsWith("tasktrace://")) {
        throw new Error(`tasktrace_read_resource only accepts tasktrace:// URIs, got: ${uri.split("://")[0]}://`);
      }

      return toolTextResult(
        summarizedReadResult(
          await withTaskTraceMcp(ctx, api.logger, async ({ client }) => await client.readResource({ uri }))
        )
      );
    }
  ), { name: "tasktrace_read_resource" });
}
