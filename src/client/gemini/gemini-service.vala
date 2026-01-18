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

    // System prompt to restrict Gemini's behavior
    private const string SYSTEM_PROMPT = """You are an AI assistant integrated into the Geary email client. Your role is to help users with email-related tasks such as:
- Answering questions about emails
- Helping compose and draft emails
- Summarizing email content
- Translating emails

IMPORTANT RESTRICTIONS:
- You do NOT have access to the user's computer, file system, or any external tools
- You cannot execute commands, run scripts, or access the internet
- You cannot read, write, or modify files on the user's system
- You can only process text that is explicitly provided to you
- Do not attempt to perform any actions outside of text-based assistance
- If asked to do something outside your capabilities, politely explain that you can only help with text-based email tasks

In the future, you may be given specific Geary email tools to use. Until then, you can only provide text-based assistance.""";

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
     * Run a prompt through gemini-cli and return the response.
     */
    public async string run_prompt(string prompt) throws Error {
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

        yield subprocess.communicate_utf8_async(null, null, out stdout_buf, out stderr_buf);

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
     * Send a chat message and get a response.
     * Includes system prompt to restrict Gemini's behavior.
     */
    public async string chat(string message) throws Error {
        string full_prompt = "[System Instructions]\n%s\n\n[User Message]\n%s".printf(SYSTEM_PROMPT, message);
        return yield run_prompt(full_prompt);
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
