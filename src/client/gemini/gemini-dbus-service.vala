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

    // Workspace directory where attachments are copied for gemini-cli access
    // This must be within the geary-gemini project directory for gemini-cli to read
    private const string ATTACHMENT_WORKSPACE_DIR = "/home/andrewhodges/Projects/geary-gemini/.gemini-attachments";

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

        // Add attachments metadata
        builder.set_member_name("attachments");
        builder.begin_array();

        if (email.fields.fulfills(Geary.Email.REQUIRED_FOR_MESSAGE)) {
            int index = 0;
            foreach (Geary.Attachment attachment in email.attachments) {
                builder.begin_object();

                builder.set_member_name("index");
                builder.add_int_value(index);

                builder.set_member_name("filename");
                builder.add_string_value(attachment.content_filename ?? "unnamed");

                builder.set_member_name("content_type");
                builder.add_string_value(attachment.content_type.get_mime_type());

                builder.set_member_name("filesize");
                builder.add_int_value(attachment.filesize);

                builder.set_member_name("has_file");
                builder.add_boolean_value(attachment.file != null);

                builder.end_object();
                index++;
            }
        }

        builder.end_array();

        builder.end_object();

        var generator = new Json.Generator();
        generator.set_root(builder.get_root());
        return generator.to_data(null);
    }

    /**
     * Get the content of a specific attachment from an email.
     *
     * @param email_id The ID of the email containing the attachment
     * @param attachment_index The index of the attachment (0-based)
     * @param max_size Maximum size in bytes to return (0 for default 10MB limit)
     *
     * Returns a JSON object with:
     * - filename: The attachment filename
     * - content_type: MIME type
     * - filesize: Size in bytes
     * - encoding: "text" or "base64"
     * - content: The actual content (text or base64-encoded)
     * - truncated: boolean indicating if content was truncated
     * - error: Error message if failed
     */
    public string get_attachment_content(string email_id, int attachment_index, int64 max_size) throws DBusError, IOError {
        var builder = new Json.Builder();
        builder.begin_object();

        // Default max size: 10MB
        if (max_size <= 0) {
            max_size = 10 * 1024 * 1024;
        }

        // Cap at 50MB absolute maximum
        if (max_size > 50 * 1024 * 1024) {
            max_size = 50 * 1024 * 1024;
        }

        if (this._main_window == null) {
            builder.set_member_name("error");
            builder.add_string_value("Main window not available");
            builder.end_object();
            var generator = new Json.Generator();
            generator.set_root(builder.get_root());
            return generator.to_data(null);
        }

        var conversations = this._main_window.conversations;
        if (conversations == null) {
            builder.set_member_name("error");
            builder.add_string_value("No conversations available");
            builder.end_object();
            var generator = new Json.Generator();
            generator.set_root(builder.get_root());
            return generator.to_data(null);
        }

        // Find the email
        Geary.Email? target_email = null;
        foreach (var conversation in conversations.read_only_view) {
            foreach (var email in conversation.get_emails(Geary.App.Conversation.Ordering.RECV_DATE_ASCENDING)) {
                if (email.id.to_string() == email_id) {
                    target_email = email;
                    break;
                }
            }
            if (target_email != null) break;
        }

        if (target_email == null) {
            builder.set_member_name("error");
            builder.add_string_value("Email not found: " + email_id);
            builder.end_object();
            var generator = new Json.Generator();
            generator.set_root(builder.get_root());
            return generator.to_data(null);
        }

        // Check if email has attachments loaded
        if (!target_email.fields.fulfills(Geary.Email.REQUIRED_FOR_MESSAGE)) {
            builder.set_member_name("error");
            builder.add_string_value("Email body not loaded - attachments unavailable");
            builder.end_object();
            var generator = new Json.Generator();
            generator.set_root(builder.get_root());
            return generator.to_data(null);
        }

        // Validate attachment index
        if (attachment_index < 0 || attachment_index >= target_email.attachments.size) {
            builder.set_member_name("error");
            builder.add_string_value("Invalid attachment index: " + attachment_index.to_string() +
                " (email has " + target_email.attachments.size.to_string() + " attachments)");
            builder.end_object();
            var generator = new Json.Generator();
            generator.set_root(builder.get_root());
            return generator.to_data(null);
        }

        Geary.Attachment attachment = target_email.attachments.get(attachment_index);

        // Add metadata
        builder.set_member_name("filename");
        builder.add_string_value(attachment.content_filename ?? "unnamed");

        builder.set_member_name("content_type");
        builder.add_string_value(attachment.content_type.get_mime_type());

        builder.set_member_name("filesize");
        builder.add_int_value(attachment.filesize);

        // Check if file exists on disk
        if (attachment.file == null) {
            builder.set_member_name("error");
            builder.add_string_value("Attachment not saved to disk");
            builder.end_object();
            var generator = new Json.Generator();
            generator.set_root(builder.get_root());
            return generator.to_data(null);
        }

        // Determine MIME type
        string mime_type = attachment.content_type.get_mime_type();
        bool is_text = is_text_content_type(mime_type);
        bool is_supported = is_gemini_supported_type(mime_type);

        // Add supported flag to response
        builder.set_member_name("supported");
        builder.add_boolean_value(is_supported);

        if (!is_supported) {
            builder.set_member_name("error");
            builder.add_string_value("File type not supported for AI analysis: " + mime_type +
                ". Supported types: images (PNG, JPEG, GIF, WebP), PDFs, and text files.");
            builder.end_object();
            var generator = new Json.Generator();
            generator.set_root(builder.get_root());
            return generator.to_data(null);
        }

        // For supported binary files (images, PDFs), copy to workspace directory
        // so gemini-cli can access them (it has workspace path restrictions)
        string accessible_path;
        if (!is_text) {
            try {
                // Ensure workspace directory exists
                var workspace_dir = File.new_for_path(ATTACHMENT_WORKSPACE_DIR);
                if (!workspace_dir.query_exists()) {
                    workspace_dir.make_directory_with_parents();
                }

                // Generate safe filename: emailid_index_filename
                string safe_email_id = email_id.replace("/", "_").replace(":", "_");
                string original_name = attachment.content_filename ?? "attachment";
                string safe_filename = "%s_%d_%s".printf(safe_email_id, attachment_index, original_name);
                var dest_file = workspace_dir.get_child(safe_filename);

                // Copy file if not already there or if source is newer
                if (!dest_file.query_exists()) {
                    attachment.file.copy(dest_file, FileCopyFlags.OVERWRITE);
                }

                accessible_path = dest_file.get_path();
            } catch (Error e) {
                builder.set_member_name("error");
                builder.add_string_value("Failed to copy attachment to accessible location: " + e.message);
                builder.end_object();
                var generator = new Json.Generator();
                generator.set_root(builder.get_root());
                return generator.to_data(null);
            }
        } else {
            // Text files - use original path (content included inline anyway)
            accessible_path = attachment.file.get_path();
        }

        // Return the accessible file path
        builder.set_member_name("file_path");
        builder.add_string_value(accessible_path);

        // For text files, also include the content inline for convenience
        if (is_text) {
            try {
                var file_buffer = new Geary.Memory.FileBuffer(attachment.file, true);
                int64 actual_size = (int64) file_buffer.size;
                bool truncated = actual_size > max_size;

                builder.set_member_name("truncated");
                builder.add_boolean_value(truncated);

                builder.set_member_name("encoding");
                builder.add_string_value("text");

                string content = file_buffer.get_valid_utf8();
                if (truncated && content.length > (long) max_size) {
                    content = content.substring(0, (long) max_size);
                }
                builder.set_member_name("content");
                builder.add_string_value(content);
            } catch (Error e) {
                // File path is still available, just no inline content
                builder.set_member_name("content_error");
                builder.add_string_value("Failed to read content: " + e.message);
            }
        } else {
            // For binary files (images, PDFs), the file has been copied to workspace
            builder.set_member_name("encoding");
            builder.add_string_value("binary");
            builder.set_member_name("note");
            builder.add_string_value("File copied to workspace - Gemini can read this file directly at the file_path");
        }

        builder.end_object();

        var generator = new Json.Generator();
        generator.set_root(builder.get_root());
        return generator.to_data(null);
    }

    /**
     * Check if a MIME type is supported by Gemini for multimodal analysis.
     * Supported types: images (PNG, JPEG, GIF, WebP), PDFs, and text-based files.
     */
    private bool is_gemini_supported_type(string mime_type) {
        // Images
        if (mime_type == "image/png") return true;
        if (mime_type == "image/jpeg") return true;
        if (mime_type == "image/jpg") return true;
        if (mime_type == "image/gif") return true;
        if (mime_type == "image/webp") return true;

        // Documents
        if (mime_type == "application/pdf") return true;

        // Text types are always supported
        if (is_text_content_type(mime_type)) return true;

        return false;
    }

    /**
     * Check if a MIME type represents text content.
     */
    private bool is_text_content_type(string mime_type) {
        // Text types
        if (mime_type.has_prefix("text/")) {
            return true;
        }

        // Common text-based application types
        string[] text_app_types = {
            "application/json",
            "application/xml",
            "application/javascript",
            "application/x-javascript",
            "application/ecmascript",
            "application/x-sh",
            "application/x-python",
            "application/sql",
            "application/xhtml+xml",
            "application/atom+xml",
            "application/rss+xml",
            "application/soap+xml",
            "application/mathml+xml",
            "application/x-yaml",
            "application/yaml",
            "application/toml",
            "application/x-httpd-php",
            "application/x-perl",
            "application/x-ruby"
        };

        foreach (string text_type in text_app_types) {
            if (mime_type == text_type) {
                return true;
            }
        }

        // Check for +xml or +json suffixes
        if (mime_type.has_suffix("+xml") || mime_type.has_suffix("+json")) {
            return true;
        }

        return false;
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
