FROM node:24.22.3-bookworm-slim AS build
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

FROM node:24.22.3-bookworm-slim AS runtime
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787 DATA_DIR=/data DOWNLOAD_DIR=/data/downloads WEB_SESSION_MODE=server PLAYWRIGHT_BROWSERS_PATH=/opt/browsers
WORKDIR /app/clients/web
COPY --from=build /app /app
RUN npm install -g pnpm@10.33.2
RUN --mount=type=cache,id=hpweb-playwright,target=/browser-cache PLAYWRIGHT_BROWSERS_PATH=/browser-cache pnpm --filter @hentai-park/browser-worker exec playwright install --with-deps chromium && mkdir -p /opt/browsers && cp -a /browser-cache/. /opt/browsers/
RUN mkdir -p /data /opt/browsers && chown -R node:node /data /opt/browsers /app
USER node
VOLUME ["/data"]
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "scripts/start-web.mjs"]
