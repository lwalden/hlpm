import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ECOSYSTEM_DIR = resolve(__dirname, "../ecosystem");

function readServices(): unknown {
  const filePath = resolve(ECOSYSTEM_DIR, "services.json");
  return JSON.parse(readFileSync(filePath, "utf-8"));
}

function readPrefs(): unknown {
  const filePath = resolve(ECOSYSTEM_DIR, "integration-prefs.json");
  return JSON.parse(readFileSync(filePath, "utf-8"));
}

const server = new Server(
  { name: "hlpm-ecosystem", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "list_services",
        description: "List all services in the HLPM ecosystem.",
        inputSchema: {
          type: "object",
          properties: {},
          required: [],
        },
      },
      {
        name: "get_service",
        description: "Get details for a specific service by name.",
        inputSchema: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "The name of the service to retrieve.",
            },
          },
          required: ["name"],
        },
      },
      {
        name: "get_integration_preference",
        description:
          "Get integration preferences for a given category. Call this BEFORE recommending external APIs to ensure alignment with existing tooling preferences.",
        inputSchema: {
          type: "object",
          properties: {
            category: {
              type: "string",
              description: "The integration category to look up.",
            },
          },
          required: ["category"],
        },
      },
      {
        name: "get_ecosystem_context",
        description:
          "Get the full ecosystem context, including both services and integration preferences.",
        inputSchema: {
          type: "object",
          properties: {},
          required: [],
        },
      },
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    let result: unknown;

    if (name === "list_services") {
      const data = readServices() as { services: unknown[] };
      result = data.services;
    } else if (name === "get_service") {
      const { name: serviceName } = args as { name: string };
      const data = readServices() as { services: Array<Record<string, unknown>> };
      result =
        data.services.find(
          (s) => String(s["name"]).toLowerCase() === serviceName.toLowerCase()
        ) ?? null;
    } else if (name === "get_integration_preference") {
      const { category } = args as { category: string };
      const data = readPrefs() as { preferences: Array<Record<string, unknown>> };
      const match = data.preferences.find((p) => p["category"] === category);
      result = match ?? data.preferences;
    } else if (name === "get_ecosystem_context") {
      const svcData = readServices() as { services: unknown[] };
      const prefData = readPrefs() as { preferences: unknown[] };
      result = {
        services: svcData.services,
        preferences: prefData.preferences,
      };
    } else {
      throw new Error(`Unknown tool: ${name}`);
    }

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(result, null, 2),
        },
      ],
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      isError: true,
      content: [
        {
          type: "text",
          text: JSON.stringify({ error: message }, null, 2),
        },
      ],
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  process.stderr.write("hlpm-ecosystem MCP server running\n");
}

main().catch((err) => {
  process.stderr.write(`Fatal error: ${err}\n`);
  process.exit(1);
});
