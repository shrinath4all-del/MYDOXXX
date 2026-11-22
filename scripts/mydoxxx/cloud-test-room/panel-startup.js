/* Cloud-panel boot feedback only. Never handles credentials or grants access. */
(function(root, factory) {
  const api=factory();
  if(typeof module==='object'&&module.exports) module.exports=api;
  else api.install(root);
})(typeof window!=='undefined'?window:this,function(){
  'use strict';
  const ORIGIN='https://mydoxxx-live-test.netlify.app';
  const ENGINE_CONFIG=Object.freeze({canvasKitForceCpuOnly:true,canvasKitMaximumSurfaces:1});
  function monitor(report,setTimer,clearTimer){
    let state='loading',timer;
    function update(next){if(state==='ready')return;state=next;report(next);}
    report(state);
    timer=setTimer(()=>{if(state==='loading')update('slow');},45000);
    return {
      fail(){if(state==='ready')return;clearTimer(timer);update('failed');},
      ready(){if(state==='ready')return;clearTimer(timer);update('ready');},
      get state(){return state;}
    };
  }
  function install(win){
    if(win.location.origin!==ORIGIN||!['/panel/','/panel','/panel/index.html'].includes(win.location.pathname))return;
    const doc=win.document,roleKey=new URL(win.location.href).searchParams.get('role');
    const box=doc.createElement('section');box.id='bfast-panel-startup';box.setAttribute('role','status');box.setAttribute('aria-live','polite');
    box.style.cssText='position:fixed;inset:0;z-index:2147483646;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;padding:28px;box-sizing:border-box;background:#eff7f7;color:#173c49;text-align:center;font:16px/1.5 Arial,sans-serif';
    const brand=doc.createElement('strong');brand.textContent='BFAST';brand.style.cssText='font-size:30px;font-weight:900;color:#c81e32';
    const title=doc.createElement('strong'),note=doc.createElement('p'),retry=doc.createElement('button');
    note.style.cssText='margin:0;max-width:320px;font-size:14px;color:#526f7b';
    retry.type='button';retry.textContent='Retry this screen';retry.hidden=true;retry.style.cssText='padding:12px 18px;border:0;border-radius:10px;background:#087e70;color:white;font:700 15px Arial,sans-serif;cursor:pointer';
    retry.addEventListener('click',()=>win.location.reload());
    box.append(brand,title,note,retry);doc.body.append(box);doc.getElementById('bfast-panel-fallback')?.remove();
    function report(state){
      if(state==='ready')box.remove();
      else{
        title.textContent=state==='loading'?'Loading your app…':state==='slow'?'This screen is taking longer to load':'This screen could not start';
        note.textContent=state==='loading'?'Preparing the secure test screen. Your other screens can stay open.':state==='slow'?'The app download or connection is slow. You can keep waiting, or retry only this screen.':'Check your connection and retry this screen. Your other sessions are unchanged.';
        retry.hidden=state==='loading';
      }
      if(win.parent!==win)win.parent.postMessage({type:'mydox:panel-status',roleKey,state},ORIGIN);
    }
    const boot=monitor(report,win.setTimeout.bind(win),win.clearTimeout.bind(win));
    win.addEventListener('flutter-first-frame',()=>boot.ready());
    win.addEventListener('error',event=>{
      const src=event.target&&event.target.src;
      if(event.target===win||(typeof src==='string'&&/\/(?:main\.dart|flutter_bootstrap|panel-bridge)\.js(?:\?|$)/.test(src)))boot.fail();
    },true);
    win.addEventListener('unhandledrejection',()=>boot.fail());
    win.MyDoxPanelStartup=Object.freeze({
      async startEngine(initializer){
        try{const runner=await initializer.initializeEngine({...ENGINE_CONFIG});await runner.runApp();}
        catch(_){boot.fail();}
      }
    });
    return boot;
  }
  return {monitor,install,ENGINE_CONFIG};
});
