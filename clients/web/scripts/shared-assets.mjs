import {readFile,readdir,mkdir,copyFile,rm,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
export const webRoot=fileURLToPath(new URL('../',import.meta.url));
export const repositoryRoot=fileURLToPath(new URL('../../../',import.meta.url));

export async function applicationVersion(){
  const text=await readFile(join(repositoryRoot,'clients/web/package.json'),'utf8');
  const version=JSON.parse(text).version;
  if(typeof version!=='string'||!/^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?$/.test(version))throw Error('clients/web/package.json must declare a valid web version');
  return version;
}
export async function prepareSharedAssets(){
  const output=join(webRoot,'assets'),sources=join(output,'sources');
  await mkdir(sources,{recursive:true});
  await mkdir(join(output,'runtime'),{recursive:true});
  const names=(await readdir(join(repositoryRoot,'assets/sources'))).filter(name=>name.endsWith('.js')).sort();
  if(!names.length)throw Error('Shared official plugins are missing');
  for(const old of await readdir(sources))if(!names.includes(old))await rm(join(sources,old));
  for(const name of names)await copyFile(join(repositoryRoot,'assets/sources',name),join(sources,name));
  await copyFile(join(repositoryRoot,'assets/runtime/park_runtime.js'),join(output,'runtime/park_runtime.js'));
  await writeFile(join(output,'application.json'),JSON.stringify({version:await applicationVersion()})+'\n');
}

export async function sharedAssetsCurrent(){
  try{
    if(JSON.parse(await readFile(join(webRoot,'assets/application.json'),'utf8')).version!==await applicationVersion())return false;
    const names=(await readdir(join(repositoryRoot,'assets/sources'))).filter(name=>name.endsWith('.js')).sort();
    if(JSON.stringify(names)!==JSON.stringify((await readdir(join(webRoot,'assets/sources'))).sort()))return false;
    for(const name of [...names.map(name=>'sources/'+name),'runtime/park_runtime.js']){
      if(!(await readFile(join(repositoryRoot,'assets',name))).equals(await readFile(join(webRoot,'assets',name))))return false;
    }
    return true;
  }catch(error){if(error.code==='ENOENT')return false;throw error;}
}
