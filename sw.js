const CACHE_NAME='ammir-shell-v7-ancient-geometry';
const APP_SHELL=['/','/index.html','/manifest.webmanifest','/icon.svg','/ammir-identity.css','/ammar-marketplace.js'];
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
  event.respondWith(fetch(request).then(async response=>{
   if(!response.ok)return response;
   const html=await response.text();
   const injected=html.replace('</head>','<link rel="stylesheet" href="/ammir-identity.css"><link rel="apple-touch-icon" sizes="any" href="/icon.svg"><meta name="mobile-web-app-capable" content="yes"></head>');
   const enhanced=new Response(injected,{status:response.status,statusText:response.statusText,headers:new Headers(response.headers)});
   const copy=enhanced.clone();caches.open(CACHE_NAME).then(cache=>cache.put('/index.html',copy));
   return enhanced;
  }).catch(()=>caches.match('/index.html')));
  return;
 }
 event.respondWith(caches.match(request).then(cached=>cached||fetch(request).then(response=>{
  if(response.ok){const copy=response.clone();caches.open(CACHE_NAME).then(cache=>cache.put(request,copy));}
  return response;
 })));
});