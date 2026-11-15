import type { DownloadTaskStatus, TaskLease } from './entities.js';
export type DownloadTaskCommand = 'start' | 'pause' | 'resume' | 'complete' | 'fail' | 'cancel' | 'cancelled' | 'retry';
const transitions: Readonly<Record<DownloadTaskStatus, Readonly<Partial<Record<DownloadTaskCommand, DownloadTaskStatus>>>>> = { queued: { start: 'running', cancel: 'cancelling' }, running: { pause: 'paused', complete: 'completed', fail: 'failed', cancel: 'cancelling' }, paused: { resume: 'running', cancel: 'cancelling' }, failed: { retry: 'queued', cancel: 'cancelling' }, cancelling: { cancelled: 'cancelled' }, completed: {}, cancelled: {} };
export const nextDownloadStatus = (current: DownloadTaskStatus, command: DownloadTaskCommand): DownloadTaskStatus | undefined => transitions[current][command];
export const canTransitionDownloadStatus = (current: DownloadTaskStatus, command: DownloadTaskCommand): boolean => nextDownloadStatus(current, command) !== undefined;
export const assertDownloadTransition = (current: DownloadTaskStatus, command: DownloadTaskCommand): DownloadTaskStatus => { const next = nextDownloadStatus(current, command); if (!next) throw new Error(`Illegal download task transition: ${current} -> ${command}`); return next; };
export interface LeaseWriteContext { readonly taskId: string; readonly leaseOwner: string; readonly leaseGeneration: number; readonly now: string; }
export const canWriteWithLease = (lease: TaskLease, context: LeaseWriteContext): boolean => {
  const now = Date.parse(context.now);
  const expiry = Date.parse(lease.leaseExpiresAt);
  return lease.taskId === context.taskId && lease.leaseOwner === context.leaseOwner &&
    lease.leaseGeneration === context.leaseGeneration && !lease.cancellationRequested &&
    Number.isFinite(now) && Number.isFinite(expiry) && now < expiry;
};
