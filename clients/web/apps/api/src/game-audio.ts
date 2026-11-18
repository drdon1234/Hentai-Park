import type { createGuardedContext } from '@hentai-park/browser-worker';

type Guarded = Awaited<ReturnType<typeof createGuardedContext>>;
type Page = Guarded['page'];
type BrowserContext = Guarded['context'];

interface ParkGameAudioState {
  streams: MediaStream[];
  recorder?: MediaRecorder;
  chunks: string[];
  failed: boolean;
  output?: MediaStream;
  mixer?: AudioContext;
  mixerDestination?: MediaStreamAudioDestinationNode;
  connectStream?: (stream: MediaStream) => void;
}

/** Capture only audio produced inside the isolated game document, dynamically wiring late streams into the active mixer. */
export async function installGameAudio(context: BrowserContext) {
  await context.addInitScript(() => {
    const holder = globalThis as unknown as { __parkGameAudio?: ParkGameAudioState };
    const connectedStreams = new WeakSet<MediaStream>();
    const state: ParkGameAudioState = (holder.__parkGameAudio = {
      streams: [],
      chunks: [],
      failed: false,
      connectStream(stream: MediaStream) {
        if (!state.streams.includes(stream)) state.streams.push(stream);
        if (state.mixer && state.mixerDestination && !connectedStreams.has(stream) && stream.getAudioTracks().length) {
          try {
            connectedStreams.add(stream);
            state.mixer.createMediaStreamSource(stream).connect(state.mixerDestination);
          } catch {
            // Stream may already be ended
          }
        }
      },
    });
    const destinations = new WeakMap<BaseAudioContext, MediaStreamAudioDestinationNode>();
    const connect = AudioNode.prototype.connect;
    AudioNode.prototype.connect = function (
      this: AudioNode,
      destination: AudioNode | AudioParam,
      output?: number,
      input?: number,
    ) {
      const result = Reflect.apply(connect, this, [
        destination,
        ...(output === undefined ? [] : [output]),
        ...(input === undefined ? [] : [input]),
      ]);
      if (destination === this.context.destination && 'createMediaStreamDestination' in this.context) {
        let captured = destinations.get(this.context);
        if (!captured) {
          captured = (this.context as AudioContext).createMediaStreamDestination();
          destinations.set(this.context, captured);
          state.connectStream?.(captured.stream);
        }
        Reflect.apply(connect, this, [captured, ...(output === undefined ? [] : [output])]);
      }
      return result;
    } as typeof AudioNode.prototype.connect;

    const capturedElements = new WeakSet<HTMLMediaElement>();
    document.addEventListener(
      'playing',
      (event) => {
        const media = event.target as HTMLMediaElement & { captureStream?: () => MediaStream };
        if (!media?.captureStream || capturedElements.has(media)) return;
        try {
          const stream = media.captureStream();
          if (stream.getAudioTracks().length) {
            capturedElements.add(media);
            state.connectStream?.(new MediaStream(stream.getAudioTracks()));
          }
        } catch {
          // Protected media element
        }
      },
      true,
    );
  });
}

export async function startGameAudio(page: Page) {
  return page.evaluate(async () => {
    const state = (globalThis as unknown as { __parkGameAudio?: ParkGameAudioState }).__parkGameAudio;
    if (!state || typeof MediaRecorder === 'undefined' || !MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) {
      return false;
    }
    if (state.recorder?.state === 'recording') return true;
    const mixer = new AudioContext();
    await mixer.resume().catch(() => {});
    const destination = mixer.createMediaStreamDestination();
    // Keep a silent constant oscillator connected so MediaRecorder produces valid Opus headers even before game BGM starts
    const silence = mixer.createGain();
    silence.gain.value = 0;
    const osc = mixer.createOscillator();
    osc.connect(silence);
    silence.connect(destination);
    osc.start();

    state.mixer = mixer;
    state.mixerDestination = destination;
    for (const stream of state.streams) {
      if (stream.getAudioTracks().some((track) => track.readyState === 'live')) {
        state.connectStream?.(stream);
      }
    }
    state.output = destination.stream;
    state.chunks = [];
    state.failed = false;

    const recorder = (state.recorder = new MediaRecorder(destination.stream, {
      mimeType: 'audio/webm;codecs=opus',
      audioBitsPerSecond: 96000,
    }));
    recorder.ondataavailable = (event) => {
      void event.data.arrayBuffer().then((buffer) => {
        if (!buffer.byteLength) return;
        if (buffer.byteLength > 524288 || state.chunks.length >= 64) {
          state.failed = true;
          recorder.stop();
          return;
        }
        const bytes = new Uint8Array(buffer);
        let binary = '';
        for (let offset = 0; offset < bytes.length; offset += 32768) {
          binary += String.fromCharCode(...bytes.subarray(offset, offset + 32768));
        }
        state.chunks.push(btoa(binary));
      });
    };
    recorder.onstop = () => {
      try {
        osc.stop();
      } catch {}
      state.output?.getTracks().forEach((track) => track.stop());
      state.mixer = undefined;
      state.mixerDestination = undefined;
      void mixer.close().catch(() => {});
    };
    recorder.start(100);
    return true;
  });
}

export async function readGameAudio(page: Page, stop = false) {
  return page.evaluate((shouldStop) => {
    const state = (globalThis as unknown as { __parkGameAudio?: ParkGameAudioState }).__parkGameAudio;
    if (!state) return { active: false, chunks: [] as string[] };
    if (shouldStop) {
      if (state.recorder?.state === 'recording') state.recorder.stop();
      state.chunks = [];
      return { active: false, chunks: [] as string[] };
    }
    if (state.failed) throw Error('Game audio consumer exceeded the bounded queue');
    return { active: state.recorder?.state === 'recording', chunks: state.chunks.splice(0) };
  }, stop);
}
