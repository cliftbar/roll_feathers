/// Shared contract for "library of built-ins + user items" features (webhook
/// payloads, and — where it fits — Pixels profiles). This is the part of the
/// unification that genuinely generalizes: the *item shape* and the *repository
/// CRUD contract*. See docs/specs/webhook_payload_editor.md (Framework §8, Issue
/// I) for why the list/editor *screens* stay specialized rather than sharing a
/// generic widget — their bodies (raw-JSON editor vs pixel/gradient forms vs DSL
/// text) and lifecycles diverge too much for a non-leaky shell.
library;

/// An item that lives in a library: either a curated built-in (read-only) or a
/// user-created, editable entry.
abstract interface class EditableLibraryItem {
  String get id;
  String get name;
  String get category;
  bool get isBuiltin;
}

/// The CRUD contract for a library of [EditableLibraryItem]s — built-ins from
/// code, user items from a data store.
abstract interface class LibraryRepository<T extends EditableLibraryItem> {
  List<T> builtins();
  Future<List<T>> loadUserItems();
  Future<void> upsert(T item);
  Future<void> delete(String id);
}
