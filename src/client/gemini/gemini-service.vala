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

    // gemini-cli config paths
    private const string GEMINI_CONFIG_DIR = ".gemini";
    private const string GOOGLE_ACCOUNTS_FILE = "google_accounts.json";

    /** The currently active Gemini account email, or null. */
    public string? active_account { get; private set; default = null; }

    // System prompt for Gemini chat - direct context mode (no MCP).
    private const string SYSTEM_PROMPT =
        "You are an AI assistant integrated into the Geary email client. You help users with their emails.\n\n" +
        "IMPORTANT DEFAULTS:\n" +
        "- When asked to translate, ALWAYS translate to %s (the user's system language) unless they specify otherwise\n" +
        "- Assume questions are about the currently selected email unless the user asks about other emails\n" +
        "- Use provided email and attachment context if present\n\n" +
        "ATTACHMENTS:\n" +
        "- If attachment text is provided, use it\n" +
        "- If an attachment is listed as unavailable, state that limitation clearly\n" +
        "- Never hallucinate attachment contents\n\n" +
        "RESPONSE STYLE:\n" +
        "- Give direct, concise responses\n" +
        "- Use markdown lightly (bullets and bold for important points)\n" +
        "- Do NOT explain internal reasoning\n" +
        "- Focus only on email-related tasks";

    /**
     * Signal emitted when authentication is required.
     */
    public signal void authentication_required();

    /**
     * Signal emitted when authentication completes.
     */
    public signal void authentication_completed(bool success, string? error_message);


    internal string? extract_first_url(string? text) {
        if (text == null || text.length == 0) {
            return null;
        }

        try {
            var regex = new Regex("(https?://[^\\s<>\"']+[^\\s<>\"'.,;:!?\\)\\]])");
            MatchInfo info;
            if (regex.match(text, 0, out info)) {
                return info.fetch(1);
            }
        } catch (RegexError e) {
            // Ignore regex errors
        }

        return null;
    }

    private bool open_auth_url(string? url) {
        if (url == null || url.length == 0) {
            return false;
        }

        try {
            AppInfo.launch_default_for_uri(url, null);
            return true;
        } catch (Error e) {
            warning("Failed to open auth URL: %s", e.message);
            return false;
        }
    }

    /**
     * Check if gemini-cli is installed (bundled with the package).
     */
    public bool is_installed() {
        return FileUtils.test(GEMINI_BINARY, FileTest.EXISTS);
    }

    /**
     * Check if user is authenticated with Google.
     */
    public async bool check_authenticated() {
        if (!is_installed()) {
            return false;
        }

        try {
            var launcher = new SubprocessLauncher(
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
            );
            launcher.setenv("NODE_NO_WARNINGS", "1", true);
            var subprocess = launcher.spawn(
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
     * Streams output line-by-line so the auth URL is opened immediately.
     */
    public async void authenticate() throws Error {
        if (!is_installed()) {
            throw new IOError.NOT_FOUND("Gemini CLI is not installed. Please reinstall geary-gemini.");
        }

        var launcher = new SubprocessLauncher(
            SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
        );
        launcher.setenv("NODE_NO_WARNINGS", "1", true);
        var subprocess = launcher.spawn(
            NODE_BINARY, GEMINI_BINARY, "auth", "login"
        );

        // Stream stdout and stderr to capture the auth URL as soon as it appears
        var stdout_stream = new DataInputStream(subprocess.get_stdout_pipe());
        var stderr_stream = new DataInputStream(subprocess.get_stderr_pipe());
        var output = new StringBuilder();
        string? auth_url = null;

        // Read stdout lines
        try {
            string? line;
            while ((line = yield stdout_stream.read_line_async()) != null) {
                output.append(line);
                output.append("\n");
                if (auth_url == null) {
                    auth_url = extract_first_url(line);
                    if (auth_url != null) {
                        open_auth_url(auth_url);
                    }
                }
            }
        } catch (Error e) {
            // Stream ended
        }

        // Read stderr lines
        try {
            string? line;
            while ((line = yield stderr_stream.read_line_async()) != null) {
                output.append(line);
                output.append("\n");
                if (auth_url == null) {
                    auth_url = extract_first_url(line);
                    if (auth_url != null) {
                        open_auth_url(auth_url);
                    }
                }
            }
        } catch (Error e) {
            // Stream ended
        }

        yield subprocess.wait_async();
        string combined = output.str;

        if (!subprocess.get_successful()) {
            // Some gemini-cli versions emit "Loaded cached credentials" and exit non-zero.
            // Treat as success if auth status is already valid.
            bool authed = yield check_authenticated();
            if (!authed) {
                string cleaned = filter_non_fatal_warnings(combined);
                string msg;
                if (auth_url != null) {
                    msg = "Authentication failed. Open this URL to continue login: %s".printf(auth_url);
                } else if (cleaned.length > 0) {
                    msg = "Authentication failed: %s".printf(cleaned);
                } else {
                    msg = "Authentication failed";
                }
                authentication_completed(false, msg);
                throw new IOError.FAILED(msg);
            }
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
     * @param tool_name The tool name (for tool_use/tool_result), null otherwise
     * @param tool_input_json The tool input as a JSON string (for tool_use), null otherwise
     */
    public delegate void StructuredStreamCallback(string msg_type, string content, string? tool_name, string? tool_input_json);

    internal string filter_non_fatal_warnings(string? stderr_text) {
        if (stderr_text == null || stderr_text.length == 0) {
            return "";
        }

        var kept = new StringBuilder();
        foreach (string raw_line in stderr_text.split("\n")) {
            string line = raw_line.strip();
            if (line.length == 0) {
                continue;
            }

            // Ignore Node deprecation noise from dependency chains
            if (line.contains("[DEP0040]") ||
                line.contains("The punycode module is deprecated") ||
                line.contains("Loaded cached credentials") ||
                line.has_prefix("(Use `node --trace-deprecation") ||
                line.has_prefix("(node:")) {
                continue;
            }

            kept.append(line);
            kept.append("\n");
        }

        return kept.str.strip();
    }

    /**
     * Run a prompt through gemini-cli and return the response.
     */
    public async string run_prompt(string prompt, StreamingCallback? on_output = null) throws Error {
        if (!is_installed()) {
            throw new IOError.NOT_FOUND(
                "Gemini CLI is not installed. Please reinstall geary-gemini."
            );
        }

        var launcher = new SubprocessLauncher(
            SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
        );
        launcher.setenv("NODE_NO_WARNINGS", "1", true);
        var subprocess = launcher.spawn(
            NODE_BINARY, GEMINI_BINARY, "-p", "-"
        );

        // Write prompt via stdin to avoid exposing email content in /proc/cmdline
        var stdin_stream = subprocess.get_stdin_pipe();
        var prompt_bytes = new GLib.Bytes(prompt.data);
        yield stdin_stream.write_bytes_async(prompt_bytes);
        yield stdin_stream.close_async();

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

            // Read all stderr lines
            var stderr_builder = new StringBuilder();
            try {
                string? err_line;
                while ((err_line = yield stderr_stream.read_line_async()) != null) {
                    stderr_builder.append(err_line);
                    stderr_builder.append("\n");
                }
            } catch (Error e) {
                // Stream ended
            }
            stderr_buf = stderr_builder.str;

            yield subprocess.wait_async();
            stdout_buf = output_builder.str;
        } else {
            yield subprocess.communicate_utf8_async(null, null, out stdout_buf, out stderr_buf);
        }

        string stderr_clean = filter_non_fatal_warnings(stderr_buf);

        if (!subprocess.get_successful()) {
            // Check if auth error
            if (stderr_clean.length > 0 && "auth" in stderr_clean.down()) {
                authentication_required();
                throw new IOError.PERMISSION_DENIED("Please login with Google first");
            }

            // Non-fatal warning-only stderr: return stdout if we have it
            if (stderr_clean.length == 0 && stdout_buf != null && stdout_buf.strip().length > 0) {
                return stdout_buf;
            }

            throw new IOError.FAILED(
                "Gemini CLI error: %s".printf(
                    stderr_clean.length > 0 ? stderr_clean : "unknown error"
                )
            );
        }

        return stdout_buf ?? "";
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


    internal string truncate_for_prompt(string text, int max_chars) {
        if (text == null) return "";
        if (text.length <= max_chars) return text;
        return text.substring(0, max_chars) + "
...[truncated]";
    }

    private string build_selected_email_context() {
        var app = GLib.Application.get_default() as Application.Client;
        if (app == null) return "";

        var window = app.get_active_main_window();
        if (window == null || window.conversation_viewer == null) return "";

        var list = window.conversation_viewer.current_list;
        if (list == null) return "";

        var email_view = list.get_reply_target();
        if (email_view == null || email_view.email == null) return "";

        var email = email_view.email;
        var ctx = new StringBuilder();
        ctx.append("[Selected Email Context]
");
        ctx.append("Subject: %s
".printf(email.subject != null ? email.subject.to_string() : ""));
        ctx.append("From: %s
".printf(email.from != null ? email.from.to_string() : ""));
        ctx.append("To: %s
".printf(email.to != null ? email.to.to_string() : ""));
        ctx.append("Date: %s

".printf(email.date != null ? email.date.to_string() : ""));

        string body = email.get_preview_as_string() ?? "";
        try {
            if (email.fields.fulfills(Geary.Email.REQUIRED_FOR_MESSAGE)) {
                var message = email.get_message();
                string? searchable = message.get_searchable_body(true);
                if (searchable != null && searchable.strip().length > 0) {
                    body = searchable;
                }
            }
        } catch (Error e) {
            debug("Failed to get full email body: %s", e.message);
        }

        ctx.append("Body:
%s

".printf(truncate_for_prompt(body, 12000)));

        if (email.attachments != null && email.attachments.size > 0) {
            ctx.append("[Attachments]\n");
            int index = 1;
            foreach (var attachment in email.attachments) {
                string name = attachment.file != null ? attachment.file.get_basename() : "attachment";
                string mime = attachment.content_type != null ? attachment.content_type.to_string() : "unknown";
                ctx.append("%d. %s (%s)\n".printf(index, name, mime));

                if (attachment.file != null && mime.has_prefix("text/")) {
                    // Inline text content directly
                    try {
                        uint8[] bytes;
                        string? etag;
                        if (attachment.file.load_contents(null, out bytes, out etag)) {
                            string text = (string) bytes;
                            if (text != null && text.strip().length > 0) {
                                ctx.append("Extracted text:\n%s\n\n".printf(
                                    truncate_for_prompt(text, 6000)));
                            }
                        }
                    } catch (Error e) {
                        debug("Attachment text extraction failed: %s", e.message);
                    }
                } else if (attachment.file != null) {
                    // For PDFs, images, and other binary files: pass the file path
                    // using gemini-cli's @ syntax so it can analyze them multimodally
                    string file_path = attachment.file.get_path();
                    if (file_path != null) {
                        ctx.append("File content: @%s\n\n".printf(file_path));
                    }
                }
                index++;
            }
        }

        return ctx.str;
    }

    /**
     * Build the full prompt with system instructions.
     */
    private string build_chat_prompt(string message) {
        string lang = get_system_language_name();
        string system = SYSTEM_PROMPT.printf(lang);
        string selected = build_selected_email_context();
        if (selected.strip().length > 0) {
            return "[System Instructions]\n%s\n\n%s\n[User Message]\n%s".printf(system, selected, message);
        }
        return "[System Instructions]\n%s\n\n[User Message]\n%s".printf(system, message);
    }

    /**
     * Send a chat message and get a response.
     */
    public async string chat(string message) throws Error {
        string full_prompt = build_chat_prompt(message);
        return yield run_prompt(full_prompt);
    }

    /**
     * Send a chat message.
     * Currently routes through plain gemini-cli prompt execution (no MCP tool stream).
     */
    public async string chat_streaming(string message, StructuredStreamCallback on_stream) throws Error {
        string full_prompt = build_chat_prompt(message);
        return yield run_prompt(full_prompt, (line) => {
            on_stream("message", line, null, null);
        });
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

    /**
     * Load the currently active Gemini account from ~/.gemini/google_accounts.json.
     */
    public void load_active_account() {
        string path = Path.build_filename(
            Environment.get_home_dir(), GEMINI_CONFIG_DIR, GOOGLE_ACCOUNTS_FILE
        );

        try {
            string contents;
            FileUtils.get_contents(path, out contents);
            var parser = new Json.Parser();
            parser.load_from_data(contents);
            var root = parser.get_root();
            if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                var obj = root.get_object();
                if (obj.has_member("active")) {
                    this.active_account = obj.get_string_member("active");
                }
            }
        } catch (Error e) {
            debug("No active Gemini account found: %s", e.message);
        }
    }

    /**
     * Switch the active Gemini account by writing to ~/.gemini/google_accounts.json.
     */
    public void switch_active_account(string email) throws Error {
        string dir_path = Path.build_filename(
            Environment.get_home_dir(), GEMINI_CONFIG_DIR
        );
        string file_path = Path.build_filename(dir_path, GOOGLE_ACCOUNTS_FILE);

        // Ensure directory exists
        DirUtils.create_with_parents(dir_path, 0755);

        // Read existing file to preserve "old" array
        Json.Array old_array = new Json.Array();
        try {
            string contents;
            FileUtils.get_contents(file_path, out contents);
            var parser = new Json.Parser();
            parser.load_from_data(contents);
            var root = parser.get_root();
            if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                var obj = root.get_object();
                if (obj.has_member("old")) {
                    old_array = obj.get_array_member("old");
                }
            }
        } catch (Error e) {
            // File doesn't exist yet, that's fine
        }

        // Build new JSON
        var generator = new Json.Generator();
        generator.pretty = true;
        var root_node = new Json.Node(Json.NodeType.OBJECT);
        var obj = new Json.Object();
        obj.set_string_member("active", email);
        obj.set_array_member("old", old_array);
        root_node.set_object(obj);
        generator.set_root(root_node);

        string json = generator.to_data(null);
        FileUtils.set_contents(file_path, json);

        this.active_account = email;
    }

    /**
     * Signal emitted when the active account changes.
     */
    public signal void active_account_changed(string? email);
}
