/*
 * Gemini AI service — calls Google Gemini API directly via HTTP.
 * API key stored in ~/.config/geary-gemini/config.ini
 */

namespace Gemini {

public class Service : GLib.Object {

    private const string CONFIG_DIR = "geary-gemini";
    private const string CONFIG_FILE = "config.ini";
    private const string API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent";

    public string? active_account { get; set; default = null; }

    private string? _api_key = null;
    private bool _key_loaded = false;

    private string get_config_path() {
        return Path.build_filename(
            Environment.get_user_config_dir(), CONFIG_DIR, CONFIG_FILE
        );
    }

    public string? get_api_key() {
        if (!this._key_loaded) {
            this._key_loaded = true;
            string config_path = get_config_path();
            if (FileUtils.test(config_path, FileTest.EXISTS)) {
                try {
                    var keyfile = new KeyFile();
                    keyfile.load_from_file(config_path, KeyFileFlags.NONE);
                    if (keyfile.has_key("gemini", "api_key")) {
                        string key = keyfile.get_string("gemini", "api_key");
                        if (key.strip().length > 0) {
                            this._api_key = key.strip();
                        }
                    }
                } catch (Error e) {
                    warning("Failed to read Gemini config: %s", e.message);
                }
            }
        }
        return this._api_key;
    }

    public void set_api_key(string? key) {
        this._api_key = (key != null && key.strip().length > 0) ? key.strip() : null;
        this._key_loaded = true;

        // Save to config file
        string config_dir = Path.build_filename(
            Environment.get_user_config_dir(), CONFIG_DIR
        );
        string config_path = get_config_path();

        try {
            DirUtils.create_with_parents(config_dir, 0700);
            var keyfile = new KeyFile();
            // Load existing if present
            if (FileUtils.test(config_path, FileTest.EXISTS)) {
                try {
                    keyfile.load_from_file(config_path, KeyFileFlags.KEEP_COMMENTS);
                } catch (Error e) {
                    // Start fresh
                }
            }
            keyfile.set_string("gemini", "api_key", this._api_key ?? "");
            keyfile.save_to_file(config_path);
            // Restrict permissions
            FileUtils.chmod(config_path, 0600);
        } catch (Error e) {
            warning("Failed to save Gemini config: %s", e.message);
        }
    }

    public bool is_configured() {
        return get_api_key() != null;
    }

    public async string? help_compose(string prompt, string? context) throws GLib.Error {
        string? key = get_api_key();
        if (key == null) {
            throw new GLib.IOError.FAILED(
                "Gemini API key not configured. Set it in Preferences > AI."
            );
        }

        string full_prompt = prompt;
        if (!Geary.String.is_empty_or_whitespace(context)) {
            full_prompt = "Context:\n%s\n\nRequest:\n%s".printf(context, prompt);
        }

        // Build JSON request body
        string escaped_prompt = full_prompt.replace("\\", "\\\\")
                                           .replace("\"", "\\\"")
                                           .replace("\n", "\\n")
                                           .replace("\r", "")
                                           .replace("\t", "\\t");

        string request_body = """{"contents":[{"parts":[{"text":"%s"}]}],"generationConfig":{"temperature":0.7,"maxOutputTokens":2048}}""".printf(escaped_prompt);

        string url = "%s?key=%s".printf(API_URL, key);

        // Use curl subprocess for HTTP (avoids libsoup version issues)
        string[] argv = {
            "curl", "-s", "-S",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", request_body,
            "--max-time", "30",
            url
        };

        Subprocess process = new Subprocess.newv(
            argv,
            SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
        );

        string? stdout_buf = null;
        string? stderr_buf = null;
        yield process.communicate_utf8_async(null, null, out stdout_buf, out stderr_buf);

        if (!process.get_successful()) {
            throw new GLib.IOError.FAILED(
                Geary.String.is_empty(stderr_buf)
                    ? "Gemini API request failed"
                    : stderr_buf
            );
        }

        if (Geary.String.is_empty_or_whitespace(stdout_buf)) {
            throw new GLib.IOError.FAILED("Empty response from Gemini API");
        }

        // Parse JSON response to extract text
        // Response format: {"candidates":[{"content":{"parts":[{"text":"..."}]}}]}
        try {
            var parser = new Json.Parser();
            parser.load_from_data(stdout_buf);
            var root = parser.get_root().get_object();

            // Check for error
            if (root.has_member("error")) {
                var error_obj = root.get_object_member("error");
                string error_msg = error_obj.get_string_member("message");
                throw new GLib.IOError.FAILED("Gemini API error: %s".printf(error_msg));
            }

            var candidates = root.get_array_member("candidates");
            var candidate = candidates.get_object_element(0);
            var content = candidate.get_object_member("content");
            var parts = content.get_array_member("parts");
            var part = parts.get_object_element(0);
            string text = part.get_string_member("text");
            return text.strip();
        } catch (Error e) {
            if (e is GLib.IOError.FAILED) {
                throw e;
            }
            throw new GLib.IOError.FAILED(
                "Failed to parse Gemini response: %s\nRaw: %s".printf(
                    e.message, stdout_buf.substring(0, int.min(200, stdout_buf.length))
                )
            );
        }
    }

}

}
