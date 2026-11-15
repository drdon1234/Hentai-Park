import type {NetworkConfirmation} from '@hentai-park/source-contract';
import {toPluginError} from '@hentai-park/source-contract';
import type {Page,JSHandle} from 'playwright';

/** Prepare only declared fields. The host clicks the returned exact element with navigation tracking. */
function confirmationAction({declaration,act}:{declaration:NetworkConfirmation;act:boolean}):{gate:boolean;ready:boolean;action?:HTMLElement} {
  const visible=(element:Element)=>element.isConnected&&element.getClientRects().length>0&&getComputedStyle(element).display!=='none'&&getComputedStyle(element).visibility!=='hidden';
  const gates=Array.from(document.querySelectorAll(declaration.selector)).filter(visible);
  const ready=!declaration.readySelector||Boolean(document.querySelector(declaration.readySelector));
  const unchanged={gate:gates.length>0,ready};if(!act||!gates.length||!declaration.auto)return unchanged;
  const auto=declaration.auto;
  const find=(selector:string,allowDisabled=false)=>Array.from(document.querySelectorAll(selector)).filter(element=>visible(element)&&(allowDisabled||!(element as HTMLInputElement).disabled)&&gates.some(gate=>gate.contains(element)));
  const safeForm=(form:HTMLFormElement)=>{const action=new URL(form.action,location.href);return action.protocol==='https:'&&action.origin===location.origin&&!action.username&&!action.password;};
  const quiz=auto.questionnaire,rows=quiz?find(quiz.rowSelector):[];
  if(quiz&&rows.length){
    if(gates.length!==1||rows.length>32)return unchanged;
    const normalize=(text:unknown)=>String(text??'').replace(/\s+/g,' ').trim();
    const answers=new Map(quiz.answers.map(item=>[normalize(item.question),normalize(item.answer)]));
    const choices:HTMLInputElement[]=[],groups=new Set<string>();let form:HTMLFormElement|null=null;
    for(const row of rows){
      const inputs=Array.from(row.querySelectorAll<HTMLInputElement>('input[type="radio"]')).filter(input=>visible(input)&&!input.disabled);
      if(!inputs.length)return unchanged;const first=inputs[0]!,range=document.createRange();range.setStart(row,0);range.setEndBefore(first);
      const answer=answers.get(normalize(range.toString()));const matches=inputs.filter(input=>normalize(input.nextSibling?.textContent)===answer);
      if(!answer||matches.length!==1||!first.form||form&&form!==first.form||!first.name||groups.has(first.name)||inputs.some(input=>input.name!==first.name||input.form!==first.form))return unchanged;
      form=first.form;groups.add(first.name);choices.push(matches[0]!);
    }
    const buttons=find(quiz.submitSelector,true).filter(element=>(element as HTMLButtonElement).form===form);
    if(!form||!safeForm(form)||buttons.length!==1)return unchanged;
    for(const choice of choices)if(!choice.checked)choice.click();if(choices.some(choice=>!choice.checked))return unchanged;
    const button=buttons[0] as HTMLButtonElement;if(button.disabled||button.getAttribute('aria-disabled')==='true')return unchanged;
    return {gate:true,ready,action:button};
  }
  const buttons=find(auto.clickSelector,true),checks=auto.checkSelector?find(auto.checkSelector):[];
  if(gates.length!==1||buttons.length!==1||auto.checkSelector&&(checks.length!==1||!(checks[0] instanceof HTMLInputElement)||checks[0].type!=='checkbox'))return unchanged;
  const birth=auto.birthDate;
  if(birth){
    const spec:Array<[string|undefined,string]>=birth.dateSelector?[[birth.dateSelector,'1999-12-31']]:[[birth.yearSelector,'1999'],[birth.monthSelector,'12'],[birth.daySelector,'31']];
    if(spec.some(([selector])=>!selector))return unchanged;const matches=spec.map(([selector])=>find(selector!));if(matches.some(items=>items.length!==1))return unchanged;
    const fields=matches.map(items=>items[0] as HTMLInputElement|HTMLSelectElement),form=fields[0]!.form;
    if(!form||!safeForm(form)||fields.some(field=>field.form!==form)||(buttons[0] as HTMLButtonElement).form!==form||checks.some(check=>(check as HTMLInputElement).form!==form))return unchanged;
    if(fields.some((field,index)=>!(field instanceof HTMLInputElement||field instanceof HTMLSelectElement)||field instanceof HTMLSelectElement&&!Array.from(field.options).some(option=>option.value===spec[index]![1]&&!option.disabled)))return unchanged;
    fields.forEach((field,index)=>{const prototype=field instanceof HTMLSelectElement?HTMLSelectElement.prototype:HTMLInputElement.prototype;Object.getOwnPropertyDescriptor(prototype,'value')!.set!.call(field,spec[index]![1]);field.dispatchEvent(new Event('input',{bubbles:true}));field.dispatchEvent(new Event('change',{bubbles:true}));});
  }
  for(const check of checks){const input=check as HTMLInputElement;if(!input.checked)input.click();if(!input.checked)return unchanged;}
  const button=buttons[0] as HTMLButtonElement;if(button.disabled||button.getAttribute('aria-disabled')==='true'||button.form&&!safeForm(button.form))return unchanged;return {gate:true,ready,action:button};
}

/** A navigation can destroy an evaluation context; that is a transport failure, never invalid plugin data. */
export function browserOperationError(error:unknown){
  if(error instanceof Error&&/Execution context was destroyed|Cannot find context|Target (?:page|closed)|(?:page|context|browser) has been closed|Failed to fetch|NetworkError when attempting to fetch/i.test(error.message))return toPluginError({code:'NETWORK',details:{reason:'RESPONSE_STREAM',transport:'browser'}});
  return toPluginError(error);
}

export async function confirmPage(page:Pick<Page,'evaluateHandle'|'waitForLoadState'>,declaration:NetworkConfirmation,act:boolean,timeout=20000):Promise<{gate:boolean;ready:boolean;acted:boolean;navigated:boolean}>{
  let prepared:JSHandle<ReturnType<typeof confirmationAction>>|undefined;
  try{
    prepared=await page.evaluateHandle(confirmationAction,{declaration,act});
    const state=await prepared.evaluate(value=>({gate:value.gate,ready:value.ready,documentId:performance.timeOrigin}));
    const property=await prepared.getProperty('action');
    try{const button=property.asElement();if(!button)return {gate:state.gate,ready:state.ready,acted:false,navigated:false};
      // ElementHandle.click waits for the navigation initiated by this one click. Never replay the action.
      await button.click({timeout});await page.waitForLoadState('domcontentloaded',{timeout});
      const current=await page.evaluateHandle(()=>performance.timeOrigin);try{return {gate:state.gate,ready:state.ready,acted:true,navigated:await current.jsonValue()!==state.documentId};}finally{await current.dispose();}
    }finally{await property.dispose();}
  }catch(error){throw browserOperationError(error);}
  finally{await prepared?.dispose();}
}
