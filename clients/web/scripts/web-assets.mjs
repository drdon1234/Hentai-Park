import {readFile,readdir} from 'node:fs/promises';
import {join} from 'node:path';

/** Pin one complete build for the lifetime of a server. Lazy chunks and workers
 * must remain available to pages already opened while the workspace rebuilds. */
export async function loadWebAssets(root) {
  const files=new Map();
  async function visit(relative='') {
    for(const entry of await readdir(join(root,relative),{withFileTypes:true})) {
      const name=relative?relative+'/'+entry.name:entry.name;
      if(entry.isDirectory())await visit(name);
      else if(entry.isFile())files.set(name,await readFile(join(root,name)));
    }
  }
  await visit();
  if(!files.has('index.html'))throw new Error('Web build is missing index.html');
  return files;
}
