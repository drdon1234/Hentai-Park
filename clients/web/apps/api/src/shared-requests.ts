type Flight<T> = { controller: AbortController; promise: Promise<T>; users: number; settled: boolean };
const cancelled=()=>Object.assign(new Error('Request cancelled'),{code:'CANCELLED',statusCode:499,publicError:true,causeCategory:'source',retryable:false});

/** Share upstream work while retaining each caller's cancellation ownership. */
export class SharedRequests<T> {
  private readonly active=new Map<string,Flight<T>>();
  run(key:string,action:(signal:AbortSignal)=>Promise<T>,signal?:AbortSignal):Promise<T>{
    if(signal?.aborted)return Promise.reject(cancelled());
    let flight=this.active.get(key);
    if(!flight){
      const controller=new AbortController();
      flight={controller,promise:Promise.resolve().then(()=>action(controller.signal)),users:0,settled:false};
      this.active.set(key,flight);const current=flight;
      const settle=()=>{current.settled=true;if(this.active.get(key)===current)this.active.delete(key);};
      void current.promise.then(settle,settle);
    }
    const current=flight;current.users++;
    return new Promise<T>((resolve,reject)=>{
      let finished=false;
      const release=()=>{if(finished)return false;finished=true;signal?.removeEventListener('abort',abort);current.users--;if(!current.users&&!current.settled){current.controller.abort();if(this.active.get(key)===current)this.active.delete(key);}return true;};
      const abort=()=>{if(release())reject(cancelled());};
      signal?.addEventListener('abort',abort,{once:true});
      void current.promise.then(value=>{if(release())resolve(value);},error=>{if(release())reject(error);});
    });
  }
}
