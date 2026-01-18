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
        this.send_button.sensitive = false;
        this.message_entry.sensitive = false;

        try {
            string response = yield this.service.chat(message);
            add_message(response.strip(), false);
        } catch (Error e) {
            add_message(_("Error: %s").printf(e.message), false, true);
        }

        this.is_processing = false;
        this.loading_revealer.reveal_child = false;
        this.message_entry.sensitive = true;
        on_entry_changed();
        this.message_entry.grab_focus();
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

        // Message content
        var content_label = new Gtk.Label(text);
        content_label.visible = true;
        content_label.wrap = true;
        content_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        content_label.xalign = 0;
        content_label.selectable = true;

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
}
