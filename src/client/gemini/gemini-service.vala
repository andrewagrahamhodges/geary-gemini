/*
 * Copyright 2025 Andrew Hodges
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Service for interacting with Google's Gemini CLI.
 *
 * This service handles:
 * - Authentication with Google
 * - Translation, summarization, and chat features
 *
 * Node.js and gemini-cli are bundled in the .deb package at /usr/share/geary-gemini/
 */
public class Gemini.Service : GLib.Object {

    // Bundled paths - installed by .deb package
    private const string NODE_BINARY = "/usr/share/geary-gemini/node/bin/node";
    private const string GEMINI_BINARY = "/usr/share/geary-gemini/node_modules/.bin/gemini";
    private const string MCP_SERVER_PATH = "/usr/share/geary-gemini/mcp-server/server.js";

    // System prompt for Gemini chat - provides context and guardrails
    private const string SYSTEM_PROMPT =
        "You are an AI assistant integrated into the Geary email client. You help users with their emails.\n\n" +
        "IMPORTANT DEFAULTS:\n" +
        "- When asked to translate, ALWAYS translate to %s (the user's system language) unless they specify otherwise\n" +
        "- When the user says \"the email\", \"this email\", or \"selected email\", use get_selected_email to retrieve it\n" +
        "- Assume questions are about the currently selected email unless the user asks about other emails\n" +
        "- When translating or summarizing, get the selected email first, then process it\n\n" +
        "FORMATTING:\n" +
        "- Use markdown formatting to make responses clear and readable\n" +
        "- Use **bold** for emphasis and important terms\n" +
        "- Use *italic* for titles, names, or subtle emphasis\n" +
        "- Use `code` for technical terms, email addresses, or IDs\n" +
        "- Use bullet lists (- item) for multiple points\n" +
        "- Use ## headers for sections in longer responses\n\n" +
        "RESPONSE STYLE:\n" +
        "- Give direct, concise responses\n" +
        "- Do NOT explain your thought process or what steps you're taking\n" +
        "- Do NOT say things like \"I will now...\", \"Let me...\", \"First I'll...\"\n" +
        "- Just provide the result directly (translation, summary, answer, etc.)\n" +
        "- If you need clarification, ask a brief question\n\n" +
        "AVAILABLE TOOLS:\n" +
        "- list_emails: List emails in the current folder\n" +
        "- get_selected_email: Get the currently selected email\n" +
        "- read_email: Read a specific email by ID\n" +
        "- search_emails: Search emails\n" +
        "- select_email: Select an email in the UI\n\n" +
        "RESTRICTIONS:\n" +
        "- You can only access emails through the provided tools\n" +
        "- You cannot send, delete, or modify emails\n" +
        "- Focus only on email-related tasks";

    /**
     * Signal emitted when authentication is required.
     */
    public signal void authentication_required();

    /**
     * Signal emitted when authentication completes.
     */
    public signal void authentication_completed(bool success, string? error_message);

    /**
     * Check if gemini-cli is installed (bundled with the package).
     */
    public bool is_installed() {
        return FileUtils.test(GEMINI_BINARY, FileTest.EXISTS);
    }

    /**
     * Configure gemini-cli MCP settings to include the Geary email tools server.
     * This writes to ~/.gemini/settings.json
     */
    public void configure_mcp_server() {
        string home = Environment.get_home_dir();
        string gemini_dir = Path.build_filename(home, ".gemini");
        string settings_path = Path.build_filename(gemini_dir, "settings.json");

        // Create .gemini directory if it doesn't exist
        var dir = File.new_for_path(gemini_dir);
        try {
            if (!dir.query_exists()) {
                dir.make_directory_with_parents();
            }
        } catch (Error e) {
            warning("Failed to create .gemini directory: %s", e.message);
            return;
        }

        // Build the settings JSON with MCP server configuration
        var builder = new Json.Builder();
        builder.begin_object();

        // Read existing settings if present
        var settings_file = File.new_for_path(settings_path);
        if (settings_file.query_exists()) {
            try {
                var parser = new Json.Parser();
                parser.load_from_file(settings_path);
                var root = parser.get_root();
                if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                    var obj = root.get_object();
                    // Copy existing members except mcpServers (we'll replace it)
                    foreach (string member in obj.get_members()) {
                        if (member != "mcpServers") {
                            builder.set_member_name(member);
                            builder.add_value(obj.get_member(member).copy());
                        }
                    }
                }
            } catch (Error e) {
                debug("Could not read existing settings.json: %s", e.message);
            }
        }

        // Add/update mcpServers configuration
        builder.set_member_name("mcpServers");
        builder.begin_object();
        builder.set_member_name("geary");
        builder.begin_object();
        builder.set_member_name("command");
        builder.add_string_value(NODE_BINARY);
        builder.set_member_name("args");
        builder.begin_array();
        builder.add_string_value(MCP_SERVER_PATH);
        builder.end_array();
        // Pass D-Bus session address to subprocess so MCP server can connect
        string? dbus_addr = Environment.get_variable("DBUS_SESSION_BUS_ADDRESS");
        if (dbus_addr != null) {
            builder.set_member_name("env");
            builder.begin_object();
            builder.set_member_name("DBUS_SESSION_BUS_ADDRESS");
            builder.add_string_value(dbus_addr);
            builder.end_object();
        }
        builder.set_member_name("timeout");
        builder.add_int_value(10000);  // 10 second timeout
        builder.end_object();
        builder.end_object();

        builder.end_object();

        // Write settings file
        var generator = new Json.Generator();
        generator.set_pretty(true);
        generator.set_indent(2);
        generator.set_root(builder.get_root());

        try {
            generator.to_file(settings_path);
            debug("MCP server configured in %s", settings_path);
        } catch (Error e) {
            warning("Failed to write gemini settings: %s", e.message);
        }
    }

    /**
     * Check if user is authenticated with Google.
     */
    public async bool check_authenticated() {
        if (!is_installed()) {
            return false;
        }

        try {
            var subprocess = new Subprocess(
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE,
                NODE_BINARY, GEMINI_BINARY, "auth", "status"
            );
            yield subprocess.wait_async();
            return subprocess.get_successful();
        } catch (Error e) {
            return false;
        }
    }

    /**
     * Authenticate with Google (opens browser).
     */
    public async void authenticate() throws Error {
        if (!is_installed()) {
            throw new IOError.NOT_FOUND("Gemini CLI is not installed. Please reinstall geary-gemini.");
        }

        var subprocess = new Subprocess(
            SubprocessFlags.NONE,  // Interactive - opens browser
            NODE_BINARY, GEMINI_BINARY, "auth", "login"
        );

        yield subprocess.wait_async();

        if (!subprocess.get_successful()) {
            authentication_completed(false, "Authentication failed");
            throw new IOError.FAILED("Authentication failed");
        }

        authentication_completed(true, null);
    }

    /**
     * Delegate for receiving streaming output from gemini-cli.
     * Called with each line of output as it arrives.
     */
    public delegate void StreamingCallback(string line);

    /**
     * Delegate for receiving structured streaming output.
     * @param msg_type The message type: "tool_use", "tool_result", "message", "thinking", etc.
     * @param content The content/description for this message
     */
    public delegate void StructuredStreamCallback(string msg_type, string content);

    /**
     * Run a prompt through gemini-cli and return the response.
     */
    public async string run_prompt(string prompt, StreamingCallback? on_output = null) throws Error {
        if (!is_installed()) {
            throw new IOError.NOT_FOUND(
                "Gemini CLI is not installed. Please reinstall geary-gemini."
            );
        }

        var subprocess = new Subprocess(
            SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE,
            NODE_BINARY, GEMINI_BINARY, "-p", prompt
        );

        string? stdout_buf = null;
        string? stderr_buf = null;

        if (on_output != null) {
            // Stream output line by line
            var stdout_stream = new DataInputStream(subprocess.get_stdout_pipe());
            var stderr_stream = new DataInputStream(subprocess.get_stderr_pipe());
            var output_builder = new StringBuilder();

            try {
                string? line;
                while ((line = yield stdout_stream.read_line_async()) != null) {
                    output_builder.append(line);
                    output_builder.append("\n");
                    on_output(line);
                }
            } catch (Error e) {
                // Stream ended
            }

            // Read any stderr
            try {
                stderr_buf = yield stderr_stream.read_line_async();
            } catch (Error e) {
                // Ignore
            }

            yield subprocess.wait_async();
            stdout_buf = output_builder.str;
        } else {
            yield subprocess.communicate_utf8_async(null, null, out stdout_buf, out stderr_buf);
        }

        if (!subprocess.get_successful()) {
            // Check if auth error
            if (stderr_buf != null && "auth" in stderr_buf.down()) {
                authentication_required();
                throw new IOError.PERMISSION_DENIED("Please login with Google first");
            }
            throw new IOError.FAILED(
                "Gemini CLI error: %s".printf(stderr_buf ?? "unknown error")
            );
        }

        return stdout_buf ?? "";
    }

    /**
     * Run a prompt with MCP tools enabled and structured JSON streaming.
     * Returns only the assistant's response text, filtering out tool use/thinking.
     *
     * @param prompt The user's message
     * @param on_stream Callback for streaming updates (type + content)
     * @return The assistant's final response text
     */
    public async string run_mcp_prompt(string prompt, StructuredStreamCallback? on_stream = null) throws Error {
        if (!is_installed()) {
            throw new IOError.NOT_FOUND(
                "Gemini CLI is not installed. Please reinstall geary-gemini."
            );
        }

        var subprocess = new Subprocess(
            SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE,
            NODE_BINARY, GEMINI_BINARY,
            "--output-format", "stream-json",
            "--allowed-mcp-server-names", "geary",
            "--yolo",
            prompt
        );

        var stdout_stream = new DataInputStream(subprocess.get_stdout_pipe());
        var response_builder = new StringBuilder();

        try {
            string? line;
            while ((line = yield stdout_stream.read_line_async()) != null) {
                // Skip non-JSON lines (deprecation warnings, status messages)
                if (!line.has_prefix("{")) {
                    continue;
                }

                // Parse the JSON line
                var parser = new Json.Parser();
                try {
                    parser.load_from_data(line);
                } catch (Error e) {
                    continue;  // Skip invalid JSON
                }

                var root = parser.get_root();
                if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                    continue;
                }

                var obj = root.get_object();
                string msg_type = obj.has_member("type") ? obj.get_string_member("type") : "";

                switch (msg_type) {
                    case "tool_use":
                        // Show tool being used in thinking indicator
                        string tool_name = obj.has_member("tool_name") ? obj.get_string_member("tool_name") : "tool";
                        if (on_stream != null) {
                            on_stream("tool_use", "Using %s...".printf(tool_name));
                        }
                        break;

                    case "tool_result":
                        // Show tool result status
                        string status = obj.has_member("status") ? obj.get_string_member("status") : "";
                        if (on_stream != null) {
                            on_stream("tool_result", status == "success" ? "Done" : "Error");
                        }
                        break;

                    case "message":
                        // Only capture assistant messages for the final response
                        string role = obj.has_member("role") ? obj.get_string_member("role") : "";
                        if (role == "assistant" && obj.has_member("content")) {
                            string content = obj.get_string_member("content");
                            response_builder.append(content);
                            if (on_stream != null) {
                                on_stream("message", content);
                            }
                        }
                        break;

                    case "result":
                        // Completion - ignore
                        break;

                    default:
                        // Other types - pass through for display
                        if (on_stream != null && msg_type.length > 0) {
                            on_stream(msg_type, "");
                        }
                        break;
                }
            }
        } catch (Error e) {
            // Stream ended
        }

        yield subprocess.wait_async();

        if (!subprocess.get_successful()) {
            throw new IOError.FAILED("Gemini CLI error");
        }

        return response_builder.str;
    }

    /**
     * Translate text to the specified language.
     */
    public async string translate(string text, string target_language) throws Error {
        string prompt = "Translate the following text to %s. Output ONLY the translation, nothing else:\n\n%s".printf(
            target_language, text
        );
        return yield run_prompt(prompt);
    }

    /**
     * Translate text to the system language.
     */
    public async string translate_to_system_language(string text) throws Error {
        string lang = get_system_language_name();
        return yield translate(text, lang);
    }

    /**
     * Summarize the given text.
     */
    public async string summarize(string text) throws Error {
        string prompt = "Summarize the following email concisely. Keep the key points and action items:\n\n%s".printf(text);
        return yield run_prompt(prompt);
    }

    /**
     * Help compose an email based on user instructions.
     */
    public async string help_compose(string instruction, string? context = null) throws Error {
        string prompt;
        if (context != null && context.length > 0) {
            prompt = "Write an email based on this instruction: %s\n\nContext (replying to):\n%s\n\nOutput ONLY the email body text, no subject line or greetings explanations.".printf(
                instruction, context
            );
        } else {
            prompt = "Write an email based on this instruction: %s\n\nOutput ONLY the email body text, no explanations.".printf(
                instruction
            );
        }
        return yield run_prompt(prompt);
    }

    /**
     * Build the full prompt with system instructions.
     */
    private string build_chat_prompt(string message) {
        string lang = get_system_language_name();
        string system = SYSTEM_PROMPT.printf(lang);
        return "[System Instructions]\n%s\n\n[User Message]\n%s".printf(system, message);
    }

    /**
     * Send a chat message and get a response.
     * Uses MCP tools to access email data from Geary.
     */
    public async string chat(string message) throws Error {
        string full_prompt = build_chat_prompt(message);
        return yield run_mcp_prompt(full_prompt, null);
    }

    /**
     * Send a chat message with structured streaming output.
     * Uses MCP tools to access email data from Geary.
     * The callback receives (msg_type, content) where msg_type is "tool_use", "tool_result", or "message".
     */
    public async string chat_streaming(string message, StructuredStreamCallback on_stream) throws Error {
        string full_prompt = build_chat_prompt(message);
        return yield run_mcp_prompt(full_prompt, on_stream);
    }

    /**
     * Get the system language code (e.g., "en", "nl", "de").
     */
    public string get_system_language_code() {
        string? lang = Environment.get_variable("LANG");
        if (lang != null && lang.length >= 2) {
            // Extract language code (e.g., "en_US.UTF-8" -> "en")
            return lang.substring(0, 2);
        }
        return "en";
    }

    /**
     * Get the system language name (e.g., "English", "Dutch", "German").
     */
    public string get_system_language_name() {
        string code = get_system_language_code();

        // Map common language codes to names
        switch (code) {
            case "en": return "English";
            case "nl": return "Dutch";
            case "de": return "German";
            case "fr": return "French";
            case "es": return "Spanish";
            case "it": return "Italian";
            case "pt": return "Portuguese";
            case "ru": return "Russian";
            case "zh": return "Chinese";
            case "ja": return "Japanese";
            case "ko": return "Korean";
            case "ar": return "Arabic";
            case "hi": return "Hindi";
            case "pl": return "Polish";
            case "tr": return "Turkish";
            case "sv": return "Swedish";
            case "da": return "Danish";
            case "no": return "Norwegian";
            case "fi": return "Finnish";
            case "cs": return "Czech";
            case "el": return "Greek";
            case "he": return "Hebrew";
            case "th": return "Thai";
            case "vi": return "Vietnamese";
            case "id": return "Indonesian";
            case "uk": return "Ukrainian";
            default: return code.up(); // Fallback to uppercase code
        }
    }
}
