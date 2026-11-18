ARG BASE_IMAGE=node:24.22.3-bookworm-slim
FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS build
WORKDIR /app/clients/web
RUN npm install -g pnpm@10.33.2
COPY clients/web/.nvmrc clients/web/package.json clients/web/pnpm-lock.yaml clients/web/pnpm-workspace.yaml clients/web/tsconfig.json clients/web/tsconfig.base.json ./
COPY clients/web/packages ./packages
COPY clients/web/apps ./apps
COPY clients/web/scripts ./scripts
COPY assets /app/assets
COPY pubspec.yaml /app/pubspec.yaml
RUN pnpm install --frozen-lockfile
RUN pnpm build
RUN CI=true pnpm install --prod --frozen-lockfile --offline

FROM ${BASE_IMAGE} AS runtime
ARG TARGETARCH
ARG APT_MIRROR=""
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787 DATA_DIR=/data DOWNLOAD_DIR=/data/downloads WEB_SESSION_MODE=server PLAYWRIGHT_BROWSERS_PATH=/opt/browsers
WORKDIR /app/clients/web
COPY --from=build /app/pubspec.yaml /app/pubspec.yaml
COPY --from=build /app/clients/web/.nvmrc ./.nvmrc
COPY --from=build /app/clients/web/package.json ./package.json
COPY --from=build /app/clients/web/pnpm-workspace.yaml ./pnpm-workspace.yaml
COPY --from=build /app/clients/web/node_modules ./node_modules
COPY --from=build /app/clients/web/assets ./assets
COPY --from=build /app/clients/web/scripts ./scripts
COPY --from=build /app/clients/web/packages ./packages
COPY --from=build /app/clients/web/apps ./apps
RUN --mount=type=cache,id=hpweb-apt-${TARGETARCH},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=hpweb-playwright-${TARGETARCH},target=/browser-cache \
    if [ -n "$APT_MIRROR" ] && [ -f /etc/apt/sources.list.d/debian.sources ]; then sed -i "s|deb.debian.org|$APT_MIRROR|g" /etc/apt/sources.list.d/debian.sources; fi && \
    apt-get update && apt-get install -y --no-install-recommends tini ca-certificates && \
    PLAYWRIGHT_BROWSERS_PATH=/browser-cache node ./apps/browser-worker/node_modules/playwright/cli.js install chromium && \
    mkdir -p /opt/browsers && cp -a /browser-cache/. /opt/browsers/ && \
    node ./apps/browser-worker/node_modules/playwright/cli.js install-deps chromium && \
    rm -rf /var/lib/apt/lists/* && \
    find packages apps -name 'src' -type d -prune -exec rm -rf '{}' + && \
    mkdir -p /data && chown -R node:node /data /opt/browsers /app
USER node
VOLUME ["/data"]
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
ENTRYPOINT ["/usr/bin/tini", "-s", "--"]
CMD ["node", "scripts/start-web.mjs"]
