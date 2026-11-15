export type SourceId = string;
export type WorkId = string;
export type ChapterId = string;
/** 变体身份必须是稳定的业务标识，不得填入临时媒体 URL。 */
export type DownloadVariant = 'original' | 'compressed' | 'stream' | (string & {});
export const MAX_DOWNLOAD_VARIANT_LENGTH = 128;
export const isStableDownloadVariant = (value: string): value is DownloadVariant =>
  value.length > 0 && value.length <= MAX_DOWNLOAD_VARIANT_LENGTH &&
  !/[\u0000-\u001F\u007F]/.test(value) && !/^(?:https?:)?\/\//i.test(value) &&
  !/^[A-Za-z][A-Za-z0-9+.-]*:/.test(value);
export const assertStableDownloadVariant = (value: string): DownloadVariant => {
  if (!isStableDownloadVariant(value)) throw new TypeError('Download variant must be a stable non-URL identifier');
  return value;
};
export interface WorkIdentity { readonly source: SourceId; readonly id: WorkId; }
export interface ChapterIdentity { readonly source: SourceId; readonly workId: WorkId; readonly chapterId: ChapterId; }
const stableTupleKey = (parts: readonly string[]): string => JSON.stringify(parts);
export const workIdentityKey = (identity: WorkIdentity): string => stableTupleKey([identity.source, identity.id]);
export const chapterIdentityKey = (identity: ChapterIdentity): string => stableTupleKey([identity.source, identity.workId, identity.chapterId]);
export const downloadIdempotencyKey = (identity: ChapterIdentity & { readonly variant: DownloadVariant }): string => stableTupleKey([identity.source, identity.workId, identity.chapterId, identity.variant]);
export const downloadTaskId = (identity: ChapterIdentity & { readonly variant: DownloadVariant }): string => `download:${downloadIdempotencyKey(identity)}`;
export const workCollectionResourceKey = (identity: WorkIdentity): string => `collection:${workIdentityKey(identity)}`;
export const subscriptionResourceKey = (source: SourceId, dimension: string, target: string): string => `subscription:${stableTupleKey([source, dimension, target])}`;
export const writeIdempotencyKey = (resourceKey: string, requestKey: string): string => stableTupleKey([resourceKey, requestKey]);
export const collectionWriteIdempotencyKey = (identity: WorkIdentity, requestKey: string): string => writeIdempotencyKey(workCollectionResourceKey(identity), requestKey);
export const subscriptionWriteIdempotencyKey = (source: SourceId, dimension: string, target: string, requestKey: string): string => writeIdempotencyKey(subscriptionResourceKey(source, dimension, target), requestKey);
