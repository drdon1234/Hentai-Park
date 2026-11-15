import { readFileSync } from 'node:fs';

export const nodeBaseline=readFileSync(new URL('../.nvmrc',import.meta.url),'utf8').trim();
export function assertSupportedNode(version=process.versions.node){
  const minimum=nodeBaseline.split('.').map(Number),actual=version.split('.').map(Number);
  if(!/^\d+\.\d+\.\d+$/.test(version)||actual[0]!==minimum[0]||actual[1]<minimum[1]||actual[1]===minimum[1]&&actual[2]<minimum[2])throw Error(`需要 Node.js ${nodeBaseline}+（${minimum[0]}.x LTS），当前为 ${version}。请使用 .nvmrc 指定版本。`);
}
