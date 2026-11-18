import { unwrapHlsResource } from '@hentai-park/source-host';
export { unwrapHlsResource } from '@hentai-park/source-host';

const invalid = () =>
  Object.assign(new Error('Invalid media envelope'), {
    code: 'PARSE',
    statusCode: 502,
    publicError: true,
    causeCategory: 'source',
    retryable: false,
  });

export function sniffSegmentMime(sample: Uint8Array): string | undefined {
  if (sample.length >= 4 && sample[0] === 0x47 && (sample.length < 189 || sample[188] === 0x47)) {
    return 'video/mp2t';
  }
  if (sample.length >= 8) {
    const box = Buffer.from(sample.subarray(4, 8)).toString('ascii');
    if (box === 'ftyp' || box === 'styp' || box === 'moof') {
      return 'video/mp4';
    }
  }
  if (
    (sample.length >= 3 && sample[0] === 0x49 && sample[1] === 0x44 && sample[2] === 0x33) ||
    (sample.length >= 2 && sample[0] === 0xff && (sample[1]! & 0xf6) === 0xf0)
  ) {
    return 'audio/aac';
  }
  return undefined;
}

/** Inspect a bounded prefix without buffering ordinary MP4/Range streams. */
export async function unwrapMediaResponse(
  response: Response,
  maxBytes: number,
  hlsBinary = false,
): Promise<Response> {
  if (!response.body || !response.ok) return response;
  const reader = response.body.getReader();
  const prefix: Uint8Array[] = [];
  let length = 0;
  try {
    while (length < 192) {
      const next = await reader.read();
      if (next.done) break;
      prefix.push(next.value);
      length += next.value.length;
    }
    const head = Buffer.concat(prefix);
    if (head.length >= 8 && head.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
      let bytes = length;
      const chunks: Uint8Array[] = [head];
      for (;;) {
        const next = await reader.read();
        if (next.done) break;
        bytes += next.value.length;
        if (bytes > 64 * 1024 * 1024 + 1024) throw invalid();
        chunks.push(next.value);
      }
      const decoded = unwrapHlsResource(Buffer.concat(chunks), maxBytes);
      const headers = new Headers(response.headers);
      headers.set('content-length', String(decoded.length));
      headers.set('content-type', sniffSegmentMime(decoded) ?? 'application/octet-stream');
      const result = new Response(new Uint8Array(decoded), { status: response.status, headers });
      Object.defineProperty(result, 'url', { value: response.url });
      reader.releaseLock();
      return result;
    }

    const headers = new Headers(response.headers);
    if (hlsBinary) {
      const currentType = (headers.get('content-type') ?? '').toLowerCase();
      const sniffed = sniffSegmentMime(head);
      if (sniffed && (!currentType || /^(?:text\/|application\/octet-stream|binary\/octet-stream|image\/)/i.test(currentType))) {
        headers.set('content-type', sniffed);
      } else if (/^(?:text\/html|text\/plain)/i.test(currentType)) {
        const sample = head.subarray(0, Math.min(head.length, 512));
        let binary = sample.some((byte) => byte < 32 && ![9, 10, 13].includes(byte));
        try {
          new TextDecoder('utf-8', { fatal: true }).decode(sample, { stream: true });
        } catch {
          binary = true;
        }
        if (binary) headers.set('content-type', sniffed ?? 'application/octet-stream');
      }
    }

    const result = new Response(
      new ReadableStream<Uint8Array>({
        start(controller) {
          for (const chunk of prefix) controller.enqueue(chunk);
        },
        async pull(controller) {
          try {
            const next = await reader.read();
            if (next.done) {
              reader.releaseLock();
              controller.close();
            } else {
              controller.enqueue(next.value);
            }
          } catch (error) {
            controller.error(error);
          }
        },
        async cancel(reason) {
          await reader.cancel(reason);
          reader.releaseLock();
        },
      }),
      { status: response.status, headers },
    );
    Object.defineProperty(result, 'url', { value: response.url });
    return result;
  } catch (error) {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
    throw error;
  }
}
