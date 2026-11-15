/** Same normalized tap regions and spread ordering as the original reader_layout.dart. */
export function tapAction(x:number,y:number,layout:number,vertical:boolean,rtl:boolean,invertH:boolean,invertV:boolean):-1|0|1 {
 if(layout===0)layout=vertical?2:1;
 if(rtl!==invertH)x=1-x;if(invertV)y=1-y;
 const a=1/3,b=2/3,mx=x>=a&&x<=b,my=y>=a&&y<=b;
 if(layout===1)return x<a?-1:x>b?1:0;
 if(layout===2)return mx&&my?0:y<a||x<a&&y<=b?-1:1;
 if(layout===3)return y<a?0:x<a?-1:1;
 if(layout===4)return !mx?1:y>b?-1:0;
 return 0;
}
export type Spread={pages:number[];half?:'left'|'right'};
export function buildSpreads(count:number,aspects:Record<number,number>,dual:boolean,cover:boolean,split:boolean,rtl:boolean):Spread[]{
 const out:Spread[]=[];for(let i=0;i<count;){const wide=(n:number)=>(aspects[n]??0)>1;
 if(dual){if(wide(i)||cover&&i===0||i+1>=count||wide(i+1))out.push({pages:[i++]});else{out.push({pages:[i,i+1]});i+=2;}}
 else if(split&&wide(i)){out.push({pages:[i],half:rtl?'right':'left'},{pages:[i++],half:rtl?'left':'right'});}else out.push({pages:[i++]});}
 return out;
}
