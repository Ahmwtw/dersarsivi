/* =====================================================================
   KVS SANAL HASTA — fizyoloji motoru
   Kapalı devre, zamanla değişen elastanslı dolaşım modeli + elektrik
   (SA düğüm, AV ileti, ritimler, EKG vektörleri) + refleksler +
   hormonlar (RAAS, ADH, ANP) + organ yatakları (Poiseuille) +
   Starling/lenf + O2 taşınımı. DOM'a dokunmaz.
   ===================================================================== */
(function (global) {
'use strict';
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const DEG = Math.PI / 180;
const sm = (x) => { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); };

/* ---------------------------------------------------------------------
   KONTROLLER — arayüz bu listeden üretilir
   ref: kitap bölümü
   --------------------------------------------------------------------- */
const R = (id, label, min, max, step, def, unit, normal, ref) => ({ type: 'range', id, label, min, max, step, def, unit: unit || '', normal: normal || '', ref: ref || '' });
const SEL = (id, label, options, def, ref) => ({ type: 'select', id, label, options, def, ref: ref || '' });
const TG = (id, label, def, ref) => ({ type: 'toggle', id, label, def, ref: ref || '' });
const BT = (id, label, ref) => ({ type: 'button', id, label, ref: ref || '' });

const CONTROLS = [
  { id: 'patient', label: 'Hasta ve çevre', items: [
    SEL('posture', 'Postür', [['supine', 'Sırtüstü yatıyor'], ['standing', 'Ayakta, hareketsiz']], 'supine', 'B10.3'),
    R('exercise', 'Egzersiz düzeyi', 0, 1, 0.05, 0, '', '0', 'B6.2, B8.9'),
    R('emotion', 'Heyecan / stres', 0, 1, 0.05, 0, '', '0', 'B6.2'),
    R('temp', 'Vücut sıcaklığı', 34, 41.5, 0.1, 37, '°C', '36,5–37,5', 'B6.2'),
    R('thyroid', 'Tiroid hormonu', 0.4, 2.5, 0.05, 1, '×', '1', 'B6.2'),
    R('arterialStiff', 'Arteriyel sertlik (yaş, ateroskleroz)', 0, 1, 0.05, 0.2, '', '0–0,3', 'B7.8, B8.4'),
  ]},
  { id: 'blood', label: 'Kan, hacim ve viskozite', items: [
    BT('hem500', '−500 ml kanama', 'B10.3'),
    BT('hem1000', '−1000 ml kanama', 'B10.10'),
    BT('cryst', '+1000 ml kristaloid', 'B9.3'),
    BT('transf', '+500 ml tam kan', 'B10.10'),
    R('hct', 'Hematokrit (eritrosit kitlesi)', 15, 70, 1, 42, '%', '40–45', 'B7.8'),
    R('fibrinogen', 'Plazma fibrinojeni', 1, 8, 0.1, 3, 'g/L', '2–4', 'B7.8'),
    R('deform', 'Eritrosit deformabilitesi', 0.2, 1, 0.05, 1, '', '1', 'B7.8'),
    R('albumin', 'Plazma albümini', 1, 5.5, 0.1, 4.2, 'g/dL', '3,5–5', 'B9.3, B9.6'),
    R('salt', 'Tuz ve su alımı', 0.3, 3, 0.1, 1, '×', '1', 'B10.8'),
  ]},
  { id: 'lytes', label: 'Elektrolitler', items: [
    R('K', 'Potasyum (K⁺)', 2, 9, 0.1, 4, 'mEq/L', '3,5–5', 'B1.6'),
    R('Na', 'Sodyum (Na⁺)', 115, 165, 1, 142, 'mEq/L', '135–145', 'B1.6'),
    R('Ca', 'Kalsiyum (Ca²⁺)', 1.2, 3.8, 0.05, 2.4, 'mEq/L', '2,2–2,6', 'B1.6'),
    R('Mg', 'Magnezyum (Mg²⁺)', 0.4, 6, 0.1, 1.7, 'mEq/L', '1,5–2,5', 'B1.6'),
  ]},
  { id: 'drugs', label: 'İlaçlar', items: [
    SEL('naClass', 'Na⁺ bloker sınıfı', [['IA', 'IA – kinidin, prokainamid'], ['IB', 'IB – lidokain'], ['IC', 'IC – flekainid']], 'IA', 'B1.7'),
    R('naBlock', 'Na⁺ kanal blokeri', 0, 1, 0.05, 0, 'doz', '', 'B1.7'),
    R('kBlock', 'K⁺ kanal blokeri (amiodaron, sotalol)', 0, 1, 0.05, 0, 'doz', '', 'B1.7'),
    R('verapamil', 'Verapamil', 0, 1, 0.05, 0, 'doz', '', 'B1.7'),
    R('diltiazem', 'Diltiazem', 0, 1, 0.05, 0, 'doz', '', 'B1.7'),
    R('nifedipine', 'Nifedipin', 0, 1, 0.05, 0, 'doz', '', 'B1.7'),
    R('betaBlock', 'β-bloker', 0, 1, 0.05, 0, 'doz', '', 'B1.7, B10.9'),
    R('digoxin', 'Digoksin', 0, 1, 0.05, 0, 'doz', '', 'B1.7'),
    R('atropine', 'Atropin (M₂ bloku)', 0, 1, 0.05, 0, 'doz', '', 'B2.2'),
    R('noradrenaline', 'Noradrenalin infüzyonu', 0, 1, 0.05, 0, 'doz', '', 'B10.7'),
    R('adrenaline', 'Adrenalin infüzyonu', 0, 1, 0.05, 0, 'doz', '', 'B8.10'),
    R('vasopressin', 'Vazopressin infüzyonu', 0, 1, 0.05, 0, 'doz', '', 'B10.7'),
    R('nitrate', 'Nitrat (NO donörü)', 0, 1, 0.05, 0, 'doz', '', 'B8.9'),
    R('diuretic', 'Diüretik', 0, 1, 0.05, 0, 'doz', '', 'B10.9'),
    R('acei', 'ACE inhibitörü', 0, 1, 0.05, 0, 'doz', '', 'B10.9'),
    R('arb', 'AT₁ reseptör blokeri', 0, 1, 0.05, 0, 'doz', '', 'B10.9'),
  ]},
  { id: 'autonomic', label: 'Otonom sistem ve refleksler', items: [
    R('sympOffset', 'Sempatik tonus (elle ek)', -0.5, 0.5, 0.05, 0, '', '0', 'B2.2'),
    R('vagOffset', 'Parasempatik tonus (elle ek)', -0.5, 0.5, 0.05, 0, '', '0', 'B2.2'),
    BT('carotid', 'Karotis sinüs masajı (8 s)', 'B10.3'),
    BT('valsalva', 'Valsalva manevrası (10 s)', 'B10.3'),
    TG('baroOn', 'Baroreseptör refleksi', true, 'B10.3'),
    TG('chemoOn', 'Kemoreseptör refleksi', true, 'B10.4'),
    TG('cnsOn', 'MSS iskemik yanıtı / Cushing', true, 'B10.5'),
    TG('cardiopulmOn', 'Kardiyopulmoner reseptörler (Bainbridge)', true, 'B10.6'),
    TG('raasOn', 'RAAS', true, 'B10.8'),
    TG('adhOn', 'ADH ve susama', true, 'B10.8'),
    TG('anpOn', 'ANP / BNP', true, 'B10.8'),
    TG('natriOn', 'Basınç natriürezi', true, 'B10.8'),
    TG('autoregOn', 'Lokal otoregülasyon', true, 'B8.9'),
    TG('respOn', 'Solunum (sinüs aritmisi, S2 çiftleşmesi)', true, 'B3.6, B5.3'),
  ]},
  { id: 'rhythm', label: 'Ritim ve ileti', items: [
    SEL('rhythm', 'Temel ritim', [['sinus', 'Sinüs ritmi'], ['af', 'Atriyal fibrilasyon'], ['flutter', 'Atriyal flatter'], ['vt', 'Ventriküler taşikardi'], ['vf', 'Ventriküler fibrilasyon']], 'sinus', 'B3.6'),
    SEL('avBlock', 'AV blok', [['0', 'Yok'], ['1', '1. derece'], ['2a', '2. derece – Mobitz I'], ['2b', '2. derece – Mobitz II'], ['3', '3. derece (komplet)']], '0', 'B3.6'),
    SEL('bbb', 'Dal bloğu', [['0', 'Yok'], ['L', 'Sol dal bloğu'], ['R', 'Sağ dal bloğu']], '0', 'B3.6'),
    R('ves', 'Ventriküler ekstrasistol sıklığı', 0, 0.4, 0.02, 0, '', '0', 'B3.6'),
  ]},
  { id: 'heart', label: 'Kalp: kasılma ve kapaklar', items: [
    R('contractility', 'Kontraktilite (elle)', 0.3, 2, 0.05, 1, '×', '1', 'B6.3'),
    SEL('hypertrophy', 'Hipertrofi', [['0', 'Yok'], ['LVH', 'Sol ventrikül hipertrofisi'], ['RVH', 'Sağ ventrikül hipertrofisi']], '0', 'B3.3'),
    R('stiffness', 'Ventrikül sertliği (fibrozis)', 1, 4, 0.1, 1, '×', '1', 'B6.5'),
    SEL('mi', 'Miyokard infarktüsü', [['0', 'Yok'], ['ant', 'Anterior MI'], ['inf', 'İnferior MI']], '0', 'B8.12'),
    R('corStenosis', 'Koroner arter darlığı (yarıçap)', 0, 0.9, 0.05, 0, '', '0', 'B8.12'),
    R('AS', 'Aort stenozu', 0, 1, 0.05, 0, '', '0', 'B5.5'),
    R('AR', 'Aort yetersizliği', 0, 1, 0.05, 0, '', '0', 'B5.5'),
    R('MS', 'Mitral stenoz', 0, 1, 0.05, 0, '', '0', 'B5.5'),
    R('MR', 'Mitral yetersizliği', 0, 1, 0.05, 0, '', '0', 'B5.5'),
    R('tamponade', 'Perikard tamponadı', 0, 20, 0.5, 0, 'mmHg', '0', 'B10.10'),
  ]},
  { id: 'vessels', label: 'Damarlar ve organ yatakları', items: [
    R('rBrain', 'Arteriyol yarıçapı – beyin', 0.5, 1.5, 0.01, 1, '×', '1', 'B7.7'),
    R('rCor', 'Arteriyol yarıçapı – koroner', 0.5, 1.5, 0.01, 1, '×', '1', 'B7.7'),
    R('rKidney', 'Arteriyol yarıçapı – böbrek', 0.5, 1.5, 0.01, 1, '×', '1', 'B7.7'),
    R('rMuscle', 'Arteriyol yarıçapı – iskelet kası', 0.5, 1.5, 0.01, 1, '×', '1', 'B7.7'),
    R('rSkin', 'Arteriyol yarıçapı – deri', 0.5, 1.5, 0.01, 1, '×', '1', 'B7.7'),
    R('rSplanch', 'Arteriyol yarıçapı – splanknik', 0.5, 1.5, 0.01, 1, '×', '1', 'B7.7'),
    TG('amputation', 'Bir bacak amputasyonu', false, 'B7.9'),
    R('renalStenosis', 'Renal arter darlığı (yarıçap)', 0, 0.85, 0.05, 0, '', '0', 'B10.9'),
    R('sepsis', 'Sepsis', 0, 1, 0.05, 0, '', '0', 'B10.10'),
    R('anaphylaxis', 'Anafilaksi', 0, 1, 0.05, 0, '', '0', 'B10.10'),
    R('rAll', 'Tüm periferik arteriyoller (daralma ↔ genişleme)', 0.75, 1.25, 0.01, 1, '×', '1', 'B7.7, B10.1'),
    R('venTone', 'Venöz tonus (elle ek)', -0.5, 0.5, 0.05, 0, '', '0', 'B8.6'),
  ]},
  { id: 'lung', label: 'Akciğer, kan gazları, kafa içi', items: [
    R('PaO2', 'Arteriyel PO₂ hedefi (inspire O₂, yükseklik)', 30, 110, 1, 95, 'mmHg', '80–100', 'B10.4'),
    R('PaCO2', 'Arteriyel PCO₂', 20, 80, 1, 40, 'mmHg', '35–45', 'B8.11'),
    R('ICP', 'İntrakraniyal basınç (kitle, ödem)', 5, 70, 1, 10, 'mmHg', '7–15', 'B10.5'),
    R('pe', 'Masif pulmoner emboli', 0, 1, 0.05, 0, '', '0', 'B10.10'),
    R('pneumo', 'Tansiyon pnömotoraks', 0, 1, 0.05, 0, '', '0', 'B10.10'),
  ]},
  { id: 'capillary', label: 'Kapiller ve lenf', items: [
    SEL('starling', 'Starling modeli', [['current', 'Güncel (glikokaliks) yaklaşım'], ['classic', 'Klasik Starling modeli']], 'current', 'B9.3'),
    R('perm', 'Kapiller geçirgenlik', 1, 5, 0.1, 1, '×', '1', 'B9.6'),
    R('lymph', 'Lenfatik drenaj kapasitesi', 0.05, 1, 0.05, 1, '×', '1', 'B9.5'),
    R('venExtra', 'Ek venöz basınç (gebelik, ven basısı)', 0, 20, 1, 0, 'mmHg', '0', 'B9.6'),
  ]},
];

const DEFAULTS = {};
CONTROLS.forEach(g => g.items.forEach(it => { if (it.type !== 'button') DEFAULTS[it.id] = it.def; }));

/* ---------------------------------------------------------------------
   ORGAN YATAKLARI (paralel bağlı)  — bazal akım ml/dk
   --------------------------------------------------------------------- */
const BEDS = [
  { id: 'brain',   name: 'Beyin',          q0: 750,  alpha: 0.03, ctl: 'rBrain' },
  { id: 'cor',     name: 'Koroner',        q0: 250,  alpha: 0.02, ctl: 'rCor' },
  { id: 'kidney',  name: 'Böbrek',         q0: 1100, alpha: 0.13, ctl: 'rKidney' },
  { id: 'muscle',  name: 'İskelet kası',   q0: 800,  alpha: 0.14, ctl: 'rMuscle' },
  { id: 'skin',    name: 'Deri',           q0: 300,  alpha: 0.24, ctl: 'rSkin' },
  { id: 'splanch', name: 'Splanknik',      q0: 1300, alpha: 0.20, ctl: 'rSplanch' },
  { id: 'other',   name: 'Diğer',          q0: 500,  alpha: 0.10, ctl: null },
];
const DP0 = 92 - 4; // bazal arteriyel-venöz fark (mmHg)

/* ---------------------------------------------------------------------
   DURUM
   --------------------------------------------------------------------- */
function freshState() {
  return {
    t: 0, tSlow: 0,
    // hacimler (ml)
    Vlv: 125, Vao: 128, Var: 790, Vsv: 3270, Vra: 55, Vrv: 120, Vpa: 150, Vpv: 330, Vla: 60,
    Qao: 80,
    // aktivasyonlar
    actLV: 0, actRV: 0, actLA: 0, actRA: 0,
    // olaylar
    beats: [], atrial: [], nextSinus: 0.3, lastV: -1, lastVvalid: -1, lastAtrialConducted: -1,
    mobitzCount: 0, prExtra: 0, escapeNext: 0, afNext: 0.3, flNext: 0.1, vtNext: 0.2,
    beatId: 0,
    // otonom
    S: 0.25, V: 0.5, Sraw: 0.25, Vraw: 0.5, epi: 0.1, Sb: 0.25, Sa: 0.25, Veff: 0.5,
    contrLV: 1, contrRV: 1, contrNow: 1, V0sv: 2700, Csv: 95, Car: 1.26, breath: 0, Pit: -4, Pit_extra: 0, adhTot: 1, angEff: 1, Hb: 14, renalPP: 93,
    baroB: 0.5, baroSet: 94, mapLP: 94, mapPrev: 92, dMap: 0,
    chemo: 0, cnsI: 0, bain: 0,
    // humoral
    renin: 1, angII: 1, aldo: 1, adh: 1, anp: 1, remodel: 1,
    // hacim/protein
    rbc: 2100, plasma: 2900, protein: 2900 * 0.042 * 1.0, // g albümin eşdeğeri (g/ml*ml)
    urine: 1, intake: 1,
    dVi: 0, dVlung: 0, legEdema: 0,
    Jsys: 2, Lsys: 2, Jlung: 0.3, Llung: 0.3,
    // yataklar
    rAuto: { brain: 1, cor: 1, kidney: 1, muscle: 1, skin: 1, splanch: 1, other: 1 },
    bedQ: {}, bedR: {}, TPR: 1.06, PVR: 0.12,
    // gazlar
    PaO2: 95, SaO2: 0.97, CaO2: 190, CvO2: 140, SvO2: 0.73, VO2: 250, pH: 7.4, lactate: 1,
    // koroner
    corDemand: 1, corSupplyMax: 4, ischemia: 0,
    // ölçümler
    m: { HR: 72, SBP: 120, DBP: 80, MAP: 93, CVP: 3, LAP: 8, PAs: 25, PAd: 10, PAm: 15, CO: 5, SV: 70, EDV: 120, ESV: 50, EF: 0.58,
         RVEDV: 120, RVSV: 70, PR: 0.16, QRS: 0.09, QT: 0.38, QTc: 0.42, axis: 59, RRint: 0.8, CPP: 83, ICP: 10, LVEDP: 9,
         split: 0.02, Re: 1200, cardiacIndex: 2.8 },
    beatRec: { maxV: 0, minV: 999, maxP: 0, minAo: 999, maxAo: 0, maxRVV: 0, minRVV: 999, start: 0, mvClose: 0, avClose: 0, pvClose: 0 },
    win: { maxAo: 0, minAo: 999, t0: 0, sumAo: 0, n: 0, sumRA: 0, sumLA: 0, sumPA: 0, maxPA: 0, minPA: 999, sumQ: 0 },
    // olay bayrakları (ses için)
    events: [],
    valve: { mv: true, av: false, tv: true, pv: false },
    maneuver: null, hemQueue: 0, hemRate: 0, fluidQueue: 0, fluidRate: 0, fluidHct: 0,
    standLag: 0,
    lastVTime: 0, vfPhase: 0,
    apd: 0.3, qrsDur: 0.09, naAvail: 1, vRest: -87,
    // kayıt halkaları (4 ms)
    rec: null,
    flags: {},
  };
}

/* halka tampon */
function Ring(n) { this.n = n; this.i = 0; this.full = false; this.ch = {}; }
Ring.prototype.chan = function (k) { if (!this.ch[k]) this.ch[k] = new Float32Array(this.n); return this.ch[k]; };
Ring.prototype.push = function (obj) { for (const k in obj) this.chan(k)[this.i] = obj[k]; this.i = (this.i + 1) % this.n; if (this.i === 0) this.full = true; };
Ring.prototype.get = function (k, back) { const a = this.chan(k); let j = (this.i - 1 - back) % this.n; if (j < 0) j += this.n; return a[j]; };

/* ---------------------------------------------------------------------
   MOTOR
   --------------------------------------------------------------------- */
function Engine() {
  this.p = Object.assign({}, DEFAULTS);
  this.s = freshState();
  this.s.rec = new Ring(1500); // 6 s @ 4 ms
  this.speed = 1;
  this.recAcc = 0;
  this.slowAcc = 0;
  this.derived = {};
  this.hold = { auto: false, hum: false, fluid: false };
  this.updateDerived(true);
}
/* öğrenci modu: motorun tam kopyası */
function deepCopy(o) {
  if (o === null || typeof o !== 'object') return o;
  if (o instanceof Float32Array) return new Float32Array(o);
  if (o instanceof Ring) { const r = new Ring(o.n); r.i = o.i; r.full = o.full; for (const k in o.ch) r.ch[k] = new Float32Array(o.ch[k]); return r; }
  if (Array.isArray(o)) return o.map(deepCopy);
  const r = {}; for (const k in o) r[k] = deepCopy(o[k]); return r;
}
Engine.prototype.clone = function () {
  const e = new Engine();
  e.p = Object.assign({}, this.p); e.s = deepCopy(this.s); e.speed = this.speed; e.recAcc = this.recAcc; e.slowAcc = this.slowAcc;
  e.hold = Object.assign({}, this.hold); e.monLead = this.monLead; e.derived = Object.assign({}, this.derived); e.updateDerived();
  return e;
};
/* anında hacim değişimi (öğrenci modu): dv<0 kanama, dv>0 tam kan */
Engine.prototype.instantVolume = function (dv) {
  const s = this.s, d = this.derived, h = d.hct;
  if (dv < 0) { const r = -dv; s.rbc -= r * h; s.plasma -= r * (1 - h); s.protein -= r * (1 - h) * (d.alb / 100); s.Vsv -= r * 0.85; s.Var -= r * 0.15; }
  else { s.rbc += dv * h; s.plasma += dv * (1 - h); s.protein += dv * (1 - h) * (d.alb / 100); s.Vsv += dv; }
  this.updateDerived();
};

Engine.prototype.set = function (id, v) { this.p[id] = v; if (id === 'hct') this.setHct(v); if (id === 'albumin') this.setAlbumin(v); };
Engine.prototype.setHct = function (h) { const s = this.s; const BV = this.bloodVolume(); s.rbc = BV * h / 100; s.plasma = BV - s.rbc; };
Engine.prototype.setAlbumin = function (a) { const s = this.s; s.protein = s.plasma * a / 100; };
Engine.prototype.bloodVolume = function () { const s = this.s; return s.Vlv + s.Vao + s.Var + s.Vsv + s.Vra + s.Vrv + s.Vpa + s.Vpv + s.Vla; };
Engine.prototype.reset = function () {
  const keepSpeed = this.speed;
  this.p = Object.assign({}, DEFAULTS); this.s = freshState(); this.s.rec = new Ring(1500);
  this.speed = keepSpeed; this.updateDerived(true); this.warm(12);
};
Engine.prototype.applyPreset = function (vals) { for (const k in vals) this.set(k, vals[k]); };

Engine.prototype.action = function (id) {
  const s = this.s;
  if (id === 'hem500') { s.hemQueue += 500; }
  else if (id === 'hem1000') { s.hemQueue += 1000; }
  else if (id === 'cryst') { s.fluidQueue += 1000; s.fluidHct = 0; s.fluidProt = 0; }
  else if (id === 'transf') { s.fluidQueue += 500; s.fluidHct = 0.42; s.fluidProt = 0.042 * 0.58; }
  else if (id === 'valsalva') { s.maneuver = { kind: 'valsalva', t0: s.t, dur: 10 }; }
  else if (id === 'carotid') { s.maneuver = { kind: 'carotid', t0: s.t, dur: 8 }; }
};

/* ---- yavaş güncellenen türetilmiş parametreler (~50 ms) ---- */
Engine.prototype.updateDerived = function (init) {
  const p = this.p, s = this.s, d = this.derived;
  // --- elektrolitler → hücre
  const Ko = p.K, Nao = p.Na, Ki = 140, Nai = 10;
  d.EK = 61.5 * Math.log10(Ko / Ki);
  d.ENa = 61.5 * Math.log10(Nao / Nai);
  d.ECa = 30.75 * Math.log10(p.Ca / 0.0001);
  d.ECl = -61.5 * Math.log10(103 / 4);
  d.EMg = 30.75 * Math.log10(p.Mg / 58);
  const pNa = 0.012;
  d.vRest = 61.5 * Math.log10((Ko + pNa * Nao) / (Ki + pNa * Nai));
  // Na kanallarının kullanılabilirliği (dinlenim potansiyeline bağlı inaktivasyon)
  const hInf = 1 / (1 + Math.exp((d.vRest + 70) / 5));
  const naClass = p.naClass;
  const naBlockPow = naClass === 'IC' ? 0.75 : naClass === 'IA' ? 0.5 : 0.25;
  d.naAvail = clamp(hInf * (1 - naBlockPow * p.naBlock) * Math.pow(Nao / 142, 0.6) / (1 / (1 + Math.exp((-87 + 70) / 5))), 0, 1.3);
  // iletim hızı ~ sqrt(dV/dt)
  d.cv = Math.sqrt(Math.max(d.naAvail, 0.02));
  d.conductionFail = d.naAvail < 0.1 || p.K > 8.6;
  // QRS süresi
  let qrs = 0.088 / d.cv;
  if (p.bbb !== '0') qrs += 0.05;
  if (p.hypertrophy === 'LVH') qrs += 0.01;
  d.qrsBase = clamp(qrs, 0.07, 0.24);
  // AP süresi (bazal 300 ms, RR'ye bağlı)
  const rr = s.m.RRint || 0.8;
  let apd = 0.29 * Math.pow(rr / 0.8, 0.35);
  apd *= 1 + 0.42 * p.kBlock;                       // Faz 3 uzar
  apd *= 1 + 0.2 * clamp((3.8 - Ko) / 1.4, 0, 1.3); // hipokalemi
  apd *= 1 - 0.14 * clamp((Ko - 5) / 3, 0, 1);       // hiperkalemi
  apd *= 1 + 0.12 * clamp((2.3 - p.Ca) / 1, 0, 1);    // hipokalsemi: ST uzar
  apd *= 1 - 0.10 * clamp((p.Ca - 2.6) / 1.1, 0, 1);  // hiperkalsemi
  if (naClass === 'IA') apd *= 1 + 0.12 * p.naBlock; else if (naClass === 'IB') apd *= 1 - 0.08 * p.naBlock;
  apd *= 1 - 0.06 * p.digoxin;
  apd *= 1 + 0.08 * clamp((37 - p.temp) / 3, 0, 1);
  d.apd = clamp(apd, 0.16, 0.6);
  d.peak = 20 * clamp(d.naAvail, 0.2, 1.1) + 0.2 * (d.ENa - 63);
  d.plateau = 8 * Math.pow(p.Ca / 2.4, 0.35) * (1 - 0.35 * p.verapamil - 0.2 * p.diltiazem - 0.15 * clamp((p.Mg - 2.5) / 3, 0, 1));
  d.tAmp = 0.32 * (1 + 0.9 * clamp((Ko - 5) / 2.5, 0, 1.6)) * (1 - 0.6 * clamp((3.6 - Ko) / 1.6, 0, 1));
  d.tNarrow = 1 - 0.35 * clamp((Ko - 5) / 2.5, 0, 1);
  d.uAmp = 0.12 * clamp((3.4 - Ko) / 1.4, 0, 1.2) + 0.03;
  d.pAmp = 0.15 * (1 - 0.8 * clamp((Ko - 6.5) / 2, 0, 1));
  d.tdpRisk = (d.apd > 0.42 && Ko < 3.4) || d.apd > 0.47;
  d.digToxic = p.digoxin > 0.75 || (p.digoxin > 0.4 && Ko < 3.3);
  // kontraktilite için Ca, Mg
  d.caFactor = Math.pow(p.Ca / 2.4, 0.55);
  d.mgFactor = 1 - 0.12 * clamp(p.Mg - 2.5, 0, 3.5);
  // --- viskozite
  const hct = s.rbc / (s.rbc + s.plasma);
  d.hct = hct;
  const etaHct = 1 + 2.5 * hct + 7.35 * hct * hct;
  d.etaRel = etaHct * (1 + 0.06 * (p.fibrinogen - 3)) * (1 + 0.45 * (1 - p.deform));
  d.etaRel0 = 1 + 2.5 * 0.42 + 7.35 * 0.42 * 0.42;
  d.viscF = d.etaRel / d.etaRel0;
  d.etaLowShear = d.etaRel * 33 * (1 + 0.4 * (p.fibrinogen - 3)) * (1 + 0.6 * (1 - p.deform));
  // --- albümin / onkotik
  const alb = 100 * s.protein / s.plasma; // g/dL
  d.alb = alb;
  d.piC = 26 * Math.pow(alb / 4.2, 1.1);
  this.derivedDone = true;
};

/* ---- ventrikül aktivasyon eğrisi ---- */
function actCurve(t, Ts) {
  if (t < 0 || t > Ts) return 0;
  const tp = 0.74 * Ts;
  if (t < tp) return Math.pow(0.5 * (1 - Math.cos(Math.PI * t / tp)), 0.7);
  return 0.5 * (1 + Math.cos(Math.PI * (t - tp) / (Ts - tp)));
}
function atrCurve(t, Ta) { if (t < 0 || t > Ta) return 0; return Math.sin(Math.PI * t / Ta) ** 2; }

/* ---------------------------------------------------------------------
   RİTİM ZAMANLAYICI — atriyal ve ventriküler olaylar
   --------------------------------------------------------------------- */
Engine.prototype.sinusRR = function () {
  const p = this.p, s = this.s, d = this.derived;
  const Sb = s.Sb, Ve = s.Veff;
  const resp = (p.respOn ? s.breath : 0);
  const Vinst = Ve * (1 - 0.12 * resp);
  let slope = 40 * (1 + 1.35 * Sb + 0.8 * s.epi * (1 - p.betaBlock)) * (1 - 0.68 * Vinst);
  slope *= 1 + 0.11 * (p.temp - 37);
  slope *= Math.pow(p.thyroid, 0.45);
  slope *= 1 - 0.45 * p.verapamil - 0.32 * p.diltiazem;
  slope *= 1 - 0.12 * p.digoxin;
  slope *= 1 - 0.15 * p.betaBlock;
  slope *= 1 - 0.2 * clamp((p.Mg - 2.5) / 3, 0, 1);
  slope *= 1 - 0.25 * clamp((p.K - 6.5) / 2, 0, 1);
  slope = Math.max(slope, 5);
  const mdp = -60 - 7 * Vinst;
  const thr = -40 + 3 * (p.verapamil + p.diltiazem);
  d.saMDP = mdp; d.saThr = thr; d.saSlope = slope;
  const ph4 = (thr - mdp) / slope;
  d.saPh4 = ph4;
  return clamp(ph4 + 0.18, 0.3, 3);
};
Engine.prototype.avDelay = function () {
  const p = this.p, s = this.s;
  let f = (1 + 0.55 * s.Veff - 0.3 * s.Sb) * (1 + 0.65 * p.verapamil + 0.4 * p.diltiazem + 0.25 * p.digoxin + 0.22 * p.betaBlock + 0.3 * clamp((p.Mg - 2.5) / 3, 0, 1) + 0.4 * clamp((p.K - 5.5) / 2.5, 0, 1.2) + 0.1 * p.naBlock);
  f = clamp(f, 0.55, 3);
  let pr = 0.135 * f;
  if (p.avBlock === '1') pr = Math.max(pr, 0.26) + 0.02;
  return pr;
};
Engine.prototype.avERP = function () {
  const p = this.p, s = this.s;
  const f = (1 + 0.6 * s.Veff - 0.35 * s.Sb) * (1 + 0.8 * p.verapamil + 0.5 * p.diltiazem + 0.6 * p.digoxin + 0.4 * p.betaBlock);
  return clamp(0.27 * f, 0.18, 0.9);
};

Engine.prototype.addVentricular = function (t, kind, extra) {
  const s = this.s, d = this.derived, p = this.p;
  // ventrikül refrakter mi?
  if (s.lastV > 0 && t - s.lastV < 0.85 * d.apd && kind !== 'vt') return false;
  const rrPrev = s.lastV > 0 ? t - s.lastV : 0.8;
  const b = { id: ++s.beatId, tV: t, kind, tP: extra && extra.tP != null ? extra.tP : null, pr: extra && extra.pr || null,
    qrs: d.qrsBase * (kind === 'v' || kind === 'vt' || kind === 'esc' ? 1.7 : 1), apd: d.apd, rr: rrPrev };
  if (kind === 'v' || kind === 'vt' || kind === 'esc') b.qrs = Math.max(b.qrs, 0.13);
  b.qt = b.qrs * 0.5 + b.apd + 0.03;
  s.beats.push(b);
  if (kind === 'n' || kind === 'esc' || kind === 'v' || kind === 'vt') {
    if (s.lastV > 0) { const rr = t - s.lastV; s.m.RRint = s.m.RRint * 0.5 + rr * 0.5; s.lastRR = rr; }
    s.lastV = t;
  }
  return true;
};
Engine.prototype.addAtrial = function (t, kind) {
  const s = this.s;
  s.atrial.push({ t, kind });
};

Engine.prototype.schedule = function () {
  const s = this.s, p = this.p, d = this.derived, t = s.t;
  if (d.conductionFail) {
    // ağır hiperkalemi / iletim kaybı: sinüs dalgası, etkisiz kasılma
    if (t >= s.nextSinus) { s.nextSinus = t + 0.9; this.addVentricular(t, 'sine'); }
    return;
  }
  const rhythm = p.rhythm;
  if (rhythm === 'vf') { return; }
  // ---- atriyal etkinlik
  if (rhythm === 'sinus') {
    if (t >= s.nextSinus) {
      const rr = this.sinusRR();
      s.nextSinus = t + rr;
      this.addAtrial(t, 'p');
      this.conduct(t, 'p');
      // VES
      if (p.ves > 0 && Math.random() < p.ves) s.vesAt = t + rr * 0.58 + 0.12;
    }
  } else if (rhythm === 'af') {
    if (t >= s.afNext) { s.afNext = t + 0.12 + Math.random() * 0.12; this.conduct(t, 'f'); }
  } else if (rhythm === 'flutter') {
    if (t >= s.flNext) { s.flNext = t + 0.2; this.addAtrial(t, 'F'); this.conduct(t, 'F'); }
  } else if (rhythm === 'vt') {
    if (t >= s.vtNext) { s.vtNext = t + 0.34; this.addVentricular(t, 'vt'); }
    // sinüs atriyumu bağımsız sürer (AV disosiyasyon)
    if (t >= s.nextSinus) { s.nextSinus = t + this.sinusRR(); this.addAtrial(t, 'p'); }
  }
  if (s.vesAt && t >= s.vesAt) { this.addVentricular(t, 'v'); s.vesAt = 0; }
  // ---- kaçış ritmi (3. derece blok vb.)
  if (rhythm !== 'vt') {
    const escInt = p.avBlock === '3' ? 1.6 : 2.2; // idiyoventriküler ~37/dk
    if (s.lastV > 0 && t - s.lastV > escInt) this.addVentricular(t, 'esc');
    if (s.lastV < 0 && t > 2.5) this.addVentricular(t, 'esc');
  }
};
Engine.prototype.conduct = function (t, kind) {
  const s = this.s, p = this.p;
  const blk = p.avBlock;
  if (blk === '3') return;
  // AV düğüm refrakterliği
  const erp = this.avERP();
  if (s.lastAVt != null && t - s.lastAVt < erp) return;
  let pr = this.avDelay();
  if (kind === 'f') pr = 0.06 + pr * 0.4;
  if (kind === 'F') pr = 0.1 + pr * 0.5;
  if (blk === '2a' && kind === 'p') {
    s.mobitzCount = (s.mobitzCount || 0) + 1;
    if (s.mobitzCount >= 4) { s.mobitzCount = 0; return; }
    pr = pr + 0.07 * (s.mobitzCount - 1);
  }
  if (blk === '2b' && kind === 'p') {
    s.mobitzCount = (s.mobitzCount || 0) + 1;
    if (s.mobitzCount >= 3) { s.mobitzCount = 0; return; }
  }
  const ok = this.addVentricular(t + pr, 'n', { tP: kind === 'p' ? t : null, pr });
  if (ok) s.lastAVt = t;
};

/* ---------------------------------------------------------------------
   YAVAŞ GÜNCELLEME — refleksler, yataklar, hormonlar, Starling, O2
   dtR: gerçek zaman adımı, dtS: yavaş zaman (dtR*speed)
   --------------------------------------------------------------------- */
Engine.prototype.slow = function (dtR, dtS) {
  const p = this.p, s = this.s, d = this.derived, m = s.m;
  this.updateDerived();
  s.tSlow += dtS;
  // ---- manevralar
  let carotidBoost = 0; s.Pit_extra = 0;
  if (s.maneuver) {
    const el = s.t - s.maneuver.t0;
    if (el > s.maneuver.dur) s.maneuver = null;
    else if (s.maneuver.kind === 'valsalva') s.Pit_extra = 30 * sm(el / 0.6);
    else if (s.maneuver.kind === 'carotid') carotidBoost = 45 * sm(el / 0.8);
  }
  // ---- MAP alçak geçiren
  const map = m.MAP;
  s.dMap = (map - s.mapPrev) / Math.max(dtR, 1e-3); s.mapPrev = map;
  // ---- gazlar
  const edemaPen = clamp((s.dVlung - 150) / 6, 0, 45);
  let pao2 = p.PaO2 - edemaPen - 25 * p.pneumo - 22 * p.pe;
  pao2 = clamp(pao2 - 0.25 * Math.max(0, p.PaCO2 - 40), 20, 600);
  s.PaO2 += (pao2 - s.PaO2) * clamp(dtR / 2, 0, 1);
  s.SaO2 = 1 / (1 + Math.pow(26.8 / s.PaO2, 2.7));
  const hb = d.hct * 100 / 3;
  s.Hb = hb;
  s.CaO2 = 10 * (1.34 * hb * s.SaO2 + 0.003 * s.PaO2);
  s.VO2 = 250 * (1 + 6.5 * p.exercise) * (1 + 0.1 * (p.temp - 37)) * Math.pow(p.thyroid, 0.6) * (1 + 0.15 * p.emotion) * (1 + 0.3 * p.sepsis);
  const coL = Math.max(m.CO, 0.2);
  s.CvO2 = Math.max(s.CaO2 - s.VO2 / coL, 5);
  s.SvO2 = clamp(s.CvO2 / (13.4 * hb), 0.02, 1);
  const lacT = 1 + 14 * clamp((0.5 - s.SvO2) / 0.35, 0, 1) + 4 * p.sepsis + 3 * clamp((60 - s.PaO2) / 30, 0, 1);
  s.lactate += (lacT - s.lactate) * clamp(dtS / 60, 0, 1);
  s.pH = 7.4 - 0.012 * (s.lactate - 1) - 0.0075 * (p.PaCO2 - 40);
  const acid = clamp((7.35 - s.pH) / 0.3, 0, 1);
  // ---- kafa içi
  const icp = p.ICP + 0.18 * Math.max(0, p.PaCO2 - 40) + 0.1 * Math.max(0, m.CVP - 8);
  m.ICP = icp; m.CPP = map - Math.max(icp, 0);
  // ---- refleksler
  // baroreseptör
  const baroIn = map + 0.35 * clamp(s.dMap, -60, 60) + carotidBoost;
  s.baroB = 1 / (1 + Math.exp(-(baroIn - s.baroSet - 22 * p.exercise) / 13));
  let Sr, Vr;
  if (p.baroOn) { Sr = 0.25 + 0.75 * (0.5 - s.baroB) * 2; Vr = 0.5 + 0.95 * (s.baroB - 0.5); }
  else { Sr = 0.3; Vr = 0.45; if (carotidBoost > 0) { Vr += 0.4; Sr -= 0.2; } }
  // kemoreseptör
  const chemo = p.chemoOn ? clamp((62 - s.PaO2) / 28, 0, 1.4) + clamp((p.PaCO2 - 45) / 25, 0, 1) + 0.6 * clamp((60 - map) / 25, 0, 1) + 0.4 * acid : 0;
  s.chemo = chemo;
  Sr += 0.45 * chemo;
  // MSS iskemik yanıt
  const cnsI = p.cnsOn ? clamp((62 - m.CPP) / 18, 0, 1.8) : 0;
  s.cnsI = cnsI;
  // Bainbridge
  const bain = p.cardiopulmOn ? clamp((m.CVP - 5) / 8, 0, 1.2) : 0;
  s.bain = bain;
  Vr -= 0.22 * bain;
  // egzersiz, heyecan, ateş, hipoksi
  Sr += 0.95 * p.exercise + 0.45 * p.emotion + 0.03 * Math.max(0, p.temp - 37);
  Vr -= 0.85 * p.exercise + 0.25 * p.emotion + 0.04 * Math.max(0, p.temp - 37);
  Sr += p.sympOffset; Vr += p.vagOffset;
  Sr = clamp(Sr, 0, 1.4); Vr = clamp(Vr, 0, 1.1);
  const HA = this.hold.auto;
  if (!HA) s.cnsS = (s.cnsS || 0) + (0.9 * cnsI - (s.cnsS || 0)) * clamp(dtR / 6, 0, 1);
  s.Sraw = Sr; s.Vraw = Vr;
  if (!HA) s.V += (Vr - s.V) * clamp(dtR / 0.35, 0, 1);      // vagal hızlı
  if (!HA) s.Sbase = (s.Sbase == null ? 0.25 : s.Sbase) + (Sr - (s.Sbase == null ? 0.25 : s.Sbase)) * clamp(dtR / 2.5, 0, 1);       // sempatik daha yavaş
  s.S = s.Sbase + s.cnsS;
  s.Sb = s.S * (1 - 0.92 * p.betaBlock) + 0.55 * p.noradrenaline * (1 - 0.8 * p.betaBlock);
  s.Sa = s.S + 0.9 * p.noradrenaline + 0.6 * clamp((p.adrenaline - 0.4) / 0.6, 0, 1);
  s.Veff = s.V * (1 - 0.95 * p.atropine) + (d.digToxic ? 0.15 : 0.06 * p.digoxin);
  const epiT = 0.08 + 0.45 * Math.max(0, s.S - 0.35) + 1.4 * p.adrenaline + 0.25 * p.exercise;
  if (!HA) s.epi += (epiT - s.epi) * clamp(dtR / 4, 0, 1);
  // baro resetting (günler) ve damar yeniden yapılanması (haftalar)
  if (p.baroOn && !this.hold.fluid) s.baroSet += (s.mapLP - s.baroSet) * clamp(dtS / (3600 * 36), 0, 1);
  const remT = 1 + 0.25 * clamp((s.mapLP - 108) / 30, 0, 1.5);
  if (!this.hold.fluid) s.remodel += (remT - s.remodel) * clamp(dtS / (3600 * 24 * 10), 0, 1);
  s.mapLP += (map - s.mapLP) * clamp(dtS / 600, 0, 1);

  // ---- hormonlar
  const rsR = 0.02 * (Math.pow(1 / (1 - p.renalStenosis), 4) - 1);
  s.renalPP = 4 + (map - 4) / (1 + rsR);
  const HH = this.hold.hum;
  if (HH) { /* hormonlar sabit */ }
  else if (p.raasOn) {
    let rT = Math.exp(-(s.renalPP - 92) / 16) * (1 + 1.4 * Math.max(0, s.Sb - 0.25)) * Math.pow(Math.max(s.anp, 0.2), -0.45) * (1 + 0.5 * p.diuretic) * (1 + 0.6 * (1 - p.salt) * (p.salt < 1 ? 1 : 0)) * (1 - 0.35 * clamp(p.salt - 1, 0, 2) / 2) * (1 - 0.4 * p.betaBlock);
    rT = clamp(rT, 0.05, 12);
    s.renin += (rT - s.renin) * clamp(dtS / 240, 0, 1);
    const aT = s.renin * (1 - 0.92 * p.acei);
    s.angII += (aT - s.angII) * clamp(dtS / 120, 0, 1);
    const alT = Math.pow(Math.max(s.angII * (1 - 0.85 * p.arb), 0.02), 0.8) * (1 + 0.35 * (p.K - 4));
    s.aldo += (clamp(alT, 0.05, 10) - s.aldo) * clamp(dtS / 1800, 0, 1);
  } else { s.renin = 1; s.angII = 1; s.aldo = 1; }
  s.angEff = s.angII * (1 - 0.85 * p.arb);
  if (HH) { }
  else if (p.adhOn) {
    const bv0 = 5000;
    let adhT = 1 + 2.8 * clamp((bv0 - this.bloodVolume()) / 1000, 0, 3) + 9 * Math.pow(clamp((78 - map) / 40, 0, 1), 1.4) + 0.18 * (p.Na - 142) - (p.cardiopulmOn ? 0.55 * clamp((m.CVP + m.LAP - 11) / 10, 0, 1) : 0) + 1.5 * clamp(p.vasopressin, 0, 1) * 0;
    adhT = clamp(adhT, 0.15, 14);
    s.adh += (adhT - s.adh) * clamp(dtS / 90, 0, 1);
  } else s.adh = 1;
  s.adhTot = s.adh + 10 * p.vasopressin;
  if (HH) { }
  else if (p.anpOn) {
    const anT = 1 + 2.2 * clamp((m.CVP + m.LAP - 11) / 8, 0, 3);
    s.anp += (anT - s.anp) * clamp(dtS / 300, 0, 1);
  } else s.anp = 1;

  // ---- organ yatakları
  const vf = d.viscF;
  let G = 0; const fracSum = BEDS.reduce((a, b) => a + b.q0, 0);
  const Pa = map, Pv = m.CVP;
  const demandMuscle = 1 + 5 * p.exercise;
  const mvo2 = (m.HR / 72) * (m.SBP / 120) * (s.contrNow || 1) ;
  s.corDemand = mvo2;
  const tissueHyp = clamp((0.6 - s.SvO2) / 0.4, 0, 1);
  const hypoxDil = 1 + 0.004 * clamp(60 - s.PaO2, 0, 40);
  for (const b of BEDS) {
    let r = b.ctl ? p[b.ctl] : 1;
    if (b.id !== 'brain' && b.id !== 'cor') r *= p.rAll;
    // sempatik α1
    r *= 1 - b.alpha * (s.Sa - 0.25) * (b.id === 'muscle' ? (1 - 0.5 * p.exercise) : 1);
    // adrenalin β2: iskelet kası ve koroner dilatasyon
    if (b.id === 'muscle') r *= 1 + 0.06 * Math.min(s.epi, 1.2);
    // anjiyotensin II
    if (b.id !== 'brain' && b.id !== 'cor') r *= 1 - 0.045 * (s.angEff - 1);
    // ADH (V1) — yüksek düzeyde
    if (s.adhTot > 3) r *= 1 - 0.012 * (s.adhTot - 3) * (b.id === 'brain' || b.id === 'cor' ? 0.2 : 1);
    // ANP
    r *= 1 + 0.025 * (s.anp - 1);
    // ilaçlar
    r *= 1 + 0.17 * p.nifedipine + 0.05 * p.verapamil + 0.06 * p.diltiazem + 0.05 * p.nitrate;
    if (b.id === 'cor') r *= 1 + 0.05 * p.diltiazem + 0.04 * p.verapamil + 0.06 * p.nifedipine;
    // sepsis, anafilaksi
    r *= 1 + (0.32 * p.sepsis + 0.3 * p.anaphylaxis) * (b.id === 'brain' ? 0.4 : 1);
    // ateş: deri dilatasyonu
    if (b.id === 'skin') r *= 1 + 0.07 * (p.temp - 37) * (p.temp > 37 ? 1 : 0.7);
    // CO2: beyin
    if (b.id === 'brain') r *= 1 + 0.009 * (p.PaCO2 - 40);
    // hipoksi: sistemik dilatasyon
    r *= hypoxDil * (1 + 0.05 * tissueHyp);
    // remodeling
    r /= Math.pow(s.remodel, 0.25);
    // otoregülasyon (miyojenik + metabolik)
    let ra = s.rAuto[b.id];
    if (p.autoregOn) {
      let target = b.q0, pp = Pa - Pv;
      if (b.id === 'muscle') target *= 1 + 11 * p.exercise;
      if (b.id === 'kidney' || b.id === 'muscle') target *= Math.pow(p.rAll, 4);
      if (b.id === 'cor') target *= mvo2;
      if (b.id === 'brain') { pp = m.CPP - Math.max(Pv - Math.max(m.ICP, 0), 0) * 0; target *= 1 + 0.03 * (p.PaCO2 - 40); }
      if (b.id === 'kidney' || b.id === 'brain' || b.id === 'cor' || b.id === 'muscle') {
        const qNow = s.bedQ[b.id] || b.q0;
        const err = (target - qNow) / target;
        const lo = b.id === 'cor' ? 0.82 : 0.8, hi = b.id === 'cor' ? 1.52 : (b.id === 'muscle' ? 2.0 : 1.3);
        ra = clamp(ra + err * clamp(dtR / 6, 0, 0.2) * ra, lo, hi);
      } else ra += (1 - ra) * clamp(dtR / 10, 0, 1);
    } else ra += (1 - ra) * clamp(dtR / 5, 0, 1);
    if (!HA) s.rAuto[b.id] = ra; else ra = s.rAuto[b.id];
    r = clamp(r * ra, 0.35, 2.3);
    let Rb = (DP0 / (b.q0 / 60)) * vf / Math.pow(r, 4);
    if (b.id === 'cor' && p.corStenosis > 0) Rb += (DP0 / (b.q0 / 60)) * 0.08 * (Math.pow(1 / (1 - p.corStenosis), 4) - 1);
    if (b.id === 'kidney' && p.renalStenosis > 0) Rb += (DP0 / (b.q0 / 60)) * 0.02 * (Math.pow(1 / (1 - p.renalStenosis), 4) - 1);
    let gb = 1 / Rb;
    if (p.amputation && (b.id === 'muscle' || b.id === 'skin')) gb *= 0.78;
    if (b.id === 'cor') gb *= Math.pow(clamp((s.diastFrac || 0.62) / 0.62, 0.3, 1.4), 0.7);
    s.bedR[b.id] = 1 / gb; s.bedRadius = s.bedRadius || {}; s.bedRadius[b.id] = r;
    s.bedQ[b.id] = (Pa - Pv) * gb * 60;
    G += gb;
  }
  s.TPR = 1 / G;
  { let rs = 0, qs = 0; for (const b of BEDS) { rs += s.bedRadius[b.id] * b.q0; qs += b.q0; } s.rAvgRadius = rs / qs; }
  // koroner yedek ve iskemi
  const corMaxQ = (Pa - Pv) * 60 / ((DP0 / (250 / 60)) * vf / Math.pow(1.52 * p.rCor, 4) + (p.corStenosis > 0 ? (DP0 / (250 / 60)) * 0.08 * (Math.pow(1 / (1 - p.corStenosis), 4) - 1) : 0)) * Math.pow(clamp((s.diastFrac || 0.62) / 0.62, 0.3, 1.4), 0.7);
  const o2frac = s.CaO2 / 190;
  s.corSupplyMax = corMaxQ * o2frac / 250;
  const ischT = clamp((mvo2 / Math.max(s.corSupplyMax, 0.05) - 0.92) / 0.5, 0, 1.5) + (p.mi !== '0' ? 0.3 : 0);
  if (!HA) s.ischemia += (ischT - s.ischemia) * clamp(dtR / 3, 0, 1);
  // pulmoner direnç
  const hpv = 1 + 1.6 * clamp((72 - s.PaO2) / 40, 0, 1);
  s.PVR = 0.095 * vf * hpv * (1 + 7 * p.pe) * (1 + 0.6 * p.pneumo) * (1 + 0.25 * (p.hypertrophy === 'RVH' ? 0 : 0));
  // ---- kontraktilite
  let c = p.contractility * (1 + 0.62 * s.Sb + 0.45 * s.epi * (1 - p.betaBlock)) / (1 + 0.62 * 0.25 + 0.45 * 0.08);
  c *= 1 - 0.32 * p.verapamil - 0.14 * p.diltiazem - 0.08 * p.betaBlock;
  c *= 1 + 0.32 * p.digoxin;
  c *= d.caFactor * d.mgFactor;
  c *= 1 - 0.5 * clamp((p.K - 6.8) / 2, 0, 1);
  c *= 1 - 0.3 * acid;
  c *= 1 - 0.3 * clamp(s.ischemia - 0.3, 0, 1);
  c *= 1 - 0.18 * p.sepsis;
  c *= 1 + 0.06 * Math.min((m.HR - 72) / 60, 1); // Bowditch
  s.contrNow = c;
  s.contrLV = c * (p.mi === 'ant' ? 0.5 : p.mi === 'inf' ? 0.72 : 1);
  s.contrRV = c * (p.mi === 'inf' ? 0.8 : 1);
  // ---- venöz sistem
  const pooling = p.posture === 'standing' ? 400 * (1 - 0.7 * p.exercise) : 0;
  s.standLag += (pooling - s.standLag) * clamp(dtR / 4, 0, 1);
  s.V0sv = 2700 * (1 - 0.27 * clamp(s.Sa - 0.25, -0.25, 1.4) - 0.1 * p.venTone) + s.standLag + 380 * p.nitrate + 300 * p.sepsis + 520 * p.anaphylaxis - 480 * p.exercise - 80 * p.noradrenaline;
  s.Csv = 95 * (1 - 0.08 * (s.Sa - 0.25));
  s.Car = 1.0 * (1 - 0.6 * p.arterialStiff) + 0.12;
  // ---- hacim dengesi (böbrek) — yavaş
  let U = 1.0;
  if (p.natriOn) U *= Math.pow(clamp((0.5 * (s.renalPP + map) - 50) / 42, 0, 3), 3);
  U *= Math.pow(s.aldo, -0.25) * Math.pow(Math.max(s.angEff, 0.05), -0.2) * Math.pow(s.adhTot, -0.42) * Math.pow(s.anp, 0.4);
  U *= 1 + 2.4 * p.diuretic;
  U = clamp(U, 0, 25);
  s.urine = U;
  const thirst = 1 + 0.35 * clamp(s.adh - 1.6, 0, 6) + 0.08 * clamp(s.angII - 1.5, 0, 6);
  s.intake = p.salt * (p.adhOn ? thirst : 1);
  // ---- Starling (sistemik)
  const Ra = 0.674, Rc = 0.221, Rv = 0.105;
  const preF = Math.pow(s.rAvgRadius || 1, -4);
  const Ra_ = Ra * preF, tot = Ra_ + Rc + Rv;
  const PvCap = Math.max(Pv, -2) + 4 + p.venExtra * 0.7;
  const Pa_cap = map;
  s.PcA = Pa_cap - (Pa_cap - PvCap) * Ra_ / tot;
  s.PcV = PvCap + (Pa_cap - PvCap) * Rv / tot;
  const piIF0 = 1 * Math.pow(p.perm, 1.2);
  const washout = clamp(Math.pow(2 / Math.max(s.Jsys, 0.4), 0.25), 0.55, 1.4);
  s.piIF = piIF0 * washout + (p.perm - 1) * 2.5;
  s.Pif = 0 + clamp(s.dVi / 2500, -0.5, 6) + clamp((s.dVi - 4000) / 4000, 0, 4);
  const sigma = 1 / (1 + 0.35 * (p.perm - 1));
  const nfpA = (s.PcA + s.piIF * 1) - (d.piC * sigma + s.Pif);
  const nfpV = (s.PcV + s.piIF * 1) - (d.piC * sigma + s.Pif);
  s.nfpA = nfpA; s.nfpV = nfpV;
  let J;
  const permEff = p.perm * (1 + 1.6 * p.sepsis + 2.2 * p.anaphylaxis);
  s.permEff = permEff;
  const Kf = 4.0 * permEff;
  if (p.starling === 'classic') J = Kf * (nfpA + nfpV) / 2;
  else {
    // glikokaliks: sürekli reabsorbsiyon yok; ani P düşüşünde geçici reabsorbsiyon
    const pos = nfpA <= 0 ? 0 : (nfpV >= 0 ? (nfpA + nfpV) / 2 : nfpA * (nfpA / (nfpA - nfpV)) / 2);
    J = 0.76 * permEff * pos;
    if (s.PcSlow == null) s.PcSlow = s.PcA;
    s.PcSlow += (s.PcA - s.PcSlow) * clamp(dtS / 2400, 0, 1);
    s.transReab = 1.2 * Math.max(0, s.PcSlow - s.PcA - 0.5);
    J -= s.transReab;
  }
  s.PcPrev = s.PcA;
  s.Jsys = J;
  const Lmax = 14 * p.lymph;
  const Lsys = Math.min(2 * Math.max(0.2, 1 + 2.8 * clamp(s.dVi / 1000, -0.5, 4)) * Math.max(0.3, Math.min(1, p.lymph * 1.2)), Lmax) + 0.25 * p.exercise;
  s.Lsys = Lsys;
  // bacak (ayakta)
  const legPc = s.PcV + (p.posture === 'standing' ? 55 * (1 - 0.7 * p.exercise) : 0) + p.venExtra;
  s.legPc = legPc;
  if (!this.hold.fluid) s.legEdema += ((legPc - 30) * 0.02 * p.perm * (p.posture === 'standing' ? 1 : 0.2) - s.legEdema * 0.0008) * dtS / 60;
  s.legEdema = clamp(s.legEdema, 0, 3000);
  // ---- Starling (akciğer)
  const PcL = m.LAP + 0.4 * (m.PAm - m.LAP);
  s.PcL = PcL;
  const JL = 0.2 * p.perm * ((PcL + 14 * (p.perm > 1.5 ? 0.6 : 0.5)) - (d.piC * sigma + (-3 + s.dVlung / 200)) + 4) ;
  s.Jlung = Math.max(JL, -0.4);
  const LmaxL = 3.2 * p.lymph;
  s.Llung = Math.min(0.3 * (1 + 4 * clamp(s.dVlung / 300, 0, 3)), LmaxL);
  // ---- hacim integrasyonu (yavaş zaman)
  const k = this.hold.fluid ? 0 : dtS / 60;
  const dPlasma = (s.intake - U) * k - (J - Lsys) * k - (s.Jlung - s.Llung) * k;
  s.dVi += (J - Lsys) * k; s.dVi = clamp(s.dVi, -1500, 25000);
  s.dVlung += (s.Jlung - s.Llung) * k; s.dVlung = clamp(s.dVlung, -60, 2500);
  // protein: filtrasyon proteini taşımaz (yaklaşık); nefrotik ayrıca albümin kontrolüyle
  s.plasma += dPlasma; s.Vsv += dPlasma;
  if (s.plasma < 600) { s.Vsv += 600 - s.plasma; s.plasma = 600; }
  // albümin hedefi kontrolden (protein kütlesi kontrol değişince setAlbumin)
  // ---- kanama / sıvı (gerçek zaman)
  if (s.hemQueue > 0) {
    const r = Math.min(s.hemQueue, 1000 / 25 * dtR);
    s.hemQueue -= r; const h = d.hct;
    s.rbc -= r * h; s.plasma -= r * (1 - h); s.protein -= r * (1 - h) * (d.alb / 100);
    s.Vsv -= r * 0.85; s.Var -= r * 0.15;
  }
  if (s.fluidQueue > 0) {
    const r = Math.min(s.fluidQueue, 1000 / 25 * dtR);
    s.fluidQueue -= r;
    s.rbc += r * s.fluidHct; s.plasma += r * (1 - s.fluidHct); s.protein += r * (s.fluidProt || 0);
    s.Vsv += r;
  }
  // görünür toplam kontrol değeri
  // ---- son
  m.Hct = d.hct * 100;
};

/* ---------------------------------------------------------------------
   HIZLI ADIM — basınç/akım (dt ~ 0.25 ms)
   --------------------------------------------------------------------- */
const C0 = {
  Cao: 0.26, V0ao: 95, L: 0.0007, Rc: 0.035,
  V0ar: 680, Rvr: 0.028,
  V0pa: 95, Cpa: 3.6, V0pv: 290, Cpv: 11, Rpvla: 0.012,
  Rmv: 0.004, Rav: 0.004, Rtv: 0.003, Rpvv: 0.004,
  lv: { Es: 2.6, V0: 10, A: 0.38, k: 0.031 },
  rv: { Es: 0.55, V0: 20, A: 0.5, k: 0.024 },
  la: { Emin: 0.2, Emax: 0.55, V0: 22 }, ra: { Emin: 0.12, Emax: 0.36, V0: 20 },
};

Engine.prototype.fast = function (dt) {
  const p = this.p, s = this.s, d = this.derived, c = C0;
  const t = s.t;
  // --- solunum
  const respRate = 12 * (1 + 0.8 * s.chemo + 1.3 * p.exercise) * (s.cnsI > 0.6 ? (0.6 + 0.4 * Math.sin(t * 0.7)) : 1);
  s.respPhase = (s.respPhase || 0) + dt * respRate / 60;
  const ph = s.respPhase % 1;
  const breath = p.respOn ? (ph < 0.4 ? Math.sin(Math.PI * ph / 0.4) : 0) : 0;
  s.breath = breath;
  let Pit = -2.5 - 2.6 * breath * (1 + 0.6 * p.exercise + 0.4 * s.chemo);
  Pit += (s.Pit_extra || 0) + 9 * p.pneumo;
  s.Pit = Pit;
  const Pper = p.tamponade;
  // --- aktivasyonlar: son vuruşlar
  let aLV = 0, aRV = 0, aLA = 0, aRA = 0;
  const bs = s.beats;
  for (let i = bs.length - 1; i >= 0 && i >= bs.length - 4; i--) {
    const b = bs[i];
    const Ts = 0.95 * b.apd + 0.11;
    let eff = 1, dLV = 0.012, dRV = 0.03;
    if (b.kind === 'v' || b.kind === 'vt') { eff = 0.72; dRV = 0.05; }
    if (b.kind === 'esc') { eff = 0.85; dRV = 0.04; }
    if (b.kind === 'sine') { eff = 0.25; }
    if (p.bbb === 'L') { dLV += 0.045; dRV += 0.0; }
    if (p.bbb === 'R') { dRV += 0.045; }
    aLV = Math.max(aLV, eff * actCurve(t - b.tV - dLV, Ts));
    aRV = Math.max(aRV, eff * actCurve(t - b.tV - dRV, Ts * 1.06));
  }
  const at = s.atrial;
  for (let i = at.length - 1; i >= 0 && i >= at.length - 3; i--) {
    const a = at[i];
    const k = a.kind === 'F' ? 0.35 : 1;
    aRA = Math.max(aRA, k * atrCurve(t - a.t - 0.03, 0.11));
    aLA = Math.max(aLA, k * atrCurve(t - a.t - 0.05, 0.11));
  }
  if (p.rhythm === 'af') { aLA = aRA = 0.04 * (1 + Math.sin(t * 38)); }
  if (p.rhythm === 'vf' || d.conductionFail) {
    s.vfPhase += dt;
    const ch = p.rhythm === 'vf' ? 0.035 * (1 + Math.sin(t * 31) * Math.sin(t * 17.3)) : aLV;
    aLV = Math.max(aLV, ch); aRV = Math.max(aRV, ch);
  }
  s.actLV = aLV; s.actRV = aRV; s.actLA = aLA; s.actRA = aRA;
  // --- basınçlar
  const lvE = c.lv.Es * s.contrLV, rvE = c.rv.Es * s.contrRV * (p.hypertrophy === 'RVH' ? 1.5 : 1);
  const lvA = c.lv.A * p.stiffness * (p.hypertrophy === 'LVH' ? 1.9 : 1) * (1 + 0.6 * clamp(s.ischemia, 0, 1)) * (p.mi !== '0' ? 1.3 : 1);
  const rvA = c.rv.A * (p.hypertrophy === 'RVH' ? 2 : 1) * Math.sqrt(p.stiffness);
  const lvEs = lvE * (p.hypertrophy === 'LVH' ? 1.3 : 1);
  const PlvED = lvA * (Math.exp(c.lv.k * (s.Vlv - c.lv.V0)) - 1);
  const PrvED = rvA * (Math.exp(c.rv.k * (s.Vrv - c.rv.V0)) - 1);
  const Plv = aLV * lvEs * (s.Vlv - c.lv.V0) + (1 - aLV) * PlvED + Pit + Pper;
  const Prv = aRV * rvE * (s.Vrv - c.rv.V0) + (1 - aRV) * PrvED + Pit + Pper;
  const Ela = c.la.Emin + (c.la.Emax - c.la.Emin) * aLA;
  const Era = c.ra.Emin + (c.ra.Emax - c.ra.Emin) * aRA;
  const Pla = Ela * (s.Vla - c.la.V0) + Pit + Pper;
  const Pra = Era * (s.Vra - c.ra.V0) + Pit + Pper;
  const Pao = (s.Vao - c.V0ao) / c.Cao + Pit;
  const Par = (s.Var - c.V0ar) / s.Car;
  const Psv = (s.Vsv - s.V0sv) / s.Csv;
  const Cpv = c.Cpv * (1 + 0.18 * breath);
  const Ppa = (s.Vpa - c.V0pa) / c.Cpa + Pit;
  const Ppv = (s.Vpv - c.V0pv) / Cpv + Pit;
  // --- kapak dirençleri
  const Rav = c.Rav + 0.3 * Math.pow(p.AS, 2.2);
  const RavB = p.AR > 0 ? 0.04 + 0.9 * Math.pow(1 - p.AR, 2.5) : 1e9;
  const Rmv = c.Rmv + 0.2 * Math.pow(p.MS, 2.2);
  const RmvB = p.MR > 0 ? 0.035 + 0.9 * Math.pow(1 - p.MR, 2.5) : 1e9;
  const Rpvv = c.Rpvv + (p.hypertrophy === 'RVH' ? 0.03 : 0);
  // --- akımlar
  const vq = (a, b, Rf, Rb) => (a > b ? (a - b) / Rf : (a - b) / Rb);
  const Qmv = vq(Pla, Plv, Rmv, RmvB);
  const Qav = vq(Plv, Pao, Rav, RavB);
  const Qtv = vq(Pra, Prv, c.Rtv, 1e9);
  const Qpv = vq(Prv, Ppa, Rpvv, 1e9);
  const Rsys = s.TPR;
  const Qsys = (Par - Psv) / Rsys;
  const PraEff = Math.max(Pra, -2);
  let Qvr = (Psv + 0.7 * (s.Pit_extra || 0) - PraEff) / (c.Rvr * (p.posture === 'standing' ? 1.1 : 1) * (1 + 0.8 * clamp(((s.Pit_extra || 0) - 12) / 20, 0, 1)) * (1 + 0.8 * p.pneumo));
  if (Qvr < 0) Qvr *= 0.05; // venöz kapaklar / kollaps: geri akım çok sınırlı
  const Qpul = (Ppa - Ppv) / s.PVR;
  const Qpvla = (Ppv - Pla) / c.Rpvla;
  s.Qao += dt * (Pao - Par - c.Rc * s.Qao) / c.L;
  // --- hacim güncelleme
  s.Vlv += dt * (Qmv - Qav);
  s.Vao += dt * (Qav - s.Qao);
  s.Var += dt * (s.Qao - Qsys);
  s.Vsv += dt * (Qsys - Qvr);
  s.Vra += dt * (Qvr - Qtv);
  s.Vrv += dt * (Qtv - Qpv);
  s.Vpa += dt * (Qpv - Qpul);
  s.Vpv += dt * (Qpul - Qpvla);
  s.Vla += dt * (Qpvla - Qmv);
  { let add = 0; if (s.Vlv < 12) { add += 12 - s.Vlv; s.Vlv = 12; } if (s.Vrv < 22) { add += 22 - s.Vrv; s.Vrv = 22; } if (s.Vla < 23) { add += 23 - s.Vla; s.Vla = 23; } if (s.Vra < 21) { add += 21 - s.Vra; s.Vra = 21; } if (add) s.Vsv -= add; }
  // --- kapak olayları (sesler)
  const mvOpen = Qmv > 0, avOpen = Qav > 0, tvOpen = Qtv > 0, pvOpen = Qpv > 0;
  const v = s.valve;
  if (aLV > 0.03 && Plv > Pla && s.m1Beat !== s.lastClosedBeat) { s.m1Beat = s.lastClosedBeat; this.event('M1', aLV); }
  if (aRV > 0.03 && Prv > Pra && s.t1Beat !== s.lastClosedBeat) { s.t1Beat = s.lastClosedBeat; this.event('T1', aRV); }
  { const lb = bs[bs.length - 1]; if (lb && lb.id !== s.lastClosedBeat && t >= lb.tV) { s.lastClosedBeat = lb.id; this.closeBeat(); } }
  if (v.av && !avOpen) this.event('A2', Pao - Plv);
  if (v.pv && !pvOpen) this.event('P2', Ppa - Prv);
  if (!v.mv && mvOpen) this.event('MO', Pla - Plv);
  if (!v.av && avOpen) this.event('AO', 0);
  v.mv = mvOpen; v.av = avOpen; v.tv = tvOpen; v.pv = pvOpen;
  // anlık değerler
  s.inst = { Plv, Prv, Pla, Pra, Pao, Par, Psv, Ppa, Ppv, Qmv, Qav, Qtv, Qpv, Qsys, Qvr, Qpul, Pit, aLV, aRV, aLA, aRA };
  // --- vuruş kaydı
  const br = s.beatRec;
  br.maxV = Math.max(br.maxV, s.Vlv); br.minV = Math.min(br.minV, s.Vlv);
  br.maxRVV = Math.max(br.maxRVV, s.Vrv); br.minRVV = Math.min(br.minRVV, s.Vrv);
  br.maxP = Math.max(br.maxP, Plv - Pit - Pper);
  if (!avOpen && aLV < 0.02 && Qmv > 0) br.edp = Plv - Pit - Pper;
  // pencere ortalamaları
  const w = s.win;
  w.maxAo = Math.max(w.maxAo, Par); w.minAo = Math.min(w.minAo, Par);
  w.sumAo += Par * dt; w.sumRA += (Pra) * dt; w.sumLA += (Pla) * dt; w.sumPA += Ppa * dt; w.sumQ += Qav * dt; w.n += dt;
  w.maxPA = Math.max(w.maxPA, Ppa); w.minPA = Math.min(w.minPA, Ppa);
  w.sumDiast = (w.sumDiast || 0) + (aLV < 0.15 ? dt : 0);
  s.t += dt;
};

Engine.prototype.event = function (k, mag) {
  const s = this.s;
  s.events.push({ k, t: s.t, mag });
  if (k === 'A2') s.lastA2 = s.t;
  if (k === 'P2') { if (s.lastA2 && s.t - s.lastA2 < 0.12) s.m.split = s.m.split * 0.6 + (s.t - s.lastA2) * 0.4; }
  if (s.events.length > 60) s.events.splice(0, 20);
};

Engine.prototype.closeBeat = function () {
  const s = this.s, br = s.beatRec, m = s.m;
  if (br.maxV > 0 && br.minV < 999 && s.t - br.start > 0.2) {
    const sv = br.maxV - br.minV;
    m.EDV = m.EDV * 0.4 + br.maxV * 0.6;
    m.ESV = m.ESV * 0.4 + br.minV * 0.6;
    m.SV = m.EDV - m.ESV;
    m.EF = m.SV / Math.max(m.EDV, 1);
    m.RVEDV = br.maxRVV; m.RVSV = br.maxRVV - br.minRVV;
    if (br.edp != null) m.LVEDP = m.LVEDP * 0.5 + br.edp * 0.5;
    m.LVSP = br.maxP;
  }
  br.maxV = 0; br.minV = 999; br.maxRVV = 0; br.minRVV = 999; br.maxP = 0; br.start = s.t; br.edp = null;
};

Engine.prototype.closeWindow = function () {
  const s = this.s, w = s.win, m = s.m;
  if (w.n < 0.5) return;
  const a = 0.5;
  m.SBP = m.SBP * (1 - a) + w.maxAo * a;
  m.DBP = m.DBP * (1 - a) + w.minAo * a;
  m.MAP = m.MAP * (1 - a) + (w.sumAo / w.n) * a;
  m.CVP = m.CVP * (1 - a) + (w.sumRA / w.n) * a;
  m.LAP = m.LAP * (1 - a) + (w.sumLA / w.n) * a;
  m.PAm = m.PAm * (1 - a) + (w.sumPA / w.n) * a;
  m.PAs = w.maxPA; m.PAd = w.minPA;
  m.CO = m.CO * (1 - a) + (w.sumQ / w.n * 60 / 1000) * a;
  s.diastFrac = clamp(w.sumDiast / w.n, 0.1, 0.9);
  s.win = { maxAo: -999, minAo: 999, sumAo: 0, sumRA: 0, sumLA: 0, sumPA: 0, sumQ: 0, n: 0, maxPA: -99, minPA: 999, sumDiast: 0 };
};

/* ---------------------------------------------------------------------
   ANA DÖNGÜ
   --------------------------------------------------------------------- */
Engine.prototype.advance = function (dtReal) {
  const s = this.s;
  dtReal = Math.min(dtReal, 0.05);
  const dt = 0.00025;
  let n = Math.round(dtReal / dt);
  for (let i = 0; i < n; i++) {
    this.schedule();
    this.fast(dt);
    this.recAcc += dt;
    if (this.recAcc >= 0.004) { this.recAcc -= 0.004; this.record(); }
    this.slowAcc += dt;
    if (this.slowAcc >= 0.02) { this.slow(this.slowAcc, this.slowAcc * this.speed); this.slowAcc = 0; }
    if (s.t - (s.win.t0 || 0) > 1.6) { this.closeWindow(); s.win.t0 = s.t; }
  }
  // eski vuruşları temizle
  const cut = s.t - 8;
  while (s.beats.length > 4 && s.beats[0].tV < cut) s.beats.shift();
  while (s.atrial.length > 4 && s.atrial[0].t < cut) s.atrial.shift();
  this.measure();
};

Engine.prototype.warm = function (sec) {
  const keep = this.speed; this.speed = 1;
  for (let t = 0; t < sec; t += 0.05) this.advance(0.05);
  this.speed = keep;
  this.s.events = [];
};

Engine.prototype.measure = function () {
  const s = this.s, m = s.m, d = this.derived, p = this.p;
  // HR ventriküler olaylardan
  const vb = s.beats.filter(b => b.kind !== 'sine');
  if (vb.length >= 3) {
    const last = vb.slice(-6);
    const span = last[last.length - 1].tV - last[0].tV;
    m.HR = span > 0 ? 60 * (last.length - 1) / span : m.HR;
    if (s.t - last[last.length - 1].tV > 2.5) m.HR = 60 / (s.t - last[last.length - 1].tV);
  } else m.HR = 0;
  if (p.rhythm === 'vf' || d.conductionFail) m.HR = p.rhythm === 'vf' ? 0 : m.HR;
  const lastN = [...s.beats].reverse().find(b => b.kind === 'n');
  m.PR = lastN && lastN.pr ? lastN.pr : 0;
  const lastB = s.beats[s.beats.length - 1];
  if (lastB) { m.QRS = lastB.qrs; m.QT = lastB.qt; m.QTc = lastB.qt / Math.sqrt(Math.max(m.RRint, 0.3)); }
  m.cardiacIndex = m.CO / 1.8;
  // Reynolds (aort, ortalama hız)
  const vMean = (m.CO * 1000 / 60) / 4.9; // cm/s
  const vPeak = vMean * 3.2;
  m.vAorta = vMean;
  m.Re = 1.06 * 2.5 * vMean / (0.0097 * d.etaRel);
  m.ReAS = p.AS > 0 ? m.Re * (1 + 4 * p.AS) : m.Re;
  m.vPeak = vPeak;
  m.ReAS = p.AS > 0 ? m.Re * (1 + 4 * p.AS) : m.Re;
  m.axis = this.axisDeg();
  m.MAPcalc = m.CO * s.TPR * 60 / 1000; // kontrol
};

/* ---------------------------------------------------------------------
   EKG — dalga vektörleri ve derivasyon projeksiyonu
   --------------------------------------------------------------------- */
const LEADS = {
  I: { f: 0, g: 1 }, II: { f: 60, g: 1 }, III: { f: 120, g: 1 },
  aVR: { f: -150, g: 0.87 }, aVL: { f: -30, g: 0.87 }, aVF: { f: 90, g: 0.87 },
  V1: { h: 120, g: 1.0 }, V2: { h: 95, g: 1.35 }, V3: { h: 75, g: 1.45 }, V4: { h: 55, g: 1.45 }, V5: { h: 30, g: 1.2 }, V6: { h: 0, g: 1.0 },
};
Engine.LEADS = LEADS;
function proj(lead, af, ah) {
  const L = LEADS[lead];
  if (L.f !== undefined) return L.g * Math.cos((af - L.f) * DEG);
  return L.g * Math.cos((ah - L.h) * DEG);
}
const gauss = (x, s) => Math.exp(-0.5 * (x / s) * (x / s));

Engine.prototype.morph = function (b) {
  // dalga listesi (önbellekli)
  if (b.waves) return b.waves;
  const p = this.p, d = this.derived, s = this.s;
  const W = [];
  const q = b.qrs, k = q / 0.09;
  let axis = 59, hMain = -12, rAmp = 1.25;
  if (p.hypertrophy === 'LVH') { axis = -15; hMain = -35; rAmp = 1.9; }
  if (p.hypertrophy === 'RVH') { axis = 120; hMain = 95; rAmp = 1.2; }
  if (p.mi === 'inf') axis -= 15;
  const t0 = b.tV;
  const kind = b.kind;
  const tA = d.tAmp, tW = 0.055 * d.tNarrow * Math.sqrt(b.apd / 0.29);
  const tPeak = t0 + b.qrs * 0.5 + b.apd * 0.82 + 0.01;
  if (kind === 'sine') {
    W.push({ t: t0 + 0.12, s: 0.11, a: 0.9, af: axis, ah: hMain });
    W.push({ t: t0 + 0.42, s: 0.14, a: -0.7, af: axis, ah: hMain });
    b.waves = W; return W;
  }
  if (kind === 'v' || kind === 'vt' || kind === 'esc') {
    const fa = kind === 'esc' ? -60 : -75, ha = 150;
    W.push({ t: t0 + 0.04 * k, s: 0.03 * k, a: 1.4, af: fa, ah: ha });
    W.push({ t: t0 + 0.1 * k, s: 0.028 * k, a: -0.5, af: fa + 40, ah: ha - 30 });
    W.push({ t: t0 + b.apd * 0.8 + 0.06, s: 0.07, a: -0.45, af: fa, ah: ha });
    b.waves = W; return W;
  }
  // P dalgası
  if (b.tP != null && p.rhythm === 'sinus') {
    const pa = d.pAmp;
    W.push({ t: b.tP + 0.03, s: 0.017, a: pa * 0.65, af: 70, ah: 70 });
    W.push({ t: b.tP + 0.065, s: 0.018, a: pa * 0.7, af: 45, ah: -45 });
  }
  // QRS
  if (p.bbb === 'L') {
    W.push({ t: t0 + 0.02 * k, s: 0.016 * k, a: 0.3, af: 10, ah: -20 });
    W.push({ t: t0 + 0.06 * k, s: 0.03 * k, a: rAmp * 1.15, af: -25, ah: -40 });
    W.push({ t: t0 + 0.095 * k, s: 0.02 * k, a: 0.35, af: -10, ah: -60 });
    W.push({ t: tPeak, s: tW * 1.2, a: -tA * 1.1, af: 155, ah: 140 });
  } else if (p.bbb === 'R') {
    W.push({ t: t0 + 0.012, s: 0.011, a: 0.18, af: 150, ah: 110 });
    W.push({ t: t0 + 0.04, s: 0.017, a: rAmp, af: axis + 15, ah: hMain });
    W.push({ t: t0 + 0.095, s: 0.024, a: 0.65, af: 160, ah: 115 });
    W.push({ t: tPeak, s: tW, a: tA * 0.8, af: 50, ah: -20 });
  } else {
    W.push({ t: t0 + 0.012 * k, s: 0.009 * k, a: 0.16, af: 145, ah: 110 });
    W.push({ t: t0 + 0.042 * k, s: 0.015 * k, a: rAmp, af: axis, ah: hMain });
    W.push({ t: t0 + 0.068 * k, s: 0.012 * k, a: 0.32, af: -120, ah: -150 });
    W.push({ t: tPeak, s: tW, a: tA, af: axis - 15, ah: 10 });
  }
  // U dalgası
  if (d.uAmp > 0.04) W.push({ t: tPeak + 0.13, s: 0.035, a: d.uAmp, af: 50, ah: 20 });
  // ST sapmaları (iskemi / MI / digoksin)
  b.st = [];
  const jT = t0 + b.qrs, stEnd = tPeak - tW;
  if (p.mi === 'ant') b.st.push({ a: 0.28, af: 60, ah: 80 });
  if (p.mi === 'inf') b.st.push({ a: 0.25, af: 105, ah: -60 });
  if (s.ischemia > 0.35 && p.mi === '0') b.st.push({ a: -0.16 * clamp(s.ischemia, 0, 1.2), af: axis, ah: hMain + 10 });
  if (p.digoxin > 0.3) b.st.push({ a: -0.08 * p.digoxin, af: axis, ah: hMain, scoop: true });
  b.stWin = [jT, stEnd + tW * 0.6];
  b.waves = W;
  return W;
};

Engine.prototype.leadValue = function (lead, t) {
  const s = this.s, p = this.p, d = this.derived;
  let v = 0;
  const bs = s.beats;
  for (let i = bs.length - 1; i >= 0; i--) {
    const b = bs[i];
    if (b.tV > t + 0.3) continue;
    if (b.tV < t - 1.3) break;
    const W = this.morph(b);
    for (let j = 0; j < W.length; j++) { const w = W[j]; const x = t - w.t; if (x > -5 * w.s && x < 5 * w.s) v += w.a * gauss(x, w.s) * proj(lead, w.af, w.ah); }
    if (b.st && b.st.length) {
      const [a0, a1] = b.stWin;
      if (t > a0 - 0.01 && t < a1 + 0.05) {
        const e = sm((t - a0 + 0.01) / 0.02) * (1 - sm((t - a1) / 0.06));
        for (const st of b.st) v += st.a * e * (st.scoop ? Math.sin(Math.PI * clamp((t - a0) / (a1 - a0), 0, 1)) : 1) * proj(lead, st.af, st.ah);
      }
    }
  }
  // atriyal etkinlik (flatter / AF / VT'de bağımsız P)
  if (p.rhythm === 'flutter') {
    const ph = (t * 5) % 1;
    v += 0.22 * (ph < 0.75 ? -ph / 0.75 + 0.5 : (ph - 0.75) / 0.25 * 1 - 0.5) * proj(lead, 95, -20);
  } else if (p.rhythm === 'af') {
    v += 0.05 * (Math.sin(t * 37.1) + 0.7 * Math.sin(t * 43.7 + 1) + 0.5 * Math.sin(t * 29.3 + 2)) * proj(lead, 80, 100);
  } else if (p.rhythm === 'vt' || p.avBlock === '3') {
    for (const a of s.atrial) { const x1 = t - a.t - 0.03, x2 = t - a.t - 0.065; if (x1 > -0.1 && x2 < 0.1) v += d.pAmp * (0.65 * gauss(x1, 0.017) * proj(lead, 70, 70) + 0.7 * gauss(x2, 0.018) * proj(lead, 45, -45)); }
  }
  if (p.avBlock !== '0' && p.avBlock !== '3' && p.rhythm === 'sinus') {
    // iletilmeyen P'ler
    for (const a of s.atrial) {
      if (a.t < t - 0.3 || a.t > t + 0.1) continue;
      const conducted = bs.some(b => b.tP === a.t);
      if (!conducted) { const x1 = t - a.t - 0.03, x2 = t - a.t - 0.065; v += d.pAmp * (0.65 * gauss(x1, 0.017) * proj(lead, 70, 70) + 0.7 * gauss(x2, 0.018) * proj(lead, 45, -45)); }
    }
  }
  if (p.rhythm === 'vf') {
    v += 0.5 * (Math.sin(t * 31) * (0.6 + 0.4 * Math.sin(t * 1.3)) + 0.5 * Math.sin(t * 23.7 + 1.1)) * proj(lead, 60 + 40 * Math.sin(t * 0.7), 0 + 60 * Math.sin(t * 0.5));
  }
  return v;
};

Engine.prototype.axisDeg = function () {
  // son normal vuruşun QRS'inin DI ve aVF'deki net alanı
  const s = this.s; const b = [...s.beats].reverse().find(x => x.kind !== 'sine');
  if (!b) return null;
  const W = this.morph(b).filter(w => w.t < b.tV + b.qrs + 0.02);
  let I = 0, F = 0;
  for (const w of W) { I += w.a * w.s * proj('I', w.af, w.ah); F += w.a * w.s * proj('aVF', w.af, w.ah) / 0.87; }
  return Math.atan2(F, I) / DEG;
};

/* ---------------------------------------------------------------------
   KAYIT (4 ms)
   --------------------------------------------------------------------- */
Engine.prototype.record = function () {
  const s = this.s, i = s.inst;
  if (!i) return;
  s.rec.push({
    t: s.t, Plv: i.Plv, Pao: i.Par, Paop: i.Pao, Pla: i.Pla, Pra: i.Pra + (s.actRV > 0.02 && s.actRV < 0.3 && s.valve.pv === false ? 1.2 * Math.sin(Math.PI * s.actRV / 0.3) : 0), Prv: i.Prv, Ppa: i.Ppa,
    Vlv: s.Vlv, Vrv: s.Vrv, ecg: this.leadValue(this.monLead || 'II', s.t), aLV: i.aLV, aLA: i.aLA,
    Qav: i.Qav, Qmv: i.Qmv, breath: s.breath, mv: (s.valve.mv || i.aLV < 0.03) ? 1 : 0, av: s.valve.av ? 1 : 0,
  });
};

/* ---------------------------------------------------------------------
   AP eğrileri (hücre sekmesi)
   --------------------------------------------------------------------- */
Engine.prototype.ventAP = function (tau) {
  // tau: aktivasyondan sonra geçen süre (s)
  const d = this.derived, apd = d.apd;
  const vr = d.vRest, pk = d.peak;
  if (tau < 0) return vr;
  const rise = 0.0015 / Math.max(d.naAvail, 0.1);
  if (tau < rise) return vr + (pk - vr) * (tau / rise);
  const t1 = rise + 0.012;
  const notch = d.plateau + 4;
  if (tau < t1) return pk + (notch - pk) * ((tau - rise) / 0.012);
  const t2 = apd * 0.72;
  if (tau < t2) return notch - 6 * ((tau - t1) / (t2 - t1));
  if (tau < apd) { const x = (tau - t2) / (apd - t2); return (notch - 6) + (vr - (notch - 6)) * (1 - Math.cos(Math.PI * x)) / 2; }
  return vr;
};
Engine.prototype.ventCurrents = function (tau) {
  const d = this.derived, apd = d.apd;
  const rise = 0.0015 / Math.max(d.naAvail, 0.1);
  const INa = tau >= 0 && tau < rise * 3 ? d.naAvail * Math.exp(-tau / (rise * 0.8)) : 0;
  const Ito = tau > rise && tau < rise + 0.03 ? Math.sin(Math.PI * (tau - rise) / 0.03) * 0.6 : 0;
  const ICaL = tau > rise && tau < apd * 0.85 ? (d.plateau / 8) * Math.sin(Math.PI * Math.min((tau - rise) / (apd * 0.6), 1)) * (tau < apd * 0.6 ? 1 : 1 - (tau - apd * 0.6) / (apd * 0.25)) : 0;
  const IK = tau > 0.03 && tau < apd * 1.05 ? Math.pow(Math.min((tau - 0.03) / (apd * 0.7), 1), 1.5) * (tau > apd ? 1 - (tau - apd) / (apd * 0.05) : 1) : 0;
  const IK1 = tau < 0 || tau > apd * 0.75 ? (tau > apd * 0.75 && tau < apd * 1.1 ? 1 : 0.35) : 0.05;
  return { INa, Ito, ICaL, IK, IK1 };
};
Engine.prototype.saAP = function (tau) {
  const d = this.derived;
  const mdp = d.saMDP || -60, thr = d.saThr || -40, slope = d.saSlope || 35;
  const ph4 = (thr - mdp) / slope;
  if (tau < ph4) return mdp + slope * tau + 0.15 * slope * tau * tau * 0;
  const t0 = tau - ph4;
  const up = 0.05 * (1 + 0.8 * this.p.verapamil + 0.5 * this.p.diltiazem);
  if (t0 < up) return thr + (5 - thr) * Math.sin(Math.PI / 2 * t0 / up);
  const rep = 0.13;
  if (t0 < up + rep) return 5 + (mdp - 5) * (1 - Math.cos(Math.PI * (t0 - up) / rep)) / 2;
  return mdp;
};

/* ---------------------------------------------------------------------
   DIŞA AKTAR
   --------------------------------------------------------------------- */
Engine.CONTROLS = CONTROLS;
Engine.DEFAULTS = DEFAULTS;
Engine.BEDS = BEDS;
Engine.clamp = clamp;
global.KVSEngine = Engine;
})(typeof window !== 'undefined' ? window : globalThis);
