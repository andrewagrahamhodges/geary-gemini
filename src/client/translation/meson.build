translation_vala_sources = files(
    "translation-service.vala",
)

translation_lib = static_library(
    "geary-translation",
    sources: translation_vala_sources,
    dependencies: [
        glib_dep,
        gobject_dep,
        gio_dep,
        gee_dep,
    ],
    vala_args: [
        "--vapidir", join_paths(source_root, "bindings/vapi"),
    ],
)

translation_dep = declare_dependency(
    link_with: [translation_lib],
    include_directories: include_directories("."),
)
