import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath, URL } from 'node:url';

export default defineConfig({ plugins: [react()], server: { host: '127.0.0.1', proxy: { '/api': { target: process.env.WEB_API_PROXY ?? 'http://127.0.0.1:8787', changeOrigin: false }, '/health': { target: process.env.WEB_API_PROXY ?? 'http://127.0.0.1:8787', changeOrigin: false } } }, resolve: { alias: { '@hentai-park/design-system': fileURLToPath(new URL('../../packages/design-system/src/index.tsx', import.meta.url)) } } });
