export type ErrorCauseCategory = 'validation' | 'not_found' | 'conflict' | 'source' | 'network' | 'storage' | 'cancelled' | 'internal';
export interface DomainError { readonly code: string; readonly messageKey: string; readonly retryable: boolean; readonly details?: Readonly<Record<string, unknown>>; readonly requestId: string; readonly source?: string; readonly operation: string; readonly causeCategory: ErrorCauseCategory; }
export const domainError = (input: DomainError): DomainError => ({ ...input, details: input.details ? { ...input.details } : undefined });
