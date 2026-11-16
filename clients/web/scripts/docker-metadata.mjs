import {appendFileSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

export function dockerMetadata({event,ref,sha,defaultBranch,image,version,publishRequested=false}){
  if(!/^[a-f0-9]{40}$/.test(sha))throw Error('Invalid commit SHA');
  const branch=ref===`refs/heads/${defaultBranch}`;
  const tag=ref.startsWith('refs/tags/')?ref.slice(10):null;
  const releaseEvent=(event==='push'&&tag!==null)||(event==='workflow_dispatch'&&branch);
  if(!releaseEvent)throw Error('Docker builds require the version release workflow');
  const publish=publishRequested===true;
  if(!image&&publish)throw Error('Configure the DOCKERHUB_IMAGE repository variable');
  image||='hentai-park/web-check';
  if(!/^[a-z0-9][a-z0-9_-]*\/[a-z0-9]+(?:[._-][a-z0-9]+)*$/.test(image))throw Error('Invalid Docker Hub namespace/repository');
  let releaseVersion=version;
  const tags=[`${image}:sha-${sha}`];
  if(tag){
    const match=/^v((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?)$/.exec(tag);
    if(!match||match[1].split('-')[0]!==version.split('-')[0]||(version.includes('-')&&match[1]!==version))throw Error('Release tag must match clients/web/package.json');
    releaseVersion=match[1];
  }
  tags.push(`${image}:${releaseVersion}`);
  if(!releaseVersion.includes('-'))tags.push(`${image}:latest`);
  return {publish,tags,version:releaseVersion};
}

if(process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1])){
  const {applicationVersion}=await import('./shared-assets.mjs');
  const event=JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH,'utf8'));
  const result=dockerMetadata({event:process.env.GITHUB_EVENT_NAME,ref:process.env.GITHUB_REF,sha:process.env.GITHUB_SHA,defaultBranch:event.repository.default_branch,image:process.env.DOCKERHUB_IMAGE,version:await applicationVersion(),publishRequested:process.env.PUBLISH_IMAGE==='true'});
  for(const [key,value]of Object.entries({...result,tags:result.tags.join(',')}))appendFileSync(process.env.GITHUB_OUTPUT,`${key}=${value}\n`);
  console.log(JSON.stringify(result));
}
