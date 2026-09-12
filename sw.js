/* Goya Staff PWA shell: intentionally network-first to avoid stale production code. */
const VERSION='goya-v27-2';
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET') return;
  event.respondWith(fetch(event.request,{cache:'no-store'}).catch(()=>fetch(event.request)));
});

self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil((async()=>{const ks=await caches.keys();await Promise.all(ks.filter(k=>k!=='goya-v27-2').map(k=>caches.delete(k)));await self.clients.claim();})()));
