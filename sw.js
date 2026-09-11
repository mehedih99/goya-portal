/* Goya Staff PWA shell: intentionally network-first to avoid stale production code. */
const VERSION='goya-staff-v24';
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET') return;
  event.respondWith(fetch(event.request,{cache:'no-store'}).catch(()=>fetch(event.request)));
});
