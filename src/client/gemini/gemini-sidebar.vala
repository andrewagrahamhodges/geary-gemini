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
    [GtkChild] private unowned Gtk.Label account_label;
    [GtkChild] private unowned Gtk.MenuButton account_menu_button;
    [GtkChild] private unowned Gtk.ScrolledWindow chat_scrolled;
    [GtkChild] private unowned Gtk.Box chat_box;
    [GtkChild] private unowned Gtk.Label welcome_label;
    [GtkChild] private unowned Gtk.TextView message_text;
    [GtkChild] private unowned Gtk.Button send_button;
    [GtkChild] private unowned Gtk.Revealer loading_revealer;
    [GtkChild] private unowned Gtk.Label loading_label;

    private bool is_processing = false;

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

        // Set up account selector popover
        setup_account_popover();

        // Load active account and check initial state
        this.service.load_active_account();
        update_account_label();
        check_gemini_status();
    }

    /**
     * Set up the account selector popover on the gear button.
     */
    private void setup_account_popover() {
        var popover = new Gtk.Popover(this.account_menu_button);
        popover.set_position(Gtk.PositionType.BOTTOM);
        this.account_menu_button.set_popover(popover);

        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        box.visible = true;
        box.margin = 6;
        popover.add(box);

        populate_account_list(box);

        // Re-populate when popover is shown
        popover.map.connect(() => {
            foreach (var child in box.get_children()) {
                box.remove(child);
            }
            populate_account_list(box);
        });
    }

    /**
     * Populate the account list in the popover.
     */
    private void populate_account_list(Gtk.Box box) {
        var app = GLib.Application.get_default() as Application.Client;
        if (app == null || app.controller == null) {
            var label = new Gtk.Label(_("No accounts available"));
            label.visible = true;
            label.margin = 12;
            label.get_style_context().add_class("dim-label");
            box.pack_start(label, false, false, 0);
            return;
        }

        string? active = this.service.active_account;
        bool found_google = false;

        foreach (var context in app.controller.get_account_contexts()) {
            var info = context.account.information;
            if (info.service_provider != Geary.ServiceProvider.GMAIL) {
                continue;
            }

            found_google = true;
            string email = info.primary_mailbox.address;
            string display = info.display_name;

            var item_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            item_box.visible = true;
            item_box.margin = 4;

            // Checkmark for active account
            var check_icon = new Gtk.Image.from_icon_name(
                "emblem-ok-symbolic", Gtk.IconSize.MENU
            );
            check_icon.visible = (active != null && active == email);
            check_icon.set_size_request(16, 16);
            item_box.pack_start(check_icon, false, false, 0);

            var label_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            label_box.visible = true;

            var name_label = new Gtk.Label(display);
            name_label.visible = true;
            name_label.xalign = 0;
            var attrs = new Pango.AttrList();
            attrs.insert(Pango.attr_weight_new(Pango.Weight.BOLD));
            name_label.attributes = attrs;
            label_box.pack_start(name_label, false, false, 0);

            var email_label = new Gtk.Label(email);
            email_label.visible = true;
            email_label.xalign = 0;
            email_label.get_style_context().add_class("dim-label");
            var email_attrs = new Pango.AttrList();
            email_attrs.insert(Pango.attr_scale_new(0.9));
            email_label.attributes = email_attrs;
            label_box.pack_start(email_label, false, false, 0);

            item_box.pack_start(label_box, true, true, 0);

            var button = new Gtk.Button();
            button.visible = true;
            button.get_style_context().add_class("flat");
            button.relief = Gtk.ReliefStyle.NONE;
            button.add(item_box);

            // Capture email for the closure
            string account_email = email;
            button.clicked.connect(() => {
                on_account_selected(account_email);
                this.account_menu_button.popover.popdown();
            });

            box.pack_start(button, false, false, 0);
        }

        if (!found_google) {
            var label = new Gtk.Label(_("No Google accounts configured in Geary"));
            label.visible = true;
            label.margin = 12;
            label.wrap = true;
            label.max_width_chars = 30;
            label.get_style_context().add_class("dim-label");
            box.pack_start(label, false, false, 0);
        }
    }

    /**
     * Handle account selection from the popover.
     */
    private void on_account_selected(string email) {
        try {
            this.service.switch_active_account(email);
            this.service.active_account_changed(email);
        } catch (Error e) {
            warning("Failed to set active account: %s", e.message);
        }

        update_account_label();

        // Show checking status while we verify auth
        this.status_label.label = _("Checking authentication...");
        this.status_revealer.reveal_child = true;
        this.login_button.visible = false;
        this.message_text.sensitive = false;

        // Check auth status for this account
        this.service.check_authenticated.begin((obj, res) => {
            if (!this.get_mapped()) return;
            bool authenticated = this.service.check_authenticated.end(res);
            if (authenticated) {
                this.status_revealer.reveal_child = false;
                this.login_button.visible = false;
                this.message_text.sensitive = true;
            } else {
                // Show login prompt — user can click to authenticate
                this.status_label.label = _("Sign in to use Gemini with %s").printf(email);
                this.status_revealer.reveal_child = true;
                this.login_button.visible = true;
                this.login_button.sensitive = true;
            }
        });
    }

    /**
     * Update the account subtitle label.
     */
    private void update_account_label() {
        string? active = this.service.active_account;
        if (active != null && active.length > 0) {
            this.account_label.label = active;
            this.account_label.visible = true;
        } else {
            this.account_label.visible = false;
        }
    }

    /**
     * Check if Gemini CLI is installed and authenticated, update UI accordingly.
     */
    private void check_gemini_status() {
        if (!this.service.is_installed()) {
            this.status_label.label = _("Gemini CLI not found. Please reinstall geary-gemini.");
            this.status_revealer.reveal_child = true;
            this.login_button.visible = false;
            this.message_text.sensitive = false;
            return;
        }

        // Check authentication asynchronously
        this.service.check_authenticated.begin((obj, res) => {
            if (!this.get_mapped()) return;
            bool authenticated = this.service.check_authenticated.end(res);
            if (authenticated) {
                this.status_revealer.reveal_child = false;
                this.message_text.sensitive = true;
            } else {
                if (this.service.active_account != null) {
                    this.status_label.label = _("Not authenticated. Select your account using the gear icon to sign in.");
                } else {
                    this.status_label.label = _("Select a Google account using the gear icon to get started.");
                }
                this.status_revealer.reveal_child = true;
                this.login_button.visible = false;
                this.message_text.sensitive = false;
            }
        });
    }

    private void on_login_clicked() {
        this.login_button.sensitive = false;
        this.status_label.label = _("Opening browser for Google sign-in...");

        this.service.authenticate.begin((obj, res) => {
            if (!this.get_mapped()) return;
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
        if (!this.get_mapped()) return;
        this.status_label.label = _("Please sign in with Google to continue.");
        this.status_revealer.reveal_child = true;
        this.login_button.visible = true;
        this.login_button.sensitive = true;
        this.message_text.sensitive = false;
    }

    private void on_authentication_completed(bool success, string? error_message) {
        if (!this.get_mapped()) return;
        if (success) {
            this.status_revealer.reveal_child = false;
            this.login_button.visible = false;
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
     * Handle key press in text view.
     * Enter sends, Ctrl+Enter inserts a newline.
     */
    private bool on_text_key_press(Gdk.EventKey event) {
        if (event.keyval == Gdk.Key.Return || event.keyval == Gdk.Key.KP_Enter) {
            bool ctrl_pressed = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
            if (ctrl_pressed) {
                return false; // default behavior: insert newline
            }

            on_send_clicked();
            return true; // consume Enter-to-send
        }

        return false;
    }

    private void on_send_clicked() {
        string message = get_message_text().strip();
        if (message.length == 0 || this.is_processing) {
            return;
        }

        // Clear input
        this.message_text.buffer.set_text("", 0);

        // Handle /login command — redirect to gear icon
        if (message.down() == "/login") {
            add_message(message, true);
            add_message(_("Use the gear icon in the header to select a Google account."), false);
            return;
        }

        // Add user message to chat and send to Gemini
        add_message(message, true);
        send_message.begin(message);
    }

    private async void send_message(string message) {
        this.is_processing = true;
        this.loading_revealer.reveal_child = true;
        this.loading_label.label = _("Thinking...");
        this.send_button.sensitive = false;
        this.message_text.sensitive = false;

        try {
            string response = yield this.service.chat_streaming(message, (msg_type, content, tool_name, input_data) => {
                if (!this.get_mapped()) return;
                update_loading_status(msg_type, content, tool_name);
            });
            if (!this.get_mapped()) return;
            add_message(response.strip(), false);
        } catch (Error e) {
            if (!this.get_mapped()) return;
            add_message(_("Error: %s").printf(e.message), false, true);
        }

        this.is_processing = false;
        this.loading_revealer.reveal_child = false;
        this.message_text.sensitive = true;
        on_text_changed();
        this.message_text.grab_focus();
    }

    /**
     * Update the single-line loading status from streaming messages.
     * Shows tool activity and response snippets inline — no expanding panel.
     */
    private void update_loading_status(string msg_type, string content, string? tool_name) {
        switch (msg_type) {
            case "tool_use":
                if (tool_name != null) {
                    this.loading_label.label = _("Using %s...").printf(tool_name);
                }
                break;

            case "message":
                string snippet = content.strip().replace("\n", " ");
                if (snippet.length > 0) {
                    this.loading_label.label = snippet;
                }
                break;

            default:
                break;
        }
    }

    /**
     * Convert markdown text to Pango markup for rendering in GTK labels.
     * Supports: **bold**, *italic*, `code`, ## headers, - lists
     */
    internal string markdown_to_pango(string markdown) {
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

        // Italic: *text* or _text_ -> <i>text</i>
        // Bold is already replaced, so single * pairs are safe to match
        try {
            var italic_regex = new Regex("\\*([^*]+)\\*");
            result = italic_regex.replace(result, -1, 0, "<i>\\1</i>");
        } catch (RegexError e) {
            // Ignore regex errors
        }
        try {
            var italic_underscore_regex = new Regex("(?<![\\w])_([^_]+)_(?![\\w])");
            result = italic_underscore_regex.replace(result, -1, 0, "<i>\\1</i>");
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
            if (!this.get_mapped()) return false;
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
     */
    public void start_loading(string initial_message) {
        this.is_processing = true;
        this.loading_label.label = initial_message;
        this.loading_revealer.reveal_child = true;
        this.send_button.sensitive = false;
        this.message_text.sensitive = false;
    }

    /**
     * Update the loading message with streaming content.
     */
    public void update_loading(string message) {
        string display_msg = message.strip().replace("\n", " ");
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
