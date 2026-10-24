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

self.addEventListener('push',event=>{let msg={};try{msg=event.data?.json()||{};}catch{}
 event.waitUntil(self.registration.showNotification(String(msg.title||'GOYA reminder'),{body:String(msg.body||'Open your staff portal.'),icon:'goya-icon-192.png',badge:'goya-icon-192.png',tag:String(msg.tag||'goya-duty'),data:{url:'staff.html'}}));
});
self.addEventListener('notificationclick',event=>{event.notification.close();event.waitUntil((async()=>{const url=new URL('staff.html',self.registration.scope).href;const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});for(const w of windows){if(w.url.startsWith(self.registration.scope)&&w.url.includes('staff.html'))return w.focus();}return self.clients.openWindow(url);})());});
