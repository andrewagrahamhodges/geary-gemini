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
 * - Auto-installation of gemini-cli via npm
 * - Authentication with Google
 * - Translation, summarization, and chat features
 */
public class Gemini.Service : GLib.Object {

    private const string GEMINI_CLI_PACKAGE = "@google/gemini-cli";
    private const string GEMINI_COMMAND = "gemini";

    private string? gemini_path = null;
    private bool is_authenticated = false;

    /**
     * Signal emitted when gemini-cli installation starts.
     */
    public signal void install_started();

    /**
     * Signal emitted when gemini-cli installation completes.
     */
    public signal void install_completed(bool success, string? error_message);

    /**
     * Signal emitted when authentication is required.
     */
    public signal void authentication_required();

    /**
     * Get the installation directory for gemini-cli.
     */
    private string get_install_dir() {
        return Path.build_filename(
            Environment.get_user_data_dir(),
            "geary-gemini"
        );
    }

    /**
     * Get the path to the local gemini binary.
     */
    private string get_local_gemini_path() {
        return Path.build_filename(
            get_install_dir(),
            "node_modules", ".bin", "gemini"
        );
    }

    /**
     * Check if gemini-cli is installed and return its path.
     */
    public string? find_gemini_cli() {
        // First check if already cached
        if (this.gemini_path != null) {
            return this.gemini_path;
        }

        // Check system PATH
        string? system_path = Environment.find_program_in_path(GEMINI_COMMAND);
        if (system_path != null) {
            this.gemini_path = system_path;
            return this.gemini_path;
        }

        // Check local install
        string local_path = get_local_gemini_path();
        if (FileUtils.test(local_path, FileTest.EXISTS | FileTest.IS_EXECUTABLE)) {
            this.gemini_path = local_path;
            return this.gemini_path;
        }

        return null;
    }

    /**
     * Check if npm is available.
     */
    public bool is_npm_available() {
        return Environment.find_program_in_path("npm") != null;
    }

    /**
     * Check if gemini-cli is installed.
     */
    public bool is_installed() {
        return find_gemini_cli() != null;
    }

    /**
     * Install gemini-cli using npm.
     */
    public async void install() throws Error {
        if (!is_npm_available()) {
            throw new IOError.NOT_FOUND(
                "npm is not installed. Please install Node.js from https://nodejs.org"
            );
        }

        install_started();

        string install_dir = get_install_dir();

        // Create install directory
        DirUtils.create_with_parents(install_dir, 0755);

        try {
            var subprocess = new Subprocess(
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE,
                "npm", "install", "--prefix", install_dir, GEMINI_CLI_PACKAGE + "@latest"
            );

            yield subprocess.wait_async();

            if (subprocess.get_successful()) {
                // Clear cached path to re-detect
                this.gemini_path = null;
                install_completed(true, null);
            } else {
                string? stderr_output = null;
                try {
                    yield subprocess.communicate_utf8_async(null, null, null, out stderr_output);
                } catch (Error e) {
                    // Ignore
                }
                throw new IOError.FAILED(
                    "Failed to install gemini-cli: %s".printf(stderr_output ?? "unknown error")
                );
            }
        } catch (Error e) {
            install_completed(false, e.message);
            throw e;
        }
    }

    /**
     * Authenticate with Google (opens browser).
     */
    public async void authenticate() throws Error {
        string? gemini = find_gemini_cli();
        if (gemini == null) {
            throw new IOError.NOT_FOUND("gemini-cli is not installed");
        }

        var subprocess = new Subprocess(
            SubprocessFlags.NONE,
            gemini, "auth", "login"
        );

        yield subprocess.wait_async();

        if (subprocess.get_successful()) {
            this.is_authenticated = true;
        } else {
            throw new IOError.FAILED("Authentication failed");
        }
    }

    /**
     * Ensure gemini-cli is available, prompting for install if needed.
     * Returns true if ready to use, false if user cancelled.
     */
    public async bool ensure_ready() throws Error {
        if (is_installed()) {
            return true;
        }

        // Signal that we need to show install dialog
        // The UI will handle showing the dialog and calling install()
        return false;
    }

    /**
     * Run a prompt through gemini-cli and return the response.
     */
    public async string run_prompt(string prompt) throws Error {
        string? gemini = find_gemini_cli();
        if (gemini == null) {
            throw new IOError.NOT_FOUND(
                "gemini-cli is not installed. Please install it first."
            );
        }

        var subprocess = new Subprocess(
            SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE,
            gemini, "-p", prompt
        );

        string? stdout_buf = null;
        string? stderr_buf = null;

        yield subprocess.communicate_utf8_async(null, null, out stdout_buf, out stderr_buf);

        if (!subprocess.get_successful()) {
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
     */
    public async string chat(string message) throws Error {
        return yield run_prompt(message);
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
