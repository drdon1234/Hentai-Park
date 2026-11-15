import type {Page,Response} from 'playwright';
import {responseChallenge} from '@hentai-park/source-host';
import {toAbortError} from '@hentai-park/source-contract';
import {clickChallengeCheckbox} from './challenge-input.js';

export const challengeFailure=(code:string,stage:string)=>Object.assign(new Error('Site verification did not complete'),{code,retryable:false,details:{reason:code==='BLOCKED'?'FIREWALL_BLOCKED':'SITE_CHALLENGE',stage}});

/** Poll observable page state; navigation/context replacement is not proof of completion. */
export async function waitForChallenge(page:Page,response:()=>Response|undefined,signal:AbortSignal,stage:string,deadline:number):Promise<void>{
  let challenged=false,navigations=0,lastUrl='',stable='',stableSince=0,attempts=0,lastInput=0,lastScan=0;
  for(;;){
    if(signal.aborted)throw toAbortError(signal);
    if(Date.now()>=deadline)throw challengeFailure(challenged?'CLOUDFLARE':'TIMEOUT',stage);
    try{
      const current=await page.evaluate(()=>({url:location.href,body:document.documentElement?.outerHTML??'',generation:performance.timeOrigin,ready:document.readyState}));
      const navigation=response();
      if(navigation&&current.url===navigation.url()){
        const code=responseChallenge({status:navigation.status(),headers:await navigation.allHeaders(),body:current.body});
        if(code==='BLOCKED')throw challengeFailure(code,stage);
        if(code){challenged=true;const key=current.url+':'+current.generation;if(key!==lastUrl){lastUrl=key;if(++navigations>4)throw challengeFailure('CLOUDFLARE',stage);}stable='';
          if(attempts<3&&Date.now()-lastInput>=8000&&Date.now()-lastScan>=500){lastScan=Date.now();if(await clickChallengeCheckbox(page,current.url,current.generation,signal)){attempts++;lastInput=Date.now();}}
        }
        else if(!challenged)return;
        else if(navigation.status()>=400)throw challengeFailure('HTTP',stage);
        else if(current.ready!=='loading'&&current.body.length>0){const key=current.url+':'+current.generation+':'+current.body;if(key!==stable){stable=key;stableSince=Date.now();}else if(Date.now()-stableSince>=500)return;}
      }
    }catch(error){if(error&&typeof error==='object'&&'code'in error)throw error;if(!(error instanceof Error)||!/Execution context was destroyed|Cannot find context/i.test(error.message))throw error;}
    await new Promise<void>((resolve,reject)=>{const done=()=>{clearTimeout(timer);signal.removeEventListener('abort',cancel);resolve();},cancel=()=>{clearTimeout(timer);signal.removeEventListener('abort',cancel);reject(toAbortError(signal));},timer=setTimeout(done,100);signal.addEventListener('abort',cancel,{once:true});if(signal.aborted)cancel();});
  }
}
