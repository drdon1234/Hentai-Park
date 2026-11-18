import { contentError, contentObject, contentText } from './content-model.js';

/** Consume OpenAI or Anthropic SSE streams, requiring a valid completion. */
export async function readTavernStream(
  response: Response,
  onDelta?: (value: string) => void | Promise<void>,
  signal?: AbortSignal,
) {
  if (!response.ok) {
    await response.body?.cancel();
    throw contentError('HTTP', 502);
  }
  if (!/text\/event-stream/i.test(response.headers.get('content-type') ?? '')) {
    await response.body?.cancel();
    throw contentError('PARSE');
  }
  const reader = response.body?.getReader();
  if (!reader) throw contentError();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let pending = '';
  let event: string[] = [];
  let done = false;
  let text = '';
  let finishReason = '';
  let totalTokens: number | undefined;

  const consume = async () => {
    if (!event.length) return;
    const raw = event.join('\n');
    event = [];
    if (raw === '[DONE]') {
      done = true;
      return;
    }
    let row: Record<string, unknown>;
    try {
      row = contentObject(JSON.parse(raw));
    } catch {
      throw contentError();
    }
    if (row.error || row.type === 'error') throw contentError();

    // Anthropic Messages API SSE format
    if (typeof row.type === 'string' && !Array.isArray(row.choices)) {
      if (row.type === 'content_block_delta' && row.delta && typeof row.delta === 'object') {
        const d = row.delta as Record<string, unknown>;
        if (typeof d.text === 'string' && d.text) {
          const value = contentText(d.text, 100000, true);
          text += value;
          if (text.length > 100000) throw contentError('RESOURCE_LIMIT', 422);
          await onDelta?.(value);
        }
      } else if (row.type === 'message_delta') {
        const d = row.delta && typeof row.delta === 'object' ? (row.delta as Record<string, unknown>) : undefined;
        if (typeof d?.stop_reason === 'string') {
          finishReason = d.stop_reason === 'end_turn' ? 'stop' : d.stop_reason === 'max_tokens' ? 'length' : d.stop_reason;
        }
        const u = row.usage && typeof row.usage === 'object' ? (row.usage as Record<string, unknown>) : undefined;
        if (u && Number.isSafeInteger(u.output_tokens)) {
          totalTokens = (totalTokens ?? 0) + Number(u.output_tokens);
        }
      } else if (row.type === 'message_start' && row.message && typeof row.message === 'object') {
        const u = (row.message as Record<string, unknown>).usage as Record<string, unknown> | undefined;
        if (u && Number.isSafeInteger(u.input_tokens)) {
          totalTokens = Number(u.input_tokens);
        }
      } else if (row.type === 'message_stop') {
        done = true;
      }
      return;
    }

    // OpenAI Chat Completions SSE format
    if (row.usage && typeof row.usage === 'object') {
      const usage = row.usage as Record<string, unknown>;
      if (Number.isSafeInteger(usage.total_tokens) && Number(usage.total_tokens) >= 0) {
        totalTokens = Number(usage.total_tokens);
      }
    }
    if (!Array.isArray(row.choices)) throw contentError();
    if (!row.choices.length) return;
    const choice = contentObject(row.choices[0]);
    if (typeof choice.finish_reason === 'string') finishReason = choice.finish_reason;
    if (!choice.delta || typeof choice.delta !== 'object') return;
    const delta = (choice.delta as Record<string, unknown>).content;
    if (delta === undefined || delta === null) return;
    const value = contentText(delta, 100000, true);
    text += value;
    if (text.length > 100000) throw contentError('RESOURCE_LIMIT', 422);
    if (value) await onDelta?.(value);
  };

  try {
    while (!done) {
      signal?.throwIfAborted();
      const next = await reader.read();
      if (next.done) {
        pending += decoder.decode();
        break;
      }
      pending += decoder.decode(next.value, { stream: true });
      if (pending.length > 1024 * 1024) throw contentError();
      let end: number;
      while ((end = pending.indexOf('\n')) >= 0) {
        const line = pending.slice(0, end).replace(/\r$/, '');
        pending = pending.slice(end + 1);
        if (!line) {
          await consume();
          if (done) break;
        } else if (line.startsWith('data:')) {
          event.push(line.slice(5).trimStart());
          if (event.reduce((sum, item) => sum + item.length, 0) > 1024 * 1024) throw contentError();
        }
      }
    }
    if (!done) {
      if (pending.startsWith('data:')) event.push(pending.slice(5).trimStart());
      await consume();
    }
    if (!done || !text || (finishReason && !['stop', 'length', 'end_turn', 'max_tokens'].includes(finishReason))) {
      throw contentError('INCOMPLETE', 502);
    }
    return { role: 'assistant', content: text, finishReason, totalTokens };
  } catch (error) {
    signal?.throwIfAborted();
    throw error;
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
