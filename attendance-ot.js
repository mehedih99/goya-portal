/* Shared OT calculation. Punch timestamps and actual working/net duration are never changed. */
(()=>{'use strict';
 function totals(row,rules={},now=Date.now()){
  const sessions=[...(row.sessions||[])].filter(s=>s.check_in_at).sort((a,b)=>Date.parse(a.check_in_at)-Date.parse(b.check_in_at));
  let sec=0,credited=0;const policy=row.ot_policy,modern=policy?.version===1;
  const regular=Math.max(1,Number(modern?policy.regular_minutes:rules.regular_net_minutes)||480),breakMinutes=Math.max(0,Number((modern?policy.break_minutes:rules.break_minutes)??60)),open=sessions.some(s=>!s.check_out_at),breakTaken=rules.force_no_break&&open?false:row.break_taken!==false,target=regular+(breakTaken?breakMinutes:0);
  for(let index=0;index<sessions.length;index++){
   const s=sessions[index],start=Date.parse(s.check_in_at),end=s.check_out_at?Date.parse(s.check_out_at):now;if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start)continue;sec+=(end-start)/1000;
   let otStart=start;
   if(modern&&index===0){
    const localDate=row.operational_date||new Date(start).toLocaleDateString('en-CA',{timeZone:'Asia/Dubai'});let schedule=row.scheduled_start;
    if(!schedule){let closest=null;for(const time of rules.shift_start_times||['08:00','09:00','10:00','11:00','12:00','13:00','14:00','15:00','16:00','17:00']){const at=Date.parse(localDate+'T'+String(time).slice(0,5)+':00+04:00'),distance=Math.abs(at-start);if(distance<=1800000&&(!closest||distance<closest.distance||(distance===closest.distance&&at>closest.at)))closest={at,distance};}if(closest)schedule=new Date(closest.at+14400000).toISOString().slice(11,16);}
    if(schedule){const scheduled=Date.parse(localDate+'T'+String(schedule).slice(0,5)+':00+04:00'),early=(scheduled-start)/1000;if(early>0&&early<=Number(policy.early_grace_minutes??30)*60)otStart=scheduled;}
   }
   credited+=Math.max(0,(end-otStart)/1000);
  }
  const net=Math.max(0,sec/60-(breakTaken?breakMinutes:0)),rawSeconds=Math.max(0,credited-target*60),rawMinutes=Math.floor(rawSeconds/60),enabled=!modern||policy.enabled!==false,ot=enabled&&(!modern||rawMinutes>Number(policy.grace_minutes??30))?rawMinutes:0;
  return {sec,net,ot,target,work:sec/60,breakTaken,creditedSeconds:credited,remainingSeconds:Math.max(0,target*60-credited),remaining:Math.max(0,target-credited/60),liveOtSeconds:ot?rawSeconds:0,liveOt:ot?rawSeconds/60:0,otEnabled:enabled,otPolicy:modern,otDisabled:modern&&!enabled};
 }
 window.GoyaOT={totals};
})();
