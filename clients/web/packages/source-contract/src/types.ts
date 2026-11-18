import type { sourceContract } from './public-contract.js';
export type PluginType = (typeof sourceContract.types)[number];
export type PluginCategory = (typeof sourceContract.categories)[number];
export type BrowseLayout = 'list' | 'grid';
export type NetworkMode = 'auto' | 'browser' | 'native';
export type MediaMode = 'browser' | 'native';
export type CapabilityName =
  | 'feed'
  | 'search'
  | 'searchSuggestions'
  | 'searchLink'
  | 'detail'
  | 'chapter'
  | 'resolveImage'
  | 'thumbnails'
  | 'videos'
  | 'webVideo'
  | 'reverseSearch'
  | 'reverseSearchMore'
  | 'subscription'
  | 'album'
  | 'subscription.media'
  | 'updateSubscriptions'
  | 'subscriptionUpdates'
  | 'rankings'
  | 'metadataSearch'
  | 'metadataDetail'
  | 'metadataMagnets'
  | 'comments'
  | 'interaction'
  | 'related'
  | 'resolveLink'
  | 'textChapter'
  | 'onlineGame'
  | 'gameResources'
  | 'resolveGameResource'
  | 'voiceDirectory'
  | 'voiceResource'
  | 'liveChat'
  | 'tavernAsset'
  | 'random'
  | 'resolveContentLink'
  | 'previewContent';

export type PluginCapability =
  | { kind: 'random'; method: 'random' }
  | { kind: 'resolveContentLink'; method: 'resolveContentLink' }
  | { kind: 'previewContent'; method: 'previewContent' }
  | { kind: 'feed'; method: 'feed' }
  | { kind: 'search'; method: 'search' }
  | { kind: 'searchSuggestions'; method: 'searchSuggestions' }
  | { kind: 'detail'; method: 'detail' }
  | { kind: 'chapter'; method: 'chapter' }
  | { kind: 'resolveImage'; method: 'resolveImage' }
  | { kind: 'thumbnails'; method: 'thumbnails' }
  | { kind: 'videos'; method: 'videos'; playback: 'native'; requires: 'media' }
  | { kind: 'webVideo'; method: 'webVideo'; playback: 'webview' }
  | { kind: 'reverseSearch'; method: 'reverseSearch'; result: 'image' }
  | { kind: 'reverseSearchMore'; method: 'reverseSearchMore'; requires: 'reverseSearch' }
  | { kind: 'subscription'; method: 'subscription'; mode: 'channel' }
  | { kind: 'album'; method: 'subscription.media'; mode: 'public-album' }
  | { kind: 'subscription.media'; method: 'subscription.media'; mode: 'album' }
  | { kind: 'updateSubscriptions'; method: 'updateSubscriptions' }
  | { kind: 'subscriptionUpdates'; method: 'subscriptionUpdates' }
  | { kind: 'rankings'; method: 'rankings' }
  | { kind: 'metadataSearch'; method: 'metadataSearch'; metadataOnly: true }
  | { kind: 'metadataDetail'; method: 'metadataDetail'; metadataOnly: true }
  | { kind: 'metadataMagnets'; method: 'metadataMagnets'; metadataOnly: true }
  | { kind: 'comments'; method: 'comments' }
  | { kind: 'interaction'; method: 'interaction' }
  | { kind: 'related'; method: 'related' }
  | { kind: 'resolveLink'; method: 'resolveLink' }
  | { kind: 'textChapter'; method: 'textChapter' }
  | { kind: 'onlineGame'; method: 'onlineGame' }
  | { kind: 'gameResources'; method: 'gameResources' }
  | { kind: 'resolveGameResource'; method: 'resolveGameResource' }
  | { kind: 'voiceDirectory'; method: 'voiceDirectory'; requires: 'voiceResource' }
  | { kind: 'voiceResource'; method: 'voiceResource' }
  | { kind: 'liveChat'; method: 'liveChat'; requires: 'chat' }
  | { kind: 'tavernAsset'; method: 'tavernAsset' };

export type CapabilitySet = Partial<Record<CapabilityName, boolean>>;
export interface PluginSetting {
  key: string;
  label: string;
  description?: string;
  type: 'select' | 'multi' | 'number' | 'text' | 'password' | 'switch';
  default?: string | number | boolean | string[];
  values?: Array<{ value: string | number | boolean; label: string; color?: string }>;
  options?: Array<{ value: string | number | boolean; label: string; color?: string }>;
  dynamic?: boolean;
  dependsOn?: string[];
  keywordDependent?: boolean;
}
export type FilterDimension = 'pages' | 'likes' | 'duration' | 'score' | 'favorites';
export interface CommonFilter {
  range?: true | Array<'min' | 'max'>;
  sort?: true | Array<'asc' | 'desc'>;
}
export type CommonFilters = Partial<Record<FilterDimension, CommonFilter>>;
export interface PluginFeed {
  key: string;
  label: string;
  options?: PluginSetting[];
  commonFilters?: CommonFilters;
}
export interface ConfirmationAuto {
  clickSelector: string;
  checkSelector?: string;
  birthDate?: { dateSelector?: string; yearSelector?: string; monthSelector?: string; daySelector?: string };
  questionnaire?: { rowSelector: string; submitSelector: string; answers: Array<{ question: string; answer: string }> };
}
export interface NetworkConfirmation {
  selector: string;
  readySelector?: string;
  requiredCookies?: string[];
  auto?: ConfirmationAuto;
  message?: string;
}
export interface NetworkPermissions {
  mode?: NetworkMode;
  headers?: StringMap;
  origin?: string;
  vpnHint?: boolean;
  confirmation?: NetworkConfirmation;
}
export interface RequestHeaderRule {
  scope: 'playback-origin';
}
export interface MediaPermissions {
  mode: MediaMode;
  scope?: 'session';
  origin?: string;
  domains?: string[];
  referrerDomains?: string[];
  requestHeaders?: Record<string, RequestHeaderRule>;
}
export interface ImageNetworkPermissions {
  mode: MediaMode;
  origin?: string;
  domains?: string[];
}
export interface ImageDecrypt {
  type: 'aes-cbc';
  key: string;
  iv: string;
}
export interface AccountField {
  key: string;
  label: string;
  hint?: string;
  secret?: boolean;
  optional?: boolean;
}
export interface PluginAccount {
  type: 'password' | 'cookies' | 'session';
  title?: string;
  hint?: string;
  required?: boolean;
  fields?: AccountField[];
  registerUrl?: string;
  loginUrl?: string;
  logoutUrl?: string;
  accountUrl?: string;
  cookieUrl?: string;
  requiredCookies?: string[];
  localStorageKeys?: string[];
  loginDomains?: string[];
  managedAccount?: boolean;
}
export interface ChatPermissions {
  domains: string[];
}
export type ReverseSearchCategory = (typeof sourceContract.reverseSearchCategories)[number];
export interface StringMap {
  [key: string]: string;
}
export interface SubscriptionDeclaration {
  hint?: string;
  joinedTargets?: boolean;
  joinedCreators?: boolean;
  communities?: boolean;
  communityHint?: string;
  communityExample?: string;
}
export interface SubscriptionUpdatesDeclaration {
  dimensions?: Array<{ key: string; label: string; hint?: string }>;
}
export interface RankingDeclaration {
  options?: Array<Omit<PluginSetting, 'type'> & { type?: PluginSetting['type'] }>;
  kind?: string;
  key: string;
  label: string;
  category: PluginCategory;
  section?: 'market' | 'site';
  metric: string;
  feed?: string;
}
export interface PluginManifest {
  key: string;
  name: string;
  version: string;
  minAppVersion: string;
  apiVersion: number;
  type: PluginType;
  category: PluginCategory;
  homepage: string;
  domains: string[];
  linkPatterns?: string[];
  idPattern?: string;
  settings?: PluginSetting[];
  account?: PluginAccount;
  feeds?: PluginFeed[];
  searchFilters?: PluginSetting[];
  searchCommonFilters?: CommonFilters;
  browseLayout?: BrowseLayout;
  i18n?: Record<string, Record<string, string>>;
  capabilities?: CapabilitySet;
  metadataOnly?: boolean;
  media?: MediaPermissions;
  imageNetwork?: ImageNetworkPermissions;
  imageDecrypt?: ImageDecrypt;
  navigationDomains?: string[];
  frameDomains?: string[];
  network?: NetworkPermissions;
  imageHeaders?: StringMap;
  postShortVideos?: boolean;
  reverseSearchCategory?: ReverseSearchCategory;
  rankingOnly?: boolean;
  reverseSearchOnly?: boolean;
  previewContent?: boolean;
  defaultFeed?: string;
  anonymousDefaultFeed?: string;
  chat?: ChatPermissions;
  subscription?: SubscriptionDeclaration;
  updateSubscriptions?: SubscriptionUpdatesDeclaration;
  rankings?: RankingDeclaration[];
  searchHint?: string;
  color?: string;
  description?: string;
}
export type PluginErrorCode =
  | 'NETWORK'
  | 'HTTP'
  | 'AUTH'
  | 'LOGIN_REQUIRED'
  | 'VERIFICATION_REQUIRED'
  | 'UNSUPPORTED'
  | 'PARSE'
  | 'TIMEOUT'
  | 'CANCELLED'
  | 'RATE_LIMITED'
  | 'INCOMPATIBLE'
  | 'INVALID_MANIFEST'
  | 'CLOUDFLARE'
  | 'BLOCKED'
  | 'CONFIG'
  | 'NOT_FOUND'
  | 'CONFIRM_REQUIRED';
export interface PluginErrorDetails {
  source?: string;
  operation?: string;
  host?: string;
  transport?: string;
  reason?: string;
  status?: number;
}
export interface PluginError {
  code: PluginErrorCode;
  message: string;
  status?: number;
  retryable?: boolean;
  details?: PluginErrorDetails;
  diagnostics?: PluginErrorDetails;
}
export const PLUGIN_ERROR_CODES: readonly PluginErrorCode[] = [
  'NETWORK',
  'HTTP',
  'AUTH',
  'LOGIN_REQUIRED',
  'VERIFICATION_REQUIRED',
  'UNSUPPORTED',
  'PARSE',
  'TIMEOUT',
  'CANCELLED',
  'RATE_LIMITED',
  'INCOMPATIBLE',
  'INVALID_MANIFEST',
  'CLOUDFLARE',
  'BLOCKED',
  'CONFIG',
  'NOT_FOUND',
  'CONFIRM_REQUIRED',
];
export const CAPABILITY_NAMES: readonly CapabilityName[] = [
  'feed',
  'search',
  'searchSuggestions',
  'searchLink',
  'detail',
  'chapter',
  'resolveImage',
  'thumbnails',
  'videos',
  'webVideo',
  'reverseSearch',
  'reverseSearchMore',
  'subscription',
  'album',
  'subscription.media',
  'updateSubscriptions',
  'subscriptionUpdates',
  'rankings',
  'metadataSearch',
  'metadataDetail',
  'metadataMagnets',
  'comments',
  'interaction',
  'related',
  'resolveLink',
  'textChapter',
  'onlineGame',
  'gameResources',
  'resolveGameResource',
  'voiceDirectory',
  'voiceResource',
  'liveChat',
  'tavernAsset',
  'random',
  'resolveContentLink',
  'previewContent',
];

/** Nested methods are authorized by their actual SDK capability, never by an arbitrary prefix. */
export function operationCapability(method: string): CapabilityName | undefined {
  if (['album', 'albumChunk', 'subscription.media', 'subscription.mediaChunk'].includes(method)) return 'album';
  if (['subscription.normalize', 'subscription.resolve', 'subscription.targets', 'subscription.posts'].includes(method)) return 'subscription';
  if (['subscriptionUpdates', 'updateSubscriptions.normalize', 'updateSubscriptions.query', 'updateSubscriptions.check'].includes(method)) return 'subscriptionUpdates';
  if (method === 'liveChatEvent') return 'liveChat';
  return (CAPABILITY_NAMES as readonly string[]).includes(method) ? (method as CapabilityName) : undefined;
}
