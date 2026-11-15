import { existsSync, readFileSync } from 'node:fs';
import {webRoot,repositoryRoot} from './shared-assets.mjs';
import {join} from 'node:path';

const required = [
  'apps/web',
  'apps/api',
  'apps/source-runner',
  'apps/task-worker',
  'apps/browser-worker',
  'packages/source-contract',
  'packages/source-runtime',
  'packages/source-host',
  'packages/domain-model',
  'packages/design-system',
];

const missing = required.filter((path) => !existsSync(join(webRoot,path)));
if (missing.length > 0) {
  console.error(`缺少目录: ${missing.join(', ')}`);
  process.exit(1);
}
console.log(`目录结构验证通过（${required.length} 项）`);
if(!readFileSync(join(repositoryRoot,'.gitignore'),'utf8').split(/\r?\n/).includes('/test/'))throw Error('.gitignore 必须包含 /test/');
