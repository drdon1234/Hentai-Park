/// Sort keys exposed by the collection screens.
///
/// The list intentionally stays small: status filters answer "what needs
/// attention", while sorting answers "how should the remaining works be
/// ordered".
const supportedLibrarySorts = <String>{'added', 'read', 'updated', 'title'};

bool librarySortAscendingByDefault(String key) => key == 'title';
