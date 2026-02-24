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
    [GtkChild] private unowned Gtk.TextView message_text;
    [GtkChild] private unowned Gtk.Button send_button;
    [GtkChild] private unowned Gtk.Revealer loading_revealer;
    [GtkChild] private unowned Gtk.Label loading_label;
    [GtkChild] private unowned Gtk.Box thinking_content_box;

    private bool is_processing = false;
    private Gtk.Box? current_tool_item = null;
    private Gtk.Label? thinking_message_label = null;

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

        // Connect text buffer signals for GtkTextView
        this.message_text.buffer.changed.connect(on_text_changed);

        // Handle Ctrl+Enter to send
        this.message_text.key_press_event.connect(on_text_key_press);

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
            this.message_text.sensitive = false;
            return;
        }

        // Check authentication asynchronously
        this.service.check_authenticated.begin((obj, res) => {
            bool authenticated = this.service.check_authenticated.end(res);
            if (authenticated) {
                this.status_revealer.reveal_child = false;
                this.message_text.sensitive = true;
            } else {
                this.status_label.label = _("Sign in with your Google account to use Gemini AI features.");
                this.status_revealer.reveal_child = true;
                this.login_button.visible = true;
                this.login_button.sensitive = true;
                this.message_text.sensitive = false;
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
        this.message_text.sensitive = false;
    }

    private void on_authentication_completed(bool success, string? error_message) {
        if (success) {
            this.status_revealer.reveal_child = false;
            this.message_text.sensitive = true;
        } else {
            this.status_label.label = _("Login failed: %s").printf(
                error_message ?? _("Unknown error")
            );
            this.login_button.sensitive = true;
        }
    }

    /**
     * Get the text from the message text view.
     */
    private string get_message_text() {
        Gtk.TextIter start, end;
        this.message_text.buffer.get_bounds(out start, out end);
        return this.message_text.buffer.get_text(start, end, false);
    }

    /**
     * Handle text buffer changes.
     */
    private void on_text_changed() {
        string text = get_message_text().strip();
        this.send_button.sensitive = text.length > 0 && !this.is_processing;
    }

    /**
     * Handle key press in text view - Ctrl+Enter sends the message.
     */
    private bool on_text_key_press(Gdk.EventKey event) {
        // Ctrl+Enter sends the message
        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
            (event.keyval == Gdk.Key.Return || event.keyval == Gdk.Key.KP_Enter)) {
            on_send_clicked();
            return true;  // Event handled
        }
        return false;  // Let normal handling continue (Enter adds newline)
    }

    private void on_send_clicked() {
        string message = get_message_text().strip();
        if (message.length == 0 || this.is_processing) {
            return;
        }

        // Clear input and add user message to chat
        this.message_text.buffer.set_text("", 0);
        add_message(message, true);

        // Send to Gemini
        send_message.begin(message);
    }

    private async void send_message(string message) {
        this.is_processing = true;
        this.loading_revealer.reveal_child = true;
        this.loading_label.label = _("Thinking...");
        this.send_button.sensitive = false;
        this.message_text.sensitive = false;

        // Clear any previous tool items
        clear_tool_items();

        try {
            // Use structured streaming - callback receives (type, content, tool_name, input_data)
            string response = yield this.service.chat_streaming(message, (msg_type, content, tool_name, input_data) => {
                handle_stream_message(msg_type, content, tool_name, input_data);
            });
            // Response already filtered - only contains assistant message content
            add_message(response.strip(), false);
        } catch (Error e) {
            add_message(_("Error: %s").printf(e.message), false, true);
        }

        this.is_processing = false;
        this.loading_revealer.reveal_child = false;
        this.current_tool_item = null;
        this.message_text.sensitive = true;
        on_text_changed();
        this.message_text.grab_focus();
    }

    /**
     * Handle structured streaming messages from gemini-cli.
     * Shows tool use in thinking panel with detailed descriptions.
     */
    private void handle_stream_message(string msg_type, string content, string? tool_name, string? tool_input_json) {
        switch (msg_type) {
            case "tool_use":
                // Add a new tool item to the thinking panel
                if (tool_name != null) {
                    string description = get_tool_description(tool_name, tool_input_json);
                    add_tool_item(tool_name, description);
                }
                break;

            case "tool_result":
                // Mark current tool as complete
                bool success = content == "success";
                complete_current_tool(success);
                break;

            case "message":
                // Assistant response streaming - update header and show content snippets
                this.loading_label.label = _("Composing response...");
                append_thinking_content(content);
                break;

            default:
                // Other message types
                break;
        }
    }

    /**
     * Generate a human-readable description for a tool based on its input.
     */
    private string get_tool_description(string tool_name, string? input_json) {
        // Parse the input JSON if provided
        Json.Object? input_data = null;
        if (input_json != null && input_json.length > 0) {
            try {
                var parser = new Json.Parser();
                parser.load_from_data(input_json);
                var root = parser.get_root();
                if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                    input_data = root.get_object();
                }
            } catch (Error e) {
                // Ignore parse errors
            }
        }

        switch (tool_name) {
            case "get_selected_email":
                return _("Reading selected email...");

            case "list_emails":
                if (input_data != null) {
                    string folder = input_data.has_member("folder") ? input_data.get_string_member("folder") : "INBOX";
                    int64 limit = input_data.has_member("limit") ? input_data.get_int_member("limit") : 10;
                    return _("Listing %lld emails from %s...").printf(limit, folder);
                }
                return _("Listing emails...");

            case "search_emails":
                if (input_data != null && input_data.has_member("query")) {
                    string query = input_data.get_string_member("query");
                    if (query.length > 30) {
                        query = query.substring(0, 27) + "...";
                    }
                    return _("Searching: %s").printf(query);
                }
                return _("Searching emails...");

            case "read_email":
                return _("Reading email content...");

            case "select_email":
                return _("Selecting email...");

            default:
                return _("Using %s...").printf(tool_name);
        }
    }

    /**
     * Add a tool item to the thinking panel.
     */
    private void add_tool_item(string tool_name, string description) {
        // Complete any previous tool first
        if (this.current_tool_item != null) {
            complete_current_tool(true);
        }

        var item_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        item_box.visible = true;

        // Spinner for in-progress
        var spinner = new Gtk.Spinner();
        spinner.visible = true;
        spinner.active = true;
        spinner.set_size_request(12, 12);
        item_box.pack_start(spinner, false, false, 0);

        // Tool name (bold)
        var name_label = new Gtk.Label(tool_name);
        name_label.visible = true;
        name_label.xalign = 0;
        var attrs = new Pango.AttrList();
        attrs.insert(Pango.attr_weight_new(Pango.Weight.BOLD));
        attrs.insert(Pango.attr_scale_new(0.9));
        name_label.attributes = attrs;
        item_box.pack_start(name_label, false, false, 0);

        // Description (dimmed)
        var desc_label = new Gtk.Label(description);
        desc_label.visible = true;
        desc_label.xalign = 0;
        desc_label.hexpand = true;
        desc_label.ellipsize = Pango.EllipsizeMode.END;
        desc_label.get_style_context().add_class("dim-label");
        var desc_attrs = new Pango.AttrList();
        desc_attrs.insert(Pango.attr_scale_new(0.9));
        desc_label.attributes = desc_attrs;
        item_box.pack_start(desc_label, true, true, 0);

        this.thinking_content_box.pack_start(item_box, false, false, 0);
        this.current_tool_item = item_box;
    }

    /**
     * Mark the current tool item as complete.
     */
    private void complete_current_tool(bool success) {
        if (this.current_tool_item == null) {
            return;
        }

        // Find and replace the spinner with a status icon
        foreach (var child in this.current_tool_item.get_children()) {
            if (child is Gtk.Spinner) {
                this.current_tool_item.remove(child);

                var icon = new Gtk.Image.from_icon_name(
                    success ? "emblem-ok-symbolic" : "dialog-error-symbolic",
                    Gtk.IconSize.MENU
                );
                icon.visible = true;
                icon.set_size_request(12, 12);
                if (success) {
                    icon.get_style_context().add_class("dim-label");
                }
                this.current_tool_item.pack_start(icon, false, false, 0);
                this.current_tool_item.reorder_child(icon, 0);
                break;
            }
        }

        // Dim the entire row for completed tools
        if (success) {
            this.current_tool_item.get_style_context().add_class("dim-label");
        }

        this.current_tool_item = null;
    }

    /**
     * Clear all tool items from the thinking panel.
     */
    private void clear_tool_items() {
        foreach (var child in this.thinking_content_box.get_children()) {
            this.thinking_content_box.remove(child);
        }
        this.current_tool_item = null;
        this.thinking_message_label = null;
    }

    private void append_thinking_content(string content) {
        string text = content.strip();
        if (text.length == 0) return;

        if (this.thinking_message_label == null) {
            this.thinking_message_label = new Gtk.Label("");
            this.thinking_message_label.visible = true;
            this.thinking_message_label.xalign = 0;
            this.thinking_message_label.wrap = true;
            this.thinking_message_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            this.thinking_message_label.selectable = true;
            this.thinking_message_label.get_style_context().add_class("dim-label");
            this.thinking_content_box.pack_start(this.thinking_message_label, false, false, 0);
            this.thinking_content_box.reorder_child(this.thinking_message_label, 0);
        }

        string current = this.thinking_message_label.label ?? "";
        string merged = current.length > 0 ? "%s
%s".printf(current, text) : text;
        if (merged.length > 1000) {
            merged = merged.substring(merged.length - 1000);
        }
        this.thinking_message_label.label = merged;
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
        this.message_text.sensitive = false;
        clear_tool_items();
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
        this.message_text.sensitive = true;
        on_text_changed();
    }
}
