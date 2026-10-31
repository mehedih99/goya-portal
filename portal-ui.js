/* Shared presentation only. Never loaded by Goya Live. */
(() => {
'use strict';
const root=document.documentElement,key='goya-theme',installedKey=/\/admin\.html$/.test(location.pathname)?'goya-admin-app-installed':'goya-app-installed';
const read=k=>{try{return localStorage.getItem(k)}catch{return null}},write=(k,v)=>{try{localStorage.setItem(k,v)}catch{}};
const system=matchMedia('(prefers-color-scheme: dark)');let choice=read(key)||'auto',promptEvent=null,pending=0,installed=read(installedKey)==='yes';
const standalone=()=>matchMedia('(display-mode: standalone)').matches||matchMedia('(display-mode: minimal-ui)').matches||navigator.standalone===true;
function apply(){root.dataset.theme=choice==='auto'?(system.matches?'dark':'light'):choice;root.style.colorScheme=root.dataset.theme;document.querySelector('meta[name="theme-color"]')?.setAttribute('content',root.dataset.theme==='dark'?'#0c1624':'#f2f5f6');}
if(!['auto','light','dark'].includes(choice))choice='auto';apply();system.addEventListener?.('change',()=>{if(choice==='auto')apply()});
window.addEventListener('storage',e=>{if(e.key===key){choice=['auto','dark','light'].includes(e.newValue)?e.newValue:'auto';apply();document.querySelectorAll('.portal-theme').forEach(x=>x.value=choice)}});
function updateInstall(){document.querySelectorAll('.portal-install').forEach(b=>b.hidden=installed||standalone());}
window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();promptEvent=e;updateInstall()});
window.addEventListener('appinstalled',()=>{installed=true;write(installedKey,'yes');promptEvent=null;updateInstall()});
matchMedia('(display-mode: standalone)').addEventListener?.('change',updateInstall);
async function install(){if(standalone()||installed)return;if(promptEvent){const event=promptEvent;promptEvent=null;try{await event.prompt();const result=await event.userChoice;if(result.outcome==='accepted'){installed=true;write(installedKey,'yes');updateInstall()}}catch{showHelp()}return;}showHelp();}
function showHelp(){const dialog=document.getElementById('portalInstallHelp');dialog.hidden=false;dialog.querySelector('button').focus();}
function begin(label='Loading…'){pending++;const bar=document.getElementById('portalLoading');if(bar){bar.hidden=false;bar.querySelector('span:last-child').textContent=label;}let done=false;return()=>{if(done)return;done=true;pending=Math.max(0,pending-1);if(!pending&&bar)bar.hidden=true;};}
async function task(fn,label){const end=begin(label);try{return await fn()}finally{end()}}
window.GoyaUI={begin,task};
document.addEventListener('DOMContentLoaded',()=>{
const tools=document.createElement('div');tools.className='portal-tools';tools.innerHTML='<label class="portal-theme-label"><span>Theme</span><select class="portal-theme" aria-label="Color theme"><option value="auto">◐ Auto</option><option value="light">☀ Light</option><option value="dark">☾ Dark</option></select></label><button type="button" class="portal-install">↓ Install App</button>';
const header=document.querySelector('.topbar');(header||document.body).appendChild(tools);if(header){const loginTools=tools.cloneNode(true);loginTools.classList.add('portal-login-tools');document.querySelector('.login-card')?.appendChild(loginTools);}
document.querySelectorAll('.portal-theme').forEach(s=>{s.value=choice;s.addEventListener('change',()=>{choice=s.value;write(key,choice);apply();document.querySelectorAll('.portal-theme').forEach(x=>x.value=choice)})});
document.querySelectorAll('.portal-install').forEach(b=>b.addEventListener('click',install));
const help=document.createElement('div');help.id='portalInstallHelp';help.className='portal-help';help.hidden=true;help.innerHTML='<section role="dialog" aria-modal="true" aria-labelledby="portalInstallTitle"><h2 id="portalInstallTitle">Install GOYA</h2><p><b>Android / PC:</b> Open this page in Chrome or Edge, then use the browser menu → Install app / Add to Home screen.</p><p><b>iPhone / iPad:</b> Open in Safari → Share → Add to Home Screen. Enable “Open as Web App” if shown.</p><p class="muted">If you opened this link inside another app, open it in your browser first. Installation options depend on your device and browser.</p><button type="button" class="btn">Got it</button></section>';document.body.appendChild(help);
let returnFocus;document.addEventListener('click',e=>{if(e.target.closest('.portal-install'))returnFocus=e.target});function close(){help.hidden=true;returnFocus?.focus()}help.querySelector('button').onclick=close;help.addEventListener('click',e=>{if(e.target===help)close()});help.addEventListener('keydown',e=>{if(e.key==='Escape')close();if(e.key==='Tab'){e.preventDefault();help.querySelector('button').focus()}});
const bar=document.createElement('div');bar.id='portalLoading';bar.hidden=pending===0;bar.setAttribute('role','status');bar.innerHTML='<span class="portal-spinner" aria-hidden="true"></span><span>Loading…</span>';document.body.appendChild(bar);updateInstall();
if(standalone()){installed=true;write(installedKey,'yes');updateInstall();}
// A second, read-only detection helps hide the button when supported by Chromium.
if(navigator.getInstalledRelatedApps)navigator.getInstalledRelatedApps().then(apps=>{if(apps.some(a=>a.platform==='webapp')){installed=true;write(installedKey,'yes');updateInstall()}}).catch(()=>{});
});
})();
