import {parseBlockRule} from './block-rules.js';
import {blockPresets} from './block-presets.js';
import {domainOrder, languages, sourceProtocol} from './public-contract.js';
/** Shared defaults and validation for editable Web preferences. */
export const preferenceDefinitions = {
  seedColor:{default:0xFFC96442,min:0,max:0xffffffff},gridColumns:{default:0,choices:[0,2,3,4]},albumColumns:{default:3,choices:[1,2,3,4,5,6]},albumCollapsed:{default:false},
  domainOrder:{default:[] as string[]},homeCategories:{default:[] as string[]},homeExpandedDomains:{default:[] as string[]},
  askCategoryOnFavorite:{default:false},librarySort:{default:'added',choices:['added','read','title','updated']},librarySortAsc:{default:false},libraryDisplay:{default:'grid',choices:['grid','list']},historyDisplay:{default:'list',choices:['grid','list']},downloadDisplay:{default:'list',choices:['grid','list']},libraryFilterKind:{default:'all',choices:['all',...sourceProtocol.mediaKinds]},libraryFilterSources:{default:[] as string[]},libraryFilterDownloaded:{default:false},libraryFilterUnread:{default:false},badgeUnread:{default:true},badgeDownloaded:{default:true},badgeSource:{default:true},
  libraryUpdateHours:{default:0,choices:[0,6,12,24,48,168]},updateOnlyMultiChapter:{default:true},updateSkipUnread:{default:false},updateSkipNotStarted:{default:false},autoDownloadNew:{default:false},deleteAfterRead:{default:false},autoSourceUpdates:{default:true},autoBackupHours:{default:24,choices:[0,12,24,72,168]},autoBackupKeep:{default:3,choices:[1,2,3,5,10]},
  tagDownloadIgnoredSources:{default:[] as string[]},tagDownloadReminders:{default:true},aggregateExcluded:{default:[] as string[]},blockedAuthorWorks:{default:{} as Record<string,string[]>},blockedTagAliases:{default:{} as Record<string,string[]>},blockPresets:{default:{} as Record<string,unknown>},
  autoTranslateContent:{default:false},translateTargets:{default:Object.values(languages).map(item=>item.translationId) as string[]},appLockAfter:{default:0,choices:[0,60,300,900]},danmakuArea:{default:'topHalf',choices:['topQuarter','topHalf','bottomHalf','full']},
  language:{default:'',choices:['',...Object.keys(languages)]},
  theme:{default:'dark',choices:['light','dark','system']},notificationsEnabled:{default:false},
  dataSavingMode:{default:'off',choices:['off','standard','super']},
  preloadPages: {default:4,min:0,max:10},
  shortVideoPreloadCount:{default:2,min:0,max:20},shortVideoRetainedCount:{default:2,min:0,max:5},
  readerMode: {default:'vertical',choices:['vertical','leftToRight','rightToLeft']},
  readerDual: {default:'off',choices:['off','landscape','always']},
  readerSplitWide:{default:false},readerTapLayout:{default:0,min:0,max:5},readerTapInvertH:{default:false},readerTapInvertV:{default:false},readerOrientation:{default:'auto',choices:['auto','portrait','landscape']},
  readerCoverSingle: {default:true}, readerCrop: {default:false},
  readerDim: {default:0,min:0,max:.8}, readerWarm: {default:0,min:0,max:.5},
  readerGrayscale: {default:false}, readerInvert: {default:false},
  readerBackground: {default:'black',choices:['black','gray','white']},
  readerShowPageNumber: {default:true}, readerAnimate: {default:true}, readerGap: {default:0,min:0,max:100},
  tapToPage: {default:true}, keepScreenOn: {default:true},
  novelFontSize: {default:22,min:12,max:42}, novelLineHeight: {default:1.8,min:1.2,max:2.8},
  novelLetterSpacing: {default:0,min:0,max:4}, novelMargin: {default:20,min:8,max:48},
  novelParagraphGap: {default:12,min:0,max:36}, novelFont: {default:'serif',choices:['system','serif','monospace']},
  novelBold: {default:false}, novelJustify: {default:false}, novelIndent: {default:true},
  novelTheme: {default:'paper',choices:['paper','white','green','dark','system']}, novelDim: {default:0,min:0,max:.7},
  novelMode:{default:'scroll',choices:['scroll','paged']},novelAnimate:{default:true},novelAutoScroll:{default:30,min:10,max:100},novelShowStatus:{default:true},novelTapToPage:{default:true},novelOrientation:{default:'auto',choices:['auto','portrait','landscape']},
  novelKeepScreenOn: {default:true}, novelSpeechRate: {default:1,min:.5,max:2},
  voiceBackgroundPlayback: {default:false}, playbackRate: {default:1,min:.5,max:2},
  cacheLimitMb:{default:1024,min:0,max:1048576},pdfPagesPerFile:{default:300,min:0,max:5000},
  imageConcurrency: {default:6,min:2,max:12},
  siteConcurrency: {default:3,min:1,max:8}, taskConcurrency: {default:1,min:1,max:8}, pageConcurrency: {default:3,min:1,max:8},
  subscriptionIntervalMs: {default:21600000,min:60000,max:86400000},
} as const;
export type PreferenceKey = keyof typeof preferenceDefinitions;
export const preferenceDefaults = Object.fromEntries(Object.entries(preferenceDefinitions).map(([key,value])=>[key,value.default]));
const integers=new Set(['seedColor','readerTapLayout','cacheLimitMb','pdfPagesPerFile','preloadPages','shortVideoPreloadCount','shortVideoRetainedCount','imageConcurrency','siteConcurrency','taskConcurrency','pageConcurrency','subscriptionIntervalMs']);
export function validatePreferences(values:Record<string,unknown>):void {
  for(const [key,value] of Object.entries(values)) {
    const definition=preferenceDefinitions[key as PreferenceKey];if(!definition)continue;
    if(Array.isArray(definition.default)){if(!Array.isArray(value)||value.length>1000||value.some(v=>typeof v!=='string'||!v.trim()||v.length>1024)||new Set(value).size!==value.length)throw new Error('Invalid preference: '+key);const allowed=key==='translateTargets'?Object.values(languages).map(item=>item.translationId):['domainOrder','homeCategories','homeExpandedDomains'].includes(key)?domainOrder:undefined;if(allowed&&(value as string[]).some(v=>!allowed.includes(v as never)))throw new Error('Invalid preference: '+key);continue;}
    if(key==='blockedTagAliases'||key==='blockPresets'||key==='blockedAuthorWorks'){
      const fail=()=>{throw new Error('Invalid preference: '+key);};const list=(v:unknown)=>{if(!Array.isArray(v)||v.length>1000||v.some(x=>typeof x!=='string'||!x.trim()||x.length>256))fail();};
      const map=(v:unknown)=>{if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length>1000)fail();return v as Record<string,unknown>;};
      for(const [name,item] of Object.entries(map(value))){if(name.length>256||['__proto__','constructor','prototype'].includes(name))fail();if(key!=='blockPresets'){list(item);if(key==='blockedTagAliases')parseBlockRule(name);continue;}if(!blockPresets.some(p=>p.id===name))fail();for(const [field,fieldValue]of Object.entries(map(item))){if(['on','title','strong'].includes(field)){if(typeof fieldValue!=='boolean')fail();}else if(['entries','strongEntries'].includes(field)){list(fieldValue);for(const entry of fieldValue as string[])parseBlockRule(entry);}else if(field==='aliases'){for(const [entry,aliases]of Object.entries(map(fieldValue))){parseBlockRule(entry);list(aliases);}}else fail();}}
      continue;
    }
    if(typeof value!==typeof definition.default||'choices' in definition&&!(definition.choices as readonly unknown[]).includes(value)||'min' in definition&&(typeof value!=='number'||!Number.isFinite(value)||value<definition.min||value>definition.max||integers.has(key)&&!Number.isInteger(value)))throw new Error('Invalid preference: '+key);
  }
}
