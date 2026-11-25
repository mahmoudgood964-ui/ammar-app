const CACHE_NAME='ammir-shell-v11-shell-only';
const APP_SHELL=['/','/index.html','/manifest.webmanifest','/icon.svg','/icon-192.png','/icon-512.png','/ammir-identity.css','/ammar-marketplace.js'];
const APP_SHELL_PATHS=new Set(APP_SHELL);
self.addEventListener('install',event=>{
 event.waitUntil(caches.open(CACHE_NAME).then(cache=>cache.addAll(APP_SHELL)).then(()=>self.skipWaiting()));
});
self.addEventListener('activate',event=>{
 event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE_NAME).map(key=>caches.delete(key)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch',event=>{
 const request=event.request;
 if(request.method!=='GET')return;
 const url=new URL(request.url);
 if(url.origin!==self.location.origin)return;
 if(request.mode==='navigate'){
  if(url.pathname!=='/'&&url.pathname!=='/index.html')return;
  event.respondWith(fetch(request).then(response=>{
   if(response.ok&&/text\/html/i.test(response.headers.get('content-type')||'')){
    const copy=response.clone();
    caches.open(CACHE_NAME).then(cache=>cache.put('/index.html',copy));
   }
   return response;
  }).catch(()=>caches.match('/index.html')));
  return;
 }
 if(!APP_SHELL_PATHS.has(url.pathname))return;
 event.respondWith(caches.match(url.pathname).then(cached=>cached||fetch(request).then(response=>{
  if(response.ok){const copy=response.clone();caches.open(CACHE_NAME).then(cache=>cache.put(url.pathname,copy));}
  return response;
 })));
});
