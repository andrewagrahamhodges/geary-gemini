/*
 * Minimal translation service integration.
 */

namespace Translation {

public class Service : GLib.Object {

    public bool is_available() {
        return GLib.Environment.find_program_in_path("trans") != null;
    }

    public async string? detect_language(string text) throws GLib.Error {
        if (Geary.String.is_empty_or_whitespace(text)) {
            return null;
        }

        string[] argv = {
            "trans",
            "-brief",
            "-identify",
            text,
            null
        };

        return yield run_command(argv);
    }

    public async string? translate(string text, string? target_lang = null) throws GLib.Error {
        if (Geary.String.is_empty_or_whitespace(text)) {
            return null;
        }

        string language = target_lang ?? get_default_target_language();
        string[] argv = {
            "trans",
            "-brief",
            ":%s".printf(language),
            text,
            null
        };

        return yield run_command(argv);
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

    private async string? run_command(string[] argv) throws GLib.Error {
        Subprocess process = new Subprocess.newv(
            argv,
            SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
        );

        string? stdout_buf = null;
        string? stderr_buf = null;
        yield process.communicate_utf8_async(
            null,
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
