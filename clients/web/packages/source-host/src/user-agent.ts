// The browser integration configures the same public identity for native and
// controlled-browser requests. Standalone hosts still send an honest identity.
const defaultPlatform =
  process.platform === 'win32'
    ? 'Windows NT 10.0; Win64; x64'
    : process.platform === 'darwin'
      ? 'Macintosh; Intel Mac OS X 10_15_7'
      : 'X11; Linux x86_64';
let sourceUserAgent = `Mozilla/5.0 (${defaultPlatform}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36`;

export function getSourceUserAgent(): string { return sourceUserAgent; }

export function configureSourceUserAgent(value: string): void {
    if (typeof value !== 'string' || value.length === 0 || value.length > 1024 || /[^\x20-\x7e]/.test(value))
        throw Object.assign(new Error('Invalid source User-Agent'), { code: 'CONFIG', retryable: false });
    sourceUserAgent = value;
}

export function withDefaultUserAgent(headers: Record<string, string> = {}): Record<string, string> {
    return Object.keys(headers).some(name => name.toLowerCase() === 'user-agent')
        ? { ...headers }
        : { 'user-agent': sourceUserAgent, ...headers };
}
