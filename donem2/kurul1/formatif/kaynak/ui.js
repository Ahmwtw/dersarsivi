/* ===================== ARAYÜZ ===================== */
(function () {
'use strict';
const E = window.KVSEngine, D = window.KVSData, clamp = E.clamp;
const $ = (id) => document.getElementById(id);
const fmt = (x, n = 0) => (x == null || !isFinite(x)) ? '–' : Number(x).toLocaleString('tr-TR', { minimumFractionDigits: n, maximumFractionDigits: n });
const sgn = (x) => (x > 0 ? '+' : '') + fmt(x, 0);

let eng = new E(); eng.warm(14);
const ref = new E(); ref.warm(14);
let paused = false, caseState = null, soundOn = false;

/* ---------- renkler (tema) ---------- */
let C = {};
function readColors() {
  const cs = getComputedStyle(document.documentElement);
  const g = (k) => cs.getPropertyValue(k).trim();
  C = { ink: g('--ink'), muted: g('--muted'), line: g('--line'), panel: g('--panel'), panel2: g('--panel2'), accent: g('--accent'),
    warn: g('--warn'), crit: g('--crit'), good: g('--good'), ecg: g('--ecg'), art: g('--art'), cvp: g('--cvp'), pap: g('--pap'), spo: g('--spo'),
    mon: g('--mon'), monLine: g('--mon-line'), monDim: g('--mon-dim'), c1: g('--c1'), c2: g('--c2'), c3: g('--c3'), c4: g('--c4'), c5: g('--c5'), c6: g('--c6'), c7: g('--c7') };
  C.dark = matchMedia('(prefers-color-scheme: dark)').matches && document.documentElement.getAttribute('data-theme') !== 'light' || document.documentElement.getAttribute('data-theme') === 'dark';
}
readColors();
try { matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => setTimeout(readColors, 50)); } catch (e) {}
new MutationObserver(() => setTimeout(readColors, 30)).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });

function fit(cv) {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = Math.max(cv.clientWidth, 10), h = Math.max(cv.clientHeight, 10);
  const W = Math.round(w * dpr), H = Math.round(h * dpr);
  if (cv.width !== W || cv.height !== H) { cv.width = W; cv.height = H; }
  const c = cv.getContext('2d'); c.setTransform(dpr, 0, 0, dpr, 0, 0);
  return { c, w, h };
}

/* =================================================================
   KONTROLLER
   ================================================================= */
const ctlEls = {};
function buildControls() {
  const host = $('controls'); host.innerHTML = '';
  E.CONTROLS.forEach((g, gi) => {
    const det = document.createElement('details'); det.className = 'grp'; if (gi < 2 && window.innerWidth > 860) det.open = true; det.dataset.g = g.id;
    det.innerHTML = `<summary>${g.label}<span class="cnt"></span></summary>`;
    const box = document.createElement('div'); box.className = 'items';
    let btnRow = null;
    g.items.forEach(it => {
      if (it.type === 'button') {
        if (!btnRow) { btnRow = document.createElement('div'); btnRow.className = 'btnrow'; box.appendChild(btnRow); }
        const b = document.createElement('button'); b.className = 'btn'; b.textContent = it.label; b.id = 'act_' + it.id;
        b.addEventListener('click', () => { eng.action(it.id); const a = D.ACTIONS[it.id]; if (a) logWhy(a); });
        btnRow.appendChild(b); return;
      }
      btnRow = null;
      const wrap = document.createElement('div');
      if (it.type === 'toggle') {
        wrap.className = 'it tg';
        wrap.innerHTML = `<input type="checkbox" id="c_${it.id}" ${it.def ? 'checked' : ''}><label for="c_${it.id}" class="lab">${it.label}</label><span class="ref" style="margin-left:auto">${it.ref}</span>`;
        box.appendChild(wrap);
        const inp = wrap.querySelector('input');
        inp.addEventListener('change', () => change(it, inp.checked));
        ctlEls[it.id] = { it, inp, wrap };
        return;
      }
      wrap.className = 'it';
      if (it.type === 'select') {
        wrap.innerHTML = `<div class="row"><label class="lab" for="c_${it.id}">${it.label}</label><span class="ref" style="margin-left:auto">${it.ref}</span></div><select class="sel" id="c_${it.id}">${it.options.map(o => `<option value="${o[0]}">${o[1]}</option>`).join('')}</select>`;
        box.appendChild(wrap);
        const inp = wrap.querySelector('select'); inp.value = it.def;
        inp.addEventListener('change', () => change(it, inp.value));
        ctlEls[it.id] = { it, inp, wrap };
        return;
      }
      wrap.innerHTML = `<div class="row"><label class="lab" for="c_${it.id}">${it.label}</label><span class="val num" id="v_${it.id}"></span></div>
        <input type="range" id="c_${it.id}" min="${it.min}" max="${it.max}" step="${it.step}" value="${it.def}">
        <div class="meta"><span>${it.normal ? 'Normal: ' + it.normal : ''}</span><span class="ref">${it.ref}</span></div>`;
      box.appendChild(wrap);
      const inp = wrap.querySelector('input'), val = wrap.querySelector('.val');
      let last = it.def;
      inp.addEventListener('input', () => { const v = parseFloat(inp.value); eng.set(it.id, v); showVal(it.id); markGroups(); });
      inp.addEventListener('change', () => { const v = parseFloat(inp.value); whyChange(it, last, v); last = v; });
      ctlEls[it.id] = { it, inp, wrap, val, setLast: (v) => { last = v; } };
      showVal(it.id);
    });
    det.appendChild(box);
    const rb = document.createElement('button'); rb.className = 'reset-g'; rb.textContent = 'Bu grubu normale döndür'; rb.style.margin = '0 8px 10px';
    rb.addEventListener('click', () => { g.items.forEach(it => { if (it.type !== 'button') setCtl(it.id, it.def, true); }); markGroups(); });
    det.appendChild(rb);
    host.appendChild(det);
  });
  markGroups();
}
function valText(it, v) {
  const u = it.unit;
  const dec = it.step >= 1 ? 0 : it.step >= 0.1 ? 1 : 2;
  if (u === 'doz') return v === 0 ? 'kapalı' : '%' + Math.round(v * 100);
  if (it.id.startsWith('r') && u === '×') return '×' + fmt(v, 2);
  if (it.id === 'corStenosis' || it.id === 'renalStenosis') return v === 0 ? 'yok' : '%' + Math.round(v * 100) + ' yarıçap';
  if (['AS', 'AR', 'MS', 'MR', 'sepsis', 'anaphylaxis', 'pe', 'pneumo', 'exercise', 'emotion', 'arterialStiff', 'ves'].includes(it.id)) return v === 0 ? 'yok' : '%' + Math.round(v * 100);
  return fmt(v, dec) + (u ? ' ' + u : '');
}
function showVal(id) {
  const c = ctlEls[id]; if (!c || !c.val) return;
  const v = parseFloat(c.inp.value);
  c.val.textContent = valText(c.it, v);
  c.val.classList.toggle('dev', Math.abs(v - c.it.def) > 1e-9);
}
function setCtl(id, v, log) {
  const c = ctlEls[id]; if (!c) return;
  const old = eng.p[id];
  if (c.it.type === 'toggle') c.inp.checked = !!v; else c.inp.value = v;
  eng.set(id, v);
  if (c.val) showVal(id);
  if (c.setLast) c.setLast(v);
  if (log && old !== v) whyChange(c.it, old, v);
}
function change(it, v) { const old = eng.p[it.id]; eng.set(it.id, v); markGroups(); whyChange(it, old, v); }
function markGroups() {
  document.querySelectorAll('.grp').forEach(det => {
    const g = E.CONTROLS.find(x => x.id === det.dataset.g);
    const n = g.items.filter(it => it.type !== 'button' && eng.p[it.id] !== it.def && !(typeof it.def === 'number' && Math.abs(eng.p[it.id] - it.def) < 1e-9)).length;
    det.querySelector('.cnt').textContent = n ? n + ' değişti' : '';
  });
}
function syncControls() { E.CONTROLS.forEach(g => g.items.forEach(it => { if (it.type === 'button') return; const c = ctlEls[it.id]; if (!c) return; const v = eng.p[it.id]; if (it.type === 'toggle') c.inp.checked = !!v; else c.inp.value = v; if (c.setLast) c.setLast(v); if (c.val) showVal(it.id); })); markGroups(); }

/* =================================================================
   NEDEN? günlüğü
   ================================================================= */
const logEl = $('log');
function whyChange(it, a, b) {
  if (caseState && !caseState.revealed) return;
  const f = D.WHY[it.id]; if (!f) return;
  let w = null; try { w = f(a, b, eng); } catch (e) { w = null; }
  if (w && w.c && w.c.length) logWhy(w);
}
function logWhy(w) {
  if (caseState && !caseState.revealed) return;
  const div = document.createElement('div'); div.className = 'log-i';
  const tm = new Date(); const ts = tm.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  div.innerHTML = `<div class="h">${w.t}<span class="ref">${w.r || ''}</span></div><div class="chain">${w.c.map(x => x).join('<span class="ar"> → </span>')}</div><div class="tm">${ts}</div>`;
  logEl.prepend(div);
  while (logEl.children.length > 30) logEl.lastChild.remove();
}

/* =================================================================
   ÜST ÇUBUK
   ================================================================= */
function buildTop() {
  const sel = $('scenario');
  sel.innerHTML = '<option value="">Hazır senaryo seç…</option>';
  const groups = {};
  D.PRESETS.forEach(p => { (groups[p.g] = groups[p.g] || []).push(p); });
  for (const g in groups) { const og = document.createElement('optgroup'); og.label = g; groups[g].forEach(p => { const o = document.createElement('option'); o.value = p.id; o.textContent = p.n; og.appendChild(o); }); sel.appendChild(og); }
  sel.addEventListener('change', () => { if (sel.value) applyPreset(sel.value); });
  $('speed').addEventListener('change', (e) => { eng.speed = parseFloat(e.target.value); });
  $('pause').addEventListener('click', () => { paused = !paused; $('pause').textContent = paused ? 'Devam' : 'Duraklat'; $('pause').setAttribute('aria-pressed', paused); });
  $('resetAll').addEventListener('click', () => { resetAll(); logWhy({ t: 'Sıfırlandı', c: ['Tüm değerler normale döndü'], r: '' }); });
  $('sound').addEventListener('click', toggleSound);
  const ml = $('monLead'); ['I', 'II', 'III', 'aVR', 'aVL', 'aVF', 'V1', 'V2', 'V3', 'V4', 'V5', 'V6'].forEach(l => { const o = document.createElement('option'); o.value = l; o.textContent = l; ml.appendChild(o); });
  ml.value = 'II'; ml.addEventListener('change', () => { eng.monLead = ml.value; });
  $('caseBtn').addEventListener('click', openCaseMenu);
  $('caseQuit').addEventListener('click', quitCase);
  $('caseAnswer').addEventListener('click', openCaseAnswer);
}
function resetAll(keepSpeed) {
  const sp = eng.speed; const ml = eng.monLead;
  eng = new E(); eng.warm(10); eng.speed = keepSpeed ? sp : 1; eng.monLead = ml || 'II';
  if (!keepSpeed) $('speed').value = '1';
  syncControls(); audioReset();
  trend.length = 0;
  if (STU.on) stuReset();
}
function applyPreset(id, silent) {
  const p = D.PRESETS.find(x => x.id === id); if (!p) return;
  if (STU.on && stuPreset(p)) { $('scenario').value = ''; return; }
  resetAll();
  if (p.set) for (const k in p.set) setCtl(k, p.set[k], false);
  eng.warm(4);
  if (p.act) p.act.forEach(a => eng.action(a));
  if (p.speed) { eng.speed = p.speed; $('speed').value = String(p.speed); }
  syncControls();
  if (!silent) {
    const chains = [];
    if (p.set) for (const k in p.set) { const f = D.WHY[k]; if (f) { const w = f(E.DEFAULTS[k], p.set[k], eng); if (w) chains.push(w); } }
    if (p.act) p.act.forEach(a => { if (D.ACTIONS[a]) chains.push(D.ACTIONS[a]); });
    chains.reverse().forEach(logWhy);
    logWhy({ t: 'Senaryo: ' + p.n, c: [p.note || 'Kontrol panelindeki değişen değerler turuncu görünür.', p.speed ? `Zaman hızı ${p.speed}×: yavaş mekanizmalar (RAAS, ADH, böbrek, ödem) hızlandırıldı.` : 'Gerçek zaman.'], r: '' });
  }
}

/* =================================================================
   MONİTÖR
   ================================================================= */
const TW = 5;
const rangeState = { art: [40, 160], cvp: [-5, 20] };
function drawSweep(cv, key, color, fixed, opt) {
  const { c, w, h } = fit(cv);
  c.fillStyle = C.mon; c.fillRect(0, 0, w, h);
  const r = eng.s.rec, tNow = eng.s.t;
  const n = Math.min(r.full ? r.n : r.i, Math.round(TW / 0.004));
  let lo = fixed[0], hi = fixed[1];
  if (opt && opt.auto) {
    let mn = 1e9, mx = -1e9;
    for (let i = 0; i < n; i++) { const v = r.get(key, i); if (v < mn) mn = v; if (v > mx) mx = v; }
    const st = rangeState[opt.auto];
    const tlo = Math.min(fixed[0], Math.floor((mn - 5) / 10) * 10), thi = Math.max(fixed[1], Math.ceil((mx + 5) / 10) * 10);
    st[0] += (tlo - st[0]) * 0.1; st[1] += (thi - st[1]) * 0.1; lo = st[0]; hi = st[1];
  }
  const Y = (v) => h - 6 - (v - lo) / (hi - lo) * (h - 18);
  // ızgara
  c.strokeStyle = C.monLine; c.lineWidth = 1; c.beginPath();
  if (opt && opt.grid) for (const g of opt.grid) { const y = Y(g); c.moveTo(0, y); c.lineTo(w, y); }
  c.stroke();
  if (opt && opt.grid) { c.fillStyle = C.monDim; c.font = '10px ' + 'JetBrains Mono, monospace'; for (const g of opt.grid) c.fillText(String(g), w - 26, Y(g) - 2); }
  c.strokeStyle = color; c.lineWidth = 1.6; c.lineJoin = 'round'; c.beginPath();
  let prevX = -1, started = false;
  for (let i = n - 1; i >= 0; i--) {
    const t = r.get('t', i); if (tNow - t > TW - 0.12) continue;
    let x = ((t % TW) / TW) * w;
    const v = r.get(key, i);
    const y = Y(opt && opt.map ? opt.map(v, i) : v);
    if (!started || x < prevX) { c.moveTo(x, y); started = true; } else c.lineTo(x, y);
    prevX = x;
  }
  c.stroke();
  // imleç
  const xc = ((tNow % TW) / TW) * w; c.fillStyle = C.mon; c.fillRect(xc + 1, 0, 10, h);
}
let plethLP = 0;
function drawMonitor() {
  drawSweep($('cvEcg'), 'ecg', C.ecg, [-1.2, 2.0], {});
  drawSweep($('cvArt'), 'Pao', C.art, [40, 160], { auto: 'art', grid: [0, 60, 120, 180] });
  const ch = $('monCh3').value;
  const keyMap = { cvp: ['Pra', C.cvp, [-5, 20], [0, 10, 20]], pap: ['Ppa', C.pap, [0, 40], [0, 20, 40]], lvp: ['Plv', C.art, [0, 160], [0, 60, 120]], lap: ['Pla', C.pap, [-5, 25], [0, 10, 20]] }[ch];
  drawSweep($('cvCvp'), keyMap[0], keyMap[1], keyMap[2], { auto: 'cvp', grid: keyMap[3] });
  drawSweep($('cvPl'), 'Pao', C.spo, [0, 1], { map: (v, i) => { const r = eng.s.rec; const a = r.get('Pao', i + 25) || v; return clamp((a - eng.s.m.DBP) / Math.max(eng.s.m.SBP - eng.s.m.DBP, 5), 0, 1) * eng.s.SaO2; } });
  // solunum çizgisi ekle
  const cv = $('cvPl'); const { c, w, h } = fit(cv); const r = eng.s.rec, tNow = eng.s.t; const n = Math.min(r.full ? r.n : r.i, 1250);
  c.strokeStyle = 'rgba(240,240,240,.55)'; c.lineWidth = 1; c.beginPath(); let px = -1, st = false;
  for (let i = n - 1; i >= 0; i -= 3) { const t = r.get('t', i); if (tNow - t > TW - 0.12) continue; const x = ((t % TW) / TW) * w; const y = h - 4 - r.get('breath', i) * (h * 0.35); if (!st || x < px) { c.moveTo(x, y); st = true; } else c.lineTo(x, y); px = x; }
  c.stroke();
}
const NUMS = [
  { id: 'hr', full: 'Kalp hızı', k: 'KH', cls: 'c-ecg', u: '/dk', f: (m) => fmt(m.HR), al: (m) => m.HR < 45 || m.HR > 140 },
  { id: 'abp', full: 'Arteriyel kan basıncı: sistolik/diyastolik (ortalama = MAP)', k: 'ABP', cls: 'c-art', u: '', f: (m) => `${fmt(m.SBP)}/${fmt(m.DBP)} <small>(${fmt(m.MAP)})</small>`, al: (m) => m.MAP < 60 || m.SBP > 180 },
  { id: 'cvp', full: 'Santral venöz basınç', k: 'CVP', cls: 'c-cvp', u: 'mmHg', f: (m) => fmt(m.CVP) },
  { id: 'pap', full: 'Pulmoner arter basıncı', k: 'PAP', cls: 'c-pap', u: '', f: (m) => `${fmt(m.PAs)}/${fmt(m.PAd)}` },
  { id: 'spo', full: 'Oksijen satürasyonu', k: 'SpO₂', cls: 'c-spo', u: '%', f: (m, s) => fmt(s.SaO2 * 100), al: (m, s) => s.SaO2 < 0.88 },
  { id: 'co', full: 'Kalp debisi (dakika hacmi)', k: 'CO', cls: 'c-w', u: 'L/dk', f: (m) => fmt(m.CO, 1) },
  { id: 'sv', full: 'Atım hacmi · Ejeksiyon fraksiyonu', k: 'SV · EF', cls: 'c-w', u: '', f: (m) => `${fmt(m.SV)} <small>ml · %${fmt(m.EF * 100)}</small>` },
  { id: 'tpr', full: 'Toplam periferik direnç', k: 'TPR', cls: 'c-w', u: 'mmHg·dk/L', f: (m, s) => fmt(s.TPR * 1000 / 60, 1) },
  { id: 'cpp', full: 'Kafa içi basınç · Serebral perfüzyon basıncı', k: 'ICP · CPP', cls: 'c-w', u: '', f: (m) => `${fmt(m.ICP)} <small>· ${fmt(m.CPP)}</small>`, al: (m) => m.CPP < 50 },
  { id: 'rr', full: 'Solunum sayısı (/dk) · Vücut sıcaklığı', k: 'Solunum · Ateş', cls: 'c-w', u: '', f: (m, s, p) => `${fmt(12 * (1 + 0.8 * s.chemo + 1.3 * p.exercise))} <small>· ${fmt(p.temp, 1)}°</small>` },
];
function buildNums() {
  $('nums').innerHTML = NUMS.map(n => `<div class="nt" id="n_${n.id}"><div class="k ${n.cls}"><span>${n.k}</span><span>${n.u}</span></div><div class="full">${n.full}</div><div class="v ${n.cls}" id="nv_${n.id}">–</div><div class="ndl" id="nd_${n.id}"></div></div>`).join('');
}
function updNums() {
  const m = eng.s.m, s = eng.s, p = eng.p;
  if (!STU.on) for (const n of NUMS) { $('nv_' + n.id).innerHTML = n.f(m, s, p); const el = $('n_' + n.id); const al = n.al ? n.al(m, s, p) : false; el.classList.toggle('alarm', !!al); }
  // ritim etiketi ve durum
  $('rhythmLbl').textContent = rhythmName();
  let tags = statusTags();
  if (caseState && !caseState.revealed) tags = tags.filter(t => /Hipotansiyon|Hipoksemi|Hipertansiyon|Zaman|Stabil|Geniş QRS|QTc/.test(t[1]));
  $('status').innerHTML = tags.map(t => `<span class="tag ${t[0]}">${t[1]}</span>`).join('');
}
function rhythmName() {
  const p = eng.p, d = eng.derived, m = eng.s.m;
  if (d.conductionFail) return 'İletim kaybı – sinüs dalgası';
  const map = { sinus: 'Sinüs ritmi', af: 'Atriyal fibrilasyon', flutter: 'Atriyal flatter', vt: 'Ventriküler taşikardi', vf: 'Ventriküler fibrilasyon' };
  let r = map[p.rhythm];
  if (p.rhythm === 'sinus') { if (p.avBlock === '3') r = 'Komplet AV blok – kaçış ritmi'; else if (m.HR < 60) r = 'Sinüs bradikardisi'; else if (m.HR > 100) r = 'Sinüs taşikardisi'; }
  return r;
}
function statusTags() {
  const p = eng.p, s = eng.s, m = s.m, d = eng.derived, T = [];
  if (p.avBlock === '1' || (m.PR > 0.205 && p.avBlock === '0' && p.rhythm === 'sinus')) T.push(['w', '1. derece AV blok (PR ' + fmt(m.PR * 1000) + ' ms)']);
  if (p.avBlock === '2a') T.push(['w', 'Mobitz I']); if (p.avBlock === '2b') T.push(['c', 'Mobitz II']); if (p.avBlock === '3') T.push(['c', 'Komplet AV blok']);
  if (p.bbb === 'L') T.push(['w', 'Sol dal bloğu']); if (p.bbb === 'R') T.push(['w', 'Sağ dal bloğu']);
  if (m.QRS > 0.12) T.push(['w', 'Geniş QRS ' + fmt(m.QRS * 1000) + ' ms']);
  if (m.QTc > 0.47) T.push(['c', 'QTc uzun ' + fmt(m.QTc * 1000) + ' ms']);
  if (p.K > 6) T.push(['c', 'Sivri T (hiperkalemi)']);
  if (p.K < 3.3) T.push(['w', 'U dalgası (hipokalemi)']);
  if (p.mi !== '0') T.push(['c', 'ST elevasyonu']);
  else if (s.ischemia > 0.35) T.push(['c', 'ST çökmesi – iskemi']);
  if (m.MAP < 65) T.push(['c', 'Hipotansiyon / şok']);
  if (m.SBP >= 140 || m.DBP >= 90) T.push(['w', 'Hipertansiyon']);
  if (s.SaO2 < 0.9) T.push(['c', 'Hipoksemi']);
  if (s.dVlung > 150) T.push(['c', 'Akciğer ödemi']);
  if (s.dVi > 1500) T.push(['w', 'Periferik ödem']);
  if (s.cnsI > 0.2) T.push(['c', 'MSS iskemik yanıtı']);
  if (eng.s.maneuver) T.push(['g', eng.s.maneuver.kind === 'valsalva' ? 'Valsalva sürüyor' : 'Karotis masajı']);
  if (eng.speed > 1) T.push(['g', 'Zaman ' + eng.speed + '×']);
  if (!T.length) T.push(['g', 'Stabil']);
  return T;
}

/* =================================================================
   SEKMELER
   ================================================================= */
const TABS = [
  { id: 'cell', n: 'Hücre ve iyon akımları' }, { id: 'ecg', n: 'EKG' }, { id: 'cycle', n: 'Kalp döngüsü ve sesler' },
  { id: 'vessels', n: 'Damarlar ve hemodinami' }, { id: 'cap', n: 'Kapiller ve ödem' }, { id: 'reflex', n: 'Refleksler ve hormonlar' }, { id: 'formula', n: 'Formül kartı' },
];
let activeTab = 'cell';
function buildTabs() {
  const bar = $('tabbar'), panes = $('panes');
  bar.innerHTML = TABS.map(t => `<button class="tab" role="tab" id="tab_${t.id}" aria-selected="${t.id === activeTab}" aria-controls="pane_${t.id}">${t.n}</button>`).join('');
  panes.innerHTML = TABS.map(t => `<div class="pane ${t.id === activeTab ? 'act' : ''}" role="tabpanel" id="pane_${t.id}">${PANE_HTML[t.id]()}</div>`).join('');
  TABS.forEach(t => $('tab_' + t.id).addEventListener('click', () => {
    activeTab = t.id; TABS.forEach(x => { $('tab_' + x.id).setAttribute('aria-selected', x.id === t.id); $('pane_' + x.id).classList.toggle('act', x.id === t.id); });
    try { localStorage.setItem('kvs_tab', t.id); } catch (e) {}
    renderTab(true); onTabVisit(t.id);
  }));
  wirePanes();
}
const PANE_HTML = {
  cell: () => `
  <div class="two">
    <div class="box"><h3>Ventrikül kası – hızlı cevap AP<span class="ref">B1.4</span></h3>
      <canvas class="plot" id="cvAP" style="height:210px"></canvas>
      <canvas class="plot" id="cvCur" style="height:140px;margin-top:6px"></canvas>
      <div class="legend"><span><i style="background:var(--c2)"></i>I<sub>Na</sub> (faz 0)</span><span><i style="background:var(--c4)"></i>I<sub>to</sub> (faz 1)</span><span><i style="background:var(--c3)"></i>I<sub>CaL</sub> (faz 2)</span><span><i style="background:var(--c1)"></i>I<sub>K</sub> (faz 3)</span><span><i style="background:var(--c5)"></i>I<sub>K1</sub> (faz 4)</span><span><i style="background:var(--muted)"></i>gri: normal</span></div>
    </div>
    <div class="box"><h3>SA düğümü – yavaş cevap (pacemaker) AP<span class="ref">B1.4</span></h3>
      <canvas class="plot" id="cvSA" style="height:210px"></canvas>
      <canvas class="plot" id="cvSAc" style="height:140px;margin-top:6px"></canvas>
      <div class="legend"><span><i style="background:var(--c2)"></i>I<sub>ƒ</sub> funny Na⁺</span><span><i style="background:var(--c6)"></i>I<sub>CaT</sub></span><span><i style="background:var(--c3)"></i>I<sub>CaL</sub> (faz 0)</span><span><i style="background:var(--c1)"></i>I<sub>K</sub> (faz 3)</span></div>
    </div>
  </div>
  <div class="two" style="margin-top:12px">
    <div class="box"><h3>Nernst denge potansiyelleri ve Goldman<span class="ref">B1.2</span></h3><div class="scroll-x" id="nernst"></div>
      <div class="note" style="margin-top:6px">E = (61,5/z)·log([dış]/[iç]), 37 °C. Slayt sütunundaki bazı değerler farklı sabitlerle hesaplanmıştır (ör. Na⁺ +63, Cl⁻ −72). Goldman, bütün iyonları geçirgenlikleriyle birlikte hesaba katar; istirahatte P<sub>K</sub> baskın olduğu için V<sub>m</sub> ≈ E<sub>K</sub>.</div></div>
    <div class="box"><h3>Uyarılabilirlik, ileti, kasılma<span class="ref">B1.5–1.7</span></h3><div class="kv" id="cellkv"></div><div class="note" id="cellnote" style="margin-top:8px"></div></div>
  </div>`,
  ecg: () => `
  <div class="box"><h3>12 derivasyonlu EKG · 25 mm/s · 10 mm/mV<span class="ref">B2.4, B3</span></h3><div class="scroll-x"><canvas class="plot" id="cv12" style="height:440px;min-width:760px"></canvas></div></div>
  <div class="two" style="margin-top:12px">
    <div class="box"><h3>Ortalama elektriksel eksen (hekzaksiyel sistem)<span class="ref">B3.3</span></h3><canvas class="plot" id="cvAxis" style="height:270px"></canvas><div class="note" id="axisTxt"></div></div>
    <div class="box"><h3>Ölçümler ve otomatik yorum<span class="ref">B3.1–3.6</span></h3><div class="kv" id="ecgkv"></div><div id="ecgInterp" style="margin-top:8px;font-size:13px"></div></div>
  </div>`,
  cycle: () => `
  <div class="two">
    <div class="box"><h3>Wiggers diyagramı – son döngü<span class="ref">B4.2</span></h3><canvas class="plot" id="cvWig" style="height:470px"></canvas>
      <div class="legend"><span><i style="background:var(--c2)"></i>Aort</span><span><i style="background:var(--c1)"></i>Sol ventrikül</span><span><i style="background:var(--c3)"></i>Sol atriyum</span><span><i style="background:var(--c4)"></i>JVP (sağ atriyum)</span></div></div>
    <div style="display:grid;gap:12px;min-width:0">
      <div class="box"><h3>Sol ventrikül basınç–hacim halkası<span class="ref">B5.1, B6.7</span></h3><canvas class="plot" id="cvPV" style="height:290px"></canvas>
        <div class="mini" style="margin-top:6px"><button class="btn" id="pvRefBtn">Şu anki halkayı referans al</button><span class="note">Gri: referans · kesikli: ESPVR ve EDPVR</span></div>
        <div class="kv" id="pvkv"></div></div>
      <div class="box"><h3>Oskültasyon<span class="ref">B5.3–5.5</span></h3>
        <div class="mini"><label class="inl">Odak <select class="sel" id="focusSel"><option value="aort">Aort (sağ 2. ara)</option><option value="pulm">Pulmoner (sol 2. ara)</option><option value="erb">Erb (sol 3. ara)</option><option value="tri">Triküspit (sol 5. ara, sternum)</option><option value="mit" selected>Mitral (apeks)</option></select></label>
        <button class="btn" id="listenBtn">Dinle</button><label class="inl"><input type="checkbox" id="beepChk"> Monitör bipi</label></div>
        <div id="auscTxt" style="font-size:13px"></div></div>
    </div>
  </div>
  <div class="box" style="margin-top:12px"><h3>Fazların süreleri (ölçülen)<span class="ref">B4.2</span></h3><div class="scroll-x" id="phaseTbl"></div></div>`,
  vessels: () => `
  <div class="three">
    <div class="box"><h3>Organ yatakları (paralel)<span class="ref">B7.9, B8.11</span></h3><div class="scroll-x" id="bedTbl"></div><div class="note" id="bedNote"></div></div>
    <div class="box"><h3>Poiseuille laboratuvarı<span class="ref">B7.7</span></h3>
      <div class="items" style="padding:0">
        ${['r|Yarıçap (r)|0.25|2|0.05|1', 'L|Uzunluk (L)|0.5|3|0.1|1', 'eta|Viskozite (η)|0.5|3|0.1|1', 'dp|Basınç farkı (ΔP)|10|150|1|90'].map(x => { const [id, l, mn, mx, st, df] = x.split('|'); return `<div class="it"><div class="row"><label class="lab" for="pz_${id}">${l}</label><span class="val num" id="pzv_${id}"></span></div><input type="range" id="pz_${id}" min="${mn}" max="${mx}" step="${st}" value="${df}"></div>`; }).join('')}
      </div><div class="kv" id="pzOut" style="margin-top:6px"></div>
      <h3 style="margin-top:10px">Seri / paralel direnç<span class="ref">B7.9</span></h3>
      <div class="mini"><label class="inl">R₁ <input id="sp1" type="number" value="10" min="0.1" step="1" style="width:64px" class="sel"></label><label class="inl">R₂ <input id="sp2" type="number" value="10" min="0.1" step="1" style="width:64px" class="sel"></label><label class="inl">R₃ <input id="sp3" type="number" value="0" min="0" step="1" style="width:64px" class="sel"></label></div><div class="kv" id="spOut"></div></div>
    <div class="box"><h3>Viskozite ve türbülans<span class="ref">B7.4, B7.8</span></h3><div class="kv" id="viscKv"></div><div class="note" id="viscNote" style="margin-top:6px"></div></div>
  </div>
  <div class="two" style="margin-top:12px">
    <div class="box"><h3>Manşonla kan basıncı ölçümü (Korotkoff)<span class="ref">B7.5</span></h3><canvas class="plot" id="cvCuff" style="height:220px"></canvas>
      <div class="mini" style="margin-top:6px"><button class="btn primary" id="cuffBtn">Manşonu şişir ve ölç</button><span id="cuffRes" class="note"></span></div></div>
    <div class="box"><h3>Akım hızı ve toplam kesit alanı<span class="ref">B8.1</span></h3><canvas class="plot" id="cvVel" style="height:220px"></canvas><div class="note">v = Q / A · Q tüm seri bölümlerde aynıdır; kesit alanı büyüdükçe hız düşer.</div></div>
  </div>
  <div class="two" style="margin-top:12px">
    <div class="box"><h3>Kan hacminin dağılımı<span class="ref">B8.5</span></h3><div id="volTbl"></div></div>
    <div class="box"><h3>Nabız ve venöz dönüş<span class="ref">B8.4, B8.6</span></h3><div class="kv" id="pulseKv"></div></div>
  </div>`,
  cap: () => `
  <div class="two">
    <div class="box"><h3>Kapiller boyunca Starling kuvvetleri<span class="ref">B9.3</span></h3><canvas class="plot" id="cvStar" style="height:260px"></canvas><div class="kv" id="starKv" style="margin-top:8px"></div></div>
    <div class="box"><h3>Lenf ve ödem<span class="ref">B9.5, B9.6</span></h3><div id="edemaBox"></div></div>
  </div>
  <div class="two" style="margin-top:12px">
    <div class="box"><h3>Ödem senaryoları (tek tıkla)<span class="ref">B9.6</span></h3><div class="btnrow" id="edemaBtns"></div><div class="note" style="margin-top:8px">Ödem saatler içinde gelişir; bu senaryolar zamanı otomatik hızlandırır.</div></div>
    <div class="box"><h3>Kapiller tipleri ve geçirgenlik<span class="ref">B9.1, B9.2</span></h3>
      <div class="scroll-x"><table class="t"><tr><th>Tip</th><th>Yer</th></tr><tr><td>Sürekli</td><td>MSS, akciğer, kas, deri</td></tr><tr><td>Pencereli (70–100 nm)</td><td>Böbrek, ince bağırsak villusu, koroid pleksus, siliyer cisim, endokrin bezler</td></tr><tr><td>Sinüzoid</td><td>Kemik iliği, karaciğer</td></tr></table></div>
      <div class="scroll-x" style="margin-top:8px"><table class="t"><tr><th>Madde</th><th>MA</th><th>Geçirgenlik</th></tr>${[['Su', 18, 1], ['NaCl', 58.5, 0.96], ['Üre', 60, 0.8], ['Glukoz', 180, 0.6], ['Sukroz', 342, 0.4], ['İnülin', 5000, 0.2], ['Miyoglobin', 17600, 0.03], ['Hemoglobin', 68000, 0.01], ['Albümin', 69000, 0.001]].map(r => `<tr><td>${r[0]}</td><td class="n">${fmt(r[1], r[1] % 1 ? 1 : 0)}</td><td class="n">${String(r[2]).replace('.', ',')}</td></tr>`).join('')}</table></div></div>
  </div>`,
  reflex: () => `
  <div class="box"><h3>Kan basıncının sinirsel ve hormonal kontrolü – canlı<span class="ref">B10</span></h3><div class="scroll-x"><div id="svgHost" style="min-width:760px"></div></div></div>
  <div class="two" style="margin-top:12px">
    <div class="box"><h3>Baroreseptör yanıt eğrisi (karotis sinüs)<span class="ref">B10.3</span></h3><canvas class="plot" id="cvBaro" style="height:220px"></canvas><div class="note">Duyarlı aralık 60–180 mmHg, en duyarlı bölge set noktası. Sürekli yüksek basınçta eğri sağa kayar (resetting).</div></div>
    <div class="box"><h3>Eğilimler (son dakikalar, simülasyon zamanı)<span class="ref">B10.8</span></h3><canvas class="plot" id="cvTrend" style="height:220px"></canvas><div class="legend"><span><i style="background:var(--c2)"></i>MAP</span><span><i style="background:var(--c1)"></i>KH</span><span><i style="background:var(--c3)"></i>Kan hacmi</span><span><i style="background:var(--c4)"></i>Ang II</span><span><i style="background:var(--c5)"></i>ADH</span></div></div>
  </div>
  <div class="box" style="margin-top:12px"><h3>Hormon ve böbrek düzeyleri<span class="ref">B10.7, B10.8</span></h3><div class="scroll-x" id="hormTbl"></div></div>`,
  formula: () => `<div class="note" style="margin-bottom:8px">Tüm formüller; altında şu anki hastanın değerleri yerine konmuş hali.</div><div class="formula" id="fxGrid"></div>`,
};

function wirePanes() {
  // Poiseuille
  ['r', 'L', 'eta', 'dp'].forEach(k => $('pz_' + k).addEventListener('input', poiseuille));
  ['sp1', 'sp2', 'sp3'].forEach(k => $(k).addEventListener('input', serPar));
  poiseuille(); serPar();
  $('pvRefBtn').addEventListener('click', () => { pvRef = capturePV(eng); });
  $('cuffBtn').addEventListener('click', startCuff);
  $('listenBtn').addEventListener('click', () => { if (!soundOn) toggleSound(); listenOn = !listenOn; $('listenBtn').classList.toggle('on', listenOn); $('listenBtn').textContent = listenOn ? 'Dinleniyor' : 'Dinle'; });
  $('beepChk').addEventListener('change', (e) => { beepOn = e.target.checked; if (beepOn && !soundOn) toggleSound(); });
  const eb = $('edemaBtns');
  ['standEd', 'lhfEd', 'rhfEd', 'nephro', 'cirr', 'preg', 'malnut', 'burn', 'infl', 'lymph', 'filar', 'cryst'].forEach(id => { const p = D.PRESETS.find(x => x.id === id); const b = document.createElement('button'); b.className = 'btn'; b.textContent = p.n; b.addEventListener('click', () => applyPreset(id)); eb.appendChild(b); });
  buildSvg();
}
function poiseuille() {
  const r = +$('pz_r').value, L = +$('pz_L').value, eta = +$('pz_eta').value, dp = +$('pz_dp').value;
  $('pzv_r').textContent = '×' + fmt(r, 2); $('pzv_L').textContent = '×' + fmt(L, 1); $('pzv_eta').textContent = '×' + fmt(eta, 1); $('pzv_dp').textContent = fmt(dp) + ' mmHg';
  const R = 8 * L * eta / (Math.PI * Math.pow(r, 4)) / (8 / Math.PI);
  const Q = dp / R / 90;
  $('pzOut').innerHTML = `<span>Direnç R = 8Lη/πr⁴</span><span class="n">×${fmt(R, R < 10 ? 2 : 0)}</span><span class="u">normale göre</span>
    <span>Akım Q = ΔP/R</span><span class="n">×${fmt(Q, Q < 10 ? 2 : 0)}</span><span class="u">normale göre</span>
    <span class="d">r⁴ etkisi: yarıçap ×${fmt(r, 2)} → direnç ×${fmt(1 / Math.pow(r, 4), 2)}. Yarıçap yarıya inince direnç 16 kat artar, akım 16 kat azalır.</span>`;
}
function serPar() {
  const v = ['sp1', 'sp2', 'sp3'].map(k => parseFloat($(k).value) || 0).filter(x => x > 0);
  const s = v.reduce((a, b) => a + b, 0); const p = 1 / v.reduce((a, b) => a + 1 / b, 0);
  $('spOut').innerHTML = `<span>Seri: R₁ + R₂ + …</span><span class="n">${fmt(s, 1)}</span><span></span><span>Paralel: 1/(1/R₁ + 1/R₂ + …)</span><span class="n">${fmt(p, 2)}</span><span></span><span class="d">Paralel toplam her zaman en küçük dirençten küçüktür; yatak eklemek direnci düşürür.</span>`;
}

/* ---------- Hücre sekmesi ---------- */
function plotAxes(c, w, h, x0, x1, y0, y1, pad, ticksY, labelX) {
  const X = (x) => pad.l + (x - x0) / (x1 - x0) * (w - pad.l - pad.r), Y = (y) => h - pad.b - (y - y0) / (y1 - y0) * (h - pad.t - pad.b);
  c.fillStyle = C.panel; c.fillRect(0, 0, w, h);
  c.strokeStyle = C.line; c.lineWidth = 1; c.font = '10.5px JetBrains Mono, monospace'; c.fillStyle = C.muted;
  c.beginPath(); for (const ty of ticksY) { const y = Y(ty); c.moveTo(pad.l, y); c.lineTo(w - pad.r, y); c.fillText(String(ty), 2, y + 3); } c.stroke();
  if (labelX) { c.fillText(labelX, w - pad.r - c.measureText(labelX).width, h - 3); }
  return { X, Y };
}
function line(c, pts, color, wdt, dash) { c.strokeStyle = color; c.lineWidth = wdt || 1.6; c.setLineDash(dash || []); c.beginPath(); pts.forEach((p, i) => i ? c.lineTo(p[0], p[1]) : c.moveTo(p[0], p[1])); c.stroke(); c.setLineDash([]); }
function renderCell() {
  const d = eng.derived, rd = ref.derived;
  // ventrikül AP
  { const { c, w, h } = fit($('cvAP')); const ax = plotAxes(c, w, h, -0.04, 0.62, -105, 45, { l: 30, r: 8, t: 8, b: 16 }, [-90, -60, -30, 0, 30], 'zaman (s)');
    const g = [], a = []; for (let t = -0.04; t <= 0.62; t += 0.002) { g.push([ax.X(t), ax.Y(ref.ventAP(t))]); a.push([ax.X(t), ax.Y(eng.ventAP(t))]); }
    line(c, g, C.muted, 1.2, [4, 3]); line(c, a, C.c2, 2);
    c.fillStyle = C.ink; c.font = '600 11px Source Sans 3, sans-serif';
    const lab = (t, txt) => c.fillText(txt, ax.X(t), ax.Y(eng.ventAP(t)) - 6);
    lab(0.0005, '0'); lab(0.012, '1'); lab(d.apd * 0.4, '2'); lab(d.apd * 0.9, '3'); c.fillText('4', ax.X(0.55), ax.Y(d.vRest) - 6);
    c.fillStyle = C.muted; c.font = '10.5px JetBrains Mono, monospace';
    c.fillText(`Vdin ${fmt(d.vRest)} mV · APD ${fmt(d.apd * 1000)} ms`, ax.X(0.2), ax.Y(38));
    line(c, [[ax.X(-0.04), ax.Y(d.EK)], [ax.X(0.62), ax.Y(d.EK)]], C.c5, 1, [2, 4]); c.fillStyle = C.c5; c.fillText('E_K ' + fmt(d.EK), ax.X(0.47), ax.Y(d.EK) + 11);
  }
  { const { c, w, h } = fit($('cvCur')); const ax = plotAxes(c, w, h, -0.04, 0.62, -1.15, 1.15, { l: 30, r: 8, t: 6, b: 6 }, [0]);
    const S = { INa: [], Ito: [], ICaL: [], IK: [], IK1: [] };
    for (let t = -0.04; t <= 0.62; t += 0.002) { const I = eng.ventCurrents(t); S.INa.push([ax.X(t), ax.Y(-Math.min(I.INa, 1.1))]); S.Ito.push([ax.X(t), ax.Y(I.Ito * 0.8)]); S.ICaL.push([ax.X(t), ax.Y(-I.ICaL * 0.6)]); S.IK.push([ax.X(t), ax.Y(I.IK * 0.7)]); S.IK1.push([ax.X(t), ax.Y(I.IK1 * 0.4)]); }
    line(c, S.INa, C.c2, 1.6); line(c, S.Ito, C.c4, 1.6); line(c, S.ICaL, C.c3, 1.8); line(c, S.IK, C.c1, 1.8); line(c, S.IK1, C.c5, 1.4);
    c.fillStyle = C.muted; c.font = '10px Source Sans 3, sans-serif'; c.fillText('dışa akım ↑', 34, 14); c.fillText('içe akım ↓', 34, h - 8);
  }
  // SA
  const cyc = (e) => { const dd = e.derived; return (dd.saThr - dd.saMDP) / dd.saSlope + 0.05 * (1 + 0.8 * e.p.verapamil + 0.5 * e.p.diltiazem) + 0.13; };
  const span = 2.4;
  { const { c, w, h } = fit($('cvSA')); const ax = plotAxes(c, w, h, 0, span, -75, 15, { l: 30, r: 8, t: 8, b: 16 }, [-60, -40, -20, 0], 'zaman (s)');
    const cl = cyc(eng), cr = cyc(ref), g = [], a = [];
    for (let t = 0; t <= span; t += 0.004) { g.push([ax.X(t), ax.Y(ref.saAP(t % cr))]); a.push([ax.X(t), ax.Y(eng.saAP(t % cl))]); }
    line(c, g, C.muted, 1.2, [4, 3]); line(c, a, C.c3, 2);
    line(c, [[ax.X(0), ax.Y(d.saThr)], [ax.X(span), ax.Y(d.saThr)]], C.c4, 1, [3, 3]);
    c.fillStyle = C.c4; c.font = '10.5px JetBrains Mono, monospace'; c.fillText('eşik ' + fmt(d.saThr), ax.X(span) - 64, ax.Y(d.saThr) - 4);
    c.fillStyle = C.muted; c.fillText(`MDP ${fmt(d.saMDP)} mV · faz 4 eğimi ${fmt(d.saSlope)} mV/s · ${fmt(60 / cl)}/dk`, ax.X(0.05), ax.Y(12));
  }
  { const { c, w, h } = fit($('cvSAc')); const ax = plotAxes(c, w, h, 0, span, -1.2, 1.2, { l: 30, r: 8, t: 6, b: 6 }, [0]);
    const cl = cyc(eng), ph4 = (d.saThr - d.saMDP) / d.saSlope;
    const S = { f: [], t: [], l: [], k: [] };
    for (let t = 0; t <= span; t += 0.004) { const x = t % cl; const If = x < ph4 ? Math.exp(-x / (ph4 * 0.6)) * 0.8 : 0; const It = x < ph4 && x > ph4 * 0.6 ? Math.sin(Math.PI * (x - ph4 * 0.6) / (ph4 * 0.4)) * 0.5 : 0; const ICl = x > ph4 && x < ph4 + 0.08 ? Math.sin(Math.PI * (x - ph4) / 0.08) * (1 - 0.6 * eng.p.verapamil - 0.4 * eng.p.diltiazem) : 0; const IK = x > ph4 + 0.04 && x < cl ? Math.sin(Math.PI * Math.min((x - ph4 - 0.04) / (cl - ph4 - 0.02), 1)) * 0.7 : 0;
      S.f.push([ax.X(t), ax.Y(-If)]); S.t.push([ax.X(t), ax.Y(-It)]); S.l.push([ax.X(t), ax.Y(-ICl)]); S.k.push([ax.X(t), ax.Y(IK)]); }
    line(c, S.f, C.c2, 1.6); line(c, S.t, C.c6, 1.6); line(c, S.l, C.c3, 1.8); line(c, S.k, C.c1, 1.8);
  }
  // Nernst
  const p = eng.p;
  const rows = [['Na⁺', 10, p.Na, d.ENa, 63], ['K⁺', 140, p.K, d.EK, -95], ['Ca²⁺', 0.0001, p.Ca, d.ECa, 137], ['Mg²⁺', 58, p.Mg, d.EMg, 9.3], ['Cl⁻', 4, 103, d.ECl, -72], ['H⁺', '63 nM', '40 nM', -12.1, -12.1], ['HCO₃⁻', 10, 28, -27.5, -12.6]];
  $('nernst').innerHTML = `<table class="t"><tr><th>İyon</th><th>İç (mEq/L)</th><th>Dış</th><th>E (mV)</th><th>Slayt</th></tr>${rows.map(r => `<tr><td>${r[0]}</td><td class="n">${typeof r[1] === 'number' ? String(r[1]).replace('.', ',') : r[1]}</td><td class="n">${typeof r[2] === 'number' ? fmt(r[2], 1) : r[2]}</td><td class="n" style="font-weight:600">${sgn(r[3])}</td><td class="n" style="color:var(--muted)">${sgn(r[4])}</td></tr>`).join('')}
    <tr><td colspan="3"><b>Goldman istirahat potansiyeli</b> (P<sub>Na</sub>/P<sub>K</sub> = 0,012)</td><td class="n" style="font-weight:600">${sgn(d.vRest)}</td><td class="n" style="color:var(--muted)">−87</td></tr></table>`;
  const s = eng.s, m = s.m;
  $('cellkv').innerHTML = [
    ['Na⁺ kanal kullanılabilirliği', '%' + fmt(d.naAvail * 100), 'inaktivasyon + bloker'],
    ['Faz 0 eğimi / iletim hızı', '×' + fmt(d.naAvail, 2) + ' / ×' + fmt(d.cv, 2), 'iletim ∝ √(dV/dt)'],
    ['QRS süresi', fmt(m.QRS * 1000) + ' ms', '< 120'],
    ['AP süresi (≈ refrakter dönem)', fmt(d.apd * 1000) + ' ms', '~300'],
    ['QT / QTc', fmt(m.QT * 1000) + ' / ' + fmt(m.QTc * 1000) + ' ms', '350–440'],
    ['Plato (L tipi Ca²⁺ girişi)', fmt(d.plateau, 1) + ' mV', 'CICR tetikleyicisi'],
    ['Kontraktilite (LV)', '×' + fmt(s.contrLV, 2), 'sempatik, Ca²⁺, ilaç'],
    ['Sempatik β₁ / vagal etki', '%' + fmt(s.Sb * 100) + ' / %' + fmt(s.Veff * 100), ''],
  ].map(r => `<span>${r[0]}</span><span class="n">${r[1]}</span><span class="u">${r[2]}</span>`).join('');
  const notes = [];
  if (p.K > 5.5) notes.push('Hiperkalemi: dinlenim potansiyeli ' + fmt(d.vRest) + ' mV\'a yükseldi; Na⁺ kanallarının bir kısmı inaktive, faz 0 yavaş.');
  if (p.K < 3.5) notes.push('Hipokalemi: membran daha negatif, repolarizasyon yavaş (faz 3 uzun) → QT uzun, U dalgası.');
  if (p.naBlock > 0) notes.push('Na⁺ bloker: faz 0 eğimi düştü, iletim yavaşladı.');
  if (p.kBlock > 0) notes.push('K⁺ bloker: faz 3 uzadı.');
  if (p.verapamil + p.diltiazem > 0) notes.push('KKB: SA düğümünde faz 4 ve faz 0 yavaş; ventrikülde plato düşük → CICR ve kasılma ↓.');
  if (p.digoxin > 0) notes.push('Digoksin: Na⁺/K⁺-ATPaz ↓ → Ca²⁺ ↑ → kasılma ↑' + (d.digToxic ? ' · toksisite riski!' : '') + '.');
  if (s.Sb > 0.4) notes.push('Sempatik β₁: I<sub>ƒ</sub> ve I<sub>CaL</sub> ↑ → faz 4 dikleşir.');
  if (s.Veff > 0.65) notes.push('Vagal (ACh/M₂): K⁺ çıkışı ↑ → hiperpolarizasyon, faz 4 yatıklaşır.');
  $('cellnote').innerHTML = (caseState && !caseState.revealed) ? '' : notes.join(' ') || 'Değerler normal. Elektrolit veya ilaç değiştirerek AP\'nin nasıl değiştiğini izleyin; gri çizgi normaldir.';
}

/* ---------- EKG sekmesi ---------- */
let last12 = 0;
function paper(c, x, y, w, h) {
  c.fillStyle = C.dark ? '#140d0e' : '#fff7f6'; c.fillRect(x, y, w, h);
  const mm = 4; // 1 mm = 4 px
  c.lineWidth = 1;
  for (let i = 0; i * mm <= w; i++) { c.strokeStyle = i % 5 === 0 ? (C.dark ? 'rgba(220,80,90,.35)' : 'rgba(225,90,100,.45)') : (C.dark ? 'rgba(220,80,90,.12)' : 'rgba(235,130,140,.22)'); c.beginPath(); c.moveTo(x + i * mm + .5, y); c.lineTo(x + i * mm + .5, y + h); c.stroke(); }
  for (let j = 0; j * mm <= h; j++) { c.strokeStyle = j % 5 === 0 ? (C.dark ? 'rgba(220,80,90,.35)' : 'rgba(225,90,100,.45)') : (C.dark ? 'rgba(220,80,90,.12)' : 'rgba(235,130,140,.22)'); c.beginPath(); c.moveTo(x, y + j * mm + .5); c.lineTo(x + w, y + j * mm + .5); c.stroke(); }
}
function render12() {
  const cv = $('cv12'); const { c, w, h } = fit(cv);
  const mm = 4, pxs = 25 * mm, pxmv = 10 * mm;
  const rowsL = [['I', 'aVR', 'V1', 'V4'], ['II', 'aVL', 'V2', 'V5'], ['III', 'aVF', 'V3', 'V6']];
  const rowH = (h - 20) / 4;
  paper(c, 0, 0, w, h);
  const colW = w / 4, segT = colW / pxs;
  const tEnd = eng.s.t - 0.3;
  const ink = C.dark ? '#f2e9e9' : '#1a1012';
  c.strokeStyle = ink; c.lineWidth = 1.3; c.font = '600 12px Source Sans 3, sans-serif'; c.fillStyle = ink;
  for (let r = 0; r < 3; r++) for (let k = 0; k < 4; k++) {
    const lead = rowsL[r][k]; const x0 = k * colW, yb = 14 + rowH * r + rowH * 0.62;
    const t0 = tEnd - 4 * segT + k * segT;
    c.beginPath();
    for (let px = 0; px <= colW - 2; px += 1.5) { const t = t0 + px / pxs; const v = eng.leadValue(lead, t); const y = yb - v * pxmv; px ? c.lineTo(x0 + px, y) : c.moveTo(x0 + px, y); }
    c.stroke(); c.fillText(lead, x0 + 4, 14 + rowH * r + 12);
    if (k) { c.beginPath(); c.moveTo(x0, yb - 6); c.lineTo(x0, yb + 6); c.stroke(); }
  }
  // ritim şeridi DII
  const yb = 14 + rowH * 3 + rowH * 0.62;
  c.beginPath(); const tt0 = tEnd - w / pxs;
  for (let px = 0; px <= w; px += 1.5) { const t = tt0 + px / pxs; const v = eng.leadValue('II', t); const y = yb - v * pxmv; px ? c.lineTo(px, y) : c.moveTo(px, y); }
  c.stroke(); c.fillText('II (ritim)', 4, 14 + rowH * 3 + 12);
  // kalibrasyon
  c.beginPath(); c.moveTo(w - 30, yb); c.lineTo(w - 26, yb); c.lineTo(w - 26, yb - pxmv); c.lineTo(w - 18, yb - pxmv); c.lineTo(w - 18, yb); c.lineTo(w - 14, yb); c.stroke();
}
function renderEcgSide() {
  const m = eng.s.m, p = eng.p;
  // eksen
  { const { c, w, h } = fit($('cvAxis')); c.fillStyle = C.panel; c.fillRect(0, 0, w, h);
    const cx = w / 2, cy = h / 2, R = Math.min(w, h) / 2 - 26;
    // normal sektör
    c.fillStyle = C.dark ? 'rgba(63,199,163,.12)' : 'rgba(13,122,100,.10)'; c.beginPath(); c.moveTo(cx, cy); c.arc(cx, cy, R, -30 * Math.PI / 180, 90 * Math.PI / 180); c.closePath(); c.fill();
    c.fillStyle = C.dark ? 'rgba(240,168,58,.10)' : 'rgba(184,110,0,.08)'; c.beginPath(); c.moveTo(cx, cy); c.arc(cx, cy, R, -90 * Math.PI / 180, -30 * Math.PI / 180); c.closePath(); c.fill();
    c.fillStyle = C.dark ? 'rgba(111,165,255,.10)' : 'rgba(47,111,214,.08)'; c.beginPath(); c.moveTo(cx, cy); c.arc(cx, cy, R, 90 * Math.PI / 180, Math.PI); c.closePath(); c.fill();
    const leads = [['I', 0], ['II', 60], ['III', 120], ['aVR', -150], ['aVL', -30], ['aVF', 90]];
    c.font = '600 11px Source Sans 3, sans-serif';
    for (const [n, a] of leads) { const r = a * Math.PI / 180; c.strokeStyle = C.line; c.lineWidth = 1; c.beginPath(); c.moveTo(cx - Math.cos(r) * R, cy - Math.sin(r) * R); c.lineTo(cx + Math.cos(r) * R, cy + Math.sin(r) * R); c.stroke(); c.fillStyle = C.muted; c.fillText(`${n} ${a > 0 ? '+' : ''}${a}°`, cx + Math.cos(r) * (R + 4) - (Math.cos(r) < -0.3 ? 46 : Math.cos(r) < 0.3 ? 16 : 0), cy + Math.sin(r) * (R + 12) + 3); }
    const ax = m.axis || 0, r = ax * Math.PI / 180;
    c.strokeStyle = C.crit; c.fillStyle = C.crit; c.lineWidth = 3; c.beginPath(); c.moveTo(cx, cy); c.lineTo(cx + Math.cos(r) * R * 0.85, cy + Math.sin(r) * R * 0.85); c.stroke();
    c.beginPath(); c.arc(cx + Math.cos(r) * R * 0.85, cy + Math.sin(r) * R * 0.85, 4, 0, 7); c.fill();
    c.fillStyle = C.muted; c.font = '10.5px Source Sans 3, sans-serif'; c.fillText('yeşil: normal (−30°…+90°) · turuncu: sol · mavi: sağ', 6, h - 6);
  }
  const ax = m.axis;
  const zone = ax == null ? '–' : (ax >= -30 && ax <= 90) ? 'normal aks' : (ax < -30 && ax >= -90) ? 'sol aks deviasyonu' : (ax > 90 && ax <= 180) ? 'sağ aks deviasyonu' : 'ekstrem aks';
  // DI ve aVF net QRS
  const lastB = [...eng.s.beats].reverse().find(b => b.tV < eng.s.t - 0.2);
  let I = 0, F = 0, rI = 0, rII = 0, rIII = 0;
  if (lastB) { for (let t = lastB.tV; t < lastB.tV + lastB.qrs + 0.02; t += 0.002) { const a = eng.leadValue('I', t), b = eng.leadValue('aVF', t); I += a; F += b; rI = Math.max(rI, a); rII = Math.max(rII, eng.leadValue('II', t)); rIII = Math.max(rIII, eng.leadValue('III', t)); } }
  $('axisTxt').innerHTML = `Aks <b>${ax == null ? '–' : sgn(ax)}°</b> → <b>${zone}</b>. DI net QRS ${I >= 0 ? 'pozitif' : 'negatif'}, aVF ${F >= 0 ? 'pozitif' : 'negatif'}${I >= 0 && F >= 0 ? ' (normal)' : I >= 0 ? ' (sol aks olasılığı)' : F >= 0 ? ' (sağ aks olasılığı)' : ' (ekstrem)'}. Normal yetişkinde ~+59°.`;
  $('ecgkv').innerHTML = [
    ['Ritim', rhythmName(), ''], ['Kalp hızı', fmt(m.HR) + '/dk', '60–100'], ['PR', m.PR ? fmt(m.PR * 1000) + ' ms' : '–', '120–200'], ['QRS', fmt(m.QRS * 1000) + ' ms', '< 120'],
    ['QT / QTc (Bazett)', fmt(m.QT * 1000) + ' / ' + fmt(m.QTc * 1000) + ' ms', '< 440'], ['R-R', fmt(m.RRint * 1000) + ' ms = ' + fmt(m.RRint / 0.04) + ' mm', '60/RR'],
    ['Einthoven (R tepe)', `I ${fmt(rI, 2)} + III ${fmt(rIII, 2)} ≈ II ${fmt(rII, 2)} mV`, 'DI + DIII = DII'],
  ].map(r => `<span>${r[0]}</span><span class="n">${r[1]}</span><span class="u">${r[2]}</span>`).join('');
  const it = [];
  it.push(`<b>${rhythmName()}</b>, ${fmt(m.HR)}/dk${m.HR > 0 ? ' (300 kuralı: ~' + fmt(300 / Math.max(m.RRint / 0.2, 0.1)) + ')' : ''}.`);
  if (p.rhythm === 'sinus' && p.avBlock !== '3') it.push(m.PR > 0.2 ? 'PR uzamış (1. derece AV gecikme).' : 'PR normal.');
  if (p.avBlock === '2a') it.push('PR giderek uzuyor, ardından iletilmeyen P (Wenckebach).');
  if (p.avBlock === '2b') it.push('PR sabit, aralıklı iletilmeyen P (Mobitz II).');
  if (p.avBlock === '3') it.push('P ve QRS bağımsız; geniş QRS kaçış ritmi.');
  if (p.rhythm === 'af') it.push('P yok, fibrilasyon dalgaları, düzensiz RR.');
  if (p.rhythm === 'flutter') it.push('Testere dişi F dalgaları (II, III, aVF).');
  it.push(m.QRS > 0.12 ? `QRS geniş (${fmt(m.QRS * 1000)} ms)${p.bbb === 'L' ? ': sol dal bloğu – V6\'da geniş R, V1\'de derin S' : p.bbb === 'R' ? ': sağ dal bloğu – V1\'de rSR\'' : ''}.` : 'QRS dar.');
  if (p.hypertrophy === 'LVH') it.push('Yüksek voltaj ve sol aks: sol ventrikül hipertrofisi.');
  if (p.hypertrophy === 'RVH') it.push('Sağ aks, V1\'de baskın R: sağ ventrikül hipertrofisi.');
  if (p.mi === 'ant') it.push('V1–V4\'te ST elevasyonu: anterior MI.'); if (p.mi === 'inf') it.push('II, III, aVF\'de ST elevasyonu: inferior MI.');
  if (eng.s.ischemia > 0.35 && p.mi === '0') it.push('Yaygın ST çökmesi: subendokardiyal iskemi.');
  if (p.K > 6) it.push('Sivri, dar T dalgaları; P küçülmüş: hiperkalemi.'); if (p.K < 3.3) it.push('Düz T, belirgin U, uzun QT: hipokalemi.');
  if (p.digoxin > 0.3) it.push('Kaşık şeklinde ST çökmesi: digoksin etkisi.');
  if (m.QTc > 0.47) it.push('QTc uzun – aritmi riski.');
  $('ecgInterp').innerHTML = (caseState && !caseState.revealed) ? '<span class="note">Vaka modunda otomatik yorum gizli; dalgaları kendiniz yorumlayın.</span>' : it.join(' ');
}

/* ---------- Kalp döngüsü sekmesi ---------- */
let pvRef = null;
function cycleWindow(e) {
  const s = e.s; const bs = s.beats.filter(b => b.tV < s.t - 0.06 && b.kind !== 'sine');
  if (bs.length < 2) return [s.t - 1.0, s.t];
  const a = bs[bs.length - 2], b = bs[bs.length - 1];
  return [a.tV - 0.16, b.tV - 0.16];
}
function sampleWin(e, t0, t1, keys) {
  const r = e.s.rec, n = r.full ? r.n : r.i, out = keys.reduce((o, k) => (o[k] = [], o), { t: [] });
  for (let i = n - 1; i >= 0; i--) { const t = r.get('t', i); if (t < t0 || t > t1) continue; out.t.push(t); keys.forEach(k => out[k].push(r.get(k, i))); }
  return out;
}
function capturePV(e) { const [t0, t1] = cycleWindow(e); const d = sampleWin(e, t0, t1, ['Vlv', 'Plv']); return { V: d.Vlv, P: d.Plv }; }
function phases(d) {
  // geçişler
  const T = d.t, ev = {};
  for (let i = 1; i < T.length; i++) {
    if (d.mv[i - 1] > 0.5 && d.mv[i] < 0.5 && ev.mc == null) ev.mc = T[i];
    if (d.av[i - 1] < 0.5 && d.av[i] > 0.5 && ev.ao == null) ev.ao = T[i];
    if (d.av[i - 1] > 0.5 && d.av[i] < 0.5 && ev.ao != null && ev.ac == null) ev.ac = T[i];
    if (d.mv[i - 1] < 0.5 && d.mv[i] > 0.5 && ev.ac != null && ev.mo == null) ev.mo = T[i];
    if (d.aLA[i - 1] < 0.05 && d.aLA[i] >= 0.05 && ev.mo != null && ev.as2 == null) ev.as2 = T[i];
    if (d.aLA[i - 1] < 0.05 && d.aLA[i] >= 0.05 && ev.as == null && ev.mc == null) ev.as = T[i];
  }
  return ev;
}
function renderCycle() {
  const [t0, t1] = cycleWindow(eng);
  const d = sampleWin(eng, t0, t1, ['Plv', 'Pao', 'Paop', 'Pla', 'Pra', 'Vlv', 'mv', 'av', 'aLA', 'aLV']);
  // zaman artan sıraya
  const ev = phases(d);
  const { c, w, h } = fit($('cvWig')); c.fillStyle = C.panel; c.fillRect(0, 0, w, h);
  const pad = { l: 36, r: 8 }, X = (t) => pad.l + (t - t0) / (t1 - t0) * (w - pad.l - pad.r);
  const lanes = { p: [8, h * 0.46], v: [h * 0.5, h * 0.66], e: [h * 0.69, h * 0.8], s: [h * 0.82, h * 0.88], j: [h * 0.9, h - 4] };
  // faz gölgeleri
  const PH = [];
  if (ev.as != null && ev.mc != null) PH.push([ev.as, ev.mc, 'Atriyal sistol']);
  if (ev.mc != null && ev.ao != null) PH.push([ev.mc, ev.ao, 'İzovol. kasılma']);
  if (ev.ao != null && ev.ac != null) { const m = ev.ao + (ev.ac - ev.ao) / 3; PH.push([ev.ao, m, 'Hızlı fırlatma']); PH.push([m, ev.ac, 'Azalmış fırlatma']); }
  if (ev.ac != null && ev.mo != null) PH.push([ev.ac, ev.mo, 'İzovol. gevşeme']);
  if (ev.mo != null) { const end = ev.as2 || t1; const m = ev.mo + (end - ev.mo) / 3; PH.push([ev.mo, m, 'Hızlı dolum']); PH.push([m, end, 'Diyastazis']); if (ev.as2) PH.push([ev.as2, t1, 'Atriyal sistol']); }
  const tint = [C.c3, C.c2, C.c1, C.c6, C.c5, C.c4, C.c7];
  c.font = '10px Source Sans 3, sans-serif';
  PH.forEach((ph, i) => { const x0 = X(ph[0]), x1 = X(ph[1]); c.globalAlpha = 0.09; c.fillStyle = tint[i % tint.length]; c.fillRect(x0, 0, x1 - x0, h); c.globalAlpha = 1; c.fillStyle = C.muted; c.save(); c.translate(x0 + 3, lanes.p[0] + 4); c.rotate(Math.PI / 2); if (x1 - x0 > 12) c.fillText(ph[2], 0, 0); c.restore(); });
  // basınçlar
  let pmax = 140; d.Plv.forEach(v => pmax = Math.max(pmax, v + 10)); d.Pao.forEach(v => pmax = Math.max(pmax, v + 10));
  const Yp = (v) => lanes.p[1] - (v / pmax) * (lanes.p[1] - lanes.p[0]);
  c.strokeStyle = C.line; c.lineWidth = 1; c.beginPath(); c.fillStyle = C.muted; c.font = '10px JetBrains Mono, monospace';
  for (let g = 0; g <= pmax; g += 40) { c.moveTo(pad.l, Yp(g)); c.lineTo(w - pad.r, Yp(g)); c.fillText(String(g), 4, Yp(g) + 3); } c.stroke();
  const L = (arr, Y, col, wd) => line(c, arr.map((v, i) => [X(d.t[i]), Y(v)]), col, wd);
  L(d.Paop, Yp, C.c2, 1.8); L(d.Plv, Yp, C.c1, 2); L(d.Pla, Yp, C.c3, 1.6);
  c.fillStyle = C.muted; c.fillText('mmHg', 4, lanes.p[0] + 8);
  // hacim
  let vmin = 1e9, vmax = -1e9; d.Vlv.forEach(v => { vmin = Math.min(vmin, v); vmax = Math.max(vmax, v); }); vmin = Math.floor(vmin / 10) * 10 - 10; vmax = Math.ceil(vmax / 10) * 10 + 10;
  const Yv = (v) => lanes.v[1] - (v - vmin) / (vmax - vmin) * (lanes.v[1] - lanes.v[0]);
  L(d.Vlv, Yv, C.c5, 1.8); c.fillStyle = C.muted; c.fillText('LV ' + Math.round(vmax - 10) + ' ml', 4, lanes.v[0] + 8); c.fillText(Math.round(vmin + 10) + '', 4, lanes.v[1]);
  // EKG
  const ecg = []; for (let t = t0; t <= t1; t += 0.004) ecg.push([X(t), (lanes.e[0] + lanes.e[1]) / 2 + 6 - eng.leadValue('II', t) * 16]);
  line(c, ecg, C.ink, 1.3); c.fillStyle = C.muted; c.fillText('EKG II', 4, lanes.e[0] + 8);
  // sesler
  c.fillText('Sesler', 4, lanes.s[1]);
  const evs = eng.s.events.filter(x => x.t >= t0 && x.t <= t1);
  const sMap = { M1: 'S1', A2: 'S2', P2: 'P2', MO: eng.p.MS > 0.3 ? 'OS' : null };
  c.font = '600 11px Source Sans 3, sans-serif';
  evs.forEach(x => { const n = sMap[x.k]; if (!n) return; const xx = X(x.t); c.fillStyle = n === 'P2' ? C.c4 : C.c2; c.fillRect(xx - 1.5, lanes.s[0], 3, lanes.s[1] - lanes.s[0]); c.fillText(n, xx + 3, lanes.s[0] + 9); });
  extraSounds(t0, t1).forEach(sx => { const xx = X(sx.t); c.fillStyle = C.c5; c.fillRect(xx - 1, lanes.s[0] + 2, 2, lanes.s[1] - lanes.s[0] - 2); c.fillText(sx.n, xx + 3, lanes.s[0] + 9); });
  // JVP
  let jmin = 1e9, jmax = -1e9; d.Pra.forEach(v => { jmin = Math.min(jmin, v); jmax = Math.max(jmax, v); }); if (jmax - jmin < 4) { jmax += 2; jmin -= 2; }
  const Yj = (v) => lanes.j[1] - (v - jmin) / (jmax - jmin) * (lanes.j[1] - lanes.j[0]);
  L(d.Pra, Yj, C.c4, 1.6); c.fillStyle = C.muted; c.font = '10px JetBrains Mono, monospace'; c.fillText('JVP', 4, lanes.j[0] + 8);
  // a c x v y etiketleri
  const lbl = (t, txt) => { if (t == null || t < t0 || t > t1) return; let i = d.t.findIndex(x => x >= t); if (i < 0) return; c.fillStyle = C.c4; c.font = '600 11px Source Sans 3, sans-serif'; c.fillText(txt, X(t) - 3, Yj(d.Pra[i]) - 4); };
  if (eng.p.rhythm === 'sinus') { const asT = ev.as2 || ev.as; lbl(asT != null ? asT + 0.05 : null, 'a'); }
  lbl(ev.mc != null ? ev.mc + 0.03 : null, 'c'); lbl(ev.ao != null ? ev.ao + 0.09 : null, 'x'); lbl(ev.mo != null ? ev.mo - 0.02 : null, 'v'); lbl(ev.mo != null ? ev.mo + 0.09 : null, 'y');
  // PV halkası
  const pv = { V: d.Vlv, P: d.Plv };
  { const { c, w, h } = fit($('cvPV'));
    let vmx = 180, pmx = 150; pv.V.forEach(v => vmx = Math.max(vmx, v + 15)); pv.P.forEach(v => pmx = Math.max(pmx, v + 15));
    if (pvRef) { pvRef.V.forEach(v => vmx = Math.max(vmx, v + 15)); pvRef.P.forEach(v => pmx = Math.max(pmx, v + 15)); }
    const ax = plotAxes(c, w, h, 0, vmx, -5, pmx, { l: 30, r: 10, t: 8, b: 18 }, [0, 40, 80, 120, 160, 200].filter(x => x < pmx), 'LV hacmi (ml)');
    c.fillStyle = C.muted; c.font = '10px JetBrains Mono, monospace'; for (let vv = 0; vv <= vmx; vv += 40) c.fillText(String(vv), ax.X(vv) - 6, h - 4);
    if (!pvRef) pvRef = refPV;
    if (pvRef) line(c, pvRef.V.map((v, i) => [ax.X(v), ax.Y(pvRef.P[i])]), C.muted, 1.4, [4, 3]);
    // ESPVR / EDPVR
    const Es = 2.6 * eng.s.contrLV * (eng.p.hypertrophy === 'LVH' ? 1.3 : 1), V0 = 10;
    const pit = -3.5;
    line(c, [[ax.X(V0), ax.Y(pit)], [ax.X(Math.min(vmx, V0 + (pmx - pit) / Es)), ax.Y(Math.min(pmx, Es * (Math.min(vmx, V0 + (pmx - pit) / Es) - V0) + pit))]], C.c2, 1, [2, 4]);
    const A = 0.38 * eng.p.stiffness * (eng.p.hypertrophy === 'LVH' ? 1.9 : 1) * (1 + 0.6 * clamp(eng.s.ischemia, 0, 1)) * (eng.p.mi !== '0' ? 1.3 : 1);
    const ed = []; for (let v = V0; v <= vmx; v += 2) { const pp = A * (Math.exp(0.031 * (v - V0)) - 1) + pit; if (pp > pmx) break; ed.push([ax.X(v), ax.Y(pp)]); } line(c, ed, C.c3, 1, [2, 4]);
    line(c, pv.V.map((v, i) => [ax.X(v), ax.Y(pv.P[i])]), C.c1, 2.2);
    // noktalar A-F (slayttaki gibi)
    const pt = (t, L) => { if (t == null) return; const i = d.t.findIndex(x => x >= t); if (i < 0) return; c.fillStyle = C.ink; c.beginPath(); c.arc(ax.X(d.Vlv[i]), ax.Y(d.Plv[i]), 3, 0, 7); c.fill(); c.font = '600 11px Source Sans 3, sans-serif'; c.fillText(L, ax.X(d.Vlv[i]) + 5, ax.Y(d.Plv[i]) - 4); };
    pt(ev.mo, 'A'); pt(ev.mc, 'C'); pt(ev.ao, 'D'); pt(ev.ac, 'F');
    if (ev.ao != null && ev.ac != null) { let im = 0, pm = -1e9; d.t.forEach((t, i) => { if (t > ev.ao && t < ev.ac && d.Plv[i] > pm) { pm = d.Plv[i]; im = i; } }); c.fillStyle = C.ink; c.beginPath(); c.arc(ax.X(d.Vlv[im]), ax.Y(d.Plv[im]), 3, 0, 7); c.fill(); c.fillText('E', ax.X(d.Vlv[im]) + 5, ax.Y(d.Plv[im]) - 4); }
    // atım işi (alan)
    let area = 0; for (let i = 1; i < pv.V.length; i++) area += (pv.V[i] - pv.V[i - 1]) * (pv.P[i] + pv.P[i - 1]) / 2;
    const m = eng.s.m;
    $('pvkv').innerHTML = [['EDV / ESV', fmt(m.EDV) + ' / ' + fmt(m.ESV) + ' ml', '120 / 50'], ['SV (halka genişliği)', fmt(m.SV) + ' ml', '~70'], ['EF', '%' + fmt(m.EF * 100), '%55–70'], ['LV sistolik / diyastol sonu', fmt(m.LVSP) + ' / ' + fmt(m.LVEDP, 1) + ' mmHg', '120 / 5–12'], ['Atım işi (halka alanı)', fmt(Math.abs(area) * 0.0001333, 2) + ' J', '~1'], ['ESPVR eğimi (kontraktilite)', fmt(Es, 2) + ' mmHg/ml', '2,6']].map(r => `<span>${r[0]}</span><span class="n">${r[1]}</span><span class="u">${r[2]}</span>`).join('');
  }
  // faz tablosu
  const dur = (a, b) => (a != null && b != null) ? Math.round((b - a) * 1000) : null;
  const rr = eng.s.m.RRint;
  const rows = [['İzovolümetrik kasılma', dur(ev.mc, ev.ao), 50], ['Fırlatma (hızlı + azalmış)', dur(ev.ao, ev.ac), 300], ['İzovolümetrik gevşeme', dur(ev.ac, ev.mo), 80], ['Dolum (diyastol)', ev.mo != null ? Math.round((t1 - ev.mo) * 1000) : null, 400], ['Döngü (R-R)', Math.round(rr * 1000), 800], ['S2 çiftleşmesi (A2–P2)', Math.round(eng.s.m.split * 1000), '20–40']];
  $('phaseTbl').innerHTML = `<table class="t"><tr><th>Faz</th><th>Ölçülen (ms)</th><th>Normal (ms)</th></tr>${rows.map(r => `<tr><td>${r[0]}</td><td class="n">${r[1] == null ? '–' : r[1]}</td><td class="n" style="color:var(--muted)">${r[2]}</td></tr>`).join('')}</table>`;
  ausculText();
}
let refPV = null;
function extraSounds(t0, t1) {
  const out = [], p = eng.p, s = eng.s;
  const s3 = hasS3(), s4 = hasS4();
  for (const ev of s.events) { if (ev.t < t0 - 0.3 || ev.t > t1) continue; if (ev.k === 'MO' && s3) out.push({ t: ev.t + 0.12, n: 'S3' }); }
  for (const a of s.atrial) { if (a.kind !== 'p' || !s4) continue; const t = a.t + 0.1; if (t >= t0 && t <= t1) out.push({ t, n: 'S4' }); }
  return out.filter(x => x.t >= t0 && x.t <= t1);
}
function hasS3() { const p = eng.p, m = eng.s.m; return (m.EF < 0.42 && m.LAP > 12) || p.MR > 0.35 || p.AR > 0.45 || p.arterialStiff < 0.06 || p.temp > 39 || p.thyroid > 1.8 || eng.derived.hct < 0.28 || m.EDV > 170; }
function hasS4() { const p = eng.p; return p.rhythm === 'sinus' && p.avBlock !== '3' && (p.stiffness > 1.6 || p.hypertrophy !== '0' || eng.s.ischemia > 0.4 || p.mi !== '0' || p.AS > 0.6); }
function ausculText() {
  const p = eng.p, m = eng.s.m, f = $('focusSel').value, L = [];
  const s1 = m.PR > 0.22 ? 'yumuşak' : (eng.s.Sb > 0.5 || m.PR < 0.13 || p.MS > 0.4) ? 'şiddetli' : 'normal';
  L.push(`<b>S1</b> (M1T1, "lab"): ${s1}.`);
  const sp = Math.round(m.split * 1000);
  L.push(`<b>S2</b> (A2P2, "dab"): ${p.bbb === 'L' || p.AS > 0.7 ? 'paradoks çiftleşme (A2 gecikiyor)' : p.bbb === 'R' || p.pe > 0.4 ? 'geniş çiftleşme' : p.respOn ? 'inspirasyonda fizyolojik çiftleşme' : 'tek'} · A2–P2 ≈ ${sp} ms.`);
  if (hasS3()) L.push('<b>S3</b>: erken diyastolik dolum sesi (apeks).');
  if (hasS4()) L.push('<b>S4</b>: geç diyastol, sertleşmiş ventriküle atriyal kasılma.');
  const mur = [];
  if (p.AS > 0.2) mur.push(['aort', 'Sistolik ejeksiyon üfürümü (crescendo-decrescendo), boyna yayılır']);
  if (p.AR > 0.2) mur.push(['erb', 'Erken diyastolik dekresendo üfürüm']);
  if (p.MR > 0.2) mur.push(['mit', 'Holosistolik üfürüm, aksillaya yayılır']);
  if (p.MS > 0.2) mur.push(['mit', 'Düşük frekanslı diyastolik rulman + açılma sesi (OS)']);
  if (m.Re > 2600 || eng.derived.hct < 0.28) mur.push(['pulm', 'Yumuşak sistolik akım üfürümü (türbülans: Re yüksek)']);
  mur.forEach(([foc, t]) => L.push(`<b>Üfürüm</b>: ${t}${foc === f ? ' – <span class="pill w">bu odakta en iyi</span>' : ''}.`));
  if (!mur.length) L.push('Üfürüm yok (laminar akım).');
  L.push('<span class="note">Dinlemek için "Dinle"ye basın; kulaklık önerilir.</span>');
  $('auscTxt').innerHTML = L.join('<br>');
}

/* ---------- Damarlar sekmesi ---------- */
let cuff = null;
function startCuff() { cuff = { p: Math.max(eng.s.m.SBP + 30, 160), t0: eng.s.t, sys: null, dia: null, lastTap: 0, trace: [], heardRun: 0 }; $('cuffRes').textContent = 'Manşon iniyor…'; }
function stepCuff(dt) {
  if (!cuff) return;
  cuff.p -= 6 * dt;
  const P = eng.s.inst.Par;
  cuff.trace.push([eng.s.t, P, cuff.p]); if (cuff.trace.length > 3000) cuff.trace.shift();
  // ses: arter basıncı manşonu aştığında kısa açılma (sistol tepeleri)
  const open = P > cuff.p;
  if (open && !cuff.wasOpen && cuff.p > (eng.s.m.DBP - 1)) {
    if (cuff.sys == null) cuff.sys = cuff.p;
    cuff.lastTap = eng.s.t; korotkoff(clamp((P - cuff.p) / 25, 0.15, 1));
  }
  cuff.wasOpen = open;
  if (cuff.sys != null && cuff.p < eng.s.m.DBP - 1 && cuff.dia == null) cuff.dia = cuff.p + 1;
  if (cuff.p < Math.min(30, eng.s.m.DBP - 20) || (cuff.dia != null && cuff.p < cuff.dia - 15)) {
    $('cuffRes').innerHTML = cuff.sys ? `İlk ses <b>${fmt(cuff.sys)}</b> (sistolik), seslerin kaybolduğu <b>${fmt(cuff.dia)}</b> (diyastolik) mmHg · monitör ${fmt(eng.s.m.SBP)}/${fmt(eng.s.m.DBP)}` : 'Ses alınamadı (çok düşük basınç).';
    cuff.done = true;
  }
}
function renderVessels() {
  const s = eng.s, m = s.m, d = eng.derived, p = eng.p;
  const tot = E.BEDS.reduce((a, b) => a + (s.bedQ[b.id] || 0), 0);
  $('bedTbl').innerHTML = `<table class="t"><tr><th>Yatak</th><th>Akım</th><th>%CO</th><th>r</th><th></th></tr>${E.BEDS.map(b => { const q = s.bedQ[b.id] || 0; const r = (s.bedRadius || {})[b.id] || 1; return `<tr><td>${b.name}</td><td class="n">${fmt(q)}</td><td class="n">${fmt(q / tot * 100)}</td><td class="n">×${fmt(r, 2)}</td><td style="width:34%"><div class="bar"><span style="width:${clamp(q / 3000 * 100, 1, 100)}%;background:${r > 1.04 ? 'var(--c3)' : r < 0.96 ? 'var(--c2)' : 'var(--accent)'}"></span></div></td></tr>`; }).join('')}</table>`;
  const tprW = s.TPR * 1000 / 60;
  $('bedNote').innerHTML = `ml/dk. Toplam ${fmt(tot)} ml/dk. TPR = 1/Σ(1/Rᵢ) = <b>${fmt(tprW, 1)}</b> mmHg·dk/L · MAP ≈ CO × TPR = ${fmt(m.CO, 1)} × ${fmt(tprW, 1)} + CVP ≈ <b>${fmt(m.CO * tprW + m.CVP)}</b> (ölçülen ${fmt(m.MAP)}). Mavi: dilatasyon, kırmızı: konstriksiyon.`;
  $('viscKv').innerHTML = [
    ['Hematokrit', '%' + fmt(d.hct * 100), '40–45'], ['η yüksek kaymada', fmt(d.etaRel, 1) + '× su', '3–5'], ['η düşük kaymada', fmt(d.etaLowShear) + '× su', '50–200'],
    ['Dirence etkisi', '×' + fmt(d.viscF, 2), '1'], ['Aort ortalama hız', fmt(m.vAorta) + ' cm/s', '~20'], ['Reynolds (aort, ortalama hız)', fmt(m.Re), '< 2000 laminar'],
    ['Albümin → πc', fmt(d.alb, 1) + ' → ' + fmt(d.piC, 1), 'g/dL → mmHg'],
  ].map(r => `<span>${r[0]}</span><span class="n">${r[1]}</span><span class="u">${r[2]}</span>`).join('');
  const tb = []; if (m.Re > 2000) tb.push('Re > 2000: türbülans eğilimi (akım üfürümü).'); if (p.AS > 0.3) tb.push('Dar aort kapağından sonra genişleme → jet ve türbülans.'); if (d.hct < 0.3) tb.push('Anemi: viskozite ↓, hız ↑ → Re ↑.'); if (d.hct > 0.55) tb.push('Polisitemi: viskozite ↑ → TPR ↑, CO ↓.');
  $('viscNote').textContent = tb.join(' ') || 'Re = DVρ/η. Laminar akımda profil paraboliktir; en hızlı akım merkezdedir.';
  // manşon
  { const { c, w, h } = fit($('cvCuff')); const tr = cuff ? cuff.trace : [];
    const tE = eng.s.t, tS = tE - 14; const ax = plotAxes(c, w, h, tS, tE, 0, 200, { l: 30, r: 8, t: 8, b: 14 }, [0, 40, 80, 120, 160, 200]);
    if (tr.length) { line(c, tr.filter(x => x[0] > tS).map(x => [ax.X(x[0]), ax.Y(x[1])]), C.c2, 1.6); line(c, tr.filter(x => x[0] > tS).map(x => [ax.X(x[0]), ax.Y(x[2])]), C.c3, 1.6, [5, 3]);
      c.fillStyle = C.muted; c.font = '10.5px Source Sans 3, sans-serif'; c.fillText('kırmızı: arter basıncı · mavi kesikli: manşon', 34, 16);
      if (cuff.sys) { c.fillStyle = C.c2; c.fillText('sistolik ' + fmt(cuff.sys), w - 90, ax.Y(cuff.sys) - 3); } if (cuff.dia) { c.fillText('diyastolik ' + fmt(cuff.dia), w - 100, ax.Y(cuff.dia) + 12); } }
    else { c.fillStyle = C.muted; c.font = '12px Source Sans 3, sans-serif'; c.fillText('Ölçüm için düğmeye basın (ses açıksa Korotkoff sesleri duyulur).', 36, h / 2); }
  }
  // hız – kesit
  { const { c, w, h } = fit($('cvVel')); c.fillStyle = C.panel; c.fillRect(0, 0, w, h);
    const V = [['Aort', 4.5], ['Arter', 20], ['Arteriyol', 400], ['Kapiller', 4500], ['Venül', 4000], ['Ven', 40], ['V. kava', 18]];
    const q = m.CO * 1000 / 60; const bw = (w - 40) / V.length;
    const maxLogA = Math.log10(5000);
    c.font = '10.5px Source Sans 3, sans-serif';
    V.forEach((v, i) => { const x = 30 + i * bw; const ah = Math.log10(v[1]) / maxLogA * (h * 0.55); c.fillStyle = C.dark ? 'rgba(240,168,58,.35)' : 'rgba(184,110,0,.25)'; c.fillRect(x + 4, h - 22 - ah, bw - 8, ah); c.fillStyle = C.muted; c.fillText(v[0], x + 4, h - 8); });
    const pts = V.map((v, i) => { const vel = q / v[1]; return [30 + i * bw + bw / 2, h - 22 - clamp(Math.log10(vel * 100 + 1) / Math.log10(2500) * (h * 0.75), 2, h - 30), vel]; });
    line(c, pts.map(x => [x[0], x[1]]), C.c1, 2.2);
    pts.forEach(x => { c.fillStyle = C.c1; c.beginPath(); c.arc(x[0], x[1], 3, 0, 7); c.fill(); c.fillStyle = C.ink; c.fillText(x[2] >= 1 ? fmt(x[2], 1) : fmt(x[2], 3), x[0] - 12, x[1] - 7); });
    c.fillStyle = C.muted; c.fillText('çizgi: ortalama hız (cm/s) · sütun: toplam kesit alanı (log)', 30, 12);
  }
  // hacim dağılımı
  const vol = [['Sistemik venler', s.Vsv], ['Sistemik arterler', s.Var + s.Vao], ['Pulmoner damarlar', s.Vpa + s.Vpv], ['Kalp odaları', s.Vlv + s.Vrv + s.Vla + s.Vra]];
  const BV = eng.bloodVolume();
  $('volTbl').innerHTML = `<table class="t"><tr><th>Bölüm</th><th>ml</th><th>%</th><th></th></tr>${vol.map(v => `<tr><td>${v[0]}</td><td class="n">${fmt(v[1])}</td><td class="n">${fmt(v[1] / BV * 100)}</td><td style="width:40%"><div class="bar"><span style="width:${v[1] / BV * 100}%"></span></div></td></tr>`).join('')}<tr><td><b>Toplam kan hacmi</b></td><td class="n"><b>${fmt(BV)}</b></td><td></td><td class="note">Hct %${fmt(d.hct * 100)} · plazma ${fmt(s.plasma)} ml</td></tr></table><div class="note" style="margin-top:4px">Slayttaki dağılım: ven ve venüller %61 (kapasitans damarları), pulmoner %12, arterler %11, kalp %9, arteriyol + kapiller %7.</div>`;
  // nabız
  const pp = m.SBP - m.DBP;
  const rrCV = (() => { const b = eng.s.beats.slice(-8); if (b.length < 4) return 0; const rr = []; for (let i = 1; i < b.length; i++) rr.push(b[i].tV - b[i - 1].tV); const mu = rr.reduce((a, x) => a + x, 0) / rr.length; return Math.sqrt(rr.reduce((a, x) => a + (x - mu) ** 2, 0) / rr.length) / mu; })();
  $('pulseKv').innerHTML = [
    ['Nabız sayısı', fmt(m.HR) + '/dk', m.HR > 100 ? 'taşikardi' : m.HR < 60 ? 'bradikardi' : 'normal'], ['Nabız basıncı (dolgunluk)', fmt(pp) + ' mmHg', pp > 60 ? 'dolgun (sıçrayıcı)' : pp < 25 ? 'zayıf, ipliksi' : 'normal'],
    ['Gerginlik', 'MAP ' + fmt(m.MAP), m.MAP > 105 ? 'gergin (HT)' : m.MAP < 70 ? 'yumuşak (hipotansiyon)' : 'normal'], ['Düzen (RR değişkenliği)', '%' + fmt(rrCV * 100), rrCV > 0.12 ? 'düzensiz' : 'düzenli'],
    ['CVP', fmt(m.CVP, 1) + ' mmHg', '0–5'], ['Solunum pompası', p.respOn ? 'aktif' : 'kapalı', 'inspirasyon VR ↑'], ['İskelet kası pompası', p.exercise > 0 ? 'aktif (%' + fmt(p.exercise * 100) + ')' : p.posture === 'standing' ? 'yok – göllenme' : 'istirahat', 'kapaklarla'],
    ['Venöz gerilmemiş hacim (V₀)', fmt(s.V0sv) + ' ml', '~2700; ↓ = venokonstriksiyon'],
  ].map(r => `<span>${r[0]}</span><span class="n">${r[1]}</span><span class="u">${r[2]}</span>`).join('');
}

/* ---------- Kapiller sekmesi ---------- */
function renderCap() {
  const s = eng.s, d = eng.derived, p = eng.p;
  const sigma = 1 / (1 + 0.35 * (s.permEff - 1));
  const { c, w, h } = fit($('cvStar'));
  const ax = plotAxes(c, w, h, 0, 1, -5, Math.max(50, s.PcA + 8), { l: 30, r: 10, t: 10, b: 18 }, [0, 10, 20, 30, 40, 50]);
  const out = (x) => s.PcA + (s.PcV - s.PcA) * x + s.piIF, inn = () => d.piC * sigma + s.Pif;
  // gölge
  for (let x = 0; x < 1; x += 0.01) { const o = out(x), i = inn(); c.fillStyle = o > i ? (C.dark ? 'rgba(255,107,94,.18)' : 'rgba(194,54,43,.14)') : (C.dark ? 'rgba(111,165,255,.18)' : 'rgba(47,111,214,.14)'); c.fillRect(ax.X(x), ax.Y(Math.max(o, i)), ax.X(x + 0.01) - ax.X(x) + 0.5, Math.abs(ax.Y(o) - ax.Y(i))); }
  line(c, [[ax.X(0), ax.Y(s.PcA)], [ax.X(1), ax.Y(s.PcV)]], C.c2, 2.2);
  line(c, [[ax.X(0), ax.Y(out(0))], [ax.X(1), ax.Y(out(1))]], C.c2, 1, [3, 3]);
  line(c, [[ax.X(0), ax.Y(inn())], [ax.X(1), ax.Y(inn())]], C.c3, 2.2);
  c.font = '600 11px Source Sans 3, sans-serif'; c.fillStyle = C.c2; c.fillText('Pc (hidrostatik)', ax.X(0.02), ax.Y(s.PcA) - 6); c.fillStyle = C.c3; c.fillText('πc·σ + Pif (onkotik)', ax.X(0.62), ax.Y(inn()) - 6);
  c.fillStyle = C.muted; c.font = '10.5px Source Sans 3, sans-serif'; c.fillText('arteriyel uç', ax.X(0) + 2, h - 4); c.fillText('venöz uç', ax.X(1) - 46, h - 4);
  c.fillText(p.starling === 'classic' ? 'kırmızı alan: filtrasyon · mavi: reabsorbsiyon' : 'güncel model: mavi bölgede sürekli reabsorbsiyon olmaz, lenf taşır', ax.X(0.02), 14);
  $('starKv').innerHTML = [
    ['Pc arteriyel / venöz uç', fmt(s.PcA, 1) + ' / ' + fmt(s.PcV, 1) + ' mmHg', '35 / 16'], ['πc plazma (σ ile)', fmt(d.piC * sigma, 1) + ' mmHg', '26'], ['πif interstisyel', fmt(s.piIF, 1) + ' mmHg', '0,1–5'], ['Pif interstisyel', fmt(s.Pif, 1) + ' mmHg', '≈ 0'],
    ['NFB arteriyel uç', sgn(s.nfpA) + ' mmHg', '+10'], ['NFB venöz uç', sgn(s.nfpV) + ' mmHg', '−9'],
    ['NFB = (Pc + πif) − (πc + Pif)', '', ''],
  ].map(r => `<span>${r[0]}</span><span class="n">${r[1]}</span><span class="u">${r[2]}</span>`).join('');
  const Lmax = 14 * p.lymph;
  const grade = s.dVi < 1500 ? ['g', 'yok'] : s.dVi < 4000 ? ['w', 'hafif (+)'] : s.dVi < 9000 ? ['c', 'belirgin (++)'] : ['c', 'anazarka (+++)'];
  const lung = s.dVlung < 150 ? ['g', 'yok'] : s.dVlung < 450 ? ['w', 'interstisyel ödem'] : ['c', 'alveoler ödem'];
  $('edemaBox').innerHTML = `
    <div class="kv">
      <span>Net filtrasyon (sistemik)</span><span class="n">${fmt(s.Jsys, 1)} ml/dk</span><span class="u">~2</span>
      <span>Lenf akımı / kapasite</span><span class="n">${fmt(s.Lsys, 1)} / ${fmt(Lmax, 1)}</span><span class="u">ml/dk</span>
      <span>Geçici reabsorbsiyon</span><span class="n">${fmt(s.transReab || 0, 1)} ml/dk</span><span class="u">Pc ani ↓</span>
      <span>İnterstisyel sıvı fazlası</span><span class="n">${sgn(s.dVi)} ml</span><span class="u"><span class="pill ${grade[0]}">${grade[1]}</span></span>
      <span>Akciğer kapiller basıncı</span><span class="n">${fmt(s.PcL, 1)} mmHg</span><span class="u">~7–10</span>
      <span>Akciğer interstisyumu</span><span class="n">${sgn(s.dVlung)} ml</span><span class="u"><span class="pill ${lung[0]}">${lung[1]}</span></span>
      <span>Bacak (ayak bileği) Pc</span><span class="n">${fmt(s.legPc, 0)} mmHg</span><span class="u">${s.legEdema > 300 ? '<span class="pill w">bacak ödemi</span>' : ''}</span>
      <span>Plazma / kan hacmi</span><span class="n">${fmt(s.plasma)} / ${fmt(eng.bloodVolume())} ml</span><span class="u"></span>
    </div>
    <div style="margin-top:8px"><div class="note">Lenf kullanım oranı</div><div class="bar"><span style="width:${clamp(s.Lsys / Math.max(Lmax, 0.1) * 100, 0, 100)}%;background:${s.Lsys / Math.max(Lmax, 0.1) > 0.9 ? 'var(--crit)' : 'var(--accent)'}"></span></div></div>
    <div class="note" style="margin-top:8px">Filtrasyon lenf kapasitesini aştığında ödem başlar. Lenf: lenf kapillerleri → lenf düğümleri → duktus torasikus / sağ lenfatik kanal → subklavyen venler. Kapakları tek yönlüdür; kas ve solunum pompası, sempatikler akımı artırır.</div>`;
}

/* ---------- Refleksler sekmesi ---------- */
const NODES = [
  ['baro', 20, 30, 190, 'Baroreseptörler', 'karotis sinüs · arcus aorta'],
  ['aff', 20, 112, 190, 'IX (Hering) · X (aortik)', 'afferent'],
  ['nts', 250, 70, 150, 'NTS', 'glutamat → AMPA'],
  ['cvlm', 250, 160, 150, 'CVLM', 'GABA → RVLM inhibe'],
  ['rvlm', 250, 250, 150, 'RVLM', 'sempatik çıkış'],
  ['amb', 450, 70, 160, 'n. ambiguus', 'vagus → SA, AV'],
  ['heart', 650, 30, 220, 'Kalp', 'β₁ / M₂'],
  ['arter', 650, 130, 220, 'Arteriyoller (α₁)', 'TPR'],
  ['vein', 650, 220, 220, 'Venler (α₁)', 'kapasitans'],
  ['chemo', 20, 200, 190, 'Kemoreseptörler', 'karotis/aort cisimciği'],
  ['cns', 20, 280, 190, 'MSS iskemik yanıt', 'CPP = MAP − ICP'],
  ['cp', 450, 160, 160, 'Kardiyopulmoner', 'Bainbridge · ADH ↓'],
  ['kid', 20, 380, 170, 'Böbrek perfüzyonu', 'basınç natriürezi'],
  ['renin', 210, 380, 120, 'Renin', 'jukstaglomerüler'],
  ['ang', 350, 380, 120, 'Ang II', 'vazokonstriksiyon'],
  ['aldo', 490, 380, 130, 'Aldosteron', 'Na⁺ tutulumu'],
  ['adh', 640, 330, 110, 'ADH', 'V₂ su · V₁ damar'],
  ['anp', 770, 330, 100, 'ANP', 'natriürez'],
  ['vol', 640, 420, 230, 'Kan hacmi · idrar', 'uzun süreli denge'],
];
const EDGES = [['baro', 'aff'], ['aff', 'nts'], ['nts', 'cvlm'], ['cvlm', 'rvlm'], ['nts', 'amb'], ['amb', 'heart'], ['rvlm', 'heart'], ['rvlm', 'arter'], ['rvlm', 'vein'], ['chemo', 'rvlm'], ['cns', 'rvlm'], ['cp', 'heart'], ['kid', 'renin'], ['renin', 'ang'], ['ang', 'aldo'], ['ang', 'arter'], ['aldo', 'vol'], ['adh', 'vol'], ['anp', 'vol'], ['cp', 'adh']];
function buildSvg() {
  const nb = {}; NODES.forEach(n => nb[n[0]] = n);
  const H = 470;
  let s = `<svg viewBox="0 0 900 ${H}" width="100%" role="img" aria-label="Kan basıncı kontrolü şeması"><defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="var(--muted)"/></marker></defs>`;
  EDGES.forEach(([a, b]) => { const A = nb[a], B = nb[b]; const ax = A[1] + A[3] / 2, ay = A[2] + 26, bx = B[1] + B[3] / 2, by = B[2] + 26; let x1 = ax, y1 = ay, x2 = bx, y2 = by; if (Math.abs(bx - ax) > Math.abs(by - ay)) { x1 = bx > ax ? A[1] + A[3] : A[1]; x2 = bx > ax ? B[1] : B[1] + B[3]; } else { y1 = by > ay ? A[2] + 52 : A[2]; y2 = by > ay ? B[2] : B[2] + 52; } s += `<path d="M${x1} ${y1} L${x2} ${y2}" stroke="var(--muted)" stroke-width="1.2" fill="none" marker-end="url(#ar)" id="e_${a}_${b}"/>`; });
  NODES.forEach(n => { s += `<g id="nd_${n[0]}"><rect x="${n[1]}" y="${n[2]}" width="${n[3]}" height="52" rx="8" fill="var(--panel)" stroke="var(--line)" stroke-width="1.2"/><rect class="glow" x="${n[1]}" y="${n[2]}" width="${n[3]}" height="52" rx="8" fill="var(--accent)" fill-opacity="0"/><text x="${n[1] + 8}" y="${n[2] + 17}" font-size="13" font-weight="600" fill="var(--ink)">${n[4]}</text><text x="${n[1] + 8}" y="${n[2] + 31}" font-size="10.5" fill="var(--muted)">${n[5]}</text><text class="vv" x="${n[1] + 8}" y="${n[2] + 46}" font-size="11.5" font-weight="600" fill="var(--accent)" font-family="JetBrains Mono, monospace"></text></g>`; });
  s += `<text x="20" y="${H - 6}" font-size="11" fill="var(--muted)">Kutunun dolgu yoğunluğu o mekanizmanın şu anki etkinliğini gösterir.</text></svg>`;
  $('svgHost').innerHTML = s;
}
function setNode(id, txt, act, color) {
  const g = document.getElementById('nd_' + id); if (!g) return;
  g.querySelector('.vv').textContent = txt;
  const gl = g.querySelector('.glow'); gl.setAttribute('fill-opacity', clamp(act, 0, 1) * 0.35); if (color) gl.setAttribute('fill', color);
}
const trend = [];
function renderReflex() {
  const s = eng.s, m = s.m, p = eng.p;
  const dev = (x) => clamp(Math.abs(x - 1), 0, 1);
  setNode('baro', 'deşarj %' + fmt(s.baroB * 100) + ' · MAP ' + fmt(m.MAP), p.baroOn ? Math.abs(s.baroB - 0.5) * 2 : 0);
  setNode('aff', p.baroOn ? 'aktif' : 'KESİK', p.baroOn ? Math.abs(s.baroB - 0.5) * 2 : 1, p.baroOn ? null : 'var(--crit)');
  setNode('nts', 'uyarı %' + fmt(s.baroB * 100), Math.abs(s.baroB - 0.5) * 2);
  setNode('cvlm', s.baroB > 0.5 ? 'RVLM inhibisyonu ↑' : 'inhibisyon ↓', Math.abs(s.baroB - 0.5) * 2);
  setNode('rvlm', 'sempatik %' + fmt(s.S * 100), clamp(s.S, 0, 1), 'var(--crit)');
  setNode('amb', 'vagal %' + fmt(s.Veff * 100), clamp(s.Veff, 0, 1), 'var(--c3)');
  setNode('heart', 'KH ' + fmt(m.HR) + ' · kontr. ×' + fmt(s.contrLV, 2), dev(m.HR / 70));
  setNode('arter', 'TPR ' + fmt(s.TPR * 1000 / 60, 1), dev(s.TPR / 1.05), s.TPR > 1.05 ? 'var(--crit)' : 'var(--c3)');
  setNode('vein', 'V₀ ' + fmt(s.V0sv) + ' ml', dev(s.V0sv / 2700) * 4);
  setNode('chemo', 'PaO₂ ' + fmt(s.PaO2) + ' · uyarı ' + fmt(s.chemo, 2), clamp(s.chemo, 0, 1), 'var(--warn)');
  setNode('cns', 'CPP ' + fmt(m.CPP) + ' · ' + fmt(s.cnsI, 2), clamp(s.cnsI, 0, 1), 'var(--crit)');
  setNode('cp', 'CVP ' + fmt(m.CVP, 1) + ' · Bainbridge ' + fmt(s.bain, 2), clamp(s.bain, 0, 1), 'var(--warn)');
  setNode('kid', 'perfüzyon ' + fmt(s.renalPP) + ' mmHg', dev(s.renalPP / 92) * 2);
  setNode('renin', '×' + fmt(s.renin, 2), dev(s.renin) / 2, 'var(--warn)');
  setNode('ang', '×' + fmt(s.angII, 2), dev(s.angII) / 2, 'var(--warn)');
  setNode('aldo', '×' + fmt(s.aldo, 2), dev(s.aldo) / 2, 'var(--warn)');
  setNode('adh', '×' + fmt(s.adhTot, 1), dev(s.adhTot) / 3, 'var(--warn)');
  setNode('anp', '×' + fmt(s.anp, 1), dev(s.anp) / 2, 'var(--c3)');
  setNode('vol', fmt(eng.bloodVolume()) + ' ml · idrar ' + fmt(s.urine * 60) + ' ml/sa', dev(eng.bloodVolume() / 5030) * 6);
  // baro eğrisi
  { const { c, w, h } = fit($('cvBaro')); const ax = plotAxes(c, w, h, 40, 220, 0, 1.05, { l: 30, r: 10, t: 8, b: 18 }, [0, 0.5, 1], 'MAP (mmHg)');
    const set = s.baroSet + 22 * p.exercise; const cur = []; const nor = [];
    for (let x = 40; x <= 220; x += 2) { cur.push([ax.X(x), ax.Y(1 / (1 + Math.exp(-(x - set) / 13)))]); nor.push([ax.X(x), ax.Y(1 / (1 + Math.exp(-(x - 94) / 13)))]); }
    line(c, nor, C.muted, 1.2, [4, 3]); line(c, cur, C.c1, 2);
    c.fillStyle = C.c2; c.beginPath(); c.arc(ax.X(clamp(m.MAP, 40, 220)), ax.Y(s.baroB), 5, 0, 7); c.fill();
    c.fillStyle = C.muted; c.font = '10px JetBrains Mono, monospace'; [60, 100, 140, 180].forEach(x => c.fillText(String(x), ax.X(x) - 8, h - 5));
    c.fillText('deşarj', 2, 10);
  }
  // eğilim
  { const { c, w, h } = fit($('cvTrend')); c.fillStyle = C.panel; c.fillRect(0, 0, w, h);
    if (trend.length > 2) {
      const t0 = trend[0].t, t1 = trend[trend.length - 1].t || t0 + 1; const X = (t) => 30 + (t - t0) / Math.max(t1 - t0, 1) * (w - 40);
      const S = (k, lo, hi, col) => line(c, trend.map(x => [X(x.t), h - 16 - clamp((x[k] - lo) / (hi - lo), 0, 1) * (h - 28)]), col, 1.8);
      S('map', 40, 160, C.c2); S('hr', 30, 190, C.c1); S('bv', 3500, 6500, C.c3); S('ang', 0, 6, C.c4); S('adh', 0, 8, C.c5);
      const span = t1 - t0; c.fillStyle = C.muted; c.font = '10.5px Source Sans 3, sans-serif';
      c.fillText(span > 7200 ? fmt(span / 3600, 1) + ' saat' : span > 120 ? fmt(span / 60, 1) + ' dakika' : fmt(span) + ' saniye', w - 70, h - 3);
      const L = trend[trend.length - 1]; c.fillText(`MAP ${fmt(L.map)} · KH ${fmt(L.hr)} · hacim ${fmt(L.bv)} · AngII ×${fmt(L.ang, 1)} · ADH ×${fmt(L.adh, 1)}`, 32, 12);
    }
  }
  const rows = [['Renin', s.renin], ['Anjiyotensin II', s.angII], ['Aldosteron', s.aldo], ['ADH (toplam)', s.adhTot], ['ANP/BNP', s.anp], ['Dolaşan epinefrin', s.epi / 0.08]];
  $('hormTbl').innerHTML = `<table class="t"><tr><th>Etken</th><th>Normale göre</th><th style="width:45%"></th></tr>${rows.map(r => `<tr><td>${r[0]}</td><td class="n">×${fmt(r[1], 2)}</td><td><div class="bar"><span style="width:${clamp(r[1] / 6 * 100, 1, 100)}%;background:${r[1] > 1.3 ? 'var(--warn)' : r[1] < 0.75 ? 'var(--c3)' : 'var(--accent)'}"></span></div></td></tr>`).join('')}
    <tr><td>İdrar / alım</td><td class="n">${fmt(s.urine * 60)} / ${fmt(s.intake * 60)} ml/sa</td><td class="note">Basınç natriürezi: renal perfüzyon ${fmt(s.renalPP)} mmHg</td></tr>
    <tr><td>Baro set noktası</td><td class="n">${fmt(s.baroSet)} mmHg</td><td class="note">${s.baroSet > 95 ? 'yukarı ayarlandı (resetting)' : 'normal'}</td></tr></table>`;
}

/* ---------- Formül kartı ---------- */
function renderFormula() {
  const s = eng.s, m = s.m, d = eng.derived, p = eng.p, tpr = s.TPR * 1000 / 60;
  const F = [
    ['Kalp debisi', 'CO = KH × SV', `${fmt(m.HR)} × ${fmt(m.SV)} ml = ${fmt(m.HR * m.SV / 1000, 2)} L/dk`, 'B6.1'],
    ['Ejeksiyon fraksiyonu', 'EF = SV / EDV × 100', `${fmt(m.SV)} / ${fmt(m.EDV)} = %${fmt(m.EF * 100)}`, 'B4.3'],
    ['Kalp indeksi', 'CI = CO / VYA', `${fmt(m.CO, 1)} / 1,8 m² = ${fmt(m.CO / 1.8, 2)} L/dk/m²`, 'B6.1'],
    ['Fick ilkesi', 'CO = VO₂ / (CaO₂ − CvO₂)', `${fmt(s.VO2)} / (${fmt(s.CaO2)} − ${fmt(s.CvO2)}) = ${fmt(s.VO2 / (s.CaO2 - s.CvO2), 1)} L/dk`, 'B6.9'],
    ['Ortalama arter basıncı', 'MAP ≈ DBP + ⅓(SBP − DBP)', `${fmt(m.DBP)} + ⅓(${fmt(m.SBP)} − ${fmt(m.DBP)}) = ${fmt(m.DBP + (m.SBP - m.DBP) / 3)}`, 'B7.5'],
    ['Sistemik direnç', 'MAP − RAP = CO × TPR', `${fmt(m.MAP)} − ${fmt(m.CVP)} = ${fmt(m.CO, 1)} × ${fmt(tpr, 1)}`, 'B7.10'],
    ['Pulmoner direnç', 'PVR = (PAPort − LAP) / CO', `(${fmt(m.PAm)} − ${fmt(m.LAP)}) / ${fmt(m.CO, 1)} = ${fmt((m.PAm - m.LAP) / Math.max(m.CO, 0.1), 1)}`, 'B7.10'],
    ['Nabız basıncı', 'NB = SBP − DBP', `${fmt(m.SBP)} − ${fmt(m.DBP)} = ${fmt(m.SBP - m.DBP)} mmHg`, 'B8.4'],
    ['Poiseuille', 'R = 8Lη / πr⁴', `η ×${fmt(d.viscF, 2)} → TPR ×${fmt(d.viscF, 2)}; r yarı → R ×16`, 'B7.7'],
    ['Akım–basınç–direnç', 'Q = ΔP / R', `${fmt(m.MAP - m.CVP)} / ${fmt(tpr, 1)} = ${fmt((m.MAP - m.CVP) / tpr, 1)} L/dk`, 'B7.6'],
    ['Akım hızı', 'v = Q / A', `aort: ${fmt(m.CO * 1000 / 60)} / 4,5 = ${fmt(m.CO * 1000 / 60 / 4.5)} cm/s`, 'B8.1'],
    ['Reynolds', 'Re = DVρ / η', `aort tepe ≈ ${fmt(m.Re)} (${m.Re > 2000 ? 'türbülan eğilim' : 'laminar'})`, 'B7.4'],
    ['Laplace', 'T = P × r', `transmural P ↑ veya r ↑ → T ↑ → miyojenik kasılma`, 'B8.9'],
    ['Kompliyans', 'C = ΔV / ΔP', `arter ${fmt(s.Car, 2)} · ven ${fmt(s.Csv)} ml/mmHg`, 'B8.5'],
    ['Starling', 'NFB = (Pc + πif) − (πc + Pif)', `art. uç: (${fmt(s.PcA)} + ${fmt(s.piIF, 1)}) − (${fmt(d.piC, 1)} + ${fmt(s.Pif, 1)}) = ${sgn(s.nfpA)}`, 'B9.3'],
    ['Serebral perfüzyon', 'CPP = MAP − ICP', `${fmt(m.MAP)} − ${fmt(m.ICP)} = ${fmt(m.CPP)} mmHg`, 'B10.5'],
    ['Nernst', 'E = (61,5/z) log([d]/[i])', `E_K = 61,5 log(${fmt(p.K, 1)}/140) = ${sgn(d.EK)} mV`, 'B1.2'],
    ['Goldman', 'Vm = 61,5 log((PK[K]d + PNa[Na]d)/(PK[K]i + PNa[Na]i))', `Vm = ${sgn(d.vRest)} mV`, 'B1.2'],
    ['EKG kalp hızı', 'KH = 60 / RR(s) = 300 / büyük kare', `60 / ${fmt(m.RRint, 2)} = ${fmt(60 / m.RRint)}/dk`, 'B3.4'],
    ['Einthoven', 'DI + DIII = DII', 'herhangi iki bipolar derivasyon üçüncüyü verir', 'B2.4'],
    ['QTc (Bazett)', 'QTc = QT / √RR', `${fmt(m.QT, 2)} / √${fmt(m.RRint, 2)} = ${fmt(m.QTc, 3)} s`, 'B3.1'],
    ['O₂ içeriği', 'CaO₂ = 1,34 × Hb × SaO₂ + 0,003 × PaO₂', `1,34 × ${fmt(s.Hb, 1)} × ${fmt(s.SaO2, 2)} = ${fmt(s.CaO2 / 10, 1)} ml/dl`, 'B6.9'],
    ['Atım hacmi', 'SV = EDV − ESV', `${fmt(m.EDV)} − ${fmt(m.ESV)} = ${fmt(m.SV)} ml`, 'B4.3'],
    ['Ventrikül kompliyansı', 'C = ΔV / ΔP (diyastolik)', `LVEDP ${fmt(m.LVEDP, 1)} mmHg @ EDV ${fmt(m.EDV)} ml`, 'B6.5'],
  ];
  $('fxGrid').innerHTML = F.map(f => `<div class="fx"><div class="fn">${f[0]}<span class="ref">${f[3]}</span></div><div class="eq">${f[1]}</div><div class="live">${f[2]}</div></div>`).join('');
}

function renderTab(force) {
  try {
    if (activeTab === 'cell') renderCell();
    else if (activeTab === 'ecg') { const now = performance.now(); if (force || now - last12 > 900) { render12(); last12 = now; } renderEcgSide(); }
    else if (activeTab === 'cycle') renderCycle();
    else if (activeTab === 'vessels') renderVessels();
    else if (activeTab === 'cap') renderCap();
    else if (activeTab === 'reflex') renderReflex();
    else if (activeTab === 'formula') renderFormula();
  } catch (e) { console.error(e); }
}
function renderActive() {
  if (caseState && !caseState.revealed) { $('actList').innerHTML = '<div class="act-i">Vaka modunda mekanizmalar gizli. Tanıyı seçince açılır.</div>'; return; }
  const L = D.active(eng);
  $('actList').innerHTML = L.map(x => `<div class="act-i ${x.lv}">${x.h}</div>`).join('');
}

/* =================================================================
   SES
   ================================================================= */
let ac = null, master = null, noiseBuf = null, mur = {}, listenOn = false, beepOn = false, lastEvIdx = 0, lastBeatId = 0, lastAtrId = 0;
function toggleSound() {
  soundOn = !soundOn;
  $('sound').textContent = soundOn ? 'Ses açık' : 'Ses kapalı'; $('sound').setAttribute('aria-pressed', soundOn); $('sound').classList.toggle('on', soundOn);
  if (soundOn && !ac) initAudio();
  if (ac) { if (soundOn) ac.resume(); else ac.suspend(); }
  if (!soundOn) { listenOn = false; const lb = $('listenBtn'); if (lb) { lb.textContent = 'Dinle'; lb.classList.remove('on'); } }
}
function initAudio() {
  try { ac = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { ac = null; return; }
  master = ac.createGain(); master.gain.value = 0.9;
  const comp = ac.createDynamicsCompressor(); master.connect(comp); comp.connect(ac.destination);
  noiseBuf = ac.createBuffer(1, ac.sampleRate * 2, ac.sampleRate); const ch = noiseBuf.getChannelData(0); for (let i = 0; i < ch.length; i++) ch[i] = Math.random() * 2 - 1;
  const mk = (f, q) => { const src = ac.createBufferSource(); src.buffer = noiseBuf; src.loop = true; const bp = ac.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = f; bp.Q.value = q; const g = ac.createGain(); g.gain.value = 0; src.connect(bp); bp.connect(g); g.connect(master); src.start(); return g; };
  mur = { as: mk(190, 1.2), mr: mk(260, 1.0), ar: mk(380, 1.4), ms: mk(75, 2.5), flow: mk(220, 1.0) };
}
function audioReset() { lastEvIdx = 0; lastBeatId = 0; lastAtrId = 0; }
function thump(when, f0, f1, dur, gain) {
  if (!ac) return;
  const o = ac.createOscillator(), g = ac.createGain(); o.type = 'sine';
  o.frequency.setValueAtTime(f0, when); o.frequency.exponentialRampToValueAtTime(Math.max(f1, 20), when + dur);
  g.gain.setValueAtTime(0.0001, when); g.gain.exponentialRampToValueAtTime(gain, when + 0.008); g.gain.exponentialRampToValueAtTime(0.0001, when + dur);
  o.connect(g); g.connect(master); o.start(when); o.stop(when + dur + 0.02);
  const n = ac.createBufferSource(); n.buffer = noiseBuf; const bp = ac.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = f0 * 2.2; bp.Q.value = 1.5; const ng = ac.createGain();
  ng.gain.setValueAtTime(0.0001, when); ng.gain.exponentialRampToValueAtTime(gain * 0.6, when + 0.006); ng.gain.exponentialRampToValueAtTime(0.0001, when + dur * 0.7);
  n.connect(bp); bp.connect(ng); ng.connect(master); n.start(when, Math.random()); n.stop(when + dur);
}
function korotkoff(k) { if (!soundOn || !ac) return; thump(ac.currentTime + 0.01, 160, 70, 0.07, 0.5 * k); }
const FOCUS_W = { aort: { s1: 0.6, s2a: 1, s2p: 0.5, as: 1, mr: 0.3, ar: 0.6, ms: 0.15, s3: 0.2 }, pulm: { s1: 0.6, s2a: 0.8, s2p: 1, as: 0.6, mr: 0.3, ar: 0.6, ms: 0.15, s3: 0.2 }, erb: { s1: 0.7, s2a: 0.9, s2p: 0.8, as: 0.6, mr: 0.4, ar: 1, ms: 0.3, s3: 0.3 }, tri: { s1: 1, s2a: 0.5, s2p: 0.5, as: 0.3, mr: 0.5, ar: 0.5, ms: 0.5, s3: 0.6 }, mit: { s1: 1, s2a: 0.5, s2p: 0.3, as: 0.4, mr: 1, ar: 0.4, ms: 1, s3: 1 } };
function audioTick() {
  if (!soundOn || !ac) return;
  const s = eng.s, p = eng.p, now = ac.currentTime, lag = 0.06;
  const fw = FOCUS_W[($('focusSel') || {}).value || 'mit'];
  if (listenOn) {
    // kapak olayları
    const evs = s.events;
    for (const ev of evs) {
      if (ev.t <= (audioTick.lastT || 0)) continue;
      const when = now + lag;
      if (ev.k === 'M1') { const pr = s.m.PR || 0.16; const loud = clamp(0.25 + (0.22 - pr) * 3 + 0.25 * s.Sb + (p.MS > 0.4 ? 0.3 : 0), 0.08, 0.8); thump(when, 55, 32, 0.13, loud * fw.s1); }
      if (ev.k === 'A2') thump(when, 85, 50, 0.07, clamp(0.25 + (s.m.DBP - 60) / 120, 0.1, 0.6) * fw.s2a);
      if (ev.k === 'P2') thump(when, 80, 48, 0.06, 0.28 * fw.s2p);
      if (ev.k === 'MO' && p.MS > 0.3) thump(when, 140, 90, 0.04, 0.35);
      if (ev.k === 'MO' && hasS3()) thump(when + 0.12, 32, 22, 0.1, 0.32 * fw.s3);
    }
    for (const a of s.atrial) { if (a.t <= (audioTick.lastT || 0) || a.kind !== 'p') continue; if (hasS4()) thump(now + lag + 0.1, 30, 22, 0.08, 0.28 * fw.s3); }
    // üfürümler (akımlarla orantılı)
    const I = s.inst; const ramp = (g, v) => g.gain.setTargetAtTime(v, now, 0.012);
    ramp(mur.as, p.AS > 0.1 ? clamp(I.Qav / 500, 0, 1) * p.AS * 0.5 * fw.as : 0);
    ramp(mur.mr, p.MR > 0.1 ? clamp(-I.Qmv / 300, 0, 1) * p.MR * 0.45 * fw.mr : 0);
    ramp(mur.ar, p.AR > 0.1 ? clamp(-I.Qav / 250, 0, 1) * p.AR * 0.35 * fw.ar : 0);
    ramp(mur.ms, p.MS > 0.1 ? clamp(I.Qmv / 400, 0, 1) * p.MS * 0.6 * fw.ms : 0);
    ramp(mur.flow, (s.m.Re > 2600 || eng.derived.hct < 0.28) ? clamp(I.Qav / 600, 0, 1) * 0.12 : 0);
  } else { for (const k in mur) mur[k].gain.setTargetAtTime(0, now, 0.03); }
  if (beepOn) {
    const b = s.beats[s.beats.length - 1];
    for (const bb of s.beats) { if (bb.id > lastBeatId && bb.tV <= s.t) { lastBeatId = bb.id; const f = 440 + 500 * clamp((s.SaO2 - 0.75) / 0.25, 0, 1); const o = ac.createOscillator(), g = ac.createGain(); o.frequency.value = f; o.type = 'triangle'; g.gain.setValueAtTime(0.0001, now); g.gain.exponentialRampToValueAtTime(0.12, now + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, now + 0.12); o.connect(g); g.connect(master); o.start(now); o.stop(now + 0.14); } }
  }
  audioTick.lastT = s.t;
}

/* =================================================================
   VAKA MODU
   ================================================================= */
function openCaseMenu() {
  const ov = $('caseOv'), dl = $('caseDlg');
  dl.innerHTML = `<h2 id="caseTitle">Vaka modu</h2><p class="note">Hasta öyküsü ve monitör verilir; kontrol paneli gizlenir. Monitörü, EKG'yi, Wiggers diyagramını, kapiller ve refleks sekmelerini inceleyip tanıyı seçin.</p>
    <button class="btn primary" id="cRand">Rastgele vaka</button>
    <div style="margin-top:10px;display:grid;gap:4px">${D.CASES.map((c, i) => `<button class="opt" data-i="${i}">Vaka ${i + 1}: ${c.t}</button>`).join('')}</div>
    <div style="margin-top:10px;text-align:right"><button class="btn" id="cClose">Kapat</button></div>`;
  ov.hidden = false;
  $('cClose').onclick = () => ov.hidden = true;
  $('cRand').onclick = () => startCase(Math.floor(Math.random() * D.CASES.length));
  dl.querySelectorAll('.opt').forEach(b => b.onclick = () => startCase(+b.dataset.i));
}
function startCase(i) {
  const cs = D.CASES[i];
  $('caseOv').hidden = true;
  resetAll();
  caseState = { i, revealed: false, answered: false };
  if (cs.set) for (const k in cs.set) setCtl(k, cs.set[k], false);
  eng.warm(6);
  if (cs.act) cs.act.forEach(a => eng.action(a));
  if (cs.speed) { eng.speed = cs.speed; $('speed').value = String(cs.speed); }
  syncControls();
  if (STU.on) stuCase(cs);
  document.body.classList.add('locked');
  $('caseBar').hidden = false;
  $('caseVg').innerHTML = `<b>Vaka ${i + 1} – ${cs.t}.</b> ${cs.v}`;
  $('scenario').disabled = true;
  logEl.innerHTML = '';
}
function openCaseAnswer() {
  if (!caseState) return;
  const cs = D.CASES[caseState.i], dl = $('caseDlg');
  dl.innerHTML = `<h2 id="caseTitle">Tanınız nedir?</h2><p>${cs.v}</p>${cs.o.map((o, j) => `<button class="opt" data-j="${j}">${o}</button>`).join('')}<div id="caseFb"></div><div style="margin-top:10px;text-align:right"><button class="btn" id="cBack">Monitöre dön</button></div>`;
  $('caseOv').hidden = false;
  $('cBack').onclick = () => $('caseOv').hidden = true;
  dl.querySelectorAll('.opt').forEach(b => b.onclick = () => {
    const j = +b.dataset.j; dl.querySelectorAll('.opt').forEach((x, k) => { x.classList.toggle('right', k === cs.a); if (k === j && j !== cs.a) x.classList.add('wrong'); x.disabled = true; });
    caseState.revealed = true;
    $('caseFb').innerHTML = `<p style="margin-top:10px"><b>${j === cs.a ? 'Doğru.' : 'Doğru cevap: ' + cs.o[cs.a] + '.'}</b> ${cs.e} <span class="ref">${cs.r}</span></p>
      <div class="btnrow"><button class="btn primary" id="cReveal">Kontrolleri göster</button><button class="btn" id="cNext">Sonraki vaka</button></div>`;
    $('cReveal').onclick = () => { $('caseOv').hidden = true; document.body.classList.remove('locked'); logWhy({ t: 'Vaka çözümü: ' + cs.o[cs.a], c: [cs.e], r: cs.r }); };
    $('cNext').onclick = () => startCase((caseState.i + 1) % D.CASES.length);
  });
}
function quitCase() { caseState = null; document.body.classList.remove('locked'); $('caseBar').hidden = true; $('scenario').disabled = false; resetAll(); }

/* =================================================================
   ANA DÖNGÜ
   ================================================================= */
let lastT = performance.now(), accNums = 0, accTab = 0, accAct = 0, accTrend = 0;
function frame(now) {
  let dt = (now - lastT) / 1000; lastT = now; dt = Math.min(dt, 0.05);
  if (!paused && !document.hidden) {
    eng.advance(dt);
    stepCuff(dt);
    audioTick();
  }
  stuTick(now);
  drawMonitor();
  accNums += dt; accTab += dt; accAct += dt; accTrend += dt;
  if (accNums > 0.25) { updNums(); accNums = 0; }
  if (accTab > (activeTab === 'ecg' ? 0.25 : 0.1)) { renderTab(); accTab = 0; }
  if (accAct > 0.5) { renderActive(); accAct = 0; }
  if (accTrend > 0.5) { const s = eng.s; trend.push({ t: s.tSlow, map: s.m.MAP, hr: s.m.HR, bv: eng.bloodVolume(), ang: s.angII, adh: s.adhTot }); if (trend.length > 600) trend.shift(); accTrend = 0; }
  requestAnimationFrame(frame);
}

/*@@STUDENT@@*/
/* ---- başlat ---- */
buildControls(); buildTop(); buildNums();
try { const t = localStorage.getItem('kvs_tab'); if (t && TABS.some(x => x.id === t)) activeTab = t; } catch (e) {}
buildTabs();
refPV = capturePV(ref);
eng.monLead = 'II';
logWhy({ t: 'Hoş geldiniz', c: ['Soldan herhangi bir etkeni değiştirin ya da üstten hazır senaryo seçin', 'monitör ve sekmeler anında yanıt verir', 'burada vücudun yanıt zinciri açıklanır'], r: '' });
buildStudent();
{ let m = 'student'; try { m = localStorage.getItem('kvs_mode') || 'student'; } catch (e) {} setMode(m, true); }
requestAnimationFrame(frame);
window.__kvs = () => eng;
})();
