// The browser integration configures the same public identity for native and
// controlled-browser requests. Standalone hosts still send an honest identity.
let sourceUserAgent = 'Hentai-Park-Web';

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
