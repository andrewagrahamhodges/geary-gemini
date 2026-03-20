/*
 * Copyright 2025 Andrew Hodges
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Gemini.ServiceTest : TestCase {

    private Service? service = null;

    public ServiceTest() {
        base("Gemini.ServiceTest");
        add_test("extract_url_simple", extract_url_simple);
        add_test("extract_url_strips_trailing_punct", extract_url_strips_trailing_punct);
        add_test("extract_url_null_input", extract_url_null_input);
        add_test("extract_url_no_url", extract_url_no_url);
        add_test("filter_warnings_null", filter_warnings_null);
        add_test("filter_warnings_keeps_real_errors", filter_warnings_keeps_real_errors);
        add_test("filter_warnings_strips_noise", filter_warnings_strips_noise);
        add_test("truncate_short_text", truncate_short_text);
        add_test("truncate_long_text", truncate_long_text);
        add_test("language_code", language_code);
    }

    public override void set_up() {
        this.service = new Service();
    }

    public override void tear_down() {
        this.service = null;
    }

    public void extract_url_simple() throws GLib.Error {
        string? url = this.service.extract_first_url(
            "Visit https://accounts.google.com/auth to login"
        );
        assert_equal(url, "https://accounts.google.com/auth");
    }

    public void extract_url_strips_trailing_punct() throws GLib.Error {
        string? url = this.service.extract_first_url(
            "Go to https://example.com/path."
        );
        assert_equal(url, "https://example.com/path");
    }

    public void extract_url_null_input() throws GLib.Error {
        assert_null(this.service.extract_first_url(null));
        assert_null(this.service.extract_first_url(""));
    }

    public void extract_url_no_url() throws GLib.Error {
        assert_null(this.service.extract_first_url("no urls here"));
    }

    public void filter_warnings_null() throws GLib.Error {
        assert_equal(this.service.filter_non_fatal_warnings(null), "");
        assert_equal(this.service.filter_non_fatal_warnings(""), "");
    }

    public void filter_warnings_keeps_real_errors() throws GLib.Error {
        string result = this.service.filter_non_fatal_warnings(
            "Error: authentication failed\n"
        );
        assert_equal(result, "Error: authentication failed");
    }

    public void filter_warnings_strips_noise() throws GLib.Error {
        string input = string.join("\n",
            "(node:12345) [DEP0040] DeprecationWarning: something",
            "The punycode module is deprecated.",
            "Loaded cached credentials",
            "(Use `node --trace-deprecation ...` to show)",
            "Real error here"
        );
        string result = this.service.filter_non_fatal_warnings(input);
        assert_equal(result, "Real error here");
    }

    public void truncate_short_text() throws GLib.Error {
        assert_equal(
            this.service.truncate_for_prompt("hello", 100),
            "hello"
        );
    }

    public void truncate_long_text() throws GLib.Error {
        string result = this.service.truncate_for_prompt("abcdefghij", 5);
        assert_true(result.has_prefix("abcde"));
        assert_true(result.contains("[truncated]"));
    }

    public void language_code() throws GLib.Error {
        assert_equal(this.service.get_system_language_name(), this.service.get_system_language_name());
        // Ensure it never returns empty
        assert_true(this.service.get_system_language_name().length > 0);
    }
}
