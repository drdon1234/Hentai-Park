// Application routes may contain dots and encoded file names. Only the asset
// namespace is served from disk; an arbitrary extension never determines routing.
export function isApplicationRoute(pathname) {
  return /^\/(?:discover|search|reverse-search|rankings|sources|sites|history|library|downloads|subscriptions|settings|channels|tavern|licenses|logs)(?:\/|$)/.test(pathname)
    || /^\/(?:domain|source|work|read|watch|short-videos|voice|live|album|channel|post|profile|game|offline)\//.test(pathname)
    || pathname === '/';
}
