#!/usr/bin/env node

/**
 * Geary Email MCP Server
 *
 * This MCP (Model Context Protocol) server provides email tools for Gemini AI.
 * It communicates with Geary via D-Bus to list, search, read, and select emails.
 *
 * MCP Protocol: https://modelcontextprotocol.io/
 */

import dbus from "dbus-next";
import { createInterface } from "readline";

// Log to stderr for debugging (gemini-cli captures this)
const log = (msg) => process.stderr.write(`[geary-mcp] ${msg}\n`);

log(`Starting Geary MCP server...`);
log(
  `DBUS_SESSION_BUS_ADDRESS: ${process.env.DBUS_SESSION_BUS_ADDRESS || "NOT SET"}`,
);

const DBUS_NAME = "org.gnome.Geary.EmailTools";
const DBUS_PATH = "/org/gnome/Geary/EmailTools";
const DBUS_INTERFACE = "org.gnome.Geary.EmailTools";

// MCP Server metadata
const SERVER_INFO = {
  name: "geary-email-tools",
  version: "1.0.0",
  protocolVersion: "2024-11-05",
};

// Tool definitions
const TOOLS = [
  {
    name: "list_emails",
    description:
      "List emails in the current folder. Returns an array of email objects with id, subject, from, date, and preview.",
    inputSchema: {
      type: "object",
      properties: {
        limit: {
          type: "number",
          description: "Maximum number of emails to return (default: 20)",
          default: 20,
        },
      },
    },
  },
  {
    name: "get_selected_email",
    description:
      "Get the full content of the currently selected email in Geary. Returns the email with id, subject, from, to, cc, date, and body.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "read_email",
    description:
      "Read a specific email by its ID. Returns the full email content with id, subject, from, to, cc, date, and body.",
    inputSchema: {
      type: "object",
      properties: {
        email_id: {
          type: "string",
          description: "The ID of the email to read",
        },
      },
      required: ["email_id"],
    },
  },
  {
    name: "search_emails",
    description:
      'Search emails in the current folder. Supports queries like "from:bob", "to:alice", "subject:invoice", or plain text search.',
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description:
            'Search query (e.g., "from:bob", "subject:meeting", or "hello world")',
        },
      },
      required: ["query"],
    },
  },
  {
    name: "select_email",
    description:
      "Select an email in Geary's UI by its ID. This will highlight and display the email.",
    inputSchema: {
      type: "object",
      properties: {
        email_id: {
          type: "string",
          description: "The ID of the email to select",
        },
      },
      required: ["email_id"],
    },
  },
];

// D-Bus connection and interface
let bus = null;
let emailTools = null;

/**
 * Initialize D-Bus connection to Geary
 */
async function initDBus() {
  if (emailTools) return emailTools;

  try {
    bus = dbus.sessionBus();
    const obj = await bus.getProxyObject(DBUS_NAME, DBUS_PATH);
    emailTools = obj.getInterface(DBUS_INTERFACE);
    return emailTools;
  } catch (error) {
    throw new Error(
      `Failed to connect to Geary D-Bus service: ${error.message}. Is Geary running?`,
    );
  }
}

/**
 * Handle tool calls
 */
async function handleToolCall(name, args) {
  const tools = await initDBus();

  switch (name) {
    case "list_emails": {
      const limit = args?.limit || 20;
      const result = await tools.ListEmails(limit);
      return JSON.parse(result);
    }

    case "get_selected_email": {
      const result = await tools.GetSelectedEmail();
      const email = JSON.parse(result);
      if (Object.keys(email).length === 0) {
        return { error: "No email is currently selected in Geary" };
      }
      return email;
    }

    case "read_email": {
      if (!args?.email_id) {
        return { error: "email_id is required" };
      }
      const result = await tools.ReadEmail(args.email_id);
      const email = JSON.parse(result);
      if (Object.keys(email).length === 0) {
        return { error: `Email not found: ${args.email_id}` };
      }
      return email;
    }

    case "search_emails": {
      if (!args?.query) {
        return { error: "query is required" };
      }
      const result = await tools.SearchEmails(args.query);
      return JSON.parse(result);
    }

    case "select_email": {
      if (!args?.email_id) {
        return { error: "email_id is required" };
      }
      const success = await tools.SelectEmail(args.email_id);
      return {
        success,
        message: success ? "Email selected" : "Email not found",
      };
    }

    default:
      return { error: `Unknown tool: ${name}` };
  }
}

/**
 * MCP Protocol message handlers
 */
function handleMessage(message) {
  const { id, method, params } = message;

  switch (method) {
    case "initialize":
      return {
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: SERVER_INFO.protocolVersion,
          capabilities: {
            tools: {},
          },
          serverInfo: {
            name: SERVER_INFO.name,
            version: SERVER_INFO.version,
          },
        },
      };

    case "initialized":
    case "notifications/initialized":
      // Notification, no response needed
      return null;

    case "tools/list":
      return {
        jsonrpc: "2.0",
        id,
        result: {
          tools: TOOLS,
        },
      };

    case "tools/call":
      // This is async, handle separately
      return handleToolCallAsync(id, params);

    case "ping":
      return {
        jsonrpc: "2.0",
        id,
        result: {},
      };

    default:
      return {
        jsonrpc: "2.0",
        id,
        error: {
          code: -32601,
          message: `Method not found: ${method}`,
        },
      };
  }
}

/**
 * Handle async tool calls
 */
async function handleToolCallAsync(id, params) {
  try {
    const { name, arguments: args } = params;
    const result = await handleToolCall(name, args);

    return {
      jsonrpc: "2.0",
      id,
      result: {
        content: [
          {
            type: "text",
            text: JSON.stringify(result, null, 2),
          },
        ],
      },
    };
  } catch (error) {
    return {
      jsonrpc: "2.0",
      id,
      error: {
        code: -32000,
        message: error.message,
      },
    };
  }
}

/**
 * Send a message to stdout
 */
function sendMessage(message) {
  if (message) {
    process.stdout.write(JSON.stringify(message) + "\n");
  }
}

/**
 * Main entry point - read from stdin, write to stdout
 */
async function main() {
  log("Setting up readline interface...");

  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false,
  });

  log("Readline interface ready, waiting for messages...");

  rl.on("line", async (line) => {
    log(`Received: ${line.substring(0, 100)}...`);
    try {
      const message = JSON.parse(line);
      log(`Parsed method: ${message.method}`);
      const response = handleMessage(message);

      // Handle async responses (tools/call)
      if (response instanceof Promise) {
        const asyncResponse = await response;
        log(`Async response ready for id: ${asyncResponse?.id}`);
        sendMessage(asyncResponse);
      } else {
        if (response) {
          log(`Sync response ready for id: ${response?.id}`);
        }
        sendMessage(response);
      }
    } catch (error) {
      log(`Error: ${error.message}`);
      // Send error response
      sendMessage({
        jsonrpc: "2.0",
        id: null,
        error: {
          code: -32700,
          message: `Parse error: ${error.message}`,
        },
      });
    }
  });

  rl.on("close", () => {
    log("stdin closed, exiting");
    process.exit(0);
  });
}

main().catch((error) => {
  log(`Fatal error: ${error.message}`);
  process.exit(1);
});
