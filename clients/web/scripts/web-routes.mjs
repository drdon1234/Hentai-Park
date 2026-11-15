// Application routes may contain dots and encoded file names. Only the asset
// namespace is served from disk; an arbitrary extension never determines routing.
export function isApplicationRoute(pathname) {
  return /^\/(?:discover|search|rankings|sources|sites|history|library|downloads|subscriptions|settings|channels|tavern)(?:\/|$)/.test(pathname)
    || /^\/(?:domain|source|work|read|watch|album|channel|post|game|offline)\//.test(pathname)
    || pathname === '/';
}
