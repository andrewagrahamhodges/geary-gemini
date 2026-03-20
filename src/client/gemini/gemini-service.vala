/*
 * Minimal Gemini service integration.
 */

namespace Gemini {

public class Service : GLib.Object {

    public string? active_account { get; set; default = null; }

    public async string? help_compose(string prompt, string? context) throws GLib.Error {
        string full_prompt = prompt;
        if (!Geary.String.is_empty_or_whitespace(context)) {
            full_prompt = "%s\n\n%s".printf(context, prompt);
        }

        string[] argv = {
            "gemini",
            "--output-format",
            "stream-json",
            "-p",
            "-",
            null
        };

        Subprocess launcher = new Subprocess.newv(
            argv,
            SubprocessFlags.STDIN_PIPE |
            SubprocessFlags.STDOUT_PIPE |
            SubprocessFlags.STDERR_PIPE
        );

        string? stdout_buf = null;
        string? stderr_buf = null;
        yield launcher.communicate_utf8_async(
            full_prompt,
            null,
            out stdout_buf,
            out stderr_buf
        );

        if (!launcher.get_successful()) {
            throw new GLib.IOError.FAILED(
                Geary.String.is_empty(stderr_buf)
                    ? "gemini command failed"
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
