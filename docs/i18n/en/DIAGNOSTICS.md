# Runtime logs and issue reports

Normal logs record failures, automatic retries, site call results and app lifecycle changes. Refresh or export runtime logs in Settings and include reproduction steps in an Issue.

For difficult problems, enable debug logs for this session to capture an immediate reproduction, or for the next launch only to capture startup. A notice appears when scheduled debug mode starts. Debug mode ends when the app exits; the next-launch option is consumed once.

Persistent logs are off by default: each launch replaces recent runtime records. Enabling them appends across launches and drops the oldest records only at 100 MiB. Disabling them immediately replaces runtime history. Independent crash history is unaffected.

Debug adds request timing, retries, cache and playback state, without accounts, cookies, tokens, content, local paths or full signed links. The page shows recent records; exports include all retained runtime logs. Redacted mode also hides target hosts and detailed OS versions. Review exports before sharing.
