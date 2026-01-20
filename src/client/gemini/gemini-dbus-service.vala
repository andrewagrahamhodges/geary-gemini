/*
 * Copyright 2025 Andrew Hodges
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * D-Bus service that exposes email operations for MCP tools.
 *
 * This allows gemini-cli to access and interact with emails in Geary
 * through the Model Context Protocol (MCP).
 */
[DBus (name = "org.gnome.Geary.EmailTools")]
public class Gemini.DBusService : GLib.Object {

    public const string BUS_NAME = "org.gnome.Geary.EmailTools";
    public const string OBJECT_PATH = "/org/gnome/Geary/EmailTools";

    // Store main window reference (not exposed via D-Bus)
    private Application.MainWindow? _main_window = null;
    private uint bus_id = 0;

    public DBusService() {
    }

    /**
     * Set the main window reference for accessing emails.
     * This is internal and not exposed via D-Bus.
     */
    [DBus (visible = false)]
    public void set_main_window(Application.MainWindow window) {
        this._main_window = window;
    }

    /**
     * Register this service on the session bus.
     */
    [DBus (visible = false)]
    public void register() {
        this.bus_id = Bus.own_name(
            BusType.SESSION,
            BUS_NAME,
            BusNameOwnerFlags.NONE,
            on_bus_acquired,
            on_name_acquired,
            on_name_lost
        );
    }

    /**
     * Unregister this service from the session bus.
     */
    [DBus (visible = false)]
    public void unregister() {
        if (this.bus_id != 0) {
            Bus.unown_name(this.bus_id);
            this.bus_id = 0;
        }
    }

    private void on_bus_acquired(DBusConnection connection, string name) {
        try {
            connection.register_object(OBJECT_PATH, this);
            debug("D-Bus service registered: %s at %s", name, OBJECT_PATH);
        } catch (IOError e) {
            warning("Failed to register D-Bus object: %s", e.message);
        }
    }

    private void on_name_acquired(DBusConnection connection, string name) {
        debug("D-Bus name acquired: %s", name);
    }

    private void on_name_lost(DBusConnection connection, string name) {
        debug("D-Bus name lost: %s", name);
    }

    /**
     * List emails in the current folder.
     *
     * Returns a JSON array of email objects with: id, subject, from, date, preview
     */
    public string list_emails(int limit) throws DBusError, IOError {
        if (this._main_window == null) {
            return "[]";
        }

        var builder = new Json.Builder();
        builder.begin_array();

        var conversations = this._main_window.conversations;
        if (conversations != null) {
            int count = 0;
            foreach (var conversation in conversations.read_only_view) {
                if (count >= limit) break;

                // Get the latest email in the conversation
                Geary.Email? email = conversation.get_latest_recv_email(
                    Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER
                );

                if (email != null) {
                    builder.begin_object();
                    builder.set_member_name("id");
                    builder.add_string_value(email.id.to_string());
                    builder.set_member_name("subject");
                    builder.add_string_value(email.subject != null ? email.subject.to_string() : "");
                    builder.set_member_name("from");
                    builder.add_string_value(email.from != null ? email.from.to_string() : "");
                    builder.set_member_name("date");
                    builder.add_string_value(email.date != null ? email.date.to_string() : "");
                    builder.set_member_name("preview");
                    builder.add_string_value(email.get_preview_as_string() ?? "");
                    builder.end_object();
                    count++;
                }
            }
        }

        builder.end_array();

        var generator = new Json.Generator();
        generator.set_root(builder.get_root());
        return generator.to_data(null);
    }

    /**
     * Get the currently selected email's full content.
     *
     * Returns a JSON object with: id, subject, from, to, cc, date, body
     * Returns empty object {} if no email is selected.
     */
    public string get_selected_email() throws DBusError, IOError {
        if (this._main_window == null) {
            return "{}";
        }

        var viewer = this._main_window.conversation_viewer;
        if (viewer == null) {
            return "{}";
        }

        var list = viewer.current_list;
        if (list == null) {
            return "{}";
        }

        // Get the email that would be replied to (last expanded or selected)
        var email_view = list.get_reply_target();
        if (email_view == null) {
            return "{}";
        }

        return email_to_json(email_view.email);
    }

    /**
     * Read a specific email by its ID.
     *
     * Returns a JSON object with: id, subject, from, to, cc, date, body
     * Returns empty object {} if email not found.
     */
    public string read_email(string email_id) throws DBusError, IOError {
        if (this._main_window == null) {
            return "{}";
        }

        var conversations = this._main_window.conversations;
        if (conversations == null) {
            return "{}";
        }

        // Search through conversations to find the email
        foreach (var conversation in conversations.read_only_view) {
            foreach (var email in conversation.get_emails(Geary.App.Conversation.Ordering.RECV_DATE_ASCENDING)) {
                if (email.id.to_string() == email_id) {
                    return email_to_json(email);
                }
            }
        }

        return "{}";
    }

    /**
     * Search emails by query string.
     *
     * Query examples: "from:bob", "subject:invoice", "hello world"
     * Returns a JSON array of matching email objects.
     */
    public string search_emails(string query) throws DBusError, IOError {
        // For now, do a simple local search through loaded conversations
        // A full search would require using SearchFolder which is async
        if (this._main_window == null) {
            return "[]";
        }

        var builder = new Json.Builder();
        builder.begin_array();

        var conversations = this._main_window.conversations;
        if (conversations != null) {
            string query_lower = query.down();

            foreach (var conversation in conversations.read_only_view) {
                Geary.Email? email = conversation.get_latest_recv_email(
                    Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER
                );

                if (email != null && email_matches_query(email, query_lower)) {
                    builder.begin_object();
                    builder.set_member_name("id");
                    builder.add_string_value(email.id.to_string());
                    builder.set_member_name("subject");
                    builder.add_string_value(email.subject != null ? email.subject.to_string() : "");
                    builder.set_member_name("from");
                    builder.add_string_value(email.from != null ? email.from.to_string() : "");
                    builder.set_member_name("date");
                    builder.add_string_value(email.date != null ? email.date.to_string() : "");
                    builder.set_member_name("preview");
                    builder.add_string_value(email.get_preview_as_string() ?? "");
                    builder.end_object();
                }
            }
        }

        builder.end_array();

        var generator = new Json.Generator();
        generator.set_root(builder.get_root());
        return generator.to_data(null);
    }

    /**
     * Select an email in the UI by its ID.
     *
     * Returns true if the email was found and selected, false otherwise.
     */
    public bool select_email(string email_id) throws DBusError, IOError {
        if (this._main_window == null) {
            return false;
        }

        var conversations = this._main_window.conversations;
        if (conversations == null) {
            return false;
        }

        // Find the conversation containing this email
        foreach (var conversation in conversations.read_only_view) {
            foreach (var email in conversation.get_emails(Geary.App.Conversation.Ordering.RECV_DATE_ASCENDING)) {
                if (email.id.to_string() == email_id) {
                    // Select this conversation
                    var to_select = new Gee.ArrayList<Geary.App.Conversation>();
                    to_select.add(conversation);
                    this._main_window.conversation_list_view.select_conversations(to_select);
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * Convert an email to JSON format.
     */
    private string email_to_json(Geary.Email email) {
        var builder = new Json.Builder();
        builder.begin_object();

        builder.set_member_name("id");
        builder.add_string_value(email.id.to_string());

        builder.set_member_name("subject");
        builder.add_string_value(email.subject != null ? email.subject.to_string() : "");

        builder.set_member_name("from");
        builder.add_string_value(email.from != null ? email.from.to_string() : "");

        builder.set_member_name("to");
        builder.add_string_value(email.to != null ? email.to.to_string() : "");

        builder.set_member_name("cc");
        builder.add_string_value(email.cc != null ? email.cc.to_string() : "");

        builder.set_member_name("date");
        builder.add_string_value(email.date != null ? email.date.to_string() : "");

        // Try to get the full body
        string? body = null;
        try {
            if (email.fields.fulfills(Geary.Email.REQUIRED_FOR_MESSAGE)) {
                var message = email.get_message();
                body = message.get_searchable_body(true);
            }
        } catch (Error e) {
            debug("Failed to get email body: %s", e.message);
        }

        // Fallback to preview
        if (body == null || body.strip().length == 0) {
            body = email.get_preview_as_string() ?? "";
        }

        builder.set_member_name("body");
        builder.add_string_value(body);

        builder.end_object();

        var generator = new Json.Generator();
        generator.set_root(builder.get_root());
        return generator.to_data(null);
    }

    /**
     * Check if an email matches a simple query.
     */
    private bool email_matches_query(Geary.Email email, string query_lower) {
        // Handle field-specific queries
        if (query_lower.has_prefix("from:")) {
            string value = query_lower.substring(5).strip();
            string from = email.from != null ? email.from.to_string().down() : "";
            return from.contains(value);
        }

        if (query_lower.has_prefix("to:")) {
            string value = query_lower.substring(3).strip();
            string to = email.to != null ? email.to.to_string().down() : "";
            return to.contains(value);
        }

        if (query_lower.has_prefix("subject:")) {
            string value = query_lower.substring(8).strip();
            string subject = email.subject != null ? email.subject.to_string().down() : "";
            return subject.contains(value);
        }

        // General search - check subject, from, and preview
        string subject = email.subject != null ? email.subject.to_string().down() : "";
        string from = email.from != null ? email.from.to_string().down() : "";
        string preview = email.get_preview_as_string() ?? "";
        preview = preview.down();

        return subject.contains(query_lower) ||
               from.contains(query_lower) ||
               preview.contains(query_lower);
    }
}
