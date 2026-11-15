export type AggregateType = 'work' | 'chapter' | 'collection' | 'download' | 'subscription' | 'plugin' | 'account';
export type EventType = 'work.updated' | 'chapter.progressed' | 'collection.changed' | 'download.statusChanged' | 'subscription.updated' | 'subscription.contentSeen' | 'plugin.installed' | 'account.updated';

/** sequence 是全局 SSE 顺序；aggregateVersion 和 eventVersion 只属于聚合流，三者不可混用。 */
export interface DomainEvent<TPayload = unknown> {
  readonly eventId: string;
  readonly sequence: number;
  readonly eventType: EventType;
  readonly aggregateType: AggregateType;
  readonly aggregateId: string;
  readonly aggregateVersion: number;
  readonly eventVersion: number;
  readonly createdAt: string;
  readonly payload: TPayload;
}

export interface GlobalEventCursor { readonly afterSequence: number; }
export interface AggregateEventCursor { readonly stream: string; readonly afterEventVersion: number; }
export type EventCursor = GlobalEventCursor;

/** 每个消费者/标签页独立记录投递处理状态；不修改不可变 DomainEvent。 */
export interface EventDelivery { readonly eventId: string; readonly consumerId: string; readonly deliveredAt: string; readonly processedAt?: string; }
export interface EventReadState { readonly eventId: string; readonly readAt: string; }

export const eventCursorAfter = (event: DomainEvent): GlobalEventCursor => ({ afterSequence: event.sequence });
export const aggregateEventCursorAfter = (event: DomainEvent): AggregateEventCursor => ({ stream: `${event.aggregateType}:${event.aggregateId}`, afterEventVersion: event.eventVersion });
export const isEventAfterCursor = (event: DomainEvent, cursor?: GlobalEventCursor): boolean => !cursor || event.sequence > cursor.afterSequence;
export const isEventAfterAggregateCursor = (event: DomainEvent, cursor?: AggregateEventCursor): boolean => !cursor || (`${event.aggregateType}:${event.aggregateId}` === cursor.stream && event.eventVersion > cursor.afterEventVersion);
