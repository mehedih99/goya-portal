/* Soft, generated tones. Audio failures never affect portal actions or saved records. */
(() => {'use strict';
 let audio=null,owner=null,preferences={notification_sound:true,attendance_sound:true,sound_volume:35},watermark=null,lastNotificationAt=-Infinity;
 const token=()=>window.GoyaStaff?._liveContext?.().token;
 const patterns={notification:[[880,0,.16]],in:[[659,0,.15],[880,.13,.2]],out:[[659,0,.16],[440,.14,.22]],error:[[220,0,.08],[220,.14,.08]]};
 async function unlock(){try{const Audio=window.AudioContext||window.webkitAudioContext;if(!Audio)return false;if(!audio||audio.state==='closed')audio=new Audio();if(audio.state==='suspended')await audio.resume();return audio.state==='running';}catch{return false;}}
 function configure(value,staff){if(staff!==owner){owner=staff;watermark=null;lastNotificationAt=-Infinity;}preferences={notification_sound:value?.notification_sound!==false,attendance_sound:value?.attendance_sound!==false,sound_volume:Number.isFinite(Number(value?.sound_volume))?Math.max(0,Math.min(100,Number(value.sound_volume))):35};}
 function play(kind,preview=false){try{if(!token()||!owner||!audio||audio.state!=='running'||!patterns[kind]||preferences.sound_volume<=0)return false;if(!preview&&!(kind==='notification'?preferences.notification_sound:preferences.attendance_sound))return false;
  const start=audio.currentTime,level=.12*preferences.sound_volume/100;
  for(const [frequency,delay,duration] of patterns[kind]){const oscillator=audio.createOscillator(),gain=audio.createGain(),at=start+delay;oscillator.type='sine';oscillator.frequency.setValueAtTime(frequency,at);gain.gain.setValueAtTime(.0001,at);gain.gain.exponentialRampToValueAtTime(Math.max(.0002,level),at+.012);gain.gain.exponentialRampToValueAtTime(.0001,at+duration);oscillator.connect(gain);gain.connect(audio.destination);oscillator.onended=()=>{oscillator.disconnect();gain.disconnect();};oscillator.start(at);oscillator.stop(at+duration+.02);}return true;
 }catch{return false;}}
 function observe(feed){try{if(feed?.staff_id!==owner)return;const latest=Number(feed.max_id)||0;if(watermark===null){watermark=latest;return;}const old=watermark;watermark=Math.max(watermark,latest);if(latest<=old||document.hidden||!feed.items?.some(n=>Number(n.id)>old&&!n.read_at)||Date.now()-lastNotificationAt<5000)return;
  let previous=null;try{previous=JSON.parse(localStorage.getItem('goya-notification-sound:'+owner)||'null');}catch{}if(Number(previous?.id)>=latest)return;
  if(play('notification')){lastNotificationAt=Date.now();try{localStorage.setItem('goya-notification-sound:'+owner,JSON.stringify({id:latest}));}catch{}}
 }catch{}}
 async function test(kind){if(!token()||!owner)return false;if(!await unlock())return false;return play(kind,true);}
 for(const event of ['pointerdown','keydown'])document.addEventListener(event,e=>{if(e.isTrusted)void unlock();},{capture:true,passive:true});
 window.GoyaStaffSounds={configure,observe,play,test};
})();
