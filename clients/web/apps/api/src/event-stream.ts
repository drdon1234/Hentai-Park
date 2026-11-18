import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { AppDatabase } from './database.js';
import type { OutgoingHttpHeaders } from 'node:http';
import type { EventEmitter } from 'node:events';

export function registerEvents(
  router: FastifyInstance,
  db: AppDatabase,
  authorized: (request: FastifyRequest) => boolean,
  events?: EventEmitter,
) {
  const streams = new Set<() => void>();
  router.addHook('preClose', async () => {
    for (const stop of streams) stop();
  });

  router.get('/events', async (request, reply) => {
    const raw = request.headers['last-event-id'] ?? (request.query as Record<string, unknown>).afterSequence;
    if (raw !== undefined && (!/^\d{1,16}$/.test(String(raw)) || !Number.isSafeInteger(Number(raw)))) {
      throw Object.assign(new Error('invalid event cursor'), { statusCode: 400 });
    }
    const range = db.db
      .prepare('SELECT MIN(sequence) AS first,COALESCE(MAX(sequence),0) AS last FROM domain_events')
      .get()!;
    let after = raw === undefined ? Number(range.last) : Number(raw);
    const reset =
      raw === undefined ||
      after > Number(range.last) ||
      (after > 0 && range.first !== null && after < Number(range.first) - 1);
    if (reset) after = Number(range.last);

    reply.hijack();
    reply.raw.writeHead(200, {
      ...reply.getHeaders(),
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache, no-store',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
    } as OutgoingHttpHeaders);
    reply.raw.write(': connected\n\n');
    if (reset) {
      reply.raw.write(
        `id: ${after}\nevent: sync.required\ndata: {"eventType":"sync.required","sequence":${after}}\n\n`,
      );
    }

    let closed = false;
    let heartbeatTimer: ReturnType<typeof setInterval>;

    const stop = () => {
      if (closed) return;
      closed = true;
      clearInterval(heartbeatTimer);
      streams.delete(stop);
      events?.off('domain-event', push);
      events?.off('download-telemetry', pushTelemetry);
      reply.raw.end();
    };

    const push = () => {
      if (closed || reply.raw.destroyed || !authorized(request)) return stop();
      if (reply.raw.writableNeedDrain) return;
      try {
        const rows = db.db
          .prepare('SELECT * FROM domain_events WHERE sequence>? ORDER BY sequence LIMIT 200')
          .all(after);
        for (const event of rows) {
          const body = {
            eventId: event.event_id,
            sequence: event.sequence,
            eventType: event.event_type,
            aggregateType: event.aggregate_type,
            aggregateId: event.aggregate_id,
            aggregateVersion: event.aggregate_version,
            eventVersion: event.event_version,
            createdAt: event.created_at,
            payload: JSON.parse(String(event.payload_json)),
          };
          const ready = reply.raw.write(
            `id: ${event.sequence}\nevent: ${event.event_type}\ndata: ${JSON.stringify(body)}\n\n`,
          );
          after = Number(event.sequence);
          if (!ready) break;
        }
      } catch {
        stop();
      }
    };

    const pushTelemetry = (telemetry: Record<string, unknown>) => {
      if (closed || reply.raw.destroyed || !authorized(request) || reply.raw.writableNeedDrain) return;
      try {
        reply.raw.write(`event: download.telemetry\ndata: ${JSON.stringify(telemetry)}\n\n`);
      } catch {
        stop();
      }
    };

    // Event-driven wakeup with a lightweight 3s fallback/heartbeat instead of 250ms SQL polling!
    let ticks = 0;
    heartbeatTimer = setInterval(() => {
      push();
      if (!closed && ++ticks % 5 === 0) {
        reply.raw.write(': heartbeat\n\n');
      }
    }, 3000);
    heartbeatTimer.unref();

    events?.on('domain-event', push);
    events?.on('download-telemetry', pushTelemetry);
    streams.add(stop);
    reply.raw.on('close', stop);
    push();
  });
}
