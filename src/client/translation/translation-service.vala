/*
 * Translation service — wraps translate-shell (trans) CLI.
 * Checks bundled binary at /usr/share/geary-gemini/bin/trans first,
 * then falls back to system PATH.
 * Text is passed via stdin to handle any length.
 */

namespace Translation {

public class Service : GLib.Object {

    private string? _trans_path = null;

    private string? find_trans_binary() {
        if (this._trans_path != null) {
            return this._trans_path;
        }
        string bundled = "/usr/share/geary-gemini/bin/trans";
        if (GLib.FileUtils.test(bundled, GLib.FileTest.IS_EXECUTABLE)) {
            this._trans_path = bundled;
            return bundled;
        }
        string? system_path = GLib.Environment.find_program_in_path("trans");
        if (system_path != null) {
            this._trans_path = system_path;
        }
        return this._trans_path;
    }

    public bool is_available() {
        return find_trans_binary() != null;
    }

    /**
     * Clean text for translation: strip zero-width chars, collapse whitespace.
     */
    private string clean_text(string text) {
        var result = new StringBuilder();
        bool last_was_space = false;
        unichar c;
        int i = 0;
        while (text.get_next_char(ref i, out c)) {
            // Skip zero-width characters (ZWSP, ZWNJ, ZWJ, FEFF, soft hyphen)
            if (c == 0x200B || c == 0x200C || c == 0x200D || c == 0xFEFF || c == 0x00AD) {
                continue;
            }
            // Collapse multiple whitespace
            if (c.isspace()) {
                if (!last_was_space) {
                    result.append_unichar(' ');
                    last_was_space = true;
                }
                continue;
            }
            last_was_space = false;
            result.append_unichar(c);
        }
        return result.str.strip();
    }

    public async string? detect_language(string text) throws GLib.Error {
        if (Geary.String.is_empty_or_whitespace(text)) {
            return null;
        }

        string? trans = find_trans_binary();
        if (trans == null) {
            throw new GLib.IOError.NOT_FOUND("translate-shell (trans) not found");
        }

        string cleaned = clean_text(text);
        // Only send first 500 chars for detection
        string sample = cleaned;
        if (cleaned.length > 500) {
            sample = cleaned.substring(0, 500);
        }

        string[] argv = { trans, "-brief", "-identify" };
        return yield run_command_with_stdin(argv, sample);
    }

    public async string? translate(string text, string? target_lang = null) throws GLib.Error {
        if (Geary.String.is_empty_or_whitespace(text)) {
            return null;
        }

        string language = target_lang ?? get_default_target_language();
        string? trans = find_trans_binary();
        if (trans == null) {
            throw new GLib.IOError.NOT_FOUND("translate-shell (trans) not found");
        }

        string cleaned = clean_text(text);
        if (Geary.String.is_empty_or_whitespace(cleaned)) {
            return null;
        }

        string[] argv = { trans, "-brief", ":%s".printf(language) };
        return yield run_command_with_stdin(argv, cleaned);
    }

    private string get_default_target_language() {
        foreach (string lang in Intl.get_language_names()) {
            if (lang != null && lang != "C" && lang != "") {
                int separator = lang.index_of_char('_');
                if (separator > 0) {
                    return lang.substring(0, separator);
                }
                separator = lang.index_of_char('.');
                if (separator > 0) {
                    return lang.substring(0, separator);
                }
                return lang;
            }
        }
        return "en";
    }

    private async string? run_command_with_stdin(string[] argv, string input) throws GLib.Error {
        Subprocess process = new Subprocess.newv(
            argv,
            SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
        );

        string? stdout_buf = null;
        string? stderr_buf = null;
        yield process.communicate_utf8_async(
            input,
            null,
            out stdout_buf,
            out stderr_buf
        );

        if (!process.get_successful()) {
            throw new GLib.IOError.FAILED(
                Geary.String.is_empty(stderr_buf)
                    ? "trans command failed"
                    : stderr_buf
            );
        }

        if (Geary.String.is_empty_or_whitespace(stdout_buf)) {
            return null;
        }

        return stdout_buf.strip();
    }

}

}
