/*
 * Copyright 2025 Andrew Hodges
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A sidebar widget for chatting with Gemini AI.
 *
 * Provides an interactive chat interface for asking questions,
 * getting help with emails, and more.
 */
[GtkTemplate (ui = "/org/gnome/Geary/gemini-sidebar.ui")]
public class Gemini.Sidebar : Gtk.Bin {

    /** The Gemini service instance. */
    public Gemini.Service service { get; construct; }

    [GtkChild] private unowned Gtk.Revealer status_revealer;
    [GtkChild] private unowned Gtk.Label status_label;
    [GtkChild] private unowned Gtk.Button login_button;
    [GtkChild] private unowned Gtk.ScrolledWindow chat_scrolled;
    [GtkChild] private unowned Gtk.Box chat_box;
    [GtkChild] private unowned Gtk.Label welcome_label;
    [GtkChild] private unowned Gtk.Entry message_entry;
    [GtkChild] private unowned Gtk.Button send_button;
    [GtkChild] private unowned Gtk.Revealer loading_revealer;
    [GtkChild] private unowned Gtk.Label loading_label;

    private bool is_processing = false;
    private Gtk.Label? streaming_content_label = null;

    static construct {
        set_css_name("gemini-sidebar");
    }

    public Sidebar(Gemini.Service service) {
        Object(service: service);
    }

    construct {
        // Connect signals
        this.login_button.clicked.connect(on_login_clicked);
        this.send_button.clicked.connect(on_send_clicked);
        this.message_entry.changed.connect(on_entry_changed);
        this.message_entry.activate.connect(on_send_clicked);

        // Connect service signals
        this.service.authentication_required.connect(on_authentication_required);
        this.service.authentication_completed.connect(on_authentication_completed);

        // Check initial state
        check_gemini_status();
    }

    /**
     * Check if Gemini CLI is installed and authenticated, update UI accordingly.
     */
    private void check_gemini_status() {
        if (!this.service.is_installed()) {
            // This shouldn't happen if .deb installed correctly
            this.status_label.label = _("Gemini CLI not found. Please reinstall geary-gemini.");
            this.status_revealer.reveal_child = true;
            this.login_button.visible = false;
            this.message_entry.sensitive = false;
            return;
        }

        // Check authentication asynchronously
        this.service.check_authenticated.begin((obj, res) => {
            bool authenticated = this.service.check_authenticated.end(res);
            if (authenticated) {
                this.status_revealer.reveal_child = false;
                this.message_entry.sensitive = true;
            } else {
                this.status_label.label = _("Sign in with your Google account to use Gemini AI features.");
                this.status_revealer.reveal_child = true;
                this.login_button.visible = true;
                this.login_button.sensitive = true;
                this.message_entry.sensitive = false;
            }
        });
    }

    private void on_login_clicked() {
        this.login_button.sensitive = false;
        this.status_label.label = _("Opening browser for Google sign-in...");

        this.service.authenticate.begin((obj, res) => {
            try {
                this.service.authenticate.end(res);
                check_gemini_status();
            } catch (Error e) {
                this.status_label.label = _("Login failed: %s").printf(e.message);
                this.login_button.sensitive = true;
            }
        });
    }

    private void on_authentication_required() {
        this.status_label.label = _("Please sign in with Google to continue.");
        this.status_revealer.reveal_child = true;
        this.login_button.visible = true;
        this.login_button.sensitive = true;
        this.message_entry.sensitive = false;
    }

    private void on_authentication_completed(bool success, string? error_message) {
        if (success) {
            this.status_revealer.reveal_child = false;
            this.message_entry.sensitive = true;
        } else {
            this.status_label.label = _("Login failed: %s").printf(
                error_message ?? _("Unknown error")
            );
            this.login_button.sensitive = true;
        }
    }

    private void on_entry_changed() {
        string text = this.message_entry.text.strip();
        this.send_button.sensitive = text.length > 0 && !this.is_processing;
    }

    private void on_send_clicked() {
        string message = this.message_entry.text.strip();
        if (message.length == 0 || this.is_processing) {
            return;
        }

        // Clear input and add user message to chat
        this.message_entry.text = "";
        add_message(message, true);

        // Send to Gemini
        send_message.begin(message);
    }

    private async void send_message(string message) {
        this.is_processing = true;
        this.loading_revealer.reveal_child = true;
        this.loading_label.label = _("Thinking...");
        this.send_button.sensitive = false;
        this.message_entry.sensitive = false;

        // Create a streaming content label to show live output
        this.streaming_content_label = null;

        try {
            // Use structured streaming - callback receives (type, content)
            // tool_use/tool_result go to thinking indicator, message content is the response
            string response = yield this.service.chat_streaming(message, (msg_type, content) => {
                handle_stream_message(msg_type, content);
            });
            // Clear streaming label and add final message
            this.streaming_content_label = null;
            // Response already filtered - only contains assistant message content
            add_message(response.strip(), false);
        } catch (Error e) {
            this.streaming_content_label = null;
            add_message(_("Error: %s").printf(e.message), false, true);
        }

        this.is_processing = false;
        this.loading_revealer.reveal_child = false;
        this.message_entry.sensitive = true;
        on_entry_changed();
        this.message_entry.grab_focus();
    }

    /**
     * Handle structured streaming messages from gemini-cli.
     * Shows tool use in thinking indicator, ignores message content (already accumulated).
     */
    private void handle_stream_message(string msg_type, string content) {
        switch (msg_type) {
            case "tool_use":
                // Show which tool is being used
                this.loading_label.label = content;  // e.g., "Using get_selected_email..."
                break;

            case "tool_result":
                // Brief status update
                if (content.length > 0) {
                    this.loading_label.label = content;
                }
                break;

            case "message":
                // Assistant response streaming - show preview in thinking area
                if (content.length > 0) {
                    string preview = content.strip();
                    if (preview.length > 50) {
                        preview = preview.substring(0, 47) + "...";
                    }
                    if (preview.length > 0) {
                        this.loading_label.label = preview;
                    }
                }
                break;

            default:
                // Other message types - just show "Processing..."
                this.loading_label.label = _("Processing...");
                break;
        }
    }

    /**
     * Convert markdown text to Pango markup for rendering in GTK labels.
     * Supports: **bold**, *italic*, `code`, ## headers, - lists
     */
    private string markdown_to_pango(string markdown) {
        // First escape any existing markup characters to prevent injection
        string result = GLib.Markup.escape_text(markdown);

        // Process line by line for headers and lists
        var lines = result.split("\n");
        var processed_lines = new GLib.GenericArray<string>();

        foreach (string line in lines) {
            string processed = line;

            // Headers: ## Header -> large bold text
            if (processed.has_prefix("## ")) {
                processed = "<span weight=\"bold\" size=\"large\">" + processed.substring(3) + "</span>";
            } else if (processed.has_prefix("# ")) {
                processed = "<span weight=\"bold\" size=\"x-large\">" + processed.substring(2) + "</span>";
            }
            // Lists: - item -> bullet point
            else if (processed.has_prefix("- ")) {
                processed = "  •  " + processed.substring(2);
            }
            // Numbered lists: 1. item -> keep as-is but indent
            else if (processed.length > 2 && processed[0].isdigit() && processed[1] == '.') {
                processed = "  " + processed;
            }

            processed_lines.add(processed);
        }

        result = string.joinv("\n", processed_lines.data);

        // Bold: **text** -> <b>text</b>
        try {
            var bold_regex = new Regex("\\*\\*(.+?)\\*\\*");
            result = bold_regex.replace(result, -1, 0, "<b>\\1</b>");
        } catch (RegexError e) {
            // Ignore regex errors
        }

        // Italic: *text* -> <i>text</i> (but not inside bold)
        try {
            var italic_regex = new Regex("(?<!\\*)\\*([^*]+)\\*(?!\\*)");
            result = italic_regex.replace(result, -1, 0, "<i>\\1</i>");
        } catch (RegexError e) {
            // Ignore regex errors
        }

        // Code: `code` -> <tt>code</tt>
        try {
            var code_regex = new Regex("`([^`]+)`");
            result = code_regex.replace(result, -1, 0, "<tt>\\1</tt>");
        } catch (RegexError e) {
            // Ignore regex errors
        }

        return result;
    }

    /**
     * Add a message to the chat display.
     */
    private void add_message(string text, bool is_user, bool is_error = false) {
        // Hide welcome message on first message
        this.welcome_label.visible = false;

        var message_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
        message_box.visible = true;
        message_box.margin_start = is_user ? 24 : 0;
        message_box.margin_end = is_user ? 0 : 24;

        // Sender label
        var sender_label = new Gtk.Label(is_user ? _("You") : _("Gemini"));
        sender_label.visible = true;
        sender_label.xalign = 0;
        sender_label.get_style_context().add_class("dim-label");
        var attrs = new Pango.AttrList();
        attrs.insert(Pango.attr_weight_new(Pango.Weight.BOLD));
        attrs.insert(Pango.attr_scale_new(0.85));
        sender_label.attributes = attrs;
        message_box.pack_start(sender_label, false, false, 0);

        // Message content - use Pango markup for Gemini responses
        var content_label = new Gtk.Label(null);
        content_label.visible = true;
        content_label.wrap = true;
        content_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        content_label.xalign = 0;
        content_label.selectable = true;

        if (is_user) {
            // Plain text for user messages
            content_label.set_text(text);
        } else {
            // Render markdown for AI responses
            content_label.use_markup = true;
            content_label.set_markup(markdown_to_pango(text));
        }

        if (is_error) {
            content_label.get_style_context().add_class("error");
        }

        message_box.pack_start(content_label, false, false, 0);

        this.chat_box.pack_start(message_box, false, false, 0);

        // Scroll to bottom
        scroll_to_bottom();
    }

    /**
     * Scroll the chat view to the bottom.
     */
    private void scroll_to_bottom() {
        // Use idle to ensure the widget has been allocated
        GLib.Idle.add(() => {
            var adj = this.chat_scrolled.vadjustment;
            adj.value = adj.upper - adj.page_size;
            return false;
        });
    }

    /**
     * Clear the chat history.
     */
    public void clear_chat() {
        // Remove all children except welcome label
        foreach (var child in this.chat_box.get_children()) {
            if (child != this.welcome_label) {
                this.chat_box.remove(child);
            }
        }
        this.welcome_label.visible = true;
    }

    /**
     * Show an AI result in the sidebar (for translate/summarize).
     * This adds a labeled result to the chat area.
     */
    public void show_ai_result(string title, string content) {
        // Hide welcome message
        this.welcome_label.visible = false;

        var result_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
        result_box.visible = true;
        result_box.margin_start = 0;
        result_box.margin_end = 0;

        // Add a styled frame around the result
        var frame = new Gtk.Frame(null);
        frame.visible = true;
        frame.get_style_context().add_class("view");

        var inner_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        inner_box.visible = true;
        inner_box.margin = 12;

        // Title label
        var title_label = new Gtk.Label(title);
        title_label.visible = true;
        title_label.xalign = 0;
        title_label.get_style_context().add_class("heading");
        var title_attrs = new Pango.AttrList();
        title_attrs.insert(Pango.attr_weight_new(Pango.Weight.BOLD));
        title_label.attributes = title_attrs;
        inner_box.pack_start(title_label, false, false, 0);

        // Separator
        var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
        sep.visible = true;
        inner_box.pack_start(sep, false, false, 0);

        // Content label
        var content_label = new Gtk.Label(content);
        content_label.visible = true;
        content_label.wrap = true;
        content_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        content_label.xalign = 0;
        content_label.selectable = true;
        inner_box.pack_start(content_label, false, false, 0);

        // Copy button
        var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        button_box.visible = true;
        button_box.halign = Gtk.Align.END;
        button_box.margin_top = 6;

        var copy_button = new Gtk.Button.with_label(_("Copy"));
        copy_button.visible = true;
        copy_button.get_style_context().add_class("flat");
        copy_button.clicked.connect(() => {
            var clipboard = Gtk.Clipboard.get_default(this.get_display());
            clipboard.set_text(content, -1);
            copy_button.label = _("Copied!");
            GLib.Timeout.add(1500, () => {
                copy_button.label = _("Copy");
                return false;
            });
        });
        button_box.pack_end(copy_button, false, false, 0);
        inner_box.pack_start(button_box, false, false, 0);

        frame.add(inner_box);
        result_box.pack_start(frame, false, false, 0);

        this.chat_box.pack_start(result_box, false, false, 0);

        // Scroll to bottom
        scroll_to_bottom();
    }

    /**
     * Start showing a loading state with streaming output.
     * Returns a callback that should be called with each line of output.
     */
    public void start_loading(string initial_message) {
        this.is_processing = true;
        this.loading_label.label = initial_message;
        this.loading_revealer.reveal_child = true;
        this.send_button.sensitive = false;
        this.message_entry.sensitive = false;
    }

    /**
     * Update the loading message with streaming content.
     */
    public void update_loading(string message) {
        string display_msg = message.strip();
        if (display_msg.length > 60) {
            display_msg = display_msg.substring(0, 57) + "...";
        }
        if (display_msg.length > 0) {
            this.loading_label.label = display_msg;
        }
    }

    /**
     * Stop the loading state.
     */
    public void stop_loading() {
        this.is_processing = false;
        this.loading_revealer.reveal_child = false;
        this.message_entry.sensitive = true;
        on_entry_changed();
    }
}
