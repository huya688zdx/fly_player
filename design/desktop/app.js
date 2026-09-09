/* ============================================================
   飞翔播放器 · Windows 桌面端原型交互
   路由 / 分屏 / 播放器 / 主题 —— 均对应真实代码中的既有逻辑
   ============================================================ */
'use strict';

/* ---------- 图标库（stroke 风格） ---------- */
const ICONS = {
  film:'<rect x="2.5" y="4" width="19" height="16" rx="2.5"/><path d="M7.5 4v16M16.5 4v16M2.5 9.5h5M2.5 14.5h5M16.5 9.5h5M16.5 14.5h5"/>',
  monitor:'<rect x="2.5" y="4" width="19" height="13" rx="2"/><path d="M9 21h6M12 17v4"/>',
  search:'<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.2-4.2"/>',
  heart:'<path d="M12 20.5S3.5 15.4 3.5 9.6C3.5 6.9 5.6 5 8 5c1.7 0 3.2.9 4 2.3C12.8 5.9 14.3 5 16 5c2.4 0 4.5 1.9 4.5 4.6 0 5.8-8.5 10.9-8.5 10.9z"/>',
  heartFill:'<path d="M12 20.5S3.5 15.4 3.5 9.6C3.5 6.9 5.6 5 8 5c1.7 0 3.2.9 4 2.3C12.8 5.9 14.3 5 16 5c2.4 0 4.5 1.9 4.5 4.6 0 5.8-8.5 10.9-8.5 10.9z" fill="currentColor" stroke="none"/>',
  download:'<path d="M12 3v11M7.5 10.5L12 15l4.5-4.5M4 19.5h16"/>',
  sliders:'<path d="M4 21v-6M4 11V3M12 21v-9M12 8V3M20 21v-4M20 13V3M1.5 15h5M9.5 8h5M17.5 17h5"/>',
  columns:'<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M12 4v16"/>',
  play:'<path d="M7 4.8v14.4c0 .8.9 1.3 1.6.9l11-7.2c.6-.4.6-1.4 0-1.8l-11-7.2c-.7-.4-1.6.1-1.6.9z" fill="currentColor" stroke="none"/>',
  pause:'<rect x="6" y="4.5" width="4" height="15" rx="1.2" fill="currentColor" stroke="none"/><rect x="14" y="4.5" width="4" height="15" rx="1.2" fill="currentColor" stroke="none"/>',
  prev:'<path d="M18 5.5v13L8.5 12z" fill="currentColor" stroke="none"/><rect x="5" y="5" width="2.4" height="14" rx="1" fill="currentColor" stroke="none"/>',
  next:'<path d="M6 5.5v13L15.5 12z" fill="currentColor" stroke="none"/><rect x="16.6" y="5" width="2.4" height="14" rx="1" fill="currentColor" stroke="none"/>',
  check:'<path d="M4.5 12.5l5 5L19.5 7"/>',
  plus:'<path d="M12 5v14M5 12h14"/>',
  dots:'<circle cx="12" cy="5" r="1.7" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.7" fill="currentColor" stroke="none"/><circle cx="12" cy="19" r="1.7" fill="currentColor" stroke="none"/>',
  chat:'<path d="M4 5.5h16v10.5H10L5.5 20v-4H4z"/><path d="M8 9.5h8M8 12.5h5"/>',
  cc:'<rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M10 10.5c-.5-.8-1.4-1.2-2.3-1.2-1.7 0-2.9 1.2-2.9 2.7s1.2 2.7 2.9 2.7c.9 0 1.8-.4 2.3-1.2M19 10.5c-.5-.8-1.4-1.2-2.3-1.2-1.7 0-2.9 1.2-2.9 2.7s1.2 2.7 2.9 2.7c.9 0 1.8-.4 2.3-1.2"/>',
  wave:'<path d="M3 12h2.5l2-6 3 12 3-9 2 3H21"/>',
  volume:'<path d="M4 9.5v5h3.5L12 18.5v-13L7.5 9.5z" fill="currentColor" stroke="none"/><path d="M15.5 9a4.2 4.2 0 0 1 0 6M18 6.7a7.6 7.6 0 0 1 0 10.6"/>',
  mute:'<path d="M4 9.5v5h3.5L12 18.5v-13L7.5 9.5z" fill="currentColor" stroke="none"/><path d="M16 9.5l5 5M21 9.5l-5 5"/>',
  speed:'<circle cx="12" cy="12" r="8.5"/><path d="M12 12l4.2-4.2M12 6.8v1.2M17.2 12H16M8 12H6.8"/>',
  grid:'<rect x="3.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="13.5" width="7" height="7" rx="1.5"/>',
  expand:'<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>',
  camera:'<rect x="3" y="7" width="18" height="13" rx="2.5"/><circle cx="12" cy="13.5" r="3.5"/><path d="M8.5 7l1.2-2.5h4.6L15.5 7"/>',
  pip:'<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><rect x="12" y="11" width="7" height="6" rx="1.5" fill="currentColor" stroke="none"/>',
  star:'<path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z" fill="currentColor" stroke="none"/>',
  starLine:'<path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/>',
  folder:'<path d="M3 7.5A2 2 0 0 1 5 5.5h4l2 2.2h8a2 2 0 0 1 2 2v8.8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  refresh:'<path d="M20 12a8 8 0 1 1-2.3-5.6M20 3.5V8h-4.5"/>',
  chevR:'<path d="M9.5 5.5l6.5 6.5-6.5 6.5"/>',
  chevL:'<path d="M14.5 5.5L8 12l6.5 6.5"/>',
  x:'<path d="M6 6l12 12M18 6L6 18"/>',
  info:'<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 7.8v.4"/>',
  keyboard:'<rect x="2.5" y="6" width="19" height="12" rx="2"/><path d="M6 10h.5M9.5 10h.5M13 10h.5M16.5 10h.5M6.5 14.5h11"/>',
  list:'<path d="M8.5 6h12M8.5 12h12M8.5 18h12"/><circle cx="4" cy="6" r="1.2" fill="currentColor" stroke="none"/><circle cx="4" cy="12" r="1.2" fill="currentColor" stroke="none"/><circle cx="4" cy="18" r="1.2" fill="currentColor" stroke="none"/>',
  eye:'<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
  chart:'<path d="M4 20V10M10 20V4M16 20v-8M21 20H3"/>',
  trash:'<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13"/>',
  pauseC:'<circle cx="12" cy="12" r="8.5"/><path d="M10 9v6M14 9v6"/>',
  playC:'<circle cx="12" cy="12" r="8.5"/><path d="M10 8.5l6 3.5-6 3.5z" fill="currentColor" stroke="none"/>',
};
const icon = (n, w=1.6) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${ICONS[n]||''}</svg>`;
const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];

/* ---------- 静态图标注水 ---------- */
$$('[data-ic]').forEach(el => el.innerHTML = icon(el.dataset.ic));
(function hydrate(){
  const map = [
    ['#btnShortcuts','keyboard'], ['#btnRefresh','refresh'],
    ['#paneClose','x'], ['#scClose','x'],
    ['#plBack','chevL'], ['#plPrev','prev'], ['#plNext','next'],
    ['#plMute','volume'], ['#plDmSet','chat'], ['#plEpBtn','list'], ['#plFull','expand'],
    ['#plBigPlay','play'], ['#plPlay','pause'],
  ];
  map.forEach(([s,n]) => { const el = $(s); if (el) el.innerHTML = icon(n); });
  $$('.icon-btn').forEach(el => {
    if (el.querySelector('svg')) return;
    const t = el.getAttribute('title') || '';
    el.innerHTML = icon(el.hasAttribute('data-back') || t.includes('返回') ? 'chevL' : t.includes('更多') ? 'dots' : t.includes('网格') ? 'grid' : 'dots');
  });
  const cap = $('#plTbtn[title="截图"]'); if (cap) cap.innerHTML = icon('camera');
  const pip = $('#plTbtn[title="小窗"]'); if (pip) pip.innerHTML = icon('pip');
  $$('.pl-btn').forEach(el => {
    if (el.querySelector('svg') || el.querySelector('.pl-lb')) return;
    const t = el.getAttribute('title') || '';
    el.innerHTML = icon(t.includes('字幕') ? 'cc' : t.includes('音轨') ? 'wave' : t.includes('设置') ? 'sliders' : 'dots');
  });
})();

/* ============================================================
   数据（模拟 NAS 媒体库）
   ============================================================ */
const ITEMS = [
  {id:'mv_dune', type:'movie', title:'沙丘哨兵', en:'DUNE SENTINEL', year:2025, rating:8.2, quality:'4K', hue:[207,28], region:'美国', dur:'166分钟', studio:'传奇影业', tags:['科幻','冒险','史诗'], progress:.62, dl:true, fav:true,
   desc:'厄拉科斯的沙暴尚未平息，一名年轻的哨兵在帝国与姐妹会的夹缝中发现了一条足以改写星际秩序的古老航道。沙海之下，沉睡的引擎正在苏醒。',
   credits:[['丹尼斯·维伦纽瓦','导演',24],['提莫西·查拉梅','主演',32],['赞达亚','主演',350],['丽贝卡·弗格森','主演',280],['哈维尔·巴登','主演',18],['斯特兰·斯卡斯加德','主演',210]]},
  {id:'mv_fog', type:'movie', title:'雾海灯塔', en:'THE FOG HORN', year:2024, rating:7.9, quality:'DV', hue:[196,218], region:'英国', dur:'128分钟', studio:'A24', tags:['悬疑','剧情'], progress:.18, fav:true,
   desc:'北纬五十八度的孤岛上，守塔人在雾季最深处接收到一段不该存在的求救信号——发报的时间戳，来自四十年后。',
   credits:[['夏洛特·威尔斯','导演',200],['比尔·奈伊','主演',40],['乔安娜·斯卡利特','主演',320]]},
  {id:'mv_echo', type:'movie', title:'回声频率', en:'ECHO FREQUENCY', year:2026, rating:7.4, quality:'4K', hue:[268,305], region:'中国', dur:'118分钟', studio:'不止空间', tags:['科幻','悬疑'],
   desc:'一座废弃的射电望远镜阵列在午夜自动开机，接收到的信号被解码成每个收听者自己童年的声音。', credits:[['林一舟','导演',260],['沈遇','主演',190],['江离','主演',320],['白川','配角',150]]},
  {id:'mv_night', type:'movie', title:'夜航西飞', en:'NIGHT COURIER', year:2023, rating:8.5, quality:'4K', hue:[32,12], region:'法国', dur:'142分钟', studio:'高蒙', tags:['犯罪','剧情'], progress:.95,
   desc:'一名只在夜间工作的信使，因为送错了一只手提箱，被卷入横跨三个国家的黄金走私网。', credits:[['克莱尔·德尼','导演',30],['文森特·林顿','主演',44],['艾莎·哈特曼','主演',300]]},
  {id:'mv_ember', type:'movie', title:'银翼余烬', en:'ASHES OF STEEL', year:2025, rating:7.8, quality:'DV', hue:[338,290], region:'美国', dur:'134分钟', tags:['动作','科幻'], fav:true,
   desc:'在复制人战争结束的第十二年，一名退役的银翼守卫接到了最后一单任务：回收自己的记忆。', credits:[['丹尼斯·维伦纽瓦','导演',24],['安娜·德·阿玛斯','主演',44],['瑞恩·高斯林','主演',210]]},
  {id:'mv_deepspace', type:'movie', title:'深空驿站', en:'DEEP HAVEN', year:2026, rating:8.1, quality:'4K', hue:[186,158], region:'美国', dur:'121分钟', tags:['科幻'],
   desc:'木星轨道上最后一座有人值守的驿站，迎来了它关闭前的最后一位客人——而这位客人声称自己来自驿站关闭之后。', credits:[['林一舟','导演',260],['陆桥','主演',150],['顾声','主演',290]]},
  {id:'mv_paper', type:'movie', title:'纸间岁月', en:'PAPER YEARS', year:2024, rating:7.2, quality:'1080p', hue:[42,18], region:'中国', dur:'106分钟', tags:['文艺'],
   desc:'一家即将拆迁的旧书店，店主决定用最后三十天，把每一本卖出去的书的故事都讲完。', credits:[['是枝裕和','导演',210],['树木希林','主演',40]]},
  {id:'mv_garden', type:'movie', title:'迷园', en:'GARDEN LABYRINTH', year:2026, rating:7.7, quality:'DV', hue:[128,160], region:'日本', dur:'112分钟', tags:['悬疑'],
   desc:'园艺师受雇修复一座百年迷宫花园，却在图纸夹层里发现了上一任园艺师未寄出的忏悔信。', credits:[['滨口龙介','导演',190],['黑木华','主演',320]]},
  {id:'doc_blue', type:'movie', title:'蓝色深海', en:'BLUE ABYSS', year:2025, rating:8.9, quality:'4K', hue:[188,212], region:'英国', dur:'98分钟', tags:['纪录片'],
   desc:'跟随深海探测器下潜一万零九百米，记录人类从未见过的发光生物群落。', credits:[['BBC 工作室','出品',210]]},
  {id:'tv_ferry', type:'tv', title:'长风渡口', en:'FERRY AT DAWN', year:2024, rating:9.1, quality:'4K', hue:[152,186], region:'中国', tags:['剧情','年代'], seasons:3, eps:[12,8,10], fav:true, nextEp:{s:1,e:4}, cur:{s:1,e:3,p:.34},
   desc:'九十年代末的南方小城，一座老渡口迎来它作为交通枢纽的最后十年。三条人生轨迹在雾气与汽笛声里交织：守渡人、下海的船长、和第一个考出去又回来的年轻人。',
   credits:[['辛爽','导演',220],['范伟','主演',40],['秦昊','主演',200],['陈明昊','主演',310],['刘琳','主演',140]]},
  {id:'tv_star', type:'tv', title:'星丛', en:'CONSTELLATA', year:2026, rating:8.3, quality:'4K', hue:[258,224], region:'美国', tags:['科幻','悬疑'], seasons:2, eps:[10,10], nextEp:{s:1,e:2},
   desc:'人类首次接收到系外星图，而星图上被圈出的坐标，正是两百年后才会建成的空间站。', credits:[['林一舟','导演',260],['沈遇','主演',190]]},
  {id:'tv_snow', type:'tv', title:'雪线', en:'SNOW LINE', year:2025, rating:8.8, quality:'DV', hue:[204,236], region:'中国', tags:['剧情','登山'], seasons:2, eps:[12,8], fav:true, cur:{s:2,e:5,p:.78}, dl:true,
   desc:'一支民间救援队在七千米雪线之上的十二年。每一次冲顶都是与遗愿的谈判。', credits:[['顾声','导演',290],['陆桥','主演',150],['白川','主演',150]]},
  {id:'tv_mist', type:'tv', title:'迷雾边界', en:'MIST BORDER', year:2026, rating:8.0, quality:'4K', hue:[232,318], region:'美国', tags:['科幻','惊悚'], seasons:1, eps:[8], nextEp:{s:1,e:3},
   desc:'小镇周围升起永不消散的雾墙，雾外传来的广播用的是镇上消失者的声音。', credits:[['沈遇','导演',190],['江离','主演',320]]},
  {id:'tv_riverside', type:'tv', title:'山河故人', en:'OLD RIVERS', year:2022, rating:9.0, quality:'1080p', hue:[88,62], region:'中国', tags:['剧情'], seasons:4, eps:[20,22,18,16], fav:true,
   desc:'一条内河航运家族四代人的编年史，从木船到货轮，从黄昏到清晨。', credits:[['贾樟柯','导演',30],['赵涛','主演',44]]},
  {id:'tv_north', type:'tv', title:'北线', en:'NORTHERN LINE', year:2025, rating:7.9, quality:'4K', hue:[220,190], region:'挪威', tags:['犯罪'], seasons:1, eps:[10],
   desc:'北极圈铁路沿线的连环失踪案，所有线索都指向一列从未存在过的夜班车。', credits:[['白川','导演',150],['陆桥','主演',150]]},
  {id:'tv_house', type:'tv', title:'老宅', en:'THE OLD HOUSE', year:2023, rating:7.6, quality:'1080p', hue:[18,348], region:'中国', tags:['悬疑'], seasons:1, eps:[16],
   desc:'一栋待拆迁的民国老宅，每个住过它的家庭都留下了一段没能讲完的录音。', credits:[['顾声','导演',290]]},
];
const byId = id => ITEMS.find(i => i.id === id);

const EP_TITLES = ['渡口','风起','夜潮','归人','旧约','暗流','白露','惊蛰','长夜','破晓','川上','远行','雾灯','候鸟','汛期','靠岸'];
function epsFor(item, s){
  const n = item.eps ? item.eps[s-1] : 10;
  return Array.from({length:n}, (_,k) => {
    const e = k+1, seed = (s*31+e*7) % 100;
    let state='new', part=0;
    if (item.cur && item.cur.s===s && item.cur.e===e){ state='part'; part=item.cur.p; }
    else if (seed < 46) { state='done'; }
    else if (seed < 58) { state='part'; part=(seed%40)/100+.08; }
    return {n:e, title: item.epTitles ? item.epTitles[k] : (EP_TITLES[k] || `第${e}集`), dur:'45:'+(12+seed%47).toString().padStart(2,'0'), durSec:2712+seed*7, state, part};
  });
}

const CATALOGS = [
  {name:'飞牛影库 · 电影', count:542, hues:[210,26], go:{key:'category', q:'type=movie'}},
  {name:'剧集空间', count:318, hues:[160,200], go:{key:'category', q:'type=tv'}},
  {name:'纪录片馆', count:76, hues:[190,222], go:{key:'category', q:'type=other'}},
];
const DOWNLOADS = [
  {id:'mv_dune', label:'沙丘哨兵 · 4K HDR 原盘', pct:100, status:'done', meta:['21.6 GB','HEVC · DV','剩余 --']},
  {id:'tv_snow', label:'雪线 第2季 第6集', pct:64, status:'downloading', meta:['2.1 GB','1080p','12.4 MB/s']},
  {id:'tv_star', label:'星丛 第1季 第1-2集', pct:31, status:'downloading', meta:['4.8 GB','4K','6.8 MB/s']},
  {id:'mv_garden', label:'迷园 · 1080p', pct:0, status:'paused', meta:['3.2 GB','1080p','已暂停']},
];
const HOT = ['沙丘','长风渡口','科幻','4K','悬疑','2026'];

/* ---------- 生成式海报/场景图 ---------- */
function art(hues, wide){
  const [a,b] = hues;
  return `<div class="${wide?'scene-art':'poster-art'}" style="background:
    radial-gradient(130% 85% at 82% -4%, hsla(${a},72%,62%,.6), transparent 58%),
    radial-gradient(110% 75% at 12% 108%, hsla(${b},68%,46%,.62), transparent 60%),
    radial-gradient(58% 42% at 52% 44%, hsla(${(a+b)/2},82%,58%,.34), transparent 70%),
    linear-gradient(158deg, hsl(${a},44%,17%), hsl(${b},52%,9%))"></div>`;
}
const grain = `<div class="poster-noise"></div>`;

function posterCard(it, opt={}){
  const seen = it.progress !== undefined && it.progress >= .98;
  return `<div class="card-poster" ${opt.w?`style="--w:${opt.w}px"`:''} data-detail="${it.id}" tabindex="0">
    <div class="poster">${art(it.hue)}${grain}<div class="poster-grad"></div>
      ${it.rating ? `<span class="badge-rating">${it.rating.toFixed(1)}</span>` : ''}
      ${it.quality ? `<span class="badge-quality">${it.quality}</span>` : ''}
      ${seen ? `<span class="seen-mark">${icon('check',2.4)}</span>` : ''}
      <div class="poster-sheen"></div>
      ${opt.cap ? '' : `<div class="poster-txt"><b>${it.title}</b><i>${it.en||''}</i></div>`}
    </div>
    ${opt.cap ? `<div class="bp-cap"><div class="bp-title">${it.title}</div><div class="bp-sub">${cardSub(it)}</div></div>` : ''}
  </div>`;
}
function cardSub(it){
  if (it.type==='tv'){ const t = it.eps.reduce((a,b)=>a+b,0); return `${it.year} · 共${it.seasons}季${t}集`; }
  return `${it.year} · ${(it.dur||'').replace('分钟',' min')}`;
}
function landCard(it, ctx, p, opt={}){
  return `<div class="card-land" ${opt.w?`style="--w:${opt.w}px"`:''} data-detail="${it.id}" tabindex="0">
    <div class="cl-thumb">${art(it.hue,true)}${grain}<div class="cl-shade"></div>
      <button class="cl-play" data-play="${it.id}" title="播放">${icon('play')}</button>
      ${it.dl ? `<span class="badge-dl">已下载</span>` : ''}
    </div>
    <div class="cl-body"><div class="cl-title">${it.title}</div><div class="cl-ctx">${ctx}</div>
      ${p!==undefined ? `<div class="progress"><i style="width:${(p*100).toFixed(1)}%"></i></div>` : ''}
    </div></div>`;
}
function catalogCard(c){
  return `<div class="card-catalog" data-go="#/screen/category?${c.go.q}" tabindex="0">
    <div class="cc-art">${[0,1,2].map(k => `<span style="background:
        radial-gradient(120% 90% at 70% 10%, hsla(${c.hues[0]+k*24},70%,55%,.55), transparent 65%),
        linear-gradient(165deg, hsl(${c.hues[0]+k*18},40%,20%), hsl(${c.hues[1]+k*14},45%,10%))"></span>`).join('')}</div>
    <div class="cc-name">${c.name}</div><div class="cc-count disp">${c.count} 部</div></div>`;
}
function statCard(ic, num, label, go){
  return `<div class="stat-card" ${go?`data-go="${go}"`:''}><span class="stat-ic">${icon(ic)}</span><div><b>${num}</b><i>${label}</i></div></div>`;
}
function section(title, inner, opt={}){
  const n = opt.n ? `<span class="hs-n disp">${opt.n}</span>` : '';
  const link = opt.link ? `<span class="hs-link" ${opt.go?`data-go="${opt.go}"`:''}>${opt.link} ${icon('chevR',2.2)}</span>` : '';
  return `<div class="h-section"><div class="hs-title">${title}${n}</div>${link}</div><div class="row-wrap">
    <button class="row-arrow left">${icon('chevL',2)}</button>
    <div class="row-scroll" ${opt.rows?'data-rows="'+opt.rows+'"':''}>${inner}</div>
    <button class="row-arrow right">${icon('chevR',2)}</button></div>`;
}

/* ============================================================
   首页渲染
   ============================================================ */
function renderHome(){
  const cw = [
    ['mv_dune','电影',.62], ['tv_ferry','第1季 · 第3集',.34], ['mv_fog','电影',.18], ['tv_snow','第2季 · 第5集',.78],
  ].map(([id,ctx,p]) => landCard(byId(id), ctx, p, {w:272})).join('');
  const next = [
    ['tv_ferry','第1季 · 第4集 · 已下载'],['tv_star','第1季 · 第2集'],['tv_mist','第1季 · 第3集'],['tv_riverside','第3季 · 第9集'],
  ].map(([id,ctx]) => landCard(byId(id), ctx, undefined, {w:272})).join('');
  const latest = ITEMS.slice(0,12).map(i => posterCard(i, {w:142})).join('');
  const mv = ITEMS.filter(i=>i.type==='movie').slice(0,9).map(i => posterCard(i, {w:138})).join('');
  const tv = ITEMS.filter(i=>i.type==='tv').slice(0,9).map(i => posterCard(i, {w:138})).join('');
  $('#homeSections').innerHTML =
    section('媒体库入口', CATALOGS.map(catalogCard).join('')) +
    section('继续观看', cw, {n:'4'}) +
    section('播放下一集', next, {n:'NEXT'}) +
    section('最近添加', latest, {n:'NEW', link:'全部', go:'#/screen/category?type=all'}) +
    `<div class="stat-row">${statCard('heart','24','收藏','#/screen/favorites')}${statCard('film','1,286','全部条目','#/screen/category?type=all')}${statCard('grid','542','电影','#/screen/category?type=movie')}${statCard('monitor','318','电视','#/screen/category?type=tv')}${statCard('folder','76','其他','#/screen/category?type=other')}</div>` +
    section('电影馆 · 最近入库', mv, {link:'查看全部', go:'#/screen/category?type=movie'}) +
    section('剧集连载', tv, {link:'查看全部', go:'#/screen/category?type=tv'});
}

/* ============================================================
   详情页渲染（对应 PlayDetailPage / TvDetailPage）
   ============================================================ */
function heroMeta(it){
  const parts = [];
  if (it.rating) parts.push(`<span class="gold">${icon('star',1.4)} ${it.rating.toFixed(1)}</span>`.replace('<svg',`<svg style="width:12px;height:12px;vertical-align:-1px"`));
  parts.push(`<span>${it.year}</span>`);
  (it.tags||[]).forEach(t => parts.push(`<span>${t}</span>`));
  parts.push(`<span>${it.region||''}</span>`);
  if (it.dur) parts.push(`<span>${it.dur}</span>`);
  if (it.seasons) parts.push(`<span class="hl">共 ${it.seasons} 季</span>`);
  parts.push(`<span class="hl">${it.quality} · ${it.hue && it.hue[0]>300?'杜比视界':'HDR10+'}</span>`);
  return parts.join('');
}
function actionBar(it, opt={}){
  const prog = it.progress || 0;
  const remain = opt.remainTxt || (prog>0 ? `剩余 ${Math.max(1, Math.round((1-prog)*((it.durSec||9000)/60)))} 分钟` : '');
  const label = prog>0 ? '继续播放' : (it.type==='tv' ? '播放第 1 季第 1 集' : '播放');
  return `<div class="action-bar">
    ${prog>0 ? `<div class="ab-progress"><div class="progress"><i style="width:${prog*100}%"></i></div><span class="ab-time">${remain}</span></div>` : ''}
    <div class="ab-btns">
      <button class="btn-play-main" data-play="${it.id}">${icon('play')} ${label}</button>
      <button class="circ-btn ${it.fav?'on':''}" data-fav="${it.id}" title="收藏">${icon(it.fav?'heartFill':'heart')}</button>
      <button class="circ-btn ${it.dl?'on':''}" data-dlcmd="${it.id}" title="下载">${icon('download')}</button>
      <button class="circ-btn" data-seen="${it.id}" title="标记已看">${icon('check')}</button>
    </div></div>`;
}
function creditsSec(it){
  if (!it.credits) return '';
  return `<div class="dsec"><div class="ds-title">演职员</div><div class="credits-row">${it.credits.map(([name,role,h]) =>
    `<div class="cr-item" data-toast="人物页 /detail/person（原型未实现跳转）"><div class="cr-ava" style="background:radial-gradient(120% 120% at 30% 20%,hsl(${h},60%,62%),hsl(${h+30},55%,34%))"></div><div class="cr-name">${name}</div><div class="cr-role">${role}</div></div>`).join('')}</div></div>`;
}
function linkSec(){
  return `<div class="dsec"><div class="ds-title">外部链接</div><div class="link-chips">
    <span class="link-chip" data-toast="IMDb 页面（原型）">${icon('external')} IMDb</span>
    <span class="link-chip" data-toast="TMDB 页面（原型）">${icon('external')} TMDB</span></div></div>`;
}
function renderMovie(it){
  $('#movieHeroBg').innerHTML = art(it.hue, true);
  $('#movieFloatTop .ft-title').textContent = it.title;
  $('#movieMeta').innerHTML = heroMeta(it);
  $('#movieBody').innerHTML = `
    <div class="cap-row">
      <span class="cap">${icon('cc')} 简中 · 繁中 · English</span>
      <span class="cap">${icon('wave')} TrueHD Atmos 7.1</span>
      <span class="cap">${icon('eye')} HDR10+ · ${it.hue[0]>300?'杜比视界':'广色域'}</span>
      <span class="cap">${icon('star')} ${it.studio||'飞牛 NAS 媒体库'}</span>
    </div>
    ${actionBar(it)}
    <div class="res-chips">
      <button class="res-chip active">4K 原盘 · 58.4 Mbps</button>
      <button class="res-chip">1080p · REMUX</button>
      <button class="res-chip">1080p · WEB-DL</button>
    </div>
    <div class="dsec"><div class="ds-title">简介</div><div class="desc-txt" id="movieDesc">${it.desc}</div><div class="desc-more" data-expander="movieDesc">展开全部 ▾</div></div>
    ${creditsSec(it)}
    <div class="dsec"><div class="ds-title">文件信息</div><div class="info-grid">
      <div class="info-card"><b>媒体文件</b><dl>
        <dt>路径</dt><dd title="//192.168.1.8/media/电影/">//NAS/media/电影/${it.title} (${it.year})/</dd>
        <dt>容器</dt><dd>Matroska · ${it.quality==='1080p'?'9.8':'21.6'} GB</dd>
        <dt>视频</dt><dd>HEVC · 3840×2160 · ${it.quality==='1080p'?'SDR':'HDR10+'}</dd>
        <dt>帧率</dt><dd>23.976 fps</dd></dl></div>
      <div class="info-card"><b>流信息</b><dl>
        <dt>音轨</dt><dd>TrueHD Atmos 7.1</dd><dt>字幕</dt><dd>简 / 繁 / EN（PGS+ASS）</dd>
        <dt>章节</dt><dd>14 chapters</dd><dt>服务器</dt><dd>飞牛 NAS · 直连播放</dd></dl></div>
    </div></div>
    ${linkSec()}`;
}

function renderTv(it){
  $('#tvHeroBg').innerHTML = art(it.hue, true);
  $('#tvFloatTop .ft-title').textContent = it.title;
  $('#tvMeta').innerHTML = heroMeta(it);
  const epsTotal = it.eps.reduce((a,b)=>a+b,0);
  $('#tvBody').innerHTML = `
    ${actionBar(it, {remainTxt: it.cur ? `看到 第${it.cur.s}季 第${it.cur.e}集` : ''})}
    <div class="dsec"><div class="ds-title">简介</div><div class="desc-txt" id="tvDesc">${it.desc}</div><div class="desc-more" data-expander="tvDesc">展开全部 ▾</div></div>
    <div class="dsec"><div class="ds-title">季<ins class="ds-cnt disp">共 ${it.seasons} 季 · ${epsTotal} 集</ins></div>
      <div class="row-wrap"><button class="row-arrow left">${icon('chevL',2)}</button>
      <div class="row-scroll">${Array.from({length:it.seasons},(_,k)=>{
        const s=k+1;
        return `<div class="card-poster" style="--w:150px" data-season="${it.id}" data-s="${s}" tabindex="0">
          <div class="poster">${art(it.hue.map(h=>h+s*14))}${grain}<div class="poster-grad"></div>
          <span class="season-badge">SEASON 0${s}</span><div class="poster-sheen"></div>
          <div class="poster-txt"><b>第 ${s} 季</b><i>${it.eps[k]} 集</i></div></div>
          <div class="bp-cap"><div class="bp-sub">${it.title} · 第 ${s} 季</div></div></div>`;
      }).join('')}</div><button class="row-arrow right">${icon('chevR',2)}</button></div></div>
    ${creditsSec(it)}
    ${linkSec()}`;
}

/* ============================================================
   季选集页（TvSeasonDetailPage）
   ============================================================ */
function renderSeason(id, s){
  const it = byId(id); s = Math.min(Math.max(1, s), it.seasons);
  $('#seasonBridgeBg').innerHTML = art(it.hue.map(h=>h+s*10), true);
  $('#seasonPoster').innerHTML = art(it.hue.map(h=>h+s*14)) + grain + '<div class="poster-grad"></div>';
  $('#seasonFloatTop .ft-title').textContent = `${it.title} · 第 ${s} 季`;
  $('#seasonInfo').innerHTML = `
    <div class="bi-season disp">SEASON 0${s} / FERRY AT DAWN</div>
    <h1>${it.title} <span style="opacity:.55">第 ${s} 季</span></h1>
    <div class="bi-line"><span class="bi-rate">${icon('star')} ${it.rating.toFixed(1)}</span><span>${it.year}</span><span>${it.eps[s-1]} 集</span><span>${it.quality}</span><span>${(it.tags||[]).join(' · ')}</span></div>
    <div style="margin-top:16px"><button class="btn-play-main" data-play-ep="${it.id}" data-s="${s}" data-e="1">${icon('play')} 播放第 1 集</button></div>`;
  const eps = epsFor(it, s);
  $('#seasonBody').innerHTML = `
    <div class="season-tabs">${Array.from({length:it.seasons},(_,k)=>`<button class="st-chip ${k+1===s?'active':''}" data-season="${id}" data-s="${k+1}">第 ${k+1} 季</button>`).join('')}</div>
    <div class="range-chips"><button class="range-chip active">全部 ${eps.length}</button><button class="range-chip">1-${Math.min(6,eps.length)}</button>${eps.length>6?`<button class="range-chip">7-${eps.length}</button>`:''}</div>
    <div class="ep-grid">${eps.map(ep=>{
      const state = ep.state==='done' ? `<span class="ep-state done">已看</span>` : ep.state==='part' ? `<span class="ep-state">看到 ${(ep.part*100)|0}%</span>` : '';
      return `<div class="ep-card" data-play-ep="${id}" data-s="${s}" data-e="${ep.n}" tabindex="0">
        <div class="ep-thumb">${art(it.hue.map(h=>(h+ep.n*9)%360), true)}${grain}
          <span class="ep-num">第 ${ep.n} 集</span>${state}</div>
        <div class="ep-body"><div class="ep-title">${ep.title}</div>
          <div class="ep-meta"><span>${ep.dur}</span><span>${it.quality}</span></div>
          ${ep.state==='part'?`<div class="progress"><i style="width:${ep.part*100}%"></i></div>`:''}
        </div></div>`;
    }).join('')}</div>
    ${linkSec()}`;
}

/* ============================================================
   搜索 / 收藏 / 分类 / 下载
   ============================================================ */
function renderSearchBase(){
  $('#hotChips').innerHTML = `<span class="hot-label">热门搜索</span>` + HOT.map(h=>`<button class="chip-btn" data-hot="${h}">${h}</button>`).join('');
}
function doSearch(q){
  const res = !q ? [] : ITEMS.filter(i => (i.title+i.en+(i.tags||[]).join()).toLowerCase().includes(q.toLowerCase()));
  $('#searchResultHead').hidden = !q;
  $('#searchResultHead').innerHTML = `找到 <b>${res.length}</b> 条与「<b>${q}</b>」相关的结果`;
  $('#searchGrid').innerHTML = res.map(i=>posterCard(i,{cap:true})).join('');
  $('#searchEmpty').hidden = !(q && !res.length);
}
function renderFav(){
  const favs = ITEMS.filter(i=>i.fav);
  $('#favCount').textContent = `共 ${favs.length} 部 · 同步自 NAS 账户`;
  $('#favGrid').innerHTML = favs.map(i=>posterCard(i,{cap:true})).join('');
}
function renderCategory(type){
  const map = {movie:'电影', tv:'电视', other:'纪录片与短片', all:'全部条目'};
  $('#catTitle').textContent = map[type] || '全部条目';
  const list = type==='all' ? ITEMS : ITEMS.filter(i => type==='other' ? (i.tags||[]).includes('纪录片') : i.type===type);
  $('#catSub').textContent = `共 ${list.length} 部 · ${type==='movie'||type==='tv'?'对应 /screen/category 路由':'媒体库视图'}`;
  $('#catGrid').innerHTML = list.map(i=>posterCard(i,{cap:true})).join('');
}
function renderDownloads(){
  $('#dlSub').textContent = '下载中 2 · 已完成 1 · 已暂停 1';
  $('#dlList').innerHTML = DOWNLOADS.map((d,idx)=>{
    const it = byId(d.id);
    const st = d.status==='done'?'<span class="dl-status done">已完成</span>':d.status==='paused'?'<span class="dl-status paused">已暂停</span>':'<span class="dl-status downloading">下载中</span>';
    const act = d.status==='downloading' ? icon('pauseC') : icon('playC');
    return `<div class="dl-row"><div class="dl-thumb">${art(it.hue,true)}</div>
      <div class="dl-info"><div class="dl-name">${d.label}</div>
        <div class="dl-meta">${d.meta.map(m=>`<span>${m}</span>`).join('')}</div>
        <div class="dl-prog"><div class="progress"><i style="width:${d.pct}%"></i></div><span class="dl-speed">${d.pct}%</span></div></div>
      ${st}<button class="dl-act" data-dlact="${idx}">${act}</button><button class="dl-act" data-dldel="${idx}">${icon('trash')}</button></div>`;
  }).join('');
}

/* ============================================================
   设置（7 套预设主题 + 8 个 accent，实时切换）
   ============================================================ */
const PRESETS = {midnight:['#09111C','#3A82F7'],ocean:['#07121A','#2E9BFF'],forest:['#0A1410','#3EBC7A'],graphite:['#121319','#83A3FF'],sunset:['#1A100D','#E6815B'],aurora:['#081513','#35C7B0'],latte:['#F8F4EC','#6C8FF1']};
const ACCENTS = {blue:'#3A82F7',cyan:'#27B5E9',green:'#37B36B',amber:'#D39A28',rose:'#D95B77',coral:'#E67358',indigo:'#6B6FE8',mint:'#39C7A7'};
const SET_SECTIONS = [
  ['appearance','外观主题','sliders'],['player','播放器','playC'],['danmaku','弹幕','chat'],
  ['downloads','下载','download'],['storage','存储空间','folder'],['stats','播放统计','chart'],['keys','快捷键','keyboard'],['about','关于','info'],
];
let setCur = 'appearance';
function renderSettings(){
  $('#setNav').innerHTML = SET_SECTIONS.map(([k,label,ic]) => `<button data-set="${k}" class="${k===setCur?'active':''}">${icon(ic)} ${label}</button>`).join('');
  const P = $('#setPanel');
  if (setCur==='appearance'){
    const app = $('#app');
    P.innerHTML = `
    <div class="sg-title">主题预设</div><div class="sg-desc">对应 app_theme.dart 的 7 套预设（midnight / ocean / forest / graphite / sunset / aurora / latte），点击即时生效</div>
    <div class="set-card"><div class="swatch-row">${Object.entries(PRESETS).map(([k,[bg,ac]]) =>
      `<div class="swatch ${app.dataset.theme===k?'active':''}" data-theme-set="${k}"><div class="sw-color" style="background:${bg};--sw-accent:${ac}"></div><span>${k}</span></div>`).join('')}</div></div>
    <div class="sg-title">强调色</div><div class="sg-desc">8 个 accent 色调（accentTone），叠加于预设之上</div>
    <div class="set-card"><div class="swatch-row">${Object.entries(ACCENTS).map(([k,c]) =>
      `<div class="swatch ${app.dataset.accent===k?'active':''}" data-accent-set="${k}"><div class="sw-color" style="background:#10151f;--sw-accent:${c}"></div><span>${k}</span></div>`).join('')}</div></div>
    <div class="sg-title">动态主题</div>
    <div class="set-card">
      <div class="set-row"><div class="sr-label"><b>详情页动态取色</b><i>对应 DynamicPageThemeScope · palette_generator 管线</i></div><div class="toggle on" data-tgl></div></div>
      <div class="set-row"><div class="sr-label"><b>取色强度</b><i>subtle / medium / vivid 三档</i></div>
        <div class="seg sm" id="vividSeg"><button>柔和</button><button class="active">适中</button><button>鲜明</button></div></div>
      <div class="set-row"><div class="sr-label"><b>首页氛围光晕</b><i>AppAtmosphericBackground 径向光晕 + 颗粒</i></div><div class="toggle on" data-tgl></div></div>
      <div class="set-row"><div class="sr-label"><b>亮色模式跟随系统</b><i>关闭时使用所选预设</i></div><div class="toggle" data-tgl></div></div>
    </div>`;
  } else if (setCur==='keys'){
    P.innerHTML = `<div class="sg-title">键盘快捷键</div><div class="sg-desc">桌面端专属 · 对应原生播放器与全局导航</div><div class="sc-grid" style="grid-template-columns:1fr">${SC_ROWS.map(([k,d])=>`<div class="sc-row"><span>${d}</span><kbd>${k}</kbd></div>`).join('')}</div>`;
  } else if (setCur==='about'){
    P.innerHTML = `<div class="sg-title">关于飞翔播放器</div>
    <div class="set-card">
      <div class="set-row"><div class="sr-label"><b>版本</b><i>Windows Desktop Concept · 对应 Flutter 3.x + mpv</i></div><span class="dl-status downloading">原型</span></div>
      <div class="set-row"><div class="sr-label"><b>播放内核</b><i>桌面端建议沿用 mpv（libmpv），替代 Android 原生壳</i></div></div>
      <div class="set-row"><div class="sr-label"><b>媒体后端</b><i>飞牛 NAS / Emby / Jellyfin 三后端中立层</i></div></div>
    </div>`;
  } else {
    const rows = {
      player:[['硬件解码','自动选择 d3d11va / nvdec，对应 mpv hwdec 配置'],['记忆播放位置','为每部作品保存上次进度（play_stats）'],['默认音轨','优先中文母语轨'],['启动时恢复上次会话','PIP / 窗口尺寸记忆，桌面端新增']],
      danmaku:[['弹幕聚合','同一时间轴弹幕去重'],['显示区域','半屏弹幕，减少遮挡'],['字体缩放','跟随 AdaptiveText.globalScale']],
      downloads:[['同时下载任务数','2 个并行'],['下载完成后自动转码','关闭'],['保存路径','D:\\FlyPlayer\\Downloads']],
      storage:[['图片缓存上限','4 GB（32px 分桶，对应 DetailRoutePayloadStore 优化）'],['播放统计数据库','SQLite · 86 MB'],['清理缩略图缓存','上次清理：12 天前']],
      stats:[['累计观看时长','486 小时'],['本周观看','9 小时 42 分'],['最长单日','5 月 12 日 · 6.1 小时']],
    }[setCur] || [];
    P.innerHTML = `<div class="sg-title">${SET_SECTIONS.find(x=>x[0]===setCur)[1]}</div>
    <div class="set-card">${rows.map(([b,i])=>`<div class="set-row"><div class="sr-label"><b>${b}</b><i>${i}</i></div>${typeof i==='string'&&['路径','数据库','时长','缩略图','缓存上限','观看'].some(w=>b.includes(w))?'':'<div class="toggle on" data-tgl></div>'}</div>`).join('')}</div>
    ${setCur==='player'?'<div class="sg-desc">播放器本体由桌面壳自建（Flutter + libmpv），替代 Android 的 NativePlayerActivity；控制条布局可参考本原型的全屏播放器页。</div>':''}`;
  }
}

/* ============================================================
   沉浸浏览（PosterBrowseLargeLayout）
   ============================================================ */
let bIdx = 0;
function renderBrowse(){
  $('#browseTrack').innerHTML = ITEMS.map((it,k) =>
    `<div class="b-card ${k===bIdx?'focus':''} ${Math.abs(k-bIdx)>2?'far':''}" data-bidx="${k}"><div class="poster">${art(it.hue)}${grain}<div class="poster-grad"></div><div class="poster-txt"><b>${it.title}</b><i>${it.en||''}</i></div></div></div>`).join('');
  updateBrowseFocus(false);
}
function updateBrowseFocus(anim=true){
  const track = $('#browseTrack');
  const cards = [...track.children];
  cards.forEach((c,k) => { c.classList.toggle('focus', k===bIdx); c.classList.toggle('far', Math.abs(k-bIdx)>2); });
  const focus = cards[bIdx];
  if (focus){
    const wrap = track.parentElement;
    wrap.scrollTo({left: focus.offsetLeft - wrap.clientWidth/2 + focus.offsetWidth/2, behavior: anim?'smooth':'auto'});
  }
  const it = ITEMS[bIdx];
  $('#browseBg').style.background = `radial-gradient(60% 80% at 30% 40%, hsla(${it.hue[0]},60%,40%,.55), transparent 70%), linear-gradient(140deg, hsl(${it.hue[1]},45%,12%), hsl(${it.hue[0]},40%,7%))`;
  $('#browseInfo').innerHTML = `
    <div class="bi-idx disp">${String(bIdx+1).padStart(2,'0')} / ${ITEMS.length} · ${it.type==='tv'?'SERIES':'MOVIE'}</div>
    <h1>${it.title}</h1>
    <div class="bi-meta"><span class="bi-rate">${icon('star')} ${it.rating.toFixed(1)}</span><span>${it.year}</span><span>${(it.tags||[]).join(' / ')}</span><span>${it.quality}</span></div>
    <div class="bi-desc">${it.desc || '来自飞牛 NAS 媒体库。'}</div>
    <div class="bi-actions">
      <button class="btn-play-main" data-play="${it.id}" style="min-width:150px;height:46px">${icon('play')} ${it.progress>0?'继续播放':'播放'}</button>
      <button class="circ-btn" data-detail="${it.id}" title="查看详情" style="width:46px;height:46px">${icon('info')}</button>
    </div>`;
}

/* ============================================================
   路由（URI-based · 对应 main.dart _buildRoute）
   ============================================================ */
const PAGES = {
  'home':      {el:'page-home',      uri: () => '/'},
  'poster-browse':{el:'page-browse', uri: () => '/screen/poster-browse'},
  'screen/search':    {el:'page-search',    uri: q => '/screen/search' + (q.q?`?q=${q.q}`:'')},
  'screen/favorites': {el:'page-favorites', uri: () => '/screen/favorites'},
  'screen/category':  {el:'page-category',  uri: q => `/screen/category?type=${q.type||'all'}`},
  'screen/downloads': {el:'page-downloads', uri: () => '/screen/downloads'},
  'screen/settings':  {el:'page-settings',  uri: () => '/screen/settings'},
  'movie':     {el:'page-movie',     uri: q => `/detail/item?itemGuid=${q.id}`, detail:true},
  'tv':        {el:'page-tv',        uri: q => `/detail/item?itemGuid=${q.id}`, detail:true},
  'season':    {el:'page-season',    uri: q => `/detail/season?seriesGuid=${q.id}&season=${q.s||1}`, detail:true},
};
const NAV_KEYS = {home:'home','poster-browse':'browse','screen/search':'search','screen/favorites':'favorites','screen/downloads':'downloads','screen/settings':'settings'};
let navStack = [], popping = false;
const split = {on:false, ratio:50};
let panePage = null;

function parseHash(){
  const h = location.hash.replace(/^#\/?/, '') || 'home';
  const [path, qs] = h.split('?');
  const params = {}; new URLSearchParams(qs||'').forEach((v,k)=>params[k]=v);
  const key = PAGES[path] ? path : 'home';
  return {key, params};
}
function setChip(mainUri, paneUri){
  $('#routePath').textContent = paneUri ? `${mainUri}  ⇢  ${paneUri}` : mainUri;
}
function activate(key, params){
  const def = PAGES[key];
  // 详情类页面渲染（每次进入重渲染，保持状态新鲜）
  if (key==='movie' || key==='tv'){ const it = byId(params.id||'mv_dune'); key==='movie' ? renderMovie(it) : renderTv(it); }
  if (key==='season') renderSeason(params.id||'tv_ferry', +params.s||1);
  if (key==='screen/category') renderCategory(params.type||'all');
  if (key==='poster-browse') updateBrowseFocus(false);
  // 若该页面正在分屏栏里，先收回来
  const node = document.getElementById(def.el);
  if (node.parentNode === $('#paneSlot')) closePane(true);
  $$('.pages-host .page').forEach(p => p.classList.remove('active'));
  node.classList.add('active');
  $('#pagesHost').scrollTop = 0;
  // 侧栏高亮
  $$('.nav-item').forEach(a => a.classList.toggle('active', a.dataset.nav === (NAV_KEYS[key]||'')));
  setChip(def.uri(params));
  return node;
}
function navigate(key, params){
  const qs = new URLSearchParams(params||{}).toString();
  const target = `#/${key}${qs?'?'+qs:''}`;
  if (location.hash === target) activate(key, params); else location.hash = target;
}
function goBack(){
  if (navStack.length > 1){ popping = true; navStack.pop(); const t = navStack[navStack.length-1]; location.hash = t; }
  else navigate('home');
}
window.addEventListener('hashchange', () => {
  if (popping) popping = false; else navStack.push(location.hash);
  const {key, params} = parseHash();
  activate(key, params);
});
function openDetail(id){
  const it = byId(id); if (!it) return;
  if (split.on){ openPane(it.type==='tv' ? 'tv' : 'movie', {id}); return; }
  navigate(it.type==='tv' ? 'tv' : 'movie', {id});
}
function openSeason(id, s){ split.on ? openPane('season', {id, s}) : navigate('season', {id, s}); }

/* ---------- 分屏（ParallelWindow / DetailHostScreen） ---------- */
function openPane(key, params){
  const def = PAGES[key];
  let node = document.getElementById(def.el);
  if (key==='movie'||key==='tv'){ const it=byId(params.id); key==='movie'?renderMovie(it):renderTv(it); }
  if (key==='season') renderSeason(params.id, +params.s||1);
  if (node.parentNode === $('#pagesHost') && node.classList.contains('active')) navigate('home');
  if (node.parentNode !== $('#paneSlot')) $('#paneSlot').appendChild(node);
  $('#paneRight').hidden = false;
  panePage = {key, params};
  const mainUri = PAGES[parseHash().key].uri(parseHash().params);
  setChip(mainUri, def.uri(params));
  $('#splitState').textContent = '浏览 | 详情';
}
function closePane(silent){
  if (panePage){
    const node = document.getElementById(PAGES[panePage.key].el);
    $('#pagesHost').appendChild(node);
    panePage = null;
  }
  $('#paneRight').hidden = true;
  setChip(PAGES[parseHash().key].uri(parseHash().params));
  $('#splitState').textContent = split.on ? '仅列表' : '关闭';
  if (!silent) $('#pagesHost').scrollTop = $('#pagesHost').scrollHeight * .2;
}
function setSplit(on){
  split.on = on;
  $('#main').classList.toggle('split', on);
  $('#btnSplit').classList.toggle('on', on);
  $('#splitDot').style.background = on ? 'var(--accent)' : '';
  $('#splitState').textContent = on ? (panePage ? '浏览 | 详情' : '仅列表') : '关闭';
  if (!on && panePage) closePane();
  if (on) toast('分屏已开启：点击任意海报将在右侧详情栏打开');
}

/* ============================================================
   播放器（桌面自建壳，替代 NativePlayerActivity）
   ============================================================ */
const player = {
  el: $('#player'), open:false, playing:false, t:0, dur:1, timer:null, item:null, eps:null, s:1,
  dmOn:true, dmTimer:null, vol:80, lastVol:80, idleT:null,
};
const DANM = ['这段运镜绝了','前方高能预警','BGM 一响 眼泪下来了','哈哈哈哈弹幕护体','名场面打卡 ✓','导演出来挨夸','4K 真的值','谁懂这句台词的含金量','补个标：2026 夏','二刷预定','这里的伏笔第三集收','灯光师加鸡腿'];
const fmt = s => { s=Math.max(0,s|0); const m=(s/60)|0, ss=s%60, h=(m/60)|0; return (h?h+':':'')+String(m%60).padStart(2,'0')+':'+String(ss).padStart(2,'0'); };

function openPlayer(id, s, e){
  const it = byId(id); if (!it) return;
  player.item = it; player.open = true;
  const isTv = it.type==='tv';
  player.s = s || (it.cur ? it.cur.s : 1);
  player.eps = isTv ? epsFor(it, player.s) : null;
  const ep = isTv ? player.eps.find(x=>x.n===(e||it.cur?.e||1)) : null;
  player.curE = isTv ? (ep ? ep.n : 1) : null;
  player.dur = ep ? ep.durSec : (it.durSec || 166*60);
  player.t = ep && ep.state==='part' ? ep.durSec*ep.part : it.progress ? player.dur*it.progress : 0;
  $('#plTitle').textContent = isTv ? `${it.title} 第${player.s}季 第${ep?ep.n:1}集 ${ep?ep.title:''}` : it.title;
  $('#plSub').textContent = `正在播放 · ${it.quality} ${it.hue[0]>300?'杜比视界':'HDR10+'} · 飞牛 NAS 直连`;
  $('#plScene').querySelector('.scene-art')?.remove();
  $('#plScene').insertAdjacentHTML('afterbegin', art(it.hue, true));
  $('#plEpBtn').style.display = isTv ? '' : 'none';
  $('#plPrev').style.opacity = isTv ? 1 : .35;
  $('#plNext').style.opacity = isTv ? 1 : .35;
  $('#plDrawer').hidden = true;
  if (isTv) buildDrawerList();
  player.el.hidden = false; player.el.classList.remove('paused','idle');
  setPlaying(true); seek(0); // 重置到实际进度
  wake();
}
function closePlayer(){
  player.open = false; player.el.hidden = true;
  clearInterval(player.timer); clearInterval(player.dmTimer);
}
function setPlaying(v){
  player.playing = v;
  player.el.classList.toggle('paused', !v);
  $('#plPlay').innerHTML = icon(v?'pause':'play');
  $('#plBigPlay').innerHTML = icon(v?'pause':'play');
  $('#plScene').classList.toggle('dim', v);
  clearInterval(player.timer); clearInterval(player.dmTimer);
  if (v){
    player.timer = setInterval(()=>{ if(player.t < player.dur){ player.t++; drawProgress(); } }, 1000);
    if (player.dmOn) player.dmTimer = setInterval(spawnDm, 760);
  }
}
function drawProgress(){
  const p = Math.min(1, player.t/player.dur);
  $('#plpFill').style.width = (p*100).toFixed(2)+'%';
  $('#plCur').textContent = fmt(player.t); $('#plDur').textContent = fmt(player.dur);
}
function seek(sec){
  player.t = Math.min(Math.max(0, sec), player.dur); drawProgress();
}
function spawnDm(){
  const box = $('#plDanmaku'); if (!player.dmOn || !player.playing) return;
  const d = document.createElement('span');
  d.className = 'dm' + (Math.random()<.12?' big':'');
  d.textContent = DANM[(Math.random()*DANM.length)|0];
  d.style.top = (6 + Math.random()*72) + '%';
  d.style.setProperty('--dmw', d.textContent.length*16 + 'px');
  const dur = 7.5 + Math.random()*4.5;
  d.style.animationDuration = dur + 's';
  d.addEventListener('animationend', ()=>d.remove());
  box.appendChild(d);
  if (box.children.length > 22) box.firstChild.remove();
}
function buildDrawerList(){
  const it = player.item;
  $('#pldTabs').innerHTML = Array.from({length:it.seasons||1},(_,k)=>`<button class="${k+1===player.s?'active':''}" data-plds="${k+1}">第 ${k+1} 季</button>`).join('');
  player.eps = epsFor(it, player.s);
  const curE = player.curE || (it.cur && it.cur.s===player.s ? it.cur.e : 1);
  $('#pldList').innerHTML = player.eps.map(ep=>{
    const now = ep.n === curE;
    return `<div class="pld-item ${now?'now':''}" data-pldep="${ep.n}">
      <div class="pld-thumb">${art(it.hue.map(h=>(h+ep.n*9)%360),true)}<span class="ep-idx">第 ${ep.n} 集</span></div>
      <div class="pld-info"><b>${ep.title}</b><i>${ep.dur} · ${it.quality}</i>
        ${ep.state==='part'?`<div class="progress"><i style="width:${ep.part*100}%"></i></div>`:''}</div>
      ${ep.state==='done'?`<span class="pld-check">${icon('check',2.4)}</span>`:''}</div>`;
  }).join('');
}

/* ============================================================
   杂项：Toast / 右键菜单 / 快捷键
   ============================================================ */
let toastT;
function toast(msg, ic='check'){
  const t = $('#toast'); t.innerHTML = icon(ic) + msg; t.hidden = false;
  clearTimeout(toastT); toastT = setTimeout(()=>t.hidden=true, 2200);
}
const SC_ROWS = [['Esc','返回 / 退出播放器'],['Ctrl K','全局搜索'],['Space','播放 / 暂停'],['← →','快退 / 快进 10 秒'],['↑ ↓','音量调节'],['F','全屏切换'],['1 - 5','切换侧栏导航'],['← →','沉浸浏览：切换焦点'],['?','快捷键说明']];
$('#btnShortcuts').onclick = () => { $('#scGrid').innerHTML = SC_ROWS.map(([k,d])=>`<div class="sc-row"><span>${d}</span><kbd>${k}</kbd></div>`).join(''); $('#shortcutsModal').hidden = false; };
$('#scClose').onclick = () => $('#shortcutsModal').hidden = true;
$('#shortcutsModal').addEventListener('click', e => { if (e.target.id==='shortcutsModal') e.target.hidden = true; });

document.addEventListener('keydown', e => {
  if (e.key === 'Escape'){
    if (!$('#shortcutsModal').hidden) return $('#shortcutsModal').hidden = true;
    if (!$('#ctxMenu').hidden) return hideCtx();
    if (player.open){ if (!$('#plDrawer').hidden) return ($('#plDrawer').hidden = true); return closePlayer(); }
    if (!$('#paneRight').hidden && panePage) return closePane();
    return goBack();
  }
  if (player.open){
    if (e.code==='Space'){ e.preventDefault(); setPlaying(!player.playing); }
    else if (e.key==='ArrowRight') seek(player.t+10);
    else if (e.key==='ArrowLeft') seek(player.t-10);
    else if (e.key==='ArrowUp'){ e.preventDefault(); setVol(Math.min(100,player.vol+5)); }
    else if (e.key==='ArrowDown'){ e.preventDefault(); setVol(Math.max(0,player.vol-5)); }
    else if (e.key==='f'||e.key==='F') toggleFull();
    return;
  }
  if ((e.ctrlKey||e.metaKey) && e.key.toLowerCase()==='k'){ e.preventDefault(); navigate('screen/search'); setTimeout(()=>$('#searchInput').focus(),60); return; }
  if (parseHash().key==='poster-browse'){
    if (e.key==='ArrowRight'){ bIdx=Math.min(ITEMS.length-1,bIdx+1); updateBrowseFocus(); }
    else if (e.key==='ArrowLeft'){ bIdx=Math.max(0,bIdx-1); updateBrowseFocus(); }
    else if (e.key==='Enter') openDetail(ITEMS[bIdx].id);
  }
  if (e.key>='1' && e.key<='5'){
    const map = ['home','poster-browse','screen/search','screen/favorites','screen/settings'];
    navigate(map[+e.key-1]);
  }
});
function setVol(v){
  player.vol = v; $('#plVol').value = v;
  $('#plMute').innerHTML = icon(v===0?'mute':'volume');
}
function toggleFull(){
  const app = $('#app');
  if (!document.fullscreenElement) (document.documentElement.requestFullscreen?.() , toast('全屏（真实环境由 Win32 / mpv 接管）','expand'));
  else document.exitFullscreen?.();
}
function wake(){
  player.el.classList.remove('idle');
  clearTimeout(player.idleT);
  player.idleT = setTimeout(()=>{ if (player.playing) player.el.classList.add('idle'); }, 2800);
}
player.el.addEventListener('mousemove', wake);

/* ---------- 右键菜单（对应长按动作表 media_item_action_sheet） ---------- */
let ctxTarget = null;
function hideCtx(){ $('#ctxMenu').hidden = true; }
document.addEventListener('contextmenu', e => {
  const card = e.target.closest('[data-detail],[data-play]');
  if (!card) return;
  e.preventDefault();
  ctxTarget = card.dataset.detail || card.dataset.play;
  const it = byId(ctxTarget);
  const m = $('#ctxMenu');
  m.innerHTML = `
    <button class="ctx-item" data-ctx="play">${icon('play')} 播放${it.progress>0?'（继续）':''}</button>
    <button class="ctx-item" data-ctx="detail">${icon('info')} 查看详情</button>
    ${!split.on?`<button class="ctx-item" data-ctx="pane">${icon('columns')} 在分屏栏打开</button>`:''}
    <div class="ctx-sep"></div>
    <button class="ctx-item" data-ctx="fav">${icon(it.fav?'heartFill':'heart')} ${it.fav?'取消收藏':'收藏'}</button>
    <button class="ctx-item" data-ctx="dl">${icon('download')} 下载</button>
    <button class="ctx-item" data-ctx="seen">${icon('check')} 标记已看</button>`;
  m.hidden = false;
  const r = m.getBoundingClientRect();
  m.style.left = Math.min(e.clientX, innerWidth - r.width - 10) + 'px';
  m.style.top = Math.min(e.clientY, innerHeight - r.height - 10) + 'px';
});
document.addEventListener('click', e => {
  if (!$('#ctxMenu').hidden && !e.target.closest('#ctxMenu')) hideCtx();
  const c = e.target.closest('[data-ctx]');
  if (c){
    const it = byId(ctxTarget); hideCtx();
    const act = {play:()=>openPlayer(it.id), detail:()=>openDetail(it.id), pane:()=>{setSplit(true);openPane(it.type==='tv'?'tv':'movie',{id:it.id});},
      fav:()=>{it.fav=!it.fav;toast(it.fav?'已加入收藏':'已取消收藏','heartFill');renderFav();}, dl:()=>toast(`「${it.title}」已加入下载队列`,'download'), seen:()=>toast(`「${it.title}」已标记为已看`)};
    act[c.dataset.ctx]();
  }
});

/* ============================================================
   全局事件委托
   ============================================================ */
document.addEventListener('click', e => {
  const t = id => byId(id);
  const go = e.target.closest('[data-go]');           if (go){ location.hash = go.dataset.go.replace(/^#/,''); return; }
  const back = e.target.closest('[data-back]');        if (back){ goBack(); return; }
  const dpl = e.target.closest('[data-play]');         if (dpl){ openPlayer(dpl.dataset.play); return; }
  const pep = e.target.closest('[data-play-ep]');      if (pep){ openPlayer(pep.dataset.playEp, +pep.dataset.s, +pep.dataset.e); return; }
  const sea = e.target.closest('[data-season]');       if (sea){ openSeason(sea.dataset.season, +sea.dataset.s); return; }
  const det = e.target.closest('[data-detail]');       if (det && !e.target.closest('[data-play]')){ openDetail(det.dataset.detail); return; }
  const hot = e.target.closest('[data-hot]');          if (hot){ $('#searchInput').value = hot.dataset.hot; doSearch(hot.dataset.hot); return; }
  const exp = e.target.closest('[data-expander]');     if (exp){ const d=document.getElementById(exp.dataset.expander); d.classList.toggle('open'); exp.textContent = d.classList.contains('open')?'收起 ▴':'展开全部 ▾'; return; }
  const rc  = e.target.closest('[data-res-chip]') || e.target.closest('.res-chip');
  if (rc && rc.parentElement.classList.contains('res-chips')){ rc.parentElement.querySelectorAll('.res-chip').forEach(b=>b.classList.remove('active')); rc.classList.add('active'); return; }
  const tg  = e.target.closest('[data-tgl]');          if (tg){ tg.classList.toggle('on'); return; }
  const set = e.target.closest('[data-set]');          if (set){ setCur = set.dataset.set; renderSettings(); return; }
  const th  = e.target.closest('[data-theme-set]');    if (th){ $('#app').dataset.theme = th.dataset.themeSet; renderSettings(); toast(`主题已切换 · ${th.dataset.themeSet}`,'sliders'); return; }
  const ac  = e.target.closest('[data-accent-set]');   if (ac){ $('#app').dataset.accent = ac.dataset.accentSet; renderSettings(); return; }
  const bi  = e.target.closest('[data-bidx]');         if (bi){ bIdx = +bi.dataset.bidx; updateBrowseFocus(); return; }
  const pdt = e.target.closest('[data-plds]');         if (pdt){ player.s = +pdt.dataset.plds; buildDrawerList(); return; }
  const pde = e.target.closest('[data-pldep]');        if (pde){ const n=+pde.dataset.pldep; const ep=player.eps.find(x=>x.n===n); player.curE=n; buildDrawerList(); openPlayer(player.item.id, player.s, n); return; }
  const dlA = e.target.closest('[data-dlact]');        if (dlA){ const d=DOWNLOADS[+dlA.dataset.dlact]; d.status = d.status==='downloading'?'paused':d.status==='paused'?'downloading':d.status; renderDownloads(); return; }
  const dlD = e.target.closest('[data-dldel]');        if (dlD){ DOWNLOADS.splice(+dlD.dataset.dldel,1); renderDownloads(); toast('已从队列移除','trash'); return; }
  const tst = e.target.closest('[data-toast]');        if (tst){ toast(tst.dataset.toast,'info'); return; }
  const fav = e.target.closest('[data-fav]');          if (fav){ const it=t(fav.dataset.fav); it.fav=!it.fav; fav.classList.toggle('on'); fav.innerHTML=icon(it.fav?'heartFill':'heart'); toast(it.fav?'已加入收藏':'已取消收藏','heartFill'); return; }
  const dlC = e.target.closest('[data-dlcmd]');        if (dlC){ toast(`「${t(dlC.dataset.dlcmd).title}」已加入下载队列`,'download'); return; }
  const sn  = e.target.closest('[data-seen]');         if (sn){ sn.classList.toggle('on'); toast('已标记为已看'); return; }
});
// 海报键盘可达（Enter 打开）
document.addEventListener('keydown', e => {
  if (e.key==='Enter' && e.target.matches('[data-detail]')) openDetail(e.target.dataset.detail);
});

/* ---------- 横向货架箭头 ---------- */
document.addEventListener('click', e => {
  const a = e.target.closest('.row-arrow'); if (!a) return;
  const row = a.parentElement.querySelector('.row-scroll');
  row.scrollBy({left: (a.classList.contains('left')?-1:1) * row.clientWidth * .8, behavior:'smooth'});
});

/* ---------- 滚动：浮层标题 + hero 视差 ---------- */
function bindScroll(scroller, root){
  scroller.addEventListener('scroll', () => {
    const ft = root.querySelector('.page.active .float-top') || root.querySelector('.float-top');
    if (ft) ft.classList.toggle('scrolled', scroller.scrollTop > 84);
    const hero = root.querySelector('.page.active .hero-bg > div, .bridge-bg > div');
    if (hero) hero.style.transform = `translateY(${scroller.scrollTop * .22}px) scale(1.05)`;
  }, {passive:true});
}
bindScroll($('#pagesHost'), $('#pagesHost'));
bindScroll($('#paneSlot'), $('#paneSlot'));

/* ---------- 播放器控件 ---------- */
$('#plPlay').onclick = $('#plBigPlay').onclick = () => setPlaying(!player.playing);
$('#plBack').onclick = closePlayer;
$('#plNext').onclick = () => stepEp(1);
$('#plPrev').onclick = () => stepEp(-1);
function stepEp(d){
  if (!player.eps) return toast('电影没有上一集/下一集','info');
  const cur = player.curE || 1; const n = cur + d;
  const ep = player.eps.find(x=>x.n===n); if (!ep) return toast(d>0?'已经是最后一集了':'已经是第一集','info');
  player.curE = n; buildDrawerList(); openPlayer(player.item.id, player.s, n);
}
$('#plEpBtn').onclick = () => { const d=$('#plDrawer'); d.hidden = !d.hidden; if(!d.hidden) buildDrawerList(); };
$('#pldClose').onclick = () => $('#plDrawer').hidden = true;
$('#plDmBtn').onclick = () => {
  player.dmOn = !player.dmOn;
  $('#plDanmaku').classList.toggle('off', !player.dmOn);
  $('#plDmBtn span').classList.toggle('off', !player.dmOn);
  if (player.dmOn && player.playing){ clearInterval(player.dmTimer); player.dmTimer = setInterval(spawnDm, 760); }
  else clearInterval(player.dmTimer);
};
$('#plDmSet').onclick = () => toast('弹幕设置（对应原生弹幕设置面板）','chat');
$('#plMute').onclick = () => { if (player.vol===0) setVol(player.lastVol||80); else { player.lastVol=player.vol; setVol(0); } };
$('#plVol').oninput = e => setVol(+e.target.value);
$('#plFull').onclick = toggleFull;
$('#plProgress').addEventListener('pointerdown', ev => {
  const r = $('#plProgress').getBoundingClientRect();
  const mv = e2 => seek(((e2.clientX - r.left)/r.width)*player.dur);
  mv(ev);
  const up = () => { removeEventListener('pointermove', mv); removeEventListener('pointerup', up); };
  addEventListener('pointermove', mv); addEventListener('pointerup', up);
});
$('#plProgress').addEventListener('pointermove', ev => {
  if (ev.pointerType === 'mouse'){
    const r = $('#plProgress').getBoundingClientRect();
    const tip = $('#plpTip');
    tip.style.left = Math.min(Math.max(0, ev.clientX - r.left), r.width) + 'px';
    tip.textContent = fmt(((ev.clientX - r.left)/r.width)*player.dur);
  }
});

/* ---------- 其余控件 ---------- */
$('#btnSplit').onclick = () => setSplit(!split.on);
$('#paneClose').onclick = () => closePane();
$$('#ratioChips button').forEach(b => b.onclick = () => {
  $$('#ratioChips button').forEach(x=>x.classList.remove('active')); b.classList.add('active');
  $('#main').style.setProperty('--splitR', b.dataset.ratio + '%');
});
$('#homeSearchInput').addEventListener('keydown', e => {
  if (e.key==='Enter'){ navigate('screen/search'); setTimeout(()=>{ $('#searchInput').value = e.target.value; doSearch(e.target.value); $('#searchInput').focus(); }, 60); }
});
$('#searchInput').addEventListener('input', e => doSearch(e.target.value.trim()));
$('#btnRefresh').onclick = () => { renderHome(); toast('媒体库已刷新','refresh'); };
$('#tipClose').onclick = () => $('#tipBar').remove();
$$('#catSeg button').forEach((b,i) => b.onclick = () => {
  $$('#catSeg button').forEach(x=>x.classList.remove('active')); b.classList.add('active');
  if (i>0) toast('对应 CategoryItemsScreen 的 列表 / 横版网格 视图（原型仅实现海报网格）','info');
});
$('#favEdit').onclick = () => toast('批量管理模式（原型）','sliders');
$('#btnPauseAll').onclick = () => { DOWNLOADS.forEach(d=>{ if(d.status==='downloading') d.status='paused'; }); renderDownloads(); toast('已全部暂停','pauseC'); };
$$('.win-btn').forEach(b => b.onclick = () => toast('窗口控制由 Win32 标题栏接管（原型演示）','info'));
$('#vividSeg')?.addEventListener?.('click', ()=>{});
document.addEventListener('click', e => {
  const v = e.target.closest('#vividSeg button');
  if (v){ [...v.parentElement.children].forEach(x=>x.classList.remove('active')); v.classList.add('active'); }
});

/* ---------- 启动 ---------- */
renderHome(); renderSearchBase(); renderFav(); renderCategory('movie'); renderDownloads(); renderSettings(); renderBrowse();
if (!location.hash) { history.replaceState(null,'','#/home'); }
navStack = [location.hash || '#/home'];
activate(...Object.values(parseHash()));
setVol(80); drawProgress();
