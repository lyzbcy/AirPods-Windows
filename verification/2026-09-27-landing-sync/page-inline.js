
/* ================= 强制刷新组件 =================
   规则：每次改页面必须更新 PAGE_VER。
   打开页面时核对远端版本号，不一致则本会话内自动强刷一次；
   用 sessionStorage 防重复刷新（刷完仍不一致就不再刷，杜绝死循环）。 */
const PAGE_VER="2.2.6";
const PAGE_LOG=[
  {v:"2.2.6",d:"09-27",t:"应用 v1.9.20 正式版：连接/断开阶段和等待原因可见，减少无声时误报可播放；首页统一问题反馈并可由用户确认附日志。偶发 Windows 蓝牙连接/播放异常及 AirPods 5 未完整验证已公开说明；应用不再自动关开整机蓝牙。"},
  {v:"2.2.4",d:"09-21",t:"应用 v1.9.12 上线：曾加入蓝牙自动自救、麦克风切换和断开核实；自动关开整机蓝牙的旧行为已在 v1.9.20 取消。"},
  {v:"2.2.3",d:"09-21",t:"应用 v1.9.10 上线：全新「问题反馈」（选类型+说明，完整日志文件直达开发者群）与「提意见」分家；AirPods 5（LE 音频）连接指引；二维码点击放大；弹窗滚动；设置保存修复"},
  {v:"2.2.2",d:"09-06",t:"新增 SmartScreen 首次运行提示说明（更多信息→仍要运行）；应用 v1.9.5 带设置项上线"},
  {v:"2.2.1",d:"08-27",t:"修复：一次误发布把本页覆盖成了简化版（静态截图），已整体回滚——恢复可交互应用界面模拟演示（连接三态/优先级排序/宠物动画/托盘演示）"},
  {v:"2.2.0",d:"08-26",t:"关于入口改为本软件专属子页 airpods-buddy-about.html（专属风格+专属反馈讨论区，通用推广页下线）"},
  {v:"2.1.0",d:"08-26",t:"应用界面改为前端模拟演示（原真实截图含真实设备名，已删除）；界面可点击：连接三态流转 + 优先级排序"},
  {v:"2.0.0",d:"08-26",t:"页面焕新：星星布丁精灵图动画演示、三态托盘图标、关于作者入口、新增一键强制刷新组件"},
  {v:"1.0.0",d:"08-19",t:"产品页首版上线"},
];

/* 更新日志渲染 */
(function(){
  const list=document.getElementById('frList');
  document.getElementById('frLabel').textContent='更新 '+PAGE_LOG[0].d;
  list.innerHTML=PAGE_LOG.map(x=>
    `<li><span class="v">v${x.v}</span><span class="d">${x.d}</span><br>${x.t}</li>`).join('');
  const btn=document.getElementById('frLogBtn'),panel=document.getElementById('frPanel');
  btn.addEventListener('click',e=>{e.stopPropagation();
    panel.hidden=!panel.hidden;btn.setAttribute('aria-expanded',String(!panel.hidden));});
  document.addEventListener('click',e=>{if(!panel.hidden&&!panel.contains(e.target))panel.hidden=true;});
})();

/* toast */
let frToastT=null;
function frToast(msg){
  const t=document.getElementById('frToast');t.textContent=msg;t.classList.add('show');
  clearTimeout(frToastT);frToastT=setTimeout(()=>t.classList.remove('show'),2200);
}

/* 一键刷新：先绕过缓存取一次本页（更新浏览器缓存），再整体重载 */
document.getElementById('frRefresh').addEventListener('click',async function(){
  const btn=this;btn.classList.remove('spin');void btn.offsetWidth;btn.classList.add('spin');
  frToast('⚡ 正在强制刷新…');
  try{await fetch(location.pathname,{cache:'reload'});}catch(e){}
  setTimeout(()=>location.reload(),250);
});

/* 打开时核对远端版本号（本地 file:// 预览跳过） */
(async function(){
  try{
    if(location.protocol==='file:')return;
    const res=await fetch(location.pathname+'?_vc='+Date.now(),{cache:'no-store'});
    const html=await res.text();
    const m=html.match(/PAGE_VER\s*=\s*"([^"]+)"/);
    if(!m||m[1]===PAGE_VER)return;                 /* 版本一致，无需刷新 */
    const key='ab_autorefreshed_'+m[1];
    if(sessionStorage.getItem(key))return;         /* 本会话已自动刷过仍不一致：不再刷，防死循环 */
    sessionStorage.setItem(key,'1');
    frToast('🆕 检测到新版本 v'+m[1]+'，正在刷新…');
    setTimeout(()=>location.replace(location.pathname+'?v='+encodeURIComponent(m[1])),600);
  }catch(e){/* 静默：离线/本地环境不打扰 */}
})();

/* ================= 滚动渐入 ================= */
(function(){
  const io=new IntersectionObserver(es=>es.forEach(e=>{
    if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target);}
  }),{threshold:.12});
  document.querySelectorAll('.rv').forEach(el=>io.observe(el));
})();

/* ================= 星星布丁宠物演示 =================
   精灵图 1536x1248（8 列 x 6 行），显示格 120x130（整体 0.625 缩放）
   行序：0 idle | 1 waving | 2 jumping | 3 failed | 4 waiting | 5 review
   帧时长与应用内 pet.html 完全一致 */
const PET_ROWS={
  idle:{row:0,frames:[280,110,110,140,140,320]},
  waving:{row:1,frames:[140,140,140,280]},
  jumping:{row:2,frames:[140,140,140,140,280]},
  failed:{row:3,frames:[140,140,140,140,140,140,140,240]},
  waiting:{row:4,frames:[150,150,150,150,150,260]},
  review:{row:5,frames:[150,150,150,150,150,280]},
};
const PET_TEXT={
  connecting:{anim:'waiting',text:'连接中',dots:true,tray:'loading'},
  ok:{anim:'jumping',text:'连上啦！💕',dots:false,tray:'on'},
  disconnecting:{anim:'review',text:'断开中',dots:true,tray:'loading'},
  off:{anim:'waving',text:'已断开 💤 拜拜~',dots:false,tray:'off'},
  fail:{anim:'failed',text:'没连上 QAQ',dots:false,tray:'off'},
  idle:{anim:'idle',text:'我在呢',dots:false,tray:'off'},
};
const FW=120,FH=130;
let petTimer=null,petFrame=0,petRow=0,autoTimer=null;
const sprite=document.getElementById('petSprite'),
      bubble=document.getElementById('petBubble'),
      stage=document.getElementById('petStage'),
      card=document.getElementById('petCard'),
      trayImg=document.getElementById('deskTrayImg');
const TRAY={off:'assets/img/airpods-buddy/tray-off.png',on:'assets/img/airpods-buddy/tray-on.png',
  loading:'assets/img/airpods-buddy/tray-loading-0.png'};
let loadingFrame=0;

function petPlayRow(name){
  const r=PET_ROWS[name];if(!r)return;
  petRow=r.row;petFrame=0;clearTimeout(petTimer);
  (function tick(){
    sprite.style.backgroundPosition=`-${petFrame*FW}px -${petRow*FH}px`;
    const d=r.frames[petFrame];
    petFrame=(petFrame+1)%r.frames.length;
    petTimer=setTimeout(tick,d);
  })();
}
function petHearts(n){
  for(let i=0;i<n;i++)setTimeout(()=>{
    const h=document.createElement('span');h.className='pet-heart';
    h.textContent=Math.random()<.5?'💕':'✨';
    h.style.left=(30+Math.random()*110)+'px';h.style.top=(80+Math.random()*30)+'px';
    card.appendChild(h);setTimeout(()=>h.remove(),1500);
  },i*160);
}
function petSetState(state){
  const cfg=PET_TEXT[state]||PET_TEXT.idle;
  /* 重新弹出一次，还原「从右下角弹出来」的手感 */
  stage.className='pet-stage';void stage.offsetWidth;stage.classList.add('in');
  petPlayRow(cfg.anim);
  bubble.className='pet-bubble'+(cfg.dots?' dots':'');
  bubble.textContent=cfg.text;
  if(state==='ok')petHearts(4);
  /* 托盘图标同步三态 */
  if(cfg.tray==='loading'){trayImg.src=TRAY.loading;}   /* 由 loadingInterval 接管换帧 */
  else{trayImg.src=TRAY[cfg.tray];}
  trayImg.dataset.mode=cfg.tray;
}
/* 连接中：托盘 loading 帧动画（6 帧循环） */
setInterval(()=>{
  const t=document.getElementById('deskTrayImg');
  if(t&&t.dataset.mode==='loading'){
    loadingFrame=(loadingFrame+1)%6;
    t.src=`assets/img/airpods-buddy/tray-loading-${loadingFrame}.png`;
  }
},95);
/* 三态展示区：中问那张 loading 也一直转 */
setInterval(()=>{
  const t=document.getElementById('trayLoadingImg');
  if(t){loadingFrame=(loadingFrame+1)%6;
    t.src=`assets/img/airpods-buddy/tray-loading-${loadingFrame}.png`;}
},95);

/* 自动演示：一个小故事循环 */
function petAutoStory(){
  const seq=[['connecting',2100],['ok',2400],['idle',1800],['off',2100],['idle',1500]];
  let i=0;
  (function next(){
    if(!autoOn)return;
    petSetState(seq[i][0]);
    autoTimer=setTimeout(next,seq[i][1]);
    i=(i+1)%seq.length;
  })();
}
let autoOn=true;
const autoBtn=document.getElementById('petAutoBtn');
function setAuto(on){
  autoOn=on;autoBtn.classList.toggle('on',on);autoBtn.textContent=on?'▶ 自动演示':'⏸ 已暂停';
  if(on)petAutoStory();else clearTimeout(autoTimer);
}
autoBtn.addEventListener('click',()=>setAuto(!autoOn));
document.querySelectorAll('.pet-btn[data-state]').forEach(b=>{
  b.addEventListener('click',()=>{setAuto(false);petSetState(b.dataset.state);});
});
/* 点桌面右下角托盘 = 单击托盘连接 */
document.getElementById('deskTray').addEventListener('click',()=>{
  setAuto(false);
  petSetState(trayImg.dataset.mode==='on'?'off':'connecting');
  setTimeout(()=>{if(!autoOn&&trayImg.dataset.mode==='loading')petSetState('ok');},1900);
});

/* 启动：预载精灵图后弹出 */
const petPre=new Image();
petPre.onload=()=>{sprite.style.backgroundImage="url('assets/img/airpods-buddy/pet-sheet.webp')";petSetState('idle');petAutoStory();};
petPre.onerror=()=>{bubble.textContent='(精灵图加载失败)';};
petPre.src='assets/img/airpods-buddy/pet-sheet.webp';

/* ================= 应用界面·前端模拟演示 =================
   还原真实应用的布局手感：设备列表（优先级可调）+ 大圆连接钮三态。
   设备名均为虚构，不含任何真实信息。 */
(function(){
  const big=document.getElementById('appBigBtn'),ico=document.getElementById('appBigIco'),
        lb=document.getElementById('appBigLb'),dev1=document.getElementById('dev1'),
        dev1St=document.getElementById('dev1St');
  let st='off',t=null;
  function set(s){
    st=s;clearTimeout(t);big.className='bigbtn '+s;
    if(s==='off'){ico.textContent='🔌';lb.textContent='点我连接';
      dev1.classList.remove('on');dev1St.textContent='未连接';}
    else if(s==='loading'){lb.textContent='连接中';dev1St.textContent='连接中…';}
    else{ico.textContent='💚';lb.textContent='已连接 · 点我断开';
      dev1.classList.add('on');dev1St.textContent='已连接 · A2DP';}
  }
  big.addEventListener('click',()=>{
    if(st==='off'){set('loading');t=setTimeout(()=>set('on'),1300);}
    else if(st==='on'){set('off');}
  });
  /* 优先级 ▲▼：真的会调换顺序 */
  document.querySelectorAll('#appList .op').forEach(b=>b.addEventListener('click',e=>{
    e.stopPropagation();
    const li=b.closest('.dev'),list=document.getElementById('appList');
    const items=[...list.children],i=items.indexOf(li);
    const j=b.dataset.mv==='up'?i-1:i+1;
    if(j<0||j>=items.length)return;
    li.classList.add('ghosted');
    setTimeout(()=>{
      b.dataset.mv==='up'?list.insertBefore(li,items[j]):list.insertBefore(items[j],li);
      li.classList.remove('ghosted');
    },140);
  }));
  /* 刷新按钮：转一圈 + 列表闪一下 */
  const rf=document.getElementById('appRefresh');
  rf.addEventListener('click',()=>{
    rf.classList.remove('spin');void rf.offsetWidth;rf.classList.add('spin');
    [...document.getElementById('appList').children].forEach(li=>{
      li.classList.add('ghosted');setTimeout(()=>li.classList.remove('ghosted'),420);});
  });
})();
