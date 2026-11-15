/** The baseline recognises challenge pages, not arbitrary scripts in successful API responses. */
export function firewallPage(body:string):boolean {
  return body.includes('cf-error-details')&&/you have been blocked|why have i been blocked|error code:?\s*10(?:0[69]|20)\b/i.test(body);
}
export function challengePage(body:string):boolean {
  if(firewallPage(body))return false;
  const title=/<title[^>]*>([^<]*)<\/title>/i.exec(body)?.[1]??'';
  return /^\s*(?:Just a moment|Attention Required)\b/i.test(title)||
    /cloudflare/i.test(body)&&/^\s*(?:请稍候|請稍候|请稍等|請稍等|しばらくお待ちください|잠시만 기다리세요|Un momento|Einen Moment|Один момент|لحظة واحدة)(?:[\s.…!！]|$)/i.test(title)||
    /(?:window\.)?_cf_chl_opt\s*=|id\s*=\s*["'](?:challenge-form|cf-challenge-running)["']/i.test(body)||
    !body.includes('<')&&/^\s*(?:Just a moment|Attention Required)\b/i.test(body);
}
export function responseChallenge(response:{status:number;headers:Record<string,string>;body:string},native=false):'BLOCKED'|'CLOUDFLARE'|undefined {
  const {status,headers,body}=response;
  if(native&&![403,429,503].includes(status))return;
  if(status===403&&(!native||/cloudflare/i.test(headers.server??''))&&firewallPage(body))return 'BLOCKED';
  if(headers['cf-mitigated']==='challenge'||(!native||/cloudflare/i.test(headers.server??''))&&challengePage(native?body.slice(0,4096):body))return 'CLOUDFLARE';
}
