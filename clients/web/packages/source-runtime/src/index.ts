import type { PluginManifest } from '@hentai-park/source-contract';
import { CAPABILITY_NAMES, validateManifest } from '@hentai-park/source-contract';

export { toPluginError as normalizePluginError } from '@hentai-park/source-contract';
export {operationCapability} from '@hentai-park/source-contract';

function clean(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(clean);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value)
      .filter(([key, item]) => item !== undefined && item !== null && (item !== '' || key === 'value' || key === 'default') && typeof item !== 'function')
      .map(([key, item]) => [key, clean(item)]));
  }
  return value;
}

/** Canonicalizes the shared Park runtime's effective declaration at the Web boundary. */
export function normalizeRuntimeManifest(
  runtimeManifest: Record<string, unknown>,
  declared: Record<string, unknown>,
  available: Record<string, boolean>,
): PluginManifest {
  const capabilities = Object.fromEntries(CAPABILITY_NAMES
    .map(key => [key, (runtimeManifest.capabilities as Record<string, unknown>)?.[key] === true || key==='previewContent'&&declared[key]===true || key!=='liveChat'&&key!=='previewContent'&&available[key] === true])
    .filter(([, supported]) => supported));
  const domains = Array.isArray(runtimeManifest.domains) && runtimeManifest.domains.length
    ? runtimeManifest.domains : [new URL(String(runtimeManifest.homepage)).hostname];
  const manifest = clean({ ...runtimeManifest, domains, capabilities }) as Record<string, unknown>;
  for (const key of ['media', 'imageNetwork', 'imageDecrypt', 'chat', 'searchCommonFilters']) {
    if (manifest[key] && Object.keys(manifest[key] as object).length === 0) delete manifest[key];
  }
  if (manifest.account) {
    const account = manifest.account as Record<string, unknown>;
    if (Array.isArray(account.loginDomains)) {
      account.loginDomains = account.loginDomains.filter(value => !(manifest.domains as string[])
        .some(domain => String(value) === domain || String(value).endsWith('.' + domain)));
    }
    for (const key of ['loginDomains', 'requiredCookies', 'localStorageKeys']) {
      if (Array.isArray(account[key]) && !account[key].length) delete account[key];
    }
  }
  if (manifest.reverseSearchOnly === true && Array.isArray(manifest.feeds) && manifest.feeds.length === 0) delete manifest.feeds;
  const normalizeSettings = (items: unknown) => {
    if (Array.isArray(items)) for (const item of items) {
      if (item && typeof item === 'object' && !('type' in item)) item.type = 'select';
    }
  };
  normalizeSettings(manifest.settings);
  normalizeSettings(manifest.searchFilters);
  if (Array.isArray(manifest.feeds)) for (const feed of manifest.feeds) normalizeSettings(feed.options);
  validateManifest(manifest);
  return manifest as unknown as PluginManifest;
}

/** The single API-parameter to SOURCE_API/Park.invoke mapping used in production. */
export function legacyInvocation(manifest: PluginManifest, method: string, params: unknown): { path: string; args: unknown[] } {
  const value = (params && typeof params === 'object' ? params : {}) as Record<string, unknown>;
  const path = method==='albumChunk'?'subscription.mediaChunk':method === 'subscription' ? 'subscription.posts'
    : method === 'album' ? 'subscription.media'
    : method === 'subscriptionUpdates' ? 'updateSubscriptions.check' : method === 'rankings' ? (value.queryOptions === true ? 'rankingOptions' : 'ranking') : method;
  if (Array.isArray(value.args)) return { path, args: value.args };
  let args: unknown[];
  switch (method) {
    case 'random': args=[]; break;
    case 'resolveContentLink': args=[value.url??params]; break;
    case 'resolveLink': args=[value.id??value.workId??params]; break;
    case 'thumbnails': args=[value.id??value.workId,value.page??1]; break;
    case 'comments':
    case 'interaction':
    case 'related': args=[value.id??value.workId,value.request??value]; break;
    case 'gameResources':
    case 'onlineGame':
    case 'tavernAsset': args=[value.id??value.workId??params]; break;
    case 'resolveGameResource': args=[value.id??value.workId,value.resourceId??value.resource,value.channelId??value.channel]; break;
    case 'liveChat': args=[value.id??value.workId??params]; break;
    case 'liveChatEvent': args=[value.state,value.event]; break;
    case 'subscription.normalize':
    case 'subscription.resolve': args=[value.input??value.target??params]; break;
    case 'subscription.targets': args=[value.request??value]; break;
    case 'subscription.posts': args=[value.target,value.request??value]; break;
    case 'subscription.mediaChunk': args=[value.resource,value.offset]; break;
    case 'updateSubscriptions.normalize': args=[value.dimension,value.input??value.target]; break;
    case 'updateSubscriptions.query': args=[{dimension:value.dimension,target:value.target}]; break;
    case 'updateSubscriptions.check': args=[{dimension:value.dimension,target:value.target},value.request??value]; break;
    case 'albumChunk':args=[value.resource,value.offset];break;
    case 'search': args = [{ ...value, keyword: value.keyword ?? value.q ?? '' }]; break;
    case 'rankings': args=[value.board,value];break;
    case 'feed': args = [value.key ?? manifest.defaultFeed ?? manifest.feeds?.[0]?.key, value]; break;
    case 'searchLink': args=[value.url,value];break;
    case 'searchSuggestions': args = [value.keyword ?? value.q ?? '', value]; break;
    case 'metadataSearch': args=[value.keyword,value];break;
    case 'metadataDetail': args = [value.workId ?? value.id, value]; break;
    case 'metadataMagnets': args = [value.workId ?? value.id]; break;
    case 'detail': args = [value.workId ?? value.id, ...(value.preview === undefined ? [] : [value.preview])]; break;
    case 'chapter':
    case 'videos':
    case 'webVideo':
    case 'voiceResource':
    case 'voiceDirectory':
    case 'textChapter': args = [value.workId ?? value.id, value.chapterId ?? value.nodeId ?? value.directoryId ?? value.episodeId ?? '_', value]; break;
    case 'resolveImage': args = [value.url ?? (params && typeof params==='object' ? {...value,id:value.id??value.workId,episodeId:value.episodeId??value.chapterId} : params)]; break;
    case 'subscriptionUpdates': args = [{ dimension: value.dimension, target: value.target }, value]; break;
    case 'subscription': args = [value.target, value]; break;
    case 'subscription.media':
    case 'album': args = [value.target !== undefined ? { target: value.target } : value.search !== undefined ? { search: value.search } : { feed: value.feed ?? value.key ?? manifest.defaultFeed ?? manifest.feeds?.[0]?.key, options: value.options ?? {}, ...(value.common === undefined ? {} : { common: value.common }) }, value]; break;
    default: args = [params];
  }
  return { path, args };
}
