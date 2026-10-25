/* =================================================================
   ÖĞRENCİ MODU — basit kontroller, aşamalı sonuç, konsol, kısaltmalar
   (ui.js IIFE'sinin içine yerleştirilir; eng, fmt, $ vb. paylaşılır)
   ================================================================= */
const ST = window.KVSSettle;
const STU = { on: false, base: null, cur: null, normal: null, normalEng: null, target: {}, applied: {}, bvT: 0, bvA: 0, job: null,
  disp: {}, tw: null, entryN: 0, tabChg: {}, lastResult: null, silent: false, extraNote: '' };

/* ---------- kısaltma sözlüğü ---------- */
const GL = [
  ['KH', 'kalp hızı'], ['ABP', 'arteriyel kan basıncı'], ['MAP', 'ortalama arter basıncı'], ['SBP', 'sistolik kan basıncı'], ['DBP', 'diyastolik kan basıncı'],
  ['CVP', 'santral venöz basınç'], ['JVP', 'juguler venöz basınç'], ['PAP', 'pulmoner arter basıncı'], ['LAP', 'sol atriyum basıncı'], ['LVEDP', 'sol ventrikül diyastol sonu basıncı'],
  ['LVSP', 'sol ventrikül sistolik basıncı'], ['LVP', 'sol ventrikül basıncı'], ['CO', 'kalp debisi'], ['SV', 'atım hacmi'], ['EF', 'ejeksiyon fraksiyonu'],
  ['EDV', 'diyastol sonu hacim'], ['ESV', 'sistol sonu hacim'], ['TPR', 'toplam periferik direnç'], ['PVR', 'pulmoner damar direnci'], ['ICP', 'intrakraniyal (kafa içi) basınç'], ['İKB', 'intrakraniyal (kafa içi) basınç'],
  ['CPP', 'serebral perfüzyon basıncı'], ['SpO₂', 'periferik oksijen satürasyonu'], ['SaO₂', 'arteriyel oksijen satürasyonu'], ['SvO₂', 'karışık venöz oksijen satürasyonu'],
  ['PaO₂', 'arteriyel kandaki O₂ kısmi basıncı'], ['PaCO₂', 'arteriyel kandaki CO₂ kısmi basıncı'], ['PCO₂', 'CO₂ kısmi basıncı'], ['PO₂', 'O₂ kısmi basıncı'], ['VO₂', 'oksijen tüketimi'], ['CaO₂', 'arteriyel O₂ içeriği'], ['CvO₂', 'venöz O₂ içeriği'],
  ['RAAS', 'renin–anjiyotensin–aldosteron sistemi'], ['ADH', 'antidiüretik hormon (vazopressin)'], ['ANP', 'atriyal natriüretik peptid'], ['BNP', 'beyin (B tipi) natriüretik peptid'],
  ['Ang II', 'anjiyotensin II'], ['AngII', 'anjiyotensin II'], ['ACE', 'anjiyotensin dönüştürücü enzim'], ['AT₁', 'anjiyotensin II tip 1 reseptörü'],
  ['NTS', 'nucleus tractus solitarius (beyin sapında duyusal çekirdek)'], ['RVLM', 'rostral ventrolateral medulla (sempatik merkez)'], ['CVLM', 'kaudal ventrolateral medulla (RVLM\'yi baskılar)'],
  ['MSS', 'merkezi sinir sistemi'], ['SA', 'sinoatriyal (düğüm)'], ['AV', 'atriyoventriküler'], ['AP', 'aksiyon potansiyeli'], ['APD', 'aksiyon potansiyeli süresi'], ['ERP', 'efektif refrakter periyot'],
  ['EKG', 'elektrokardiyogram'], ['QRS', 'ventrikül depolarizasyonu dalgası'], ['QTc', 'kalp hızına göre düzeltilmiş QT'], ['QT', 'ventriküllerin depolarizasyon + repolarizasyon süresi'], ['PR', 'atriyumdan ventriküle ileti süresi'],
  ['ST', 'QRS sonu ile T başı arası segment'], ['LV', 'sol ventrikül'], ['RV', 'sağ ventrikül'], ['LA', 'sol atriyum'], ['RA', 'sağ atriyum'], ['MI', 'miyokard infarktüsü'],
  ['AF', 'atriyal fibrilasyon'], ['VT', 'ventriküler taşikardi'], ['VF', 'ventriküler fibrilasyon'], ['VES', 'ventriküler ekstrasistol'], ['LVH', 'sol ventrikül hipertrofisi'], ['RVH', 'sağ ventrikül hipertrofisi'],
  ['CICR', 'Ca²⁺ ile tetiklenen Ca²⁺ salınımı'], ['NO', 'nitrik oksit'], ['cGMP', 'siklik GMP'], ['cAMP', 'siklik AMP'], ['ACh', 'asetilkolin'], ['NA', 'noradrenalin'],
  ['M₂', 'muskarinik tip 2 reseptör'], ['β₁', 'beta-1 adrenerjik reseptör (kalp)'], ['β₂', 'beta-2 adrenerjik reseptör (damar, bronş)'], ['α₁', 'alfa-1 adrenerjik reseptör (damar daralması)'],
  ['E_K', 'K⁺ denge (Nernst) potansiyeli'], ['E_Na', 'Na⁺ denge (Nernst) potansiyeli'], ['NFB', 'net filtrasyon basıncı'], ['Pc', 'kapiller hidrostatik basınç'], ['πc', 'plazma onkotik basıncı'],
  ['πif', 'interstisyel onkotik basınç'], ['Pif', 'interstisyel hidrostatik basınç'], ['Kf', 'filtrasyon katsayısı'], ['Hct', 'hematokrit'], ['Re', 'Reynolds sayısı'],
  ['ESPVR', 'sistol sonu basınç–hacim ilişkisi'], ['EDPVR', 'diyastol sonu basınç–hacim ilişkisi'], ['KY', 'kalp yetersizliği'], ['HT', 'hipertansiyon'], ['HPV', 'hipoksik pulmoner vazokonstriksiyon'],
  ['S1', 'birinci kalp sesi (AV kapaklar kapanır)'], ['S2', 'ikinci kalp sesi (semilunar kapaklar kapanır)'], ['S3', 'üçüncü kalp sesi (hızlı dolum)'], ['S4', 'dördüncü kalp sesi (atriyum kasılması)'],
  ['A2', 'aort kapağı kapanma sesi'], ['P2', 'pulmoner kapak kapanma sesi'], ['IVC', 'izovolümetrik kasılma'], ['IVR', 'izovolümetrik gevşeme'], ['PV', 'basınç–hacim'],
  ['Iƒ', 'funny (HCN) akımı'], ['IK1', 'içe doğru düzeltici K⁺ akımı'], ['IKr', 'gecikmiş düzeltici K⁺ akımı (hızlı)'], ['IKs', 'gecikmiş düzeltici K⁺ akımı (yavaş)'], ['INa', 'hızlı Na⁺ akımı'], ['ICaL', 'L tipi Ca²⁺ akımı'],
  ['GHK', 'Goldman–Hodgkin–Katz'], ['RR', 'iki R dalgası arası süre'], ['ART', 'arteriyel basınç eğrisi'], ['PLETH', 'pletismografi (parmak nabız dalgası)'], ['ECF', 'hücre dışı sıvı'],
];
const LET = 'A-Za-zÇĞİÖŞÜçğıöşü0-9₀-₉²⁺⁻ƒ_';
const GLRE = new RegExp('(?<![' + LET + '])(' + GL.map(g => g[0]).sort((a, b) => b.length - a.length).map(k => k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|') + ')(?![' + LET + '])', 'g');
const GLMAP = Object.fromEntries(GL);
function mkX() {
  const seen = new Set();
  return (html) => String(html).split(/(<[^>]+>)/).map(seg => seg.startsWith('<') ? seg : seg.replace(GLRE, (m) => {
    if (seen.has(m)) return m; seen.add(m); return m + ' <span class="ab" style="color:var(--muted)">(' + GLMAP[m] + ')</span>';
  })).join('');
}
function abbrsIn(text) { const f = new Set(); let r; GLRE.lastIndex = 0; while ((r = GLRE.exec(text))) f.add(r[1]); return [...f]; }

/* ---------- ölçüm sözlüğü: kısa ad, açılım, birim, ondalık, eşik (+ mutlak, − göreli) ---------- */
const KM = {
  HR: ['KH', 'Kalp hızı', '/dk', 0, 3], SBP: ['SBP', 'Sistolik kan basıncı', 'mmHg', 0, 4], DBP: ['DBP', 'Diyastolik kan basıncı', 'mmHg', 0, 3], MAP: ['MAP', 'Ortalama arter basıncı', 'mmHg', 0, 3],
  CVP: ['CVP', 'Santral venöz basınç', 'mmHg', 1, 1], LAP: ['LAP', 'Sol atriyum basıncı', 'mmHg', 1, 1.5], PAs: ['PAP', 'Pulmoner arter sistolik basıncı', 'mmHg', 0, 3], PAd: ['PAPd', 'Pulmoner arter diyastolik basıncı', 'mmHg', 0, 3],
  CO: ['CO', 'Kalp debisi', 'L/dk', 1, 0.3], SV: ['SV', 'Atım hacmi', 'ml', 0, 5], EDV: ['EDV', 'Diyastol sonu hacim', 'ml', 0, 6], ESV: ['ESV', 'Sistol sonu hacim', 'ml', 0, 6], EF: ['EF', 'Ejeksiyon fraksiyonu', '%', 0, 3],
  LVEDP: ['LVEDP', 'Sol ventrikül diyastol sonu basıncı', 'mmHg', 0, 2], LVSP: ['LVSP', 'Sol ventrikül sistolik basıncı', 'mmHg', 0, 6],
  TPR: ['TPR', 'Toplam periferik direnç', 'mmHg·dk/L', 1, 1.0], SaO2: ['SpO₂', 'Oksijen satürasyonu', '%', 0, 1.5], PaO2: ['PaO₂', 'Arteriyel O₂ basıncı', 'mmHg', 0, 4],
  ICP: ['ICP', 'Kafa içi basınç', 'mmHg', 0, 3], CPP: ['CPP', 'Serebral perfüzyon basıncı', 'mmHg', 0, 4],
  PR: ['PR', 'PR aralığı', 'ms', 0, 15], QRS: ['QRS', 'QRS süresi', 'ms', 0, 8], QTc: ['QTc', 'Düzeltilmiş QT', 'ms', 0, 18], axis: ['Aks', 'QRS ekseni', '°', 0, 15],
  S: ['Sempatik', 'Sempatik aktivite', '%', 0, 6], V: ['Vagus', 'Parasempatik (vagus) aktivite', '%', 0, 6], baro: ['Baro', 'Baroreseptör deşarjı', '%', 0, 6],
  renin: ['Renin', 'Renin', '× normal', 2, -0.22], angII: ['Ang II', 'Anjiyotensin II', '× normal', 2, -0.22], aldo: ['Aldosteron', 'Aldosteron', '× normal', 2, -0.22], adh: ['ADH', 'ADH (vazopressin)', '× normal', 2, -0.22], anp: ['ANP', 'ANP', '× normal', 2, -0.22],
  BV: ['Kan volümü', 'Toplam kan hacmi', 'ml', 0, 60], Hct: ['Hct', 'Hematokrit', '%', 0, 2], visc: ['Viskozite', 'Kan viskozitesi (normale göre)', '×', 2, 0.05],
  Jsys: ['Filtrasyon', 'Kapillerden net sıvı filtrasyonu', 'ml/dk', 1, 0.8], Lsys: ['Lenf', 'Lenf akımı', 'ml/dk', 1, 0.8], PcA: ['Pc', 'Kapiller hidrostatik basınç', 'mmHg', 0, 2], piC: ['πc', 'Plazma onkotik basıncı', 'mmHg', 0, 1.5],
  dVi: ['Ödem', 'Dokularda biriken fazla sıvı (periferik ödem)', 'ml', 0, 150], dVlung: ['Akciğer sıvısı', 'Akciğer dokusundaki fazla sıvı', 'ml', 0, 40],
  vRest: ['Vm', 'Dinlenim zar potansiyeli', 'mV', 0, 2], naAvail: ['Na⁺ kanalı', 'Kullanılabilir hızlı Na⁺ kanalı', '%', 0, 5], apd: ['APD', 'Aksiyon potansiyeli süresi', 'ms', 0, 15],
  contr: ['Kontraktilite', 'Kasılma gücü (normale göre)', '×', 2, 0.05], urine: ['İdrar', 'Na⁺ ve su atılımı (normale göre)', '×', 2, -0.25],
  q_brain: ['Beyin', 'Beyin kan akımı', 'ml/dk', 0, -0.07], q_cor: ['Koroner', 'Koroner kan akımı', 'ml/dk', 0, -0.08], q_kidney: ['Böbrek', 'Böbrek kan akımı', 'ml/dk', 0, -0.08],
  q_muscle: ['Kas', 'İskelet kası kan akımı', 'ml/dk', 0, -0.1], q_skin: ['Deri', 'Deri kan akımı', 'ml/dk', 0, -0.1], q_splanch: ['Splanknik', 'Sindirim organları kan akımı', 'ml/dk', 0, -0.1],
  RR: ['Solunum', 'Solunum sayısı', '/dk', 0, 2], isch: ['İskemi', 'Koroner iskemi göstergesi', '%', 0, 15], epi: ['Adrenalin', 'Dolaşan adrenalin', '×', 2, 0.1], chemo: ['Kemo', 'Kemoreseptör uyarısı', '', 2, 0.1],
};
function chg(k, a, b) { const m = KM[k]; if (!m || a == null || b == null || !isFinite(a) || !isFinite(b)) return false; const t = m[4]; return t < 0 ? Math.abs(b - a) > Math.abs(a) * -t + 1e-9 : Math.abs(b - a) >= t; }
function fv(k, v) { const m = KM[k]; return fmt(v, m ? m[3] : 0); }
function arrow(a, b) { return b > a ? '↑' : '↓'; }
function mline(k, a, b) { const m = KM[k]; const cls = b > a ? 'up' : 'dn'; const skip = GLMAP[m[0]] || m[1].toLowerCase().startsWith(m[0].toLowerCase()); return `<b>${m[0]}</b>${skip ? '' : ' (' + m[1].toLowerCase() + ')'}: ${fv(k, a)} → <b class="${cls}">${fv(k, b)}</b> ${m[2]} <b class="${cls}">${arrow(a, b)}</b>`; }
function rtab(keys, P, Q, onlyChanged) {
  const rows = keys.filter(k => !onlyChanged || chg(k, P[k], Q[k]));
  if (!rows.length) return '';
  return `<table class="rtab"><tbody>${rows.map(k => { const c = chg(k, P[k], Q[k]); const cls = !c ? '' : Q[k] > P[k] ? 'up' : 'dn'; return `<tr><td>${KM[k][1]} <span class="note">(${KM[k][0]})</span></td><td class="n">${fv(k, P[k])}</td><td class="n">→</td><td class="n ${cls}">${fv(k, Q[k])} ${c ? arrow(P[k], Q[k]) : ''}</td><td class="note">${KM[k][2]}</td></tr>`; }).join('')}</tbody></table>`;
}

/* ---------- basit kontroller ---------- */
const L5 = (a, b, c, d, e2, u) => [['Çok düşük', a], ['Düşük', b], ['Normal', c], ['Yüksek', d], ['Çok yüksek', e2]].map(x => x.concat(u || ''));
const SC = [
  { s: 'Kan ve sıvılar' },
  { id: 'bv', t: 'Kan volümü', h: 'Dolaşımdaki toplam kan (normal ≈ 5 L). Azaltmak = kanama, artırmak = sıvı/kan yüklemesi.', kind: 'bv', ref: 'B10.3, B10.10',
    lv: [['Ağır kanama', -1000, '−1 L'], ['Kanama', -500, '−500 ml'], ['Normal', 0, '5 L'], ['Fazla', 500, '+500 ml'], ['Çok fazla', 1000, '+1 L']] },
  { id: 'hct', t: 'Kan viskozitesi (hematokrit)', h: 'Kandaki eritrosit oranı. Düşük = anemi (akışkan kan), yüksek = polisitemi (koyu kan).', p: 'hct', ref: 'B7.8',
    lv: [['Ağır anemi', 22, '%22'], ['Anemi', 32, '%32'], ['Normal', 42, '%42'], ['Yüksek', 54, '%54'], ['Polisitemi', 64, '%64']] },
  { id: 'alb', t: 'Plazma proteini (albümin)', h: 'Kanın suyu damarda tutma gücü (onkotik basınç). Düşerse sıvı dokuya kaçar.', p: 'albumin', long: true, ref: 'B9.3, B9.6',
    lv: [['Çok düşük', 1.5, '1,5 g/dL'], ['Düşük', 2.5, '2,5'], ['Normal', 4.2, '4,2'], ['Yüksek', 5.2, '5,2']] },
  { id: 'salt', t: 'Tuz ve su alımı', h: 'Günlük tuz/su alımı. Etkisi böbrek üzerinden günler içinde görülür.', p: 'salt', long: true, ref: 'B10.8',
    lv: [['Çok az', 0.3, '×0,3'], ['Az', 0.6, '×0,6'], ['Normal', 1, '×1'], ['Fazla', 2, '×2'], ['Çok fazla', 3, '×3']] },
  { s: 'Kalp ve damarlar' },
  { id: 'contr', t: 'Kalbin kasılma gücü (kontraktilite)', h: 'Kalp kasının ne kadar güçlü sıkıştığı (inotropi).', p: 'contractility', ref: 'B6.3',
    lv: [['Çok zayıf', 0.45, '×0,45'], ['Zayıf', 0.7, '×0,7'], ['Normal', 1, '×1'], ['Güçlü', 1.35, '×1,35'], ['Çok güçlü', 1.7, '×1,7']] },
  { id: 'pre', t: 'Ön yük (preload) – venöz dönüş', h: 'Venlerin tonusu: venler daralırsa kalbe dönen kan ve dolum (EDV) artar.', p: 'venTone', ref: 'B6.5, B8.6',
    lv: [['Çok düşük', -0.5, ''], ['Düşük', -0.25, ''], ['Normal', 0, ''], ['Yüksek', 0.25, ''], ['Çok yüksek', 0.5, '']] },
  { id: 'aft', t: 'Art yük (afterload) – damar direnci, kan basıncı', h: 'Arteriyollerin çapı. Daralırsa direnç ve kan basıncı artar; genişlerse azalır.', p: 'rAll', ref: 'B7.7, B10.1',
    lv: [['Çok geniş', 1.15, 'r ×1,15'], ['Geniş', 1.07, 'r ×1,07'], ['Normal', 1, 'r ×1'], ['Dar', 0.93, 'r ×0,93'], ['Çok dar', 0.86, 'r ×0,86']] },
  { id: 'valve', t: 'Kalp kapağı', h: 'Orta–ağır kapak hastalığı ekle.', kind: 'obj', ref: 'B5.5',
    lv: [['Sağlam', { AS: 0, AR: 0, MS: 0, MR: 0 }, ''], ['Aort darlığı', { AS: 0.75, AR: 0, MS: 0, MR: 0 }, 'AS'], ['Aort yetersizliği', { AS: 0, AR: 0.7, MS: 0, MR: 0 }, 'AR'], ['Mitral darlığı', { AS: 0, AR: 0, MS: 0.75, MR: 0 }, 'MS'], ['Mitral yetersizliği', { AS: 0, AR: 0, MS: 0, MR: 0.7 }, 'MR']], norm: 0 },
  { id: 'rhy', t: 'Kalp ritmi', h: 'Elektriksel ritim bozukluğu seç.', kind: 'obj', ref: 'B3.6',
    lv: [['Sinüs (normal)', { rhythm: 'sinus', avBlock: '0' }, ''], ['Atriyal fibrilasyon', { rhythm: 'af', avBlock: '0' }, 'AF'], ['1. derece AV blok', { rhythm: 'sinus', avBlock: '1' }, ''], ['3. derece AV blok', { rhythm: 'sinus', avBlock: '3' }, 'komplet'], ['Ventriküler taşikardi', { rhythm: 'vt', avBlock: '0' }, 'VT']], norm: 0 },
  { id: 'mi', t: 'Kalp krizi (miyokard infarktüsü)', h: 'Koroner tıkanması sonucu kalp kasının bir bölümü kasılamaz.', p: 'mi', ref: 'B8.12',
    lv: [['Yok', '0', ''], ['İnferior MI', 'inf', 'alt duvar'], ['Anterior MI', 'ant', 'ön duvar']], norm: 0 },
  { s: 'Sinir sistemi ve vücut' },
  { id: 'symp', t: 'Sempatik sinir sistemi', h: 'Dışarıdan ek sempatik uyarı (stres, ağrı) ya da baskılama.', p: 'sympOffset', ref: 'B2.2',
    lv: [['Çok az', -0.4, ''], ['Az', -0.2, ''], ['Normal', 0, ''], ['Fazla', 0.2, ''], ['Çok fazla', 0.4, '']] },
  { id: 'vag', t: 'Parasempatik (vagus) sinir', h: 'Vagusun kalbe etkisi: artarsa kalp yavaşlar.', p: 'vagOffset', ref: 'B2.2',
    lv: [['Çok az', -0.4, ''], ['Az', -0.2, ''], ['Normal', 0, ''], ['Fazla', 0.2, ''], ['Çok fazla', 0.4, '']] },
  { id: 'baro', t: 'Baroreseptör refleksi', h: 'Kapatırsan basınç değişiklikleri sinir sistemiyle düzeltilmez.', p: 'baroOn', ref: 'B10.3',
    lv: [['Açık', true, ''], ['Kapalı', false, 'denervasyon']], norm: 0 },
  { id: 'ex', t: 'Egzersiz', h: 'Kas çalışması: kas damarları genişler, sempatik artar.', p: 'exercise', ref: 'B6.2, B8.9',
    lv: [['Dinlenme', 0, ''], ['Hafif', 0.25, ''], ['Orta', 0.5, ''], ['Ağır', 0.85, '']], norm: 0 },
  { id: 'pos', t: 'Vücut pozisyonu', h: 'Ayağa kalkınca kan bacaklarda göllenir.', p: 'posture', ref: 'B10.3',
    lv: [['Yatıyor', 'supine', ''], ['Ayakta', 'standing', '']], norm: 0 },
  { id: 'temp', t: 'Vücut sıcaklığı', h: 'Ateş kalbi hızlandırır, deri damarlarını genişletir.', p: 'temp', ref: 'B6.2',
    lv: [['Hipotermi', 35, '35 °C'], ['Normal', 37, '37 °C'], ['Ateş', 39, '39 °C'], ['Yüksek ateş', 40.5, '40,5 °C']], norm: 1 },
  { s: 'İyonlar (elektrolitler)' },
  { id: 'K', t: 'Potasyum (K⁺)', h: 'Dinlenim zar potansiyelini belirler: EKG\'de T dalgası, QRS.', p: 'K', ref: 'B1.6', lv: L5(2.6, 3.2, 4, 6.5, 8, '').map((x, i) => [x[0], x[1], fmt(x[1], 1) + ' mEq/L']) },
  { id: 'Na', t: 'Sodyum (Na⁺)', h: 'Aksiyon potansiyelinin faz 0\'ı ve vücut sıvı dengesi.', p: 'Na', ref: 'B1.6', lv: L5(120, 130, 142, 152, 162).map(x => [x[0], x[1], x[1] + '']) },
  { id: 'Ca', t: 'Kalsiyum (Ca²⁺)', h: 'Plato fazı ve kasılma gücü.', p: 'Ca', ref: 'B1.5, B1.6', lv: L5(1.5, 1.9, 2.4, 3.0, 3.6).map(x => [x[0], x[1], fmt(x[1], 1)]) },
  { s: 'İlaçlar (aç/kapat)', drugs: true },
  { id: 'd_na', t: 'Na⁺ kanal blokeri', p: 'naBlock', drug: 1, ref: 'B1.7' }, { id: 'd_k', t: 'K⁺ kanal blokeri', p: 'kBlock', drug: 1, ref: 'B1.7' },
  { id: 'd_ver', t: 'Ca²⁺ kanal blokeri (kalp – verapamil)', p: 'verapamil', drug: 1, ref: 'B1.7' }, { id: 'd_nif', t: 'Ca²⁺ kanal blokeri (damar – nifedipin)', p: 'nifedipine', drug: 1, ref: 'B1.7' },
  { id: 'd_bb', t: 'β-bloker', p: 'betaBlock', drug: 1, ref: 'B1.7' }, { id: 'd_atr', t: 'Atropin', p: 'atropine', drug: 1, ref: 'B2.2' },
  { id: 'd_adr', t: 'Adrenalin', p: 'adrenaline', drug: 1, ref: 'B8.10' }, { id: 'd_nor', t: 'Noradrenalin', p: 'noradrenaline', drug: 1, ref: 'B10.7' },
  { id: 'd_nit', t: 'Nitrat', p: 'nitrate', drug: 1, ref: 'B8.9' }, { id: 'd_dig', t: 'Digoksin', p: 'digoxin', drug: 1, ref: 'B1.7' },
  { id: 'd_diu', t: 'Diüretik', p: 'diuretic', drug: 1, long: true, ref: 'B10.9' }, { id: 'd_ace', t: 'ACE inhibitörü', p: 'acei', drug: 1, long: true, ref: 'B10.9' },
  { s: 'Solunum, beyin, kapiller' },
  { id: 'o2', t: 'Oksijen (hipoksi)', h: 'Arteriyel O₂ basıncı: yükseklik, solunum yetmezliği.', p: 'PaO2', ref: 'B10.4',
    lv: [['Normal', 95, '95 mmHg'], ['Hafif hipoksi', 70, '70'], ['Orta', 52, '52'], ['Ağır', 40, '40']], norm: 0 },
  { id: 'co2', t: 'Karbondioksit (CO₂)', h: 'Hipoventilasyonda yükselir, hiperventilasyonda düşer.', p: 'PaCO2', ref: 'B8.11',
    lv: [['Çok düşük', 25, '25'], ['Düşük', 32, '32'], ['Normal', 40, '40'], ['Yüksek', 55, '55'], ['Çok yüksek', 70, '70 mmHg']] },
  { id: 'icp', t: 'Kafa içi basıncı', h: 'Beyin kitlesi/ödemi. Çok artarsa Cushing refleksi.', p: 'ICP', ref: 'B10.5',
    lv: [['Normal', 10, '10 mmHg'], ['Yüksek', 25, '25'], ['Çok yüksek', 40, '40'], ['Kritik', 55, '55']], norm: 0 },
  { id: 'perm', t: 'Kapiller geçirgenlik', h: 'İnflamasyon, yanık, sepsiste artar → protein ve sıvı kaçar.', p: 'perm', long: true, ref: 'B9.6',
    lv: [['Normal', 1, '×1'], ['Artmış', 2, '×2'], ['Çok artmış', 3.5, '×3,5']], norm: 0 },
  { id: 'lym', t: 'Lenf drenajı', h: 'Fazla doku sıvısını geri taşır. Tıkanırsa lenfödem.', p: 'lymph', long: true, ref: 'B9.5',
    lv: [['Normal', 1, ''], ['Azalmış', 0.35, ''], ['Tıkalı', 0.08, '']], norm: 0 },
  { id: 'vex', t: 'Venöz tıkanma (ek venöz basınç)', h: 'Gebelik, ven basısı, sağ kalp yetersizliği.', p: 'venExtra', long: true, ref: 'B9.6',
    lv: [['Yok', 0, ''], ['Orta', 8, '+8 mmHg'], ['Ağır', 16, '+16 mmHg']], norm: 0 },
];
SC.forEach(c => { if (c.drug) { c.lv = [['Yok', 0, ''], ['Var', 0.7, '']]; c.norm = 0; } if (c.lv && c.norm == null) c.norm = c.lv.findIndex(x => x[0] === 'Normal'); });
const SCL = SC.filter(c => c.id);
function lvVal(c, i) { return c.lv[i][1]; }
function applyLevel(e, c, i) {
  if (c.kind === 'bv') return;
  const v = lvVal(c, i);
  if (c.kind === 'obj') { for (const k in v) e.set(k, v[k]); return; }
  e.set(c.p, v);
}
function detectLevel(p, c) {
  if (c.kind === 'bv') return 2;
  for (let i = 0; i < c.lv.length; i++) {
    const v = c.lv[i][1];
    if (c.kind === 'obj') { if (Object.keys(v).every(k => p[k] === v[k])) return i; }
    else if (typeof v === 'number' ? Math.abs(p[c.p] - v) < 1e-6 : p[c.p] === v) return i;
  }
  return -1;
}

function buildSControls() {
  const host = $('scontrols');
  let h = `<div class="scs"><div class="scs-top"><b>Basit kontroller</b><button class="reset-g" id="sReset">Hepsini normale döndür</button></div>
    <div class="note" style="padding:0 4px">Bir düğmeye bas: vücudun yanıtı hesaplanır, değerler yeni dengeye yavaşça gelir ve orada sabit kalır.</div>`;
  let inDrugs = false;
  SC.forEach(c => {
    if (c.s) { if (inDrugs) h += '</div></div>'; h += `<div class="sc-sec"><h3>${c.s}</h3>`; inDrugs = !!c.drugs; if (inDrugs) h += '<div class="sc"><div class="h">Etkisini görmek istediğin ilacı aç. Birden fazla seçebilirsin.</div><div class="chips">'; else h += ''; return; }
    if (c.drug) { h += `<button class="chip" id="sc_${c.id}" aria-pressed="false">${c.t}</button>`; return; }
    h += `<div class="sc" id="scw_${c.id}"><div class="t">${c.t}<span class="ref">${c.ref}</span></div>${c.h ? `<div class="h">${c.h}</div>` : ''}<div class="lvs" role="group" aria-label="${c.t}">${c.lv.map((l, i) => `<button class="lv ${i === c.norm ? 'norm' : ''}" data-c="${c.id}" data-i="${i}" aria-pressed="false">${l[0]}${l[2] ? `<small>${l[2]}</small>` : ''}</button>`).join('')}</div></div>`;
  });
  h += '</div></div></div>';
  host.innerHTML = h;
  host.querySelectorAll('.lv').forEach(b => b.addEventListener('click', () => sSet(b.dataset.c, +b.dataset.i)));
  SCL.filter(c => c.drug).forEach(c => $('sc_' + c.id).addEventListener('click', () => sSet(c.id, STU.target[c.id] === 1 ? 0 : 1)));
  $('sReset').addEventListener('click', () => { SCL.forEach(c => { STU.target[c.id] = c.norm; }); STU.bvT = 0; startJob({ title: 'Her şey normale döndürüldü', baseEng: STU.normalEng.clone(), mutate: () => {} }); paintSC(); });
}
function paintSC() {
  SCL.forEach(c => {
    const t = STU.target[c.id];
    if (c.drug) { const b = $('sc_' + c.id); b.setAttribute('aria-pressed', t === 1); return; }
    const w = $('scw_' + c.id); if (!w) return;
    w.querySelectorAll('.lv').forEach(b => b.setAttribute('aria-pressed', +b.dataset.i === t));
    w.classList.toggle('dev', t !== c.norm);
  });
}
function sSet(id, i) {
  const c = SCL.find(x => x.id === id); if (!c) return;
  if (caseState && !caseState.revealed) return;
  if (STU.target[id] === i) return;
  STU.target[id] = i;
  if (c.kind === 'bv') STU.bvT = lvVal(c, i);
  paintSC();
  startJob({});
}

/* ---------- iş (aşamalı hesap) ---------- */
function pendingChanges() {
  const out = [];
  SCL.forEach(c => {
    const a = STU.applied[c.id], b = STU.target[c.id];
    if (a !== b && b != null && b >= 0) out.push({ c, from: a, to: b });
  });
  return out;
}
function startJob(opt) {
  opt = opt || {};
  if (STU.job) STU.job.dead = true;
  const changes = opt.preset ? [] : pendingChanges();
  const bvD = STU.bvT - STU.bvA;
  const base = opt.baseEng || STU.base, P0 = opt.P0 || STU.cur;
  const long = !!opt.onlyC || !!opt.long || changes.some(x => x.c.long);
  const mutate = opt.mutate || ((e) => {
    changes.forEach(x => applyLevel(e, x.c, x.to));
    if (bvD) e.instantVolume(bvD);
  });
  if (!changes.length && !bvD && !opt.mutate && !opt.onlyC && !opt.title) { return; }
  const job = { dead: false, P0, changes, long, onlyC: !!opt.onlyC, gen: ST.plan(base, mutate, { long, onlyC: !!opt.onlyC }), queue: [], done: false, snaps: {},
    silent: !!opt.silent || !!(caseState && !caseState.revealed), title: opt.title, preset: opt.preset, nextAt: 0, stage: 'start', chips: [] };
  STU.job = job;
  if (!job.silent) newEntry(job); else job.entry = null;
  if (!job.silent) addSteps(job, causeSteps(job));
  sBanner();
  const pump = () => {
    if (job.dead) return;
    const t0 = performance.now();
    let r;
    do { r = job.gen.next(); if (r.done) { job.done = true; break; } if (r.value.snap) job.queue.push(r.value); else job.prog = r.value; } while (performance.now() - t0 < 25 && !r.value.snap);
    sBanner();
    if (!job.done) setTimeout(pump, 0);
  };
  setTimeout(pump, 10);
}
const STAGE_DUR = { A: 1700, B: 2600, C: 2600 };
function tickJob(now) {
  const job = STU.job; if (!job || job.dead) return;
  if (job.queue.length && now >= job.nextAt) {
    const it = job.queue.shift();
    job.snaps[it.stage] = it.snap;
    eng = it.eng; audioReset();
    tweenTo(it.snap, STAGE_DUR[it.stage]);
    job.stage = it.stage;
    if (!job.silent) {
      if (it.stage === 'A') addSteps(job, stepsA(job));
      if (it.stage === 'B') addSteps(job, stepsB(job));
      if (it.stage === 'C') addSteps(job, stepsC(job));
    }
    markTabs(job.P0, it.snap, job);
    job.nextAt = now + STAGE_DUR[it.stage] + 700;
    sBanner();
  }
  if (job.done && !job.queue.length && now >= job.nextAt && !job.finished) {
    job.finished = true;
    const last = job.snaps.C || job.snaps.B;
    STU.base = eng; STU.cur = last;
    SCL.forEach(c => { STU.applied[c.id] = STU.target[c.id]; });
    STU.bvA = STU.bvT;
    STU.lastResult = { P0: job.P0, R: last, job };
    if (!job.silent) addSteps(job, resultSteps(job));
    STU.job = null;
    sBanner();
  }
}

/* ---------- görüntülenen değerler ---------- */
function tweenTo(snap, dur) {
  const from = {}; for (const k in snap) from[k] = STU.disp[k] != null ? STU.disp[k] : snap[k];
  STU.tw = { from, to: snap, t0: performance.now(), dur };
}
function tickTween(now) {
  const tw = STU.tw; if (!tw) return;
  let x = clamp((now - tw.t0) / tw.dur, 0, 1); x = x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
  for (const k in tw.to) STU.disp[k] = tw.from[k] + (tw.to[k] - tw.from[k]) * x;
  if (x >= 1) STU.tw = null;
}
const TILEK = { hr: ['HR'], abp: ['SBP', 'DBP', 'MAP'], cvp: ['CVP'], pap: ['PAs', 'PAd'], spo: ['SaO2'], co: ['CO'], sv: ['SV', 'EF'], tpr: ['TPR'], cpp: ['ICP', 'CPP'], rr: ['RR'] };
function updNumsStudent() {
  const d = STU.disp, P = (STU.lastResult && !STU.job) ? STU.lastResult.P0 : (STU.job ? STU.job.P0 : null);
  if (!d.HR && d.HR !== 0) return;
  const set = (id, h) => { $('nv_' + id).innerHTML = h; };
  set('hr', fmt(d.HR)); set('abp', `${fmt(d.SBP)}/${fmt(d.DBP)} <small>(${fmt(d.MAP)})</small>`); set('cvp', fmt(d.CVP, 1)); set('pap', `${fmt(d.PAs)}/${fmt(d.PAd)}`);
  set('spo', fmt(d.SaO2)); set('co', fmt(d.CO, 1)); set('sv', `${fmt(d.SV)} <small>ml · %${fmt(d.EF)}</small>`); set('tpr', fmt(d.TPR, 1));
  set('cpp', `${fmt(d.ICP)} <small>· ${fmt(d.CPP)}</small>`); set('rr', `${fmt(d.RR)} <small>· ${fmt(eng.p.temp, 1)}°</small>`);
  for (const id in TILEK) {
    const el = $('n_' + id), dl = $('nd_' + id); if (!el || !dl) continue;
    const ks = TILEK[id]; const changed = P && ks.some(k => chg(k, P[k], d[k]));
    el.classList.toggle('chg', !!changed);
    el.classList.toggle('alarm', (id === 'abp' && d.MAP < 60) || (id === 'spo' && d.SaO2 < 88) || (id === 'hr' && (d.HR < 45 || d.HR > 140)) || (id === 'cpp' && d.CPP < 50));
    if (changed) { const k = ks[ks.length === 3 ? 2 : 0]; const up = d[k] > P[k]; dl.innerHTML = `önce ${fv(k, P[k])} <span class="${up ? 'u' : 'd'}">${up ? '↑' : '↓'}</span>`; }
    else dl.textContent = '';
  }
}

/* ---------- sekme işaretleri ---------- */
const TAB_KEYS = {
  cell: ['vRest', 'naAvail', 'apd', 'HR'], ecg: ['HR', 'PR', 'QRS', 'QTc', 'axis'], cycle: ['EDV', 'ESV', 'SV', 'EF', 'LVEDP', 'LVSP', 'LAP'],
  vessels: ['MAP', 'CO', 'TPR', 'visc', 'q_brain', 'q_cor', 'q_kidney', 'q_muscle', 'q_skin', 'q_splanch'], cap: ['PcA', 'piC', 'Jsys', 'Lsys', 'dVi', 'dVlung'],
  reflex: ['S', 'V', 'baro', 'renin', 'angII', 'aldo', 'adh', 'anp'], formula: [],
};
function tabChanged(id, P, Q, job) {
  if (id === 'formula') return false;
  const keys = TAB_KEYS[id].filter(k => !(id === 'cell' && k === 'HR'));
  let c = keys.some(k => chg(k, P[k], Q[k]));
  if (id === 'cell' && Math.abs(Q.HR - P.HR) >= 10) c = true;
  if (job && job.changes.some(x => ['rhy', 'mi'].includes(x.c.id)) && (id === 'ecg' || id === 'cycle')) c = true;
  if (job && job.changes.some(x => x.c.id === 'valve') && id === 'cycle') c = true;
  if (job && job.changes.some(x => ['K', 'Na', 'Ca', 'd_na', 'd_k', 'd_ver', 'd_dig'].includes(x.c.id)) && (id === 'cell' || id === 'ecg')) c = true;
  return c;
}
function markTabs(P, Q, job) {
  if (!P || !Q || (job && job.silent)) return;
  TABS.forEach(t => { if (tabChanged(t.id, P, Q, job) && !(job && job.silent && false)) STU.tabChg[t.id] = { P, Q }; });
  paintTabs();
}
function paintTabs() {
  TABS.forEach(t => { const b = $('tab_' + t.id); if (b) b.classList.toggle('chg', STU.on && !!STU.tabChg[t.id] && !(caseState && !caseState.revealed && false)); });
  renderStrip(activeTab);
}
function onTabVisit(id) {
  if (!STU.on) return;
  renderStrip(id);
  const b = $('tab_' + id); if (b) b.classList.remove('chg');
  // görüldü: çerçeveyi kaldır ama şerit kalsın
  if (STU.tabChg[id]) STU.tabChg[id].seen = true;
  setTimeout(() => { TABS.forEach(t => { const bb = $('tab_' + t.id); if (bb) bb.classList.toggle('chg', STU.on && !!STU.tabChg[t.id] && !STU.tabChg[t.id].seen); }); }, 0);
}
function renderStrip(id) {
  const el = $('ss_' + id); if (!el) return;
  const pane = $('pane_' + id);
  const tc = STU.tabChg[id];
  let h = '';
  if (tc) {
    const ks = TAB_KEYS[id].filter(k => chg(k, tc.P[k], tc.Q[k]));
    if (ks.length) h += `<h4>Bu sekmede değişenler (önce → sonra)</h4><div class="rows">${ks.map(k => { const up = tc.Q[k] > tc.P[k]; return `<span class="dchip ${up ? 'up' : 'dn'}" title="${KM[k][1]}">${KM[k][1]}: ${fv(k, tc.P[k])} → ${fv(k, tc.Q[k])} ${KM[k][2]} ${up ? '↑' : '↓'}</span>`; }).join('')}</div>`;
    else h += `<h4>Bu sekmede şekil/ritim değişti</h4><div class="note">Grafiklere bak; sayısal değerler büyük ölçüde aynı.</div>`;
  }
  // kısaltmalar
  const clone = pane.cloneNode(true); const s = clone.querySelector('.sstrip'); if (s) s.remove();
  const ab = abbrsIn(clone.textContent).filter(a => GLMAP[a]);
  if (ab.length) h += `<details ${tc ? '' : 'open'}><summary>Bu sekmedeki kısaltmalar (${ab.length})</summary><div class="gl">${ab.map(a => `<div><b>${a}</b> = ${GLMAP[a]}</div>`).join('')}</div></details>`;
  el.innerHTML = h;
}

/* ---------- konsol ---------- */
function newEntry(job) {
  const body = $('conBody');
  body.querySelectorAll('.centry').forEach(x => x.classList.add('old'));
  const n = ++STU.entryN;
  const div = document.createElement('div'); div.className = 'centry';
  const title = job.title || (job.preset ? 'Senaryo: ' + job.preset.n : job.changes.map(x => x.c.t).join(' + ') || 'Kan volümü');
  div.innerHTML = `<div class="ch">#${n} · ${title}<span class="tm">${new Date().toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })}</span></div><div class="csteps"></div><div class="cmore"></div>`;
  body.prepend(div);
  while (body.children.length > 12) body.lastChild.remove();
  job.entry = div; job.stepN = 0; job.X = mkX(); job.revealQ = []; job.revealAt = 0;
}
function addSteps(job, steps) { if (!job.entry) return; steps.forEach(s => job.revealQ.push(s)); }
function tickReveal(now) {
  const job = STU.job || (STU.lastResult && STU.lastResult.job);
  if (!job || !job.entry || !job.revealQ || !job.revealQ.length || now < job.revealAt) return;
  const s = job.revealQ.shift();
  job.revealAt = now + 420;
  const d = document.createElement('div');
  d.className = 'cst ' + (s.kind || '');
  const no = s.kind === 'ph' ? '⏱' : s.kind === 'res' ? '✓' : s.kind === 'cause' ? '✎' : String(++job.stepN);
  const tabs = (s.tabs || []).map(id => { const t = TABS.find(x => x.id === id); return t ? `<button class="tabgo" data-tab="${id}">${t.n} sekmesine bak ›</button>` : ''; }).join(' ');
  d.innerHTML = `<div class="no">${no}</div><div><div class="tt">${job.X(s.title)}</div><div class="tx">${job.X(s.html || '')}</div>${tabs}</div>`;
  d.querySelectorAll('.tabgo').forEach(b => b.addEventListener('click', () => { const tb = $('tab_' + b.dataset.tab); if (tb) { tb.click(); tb.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); } }));
  job.entry.querySelector('.csteps').appendChild(d);
}
const ARW = '<span class="ar">→</span>';
function chainHtml(c) { return c && c.length ? c.map((x, i) => (i ? ARW + ' ' : '') + x).join('<br>') : ''; }
function levelLabel(c, i) { if (i == null || i < 0) return 'özel'; return c.lv[i][0] + (c.lv[i][2] ? ' (' + c.lv[i][2] + ')' : ''); }
function causeSteps(job) {
  const out = [];
  if (job.preset) {
    const p = job.preset; const ch = [];
    if (p.set) for (const k in p.set) { const f = D.WHY[k]; if (f) { try { const w = f(E.DEFAULTS[k], p.set[k], eng); if (w && w.c) ch.push(`<b>${w.t}</b><br>` + chainHtml(w.c)); } catch (e) {} } }
    out.push({ kind: 'cause', title: 'Senaryo: ' + p.n, html: (p.note ? p.note + '<br>' : '') + ch.join('<br><br>') });
    return out;
  }
  if (job.onlyC) { out.push({ kind: 'cause', title: 'Zamanı ileri sardın: günler sonra ne olur?', html: 'Hormonlar (aldosteron, ADH, ANP) ve böbrek Na⁺/su dengesi yavaş çalışır. Şimdi bu yavaş mekanizmaların sonucunu görüyoruz.' }); return out; }
  if (job.title && !job.changes.length && !(STU.bvT - STU.bvA)) { out.push({ kind: 'cause', title: job.title, html: 'Tüm etkenler normal değerlerine döndürüldü; vücut normal dengesine dönüyor.' }); }
  job.changes.forEach(x => {
    const c = x.c, a = x.from, b = x.to;
    let ttl = `Değiştirdin: ${c.t} — ${levelLabel(c, a)} → ${levelLabel(c, b)}`;
    let html = '';
    if (c.kind === 'bv') {
      const dv = lvVal(c, b) - (a != null && a >= 0 ? lvVal(c, a) : 0);
      html = dv < 0 ? chainHtml([`Dolaşımdan ${fmt(-dv)} ml kan çıktı (kanama)`, 'venlerdeki kan azalır → venöz dönüş (kalbe dönen kan) azalır', 'kalbin dolumu (ön yük, EDV) azalır', 'Frank–Starling yasası: daha az gerilen kalp daha az kan atar → SV ve CO azalır', 'MAP = CO × TPR → kan basıncı düşer'])
        : chainHtml([`Dolaşıma ${fmt(dv)} ml kan/sıvı eklendi`, 'venöz dönüş ve kalbin dolumu (EDV) artar', 'Frank–Starling: kalp daha çok gerilir → SV ve CO artar', 'MAP = CO × TPR → kan basıncı yükselir', 'atriyumlar gerilir']);
    } else if (c.id === 'aft') {
      const up = lvVal(c, b) < (a != null && a >= 0 ? lvVal(c, a) : 1);
      html = up ? chainHtml(['Arteriyoller daraldı (yarıçap küçüldü)', 'Poiseuille: direnç yarıçapın 4. kuvvetiyle ters orantılı (R ∝ 1/r⁴) → küçük daralma büyük direnç artışı', 'TPR ↑ → sol ventrikülün art yükü ↑', 'MAP = CO × TPR → kan basıncı ↑'])
        : chainHtml(['Arteriyoller genişledi (yarıçap büyüdü)', 'R ∝ 1/r⁴ → direnç belirgin azalır', 'TPR ↓ → art yük ↓', 'MAP = CO × TPR → kan basıncı ↓']);
    } else if (c.kind === 'obj') {
      const v = lvVal(c, b);
      for (const k in v) { const old = eng.p[k]; const f = D.WHY[k]; if (f && v[k] !== (a != null && a >= 0 ? lvVal(c, a)[k] : old)) { try { const w = f(a != null && a >= 0 ? lvVal(c, a)[k] : old, v[k], eng); if (w && w.c && w.c.length) html += `<b>${w.t}</b><br>${chainHtml(w.c)}<br>`; } catch (e) {} } }
      if (!html) html = 'Normal yapıya dönüldü.';
    } else {
      const f = D.WHY[c.p];
      const av = a != null && a >= 0 ? lvVal(c, a) : E.DEFAULTS[c.p], bv = lvVal(c, b);
      if (f) { try { const w = f(av, bv, eng); if (w && w.c) html = `<b>${w.t}</b><br>${chainHtml(w.c)}`; } catch (e) {} }
    }
    if (c.long) html += '<br><i>Bu etken asıl sonucunu saatler–günler içinde gösterir; hesap “günler sonra” aşamasını da içerecek.</i>';
    out.push({ kind: 'cause', title: ttl, html });
  });
  if (!job.changes.some(x => x.c.kind === 'bv') && (STU.bvT - STU.bvA)) out.push({ kind: 'cause', title: 'Kan volümü değişti', html: `${fmt(STU.bvT - STU.bvA)} ml` });
  return out;
}
const KEYS_A = ['MAP', 'SBP', 'DBP', 'CO', 'SV', 'EDV', 'CVP', 'LAP', 'HR', 'TPR', 'SaO2', 'CPP', 'PR', 'QRS', 'QTc', 'Jsys'];
function stepsA(job) {
  const P = job.P0, A = job.snaps.A, out = [];
  if (job.onlyC) return out;
  const ls = KEYS_A.filter(k => chg(k, P[k], A[k])).map(k => mline(k, P[k], A[k]));
  let html = ls.length ? '<ul>' + ls.map(x => `<li>${x}</li>`).join('') + '</ul>' : 'Dolaşım değerlerinde ilk anda belirgin bir değişiklik yok.';
  const notes = [];
  if (chg('EDV', P.EDV, A.EDV) && chg('SV', P.SV, A.SV) && (A.EDV - P.EDV) * (A.SV - P.SV) > 0) notes.push(`Frank–Starling: kalbin dolumu (EDV) ${A.EDV < P.EDV ? 'azaldı' : 'arttı'} → atım hacmi (SV) de ${A.SV < P.SV ? 'azaldı' : 'arttı'}.`);
  if (chg('TPR', P.TPR, A.TPR)) notes.push('Direnç değişti: MAP = CO × TPR.');
  if (chg('MAP', P.MAP, A.MAP)) notes.push('Bu basınç değişikliğini şimdi reseptörler algılayacak…');
  out.push({ kind: 'ph', title: 'İlk birkaç saniye — refleksler henüz devreye girmeden', html: html + (notes.length ? '<div class="note" style="margin-top:3px">' + notes.join(' ') + '</div>' : ''), tabs: chg('MAP', P.MAP, A.MAP) || chg('SV', P.SV, A.SV) ? ['cycle'] : [] });
  // hücre düzeyi
  const cl = ['vRest', 'naAvail', 'apd'].filter(k => chg(k, P[k], A[k]));
  const el = ['PR', 'QRS', 'QTc'].filter(k => chg(k, P[k], A[k]));
  if (cl.length || el.length) {
    const L = [];
    if (cl.includes('vRest')) L.push(mline('vRest', P.vRest, A.vRest) + ' — zar potansiyeli K⁺ dengesine bağlıdır (Nernst/Goldman).');
    if (cl.includes('naAvail')) L.push(mline('naAvail', P.naAvail, A.naAvail) + ` — ${A.naAvail < P.naAvail ? 'daha az Na⁺ kanalı açılabilir → faz 0 yavaşlar → uyarı kalpte daha yavaş yayılır' : 'faz 0 daha hızlı'}.`);
    if (cl.includes('apd')) L.push(mline('apd', P.apd, A.apd) + ` — ${A.apd > P.apd ? 'repolarizasyon gecikti' : 'repolarizasyon hızlandı'}.`);
    el.forEach(k => L.push(mline(k, P[k], A[k])));
    out.push({ kind: '', title: 'Hücre ve EKG düzeyinde', html: '<ul>' + L.map(x => `<li>${x}</li>`).join('') + '</ul>', tabs: ['cell', 'ecg'] });
  }
  return out;
}
function stepsB(job) {
  const P = job.P0, A = job.snaps.A || job.P0, B = job.snaps.B, p = eng.p, out = [];
  const dMap = A.MAP - P.MAP;
  // algılama
  const rec = [];
  if (Math.abs(dMap) >= 4 || (job.changes.some(x => x.c.id === 'baro'))) {
    if (!p.baroOn) rec.push('<b>Baroreseptör refleksi kapalı</b>: basınçtaki değişiklik algılanmıyor, bu yüzden sinir sistemi KH ve TPR ile düzeltme yapamıyor.');
    else if (dMap < 0) rec.push(`<b>Baroreseptörler</b> (karotis sinüsü ve aort kemerindeki gerilme reseptörleri) daha az gerilir; deşarjları %${fmt(P.baro)} → %${fmt(Math.min(A.baro, B.baro))} ${ARW} IX. (glossofaringeal) ve X. (vagus) sinirlerle beyin sapındaki NTS'ye daha az uyarı gider ${ARW} vazomotor merkez (RVLM) baskıdan kurtulur, vagus çekirdeği (n. ambiguus) daha az uyarılır.`);
    else rec.push(`<b>Baroreseptörler</b> (karotis sinüsü ve aort kemeri) daha çok gerilir ve daha sık ateşler ${ARW} IX. ve X. sinirlerle NTS uyarılır ${ARW} CVLM üzerinden sempatik merkez (RVLM) baskılanır, vagus (n. ambiguus) uyarılır.`);
  }
  if (job.changes.some(x => x.c.id === 'ex') && p.exercise > 0) rec.push('<b>Merkezi komut</b> (motor korteks) egzersizle birlikte sempatiği doğrudan artırır ve baroreseptör ayar noktasını yukarı kaydırır; bu yüzden basınç yüksekken bile KH artabilir.');
  const dC = A.CVP - P.CVP;
  if (Math.abs(dC) >= 1 || Math.abs(A.LAP - P.LAP) >= 1.5) {
    if (dC < 0) rec.push(`Atriyumlar ve büyük venlerdeki <b>düşük basınç (hacim) reseptörleri</b> daha az gerilir (CVP ${fmt(P.CVP, 1)} → ${fmt(A.CVP, 1)} mmHg) ${ARW} hipotalamusa giden inhibisyon azalır ${ARW} ADH ↑, böbreğe sempatik ↑.`);
    else rec.push(`Atriyumlar daha çok gerilir (CVP ${fmt(P.CVP, 1)} → ${fmt(A.CVP, 1)} mmHg) ${ARW} <b>atriyal gerilme reseptörleri</b>: Bainbridge refleksi (KH ↑), ADH ↓ ve atriyumdan ANP salınır.`);
  }
  if (B.chemo - P.chemo >= 0.1) {
    const why = []; if (B.PaO2 < 65) why.push('düşük PaO₂'); if (p.PaCO2 > 45) why.push('yüksek PaCO₂'); if (B.MAP < 65) why.push('düşük kan akımı'); if (B.pH < 7.35) why.push('asidoz');
    rec.push(`<b>Periferik kemoreseptörler</b> (karotis ve aort cisimcikleri) ${why.join(', ') || 'kimyasal değişikliği'} algılar ${ARW} solunum merkezi uyarılır (solunum ${fmt(P.RR)} → ${fmt(B.RR)}/dk) ve sempatik aktivite artar.`);
  }
  if (B.cns >= 0.05) {
    rec.push(`<b>MSS iskemik yanıtı</b>: CPP (MAP − ICP) ${fmt(A.CPP)} mmHg'ya düştü ${ARW} beyin sapındaki vazomotor merkez yeterince kanlanmaz, CO₂ birikir ${ARW} vücuttaki en güçlü sempatik deşarj ${ARW} damarlar daralır, MAP yükselir.` + (p.ICP > 20 ? ` Yükselen MAP baroreseptörleri uyarır ${ARW} vagus ↑ ${ARW} göreceli bradikardi; solunum düzensizleşir: <b>Cushing triadı</b> (hipertansiyon, bradikardi, düzensiz solunum).` : ''));
  }
  if (rec.length) out.push({ kind: '', title: 'Algılama — reseptörler fark eder', html: rec.join('<br><br>'), tabs: ['reflex'] });
  // otonom yanıt
  const dS = B.S - P.S, dV = B.V - P.V;
  if (Math.abs(dS) >= 5 || Math.abs(dV) >= 5) {
    const L = [];
    L.push(mline('S', P.S, B.S)); L.push(mline('V', P.V, B.V));
    const eff = [];
    if (chg('HR', A.HR, B.HR)) eff.push(`SA düğümü ${B.HR > A.HR ? 'hızlanır (pozitif kronotropi)' : 'yavaşlar (negatif kronotropi)'}: ${mline('HR', A.HR, B.HR)}`);
    if (chg('contr', A.contr, B.contr)) eff.push(`Kalp kası (β₁): ${mline('contr', A.contr, B.contr)} — ${B.contr > A.contr ? 'pozitif' : 'negatif'} inotropi`);
    if (chg('TPR', A.TPR, B.TPR)) eff.push(`Arteriyoller (α₁) ${B.TPR > A.TPR ? 'daralır' : 'genişler'}: ${mline('TPR', A.TPR, B.TPR)}`);
    if (Math.abs(B.venTone - A.venTone) > 40) eff.push(`Venler ${B.venTone < A.venTone ? 'daralır → depodaki kan kalbe itilir (venöz dönüş ↑)' : 'gevşer → kan venlerde birikir'}`);
    if (B.epi - P.epi > 0.08) eff.push(`Adrenal medulladan adrenalin salınır (×${fmt(P.epi / 0.1, 1)} → ×${fmt(B.epi / 0.1, 1)})`);
    if (p.betaBlock > 0 && dS > 5) eff.push('<i>β-bloker sempatiğin kalp üzerindeki etkisini büyük ölçüde engelliyor → KH ve kasılma artışı sınırlı.</i>');
    if (p.atropine > 0 && dV > 5) eff.push('<i>Atropin vagusun kalbe etkisini engelliyor → yavaşlama olmaz.</i>');
    out.push({ kind: '', title: 'Sinir sistemi yanıtı — beyin sapı vazomotor merkezi', html: '<ul>' + L.map(x => `<li>${x}</li>`).join('') + '</ul>' + (eff.length ? '<b>Sonuçları:</b><ul>' + eff.map(x => `<li>${x}</li>`).join('') + '</ul>' : ''), tabs: ['reflex'] });
  }
  // hormonlar
  const H = [];
  const ratio = (k) => B[k] / Math.max(P[k], 0.01);
  const hx = (k) => `×${fmt(P[k], 2)} → <b class="${B[k] > P[k] ? 'up' : 'dn'}">×${fmt(B[k], 2)}</b>`;
  if (chg('renin', P.renin, B.renin)) H.push(ratio('renin') > 1 ? `<b>Renin</b> ${hx('renin')}: böbreğe gelen basınç düştü (${fmt(B.renalPP)} mmHg) ve/veya böbreğe sempatik (β₁) arttı → jukstaglomerüler hücreler renin salar.` : `<b>Renin</b> ${hx('renin')}: böbrek perfüzyonu yeterli/yüksek → renin salınımı baskılanır.`);
  if (chg('angII', P.angII, B.angII)) H.push(`<b>Anjiyotensin II</b> ${hx('angII')}: renin → anjiyotensin I → (akciğerde ACE ile) anjiyotensin II. ${ratio('angII') > 1 ? 'Arteriyolleri daraltır, aldosteron ve ADH salgılatır, susama yapar.' : 'Daraltıcı etkisi azalır.'}`);
  if (chg('aldo', P.aldo, B.aldo)) H.push(`<b>Aldosteron</b> ${hx('aldo')} (böbrek üstü korteksi): böbrekte Na⁺ ${ratio('aldo') > 1 ? 've su geri emilimi artar' : 'tutulumu azalır'}.`);
  if (chg('adh', P.adh, B.adh)) H.push(`<b>ADH</b> ${hx('adh')} (arka hipofiz): ${ratio('adh') > 1 ? 'V₂ ile toplayıcı kanalda su geri emilimi ↑; yüksek düzeyde V₁ ile damar daralması.' : 'su atılımı artar.'}`);
  if (chg('anp', P.anp, B.anp)) H.push(`<b>ANP</b> ${hx('anp')}: ${ratio('anp') > 1 ? 'gerilen atriyumlardan salınır → böbrekten Na⁺ ve su atılımı ↑, damar genişler, renin ve aldosteron baskılanır.' : 'azalır.'}`);
  if (H.length) out.push({ kind: '', title: 'Hormonlar (dakikalar–saatler)', html: H.join('<br>') + (job.long ? '' : '<div class="note" style="margin-top:4px">Hormonların böbrekte sıvı tutma/atma sonucu günler sürer: sonuçtaki “Günler sonra ne olur?” düğmesiyle görebilirsin.</div>'), tabs: ['reflex'] });
  // lokal
  const LC = [];
  if (Math.abs(dMap) >= 8) {
    const beds = ['q_brain', 'q_cor', 'q_kidney'].filter(k => P[k] > 0);
    LC.push(`<b>Lokal otoregülasyon</b>: beyin, kalp ve böbrek kendi arteriyol çaplarını ayarlayıp akımlarını korumaya çalışır (miyojenik + metabolik):<ul>${beds.map(k => `<li>${chg(k, P[k], B[k]) ? mline(k, P[k], B[k]) : `<b>${KM[k][1]}</b>: ${fv(k, P[k])} → ${fv(k, B[k])} ml/dk (korundu)`}</li>`).join('')}</ul>`);
  }
  if (B.SaO2 < 90) LC.push(`<b>Hipoksi</b> (SpO₂ %${fmt(B.SaO2)}): sistemik arteriyoller genişler (metabolik), akciğer arteriyolleri ise daralır (HPV) → PAP ${fmt(P.PAs)} → ${fmt(B.PAs)} mmHg.`);
  if (B.isch >= 30 && P.isch < 30) LC.push(`<b>Koroner iskemi</b>: kalbin O₂ ihtiyacı (KH × basınç × kasılma) koroner arzı aşıyor → kasılma zayıflar, EKG'de ST değişikliği.`);
  if (job.changes.some(x => x.c.id === 'hct')) LC.push(`<b>Viskozite</b> ${fmt(P.visc, 2)} → ${fmt(B.visc, 2)} × normal: Poiseuille R = 8Lη/πr⁴ → direnç viskoziteyle doğru orantılı.` + (B.Hct < 35 ? ' O₂ içeriği düştüğü için dokular metabolik olarak damarlarını genişletir; düşük viskozite de venöz dönüşü artırır → CO ↑.' : ''));
  if (LC.length) out.push({ kind: '', title: 'Dokular ve damarlar', html: LC.join('<br>'), tabs: ['vessels'] });
  // kapiller
  if (chg('Jsys', P.Jsys, B.Jsys)) {
    const up = B.Jsys > P.Jsys;
    out.push({ kind: '', title: 'Kapiller — Starling kuvvetleri', html: `Kapiller basınç (Pc) ${fmt(P.PcA)} → ${fmt(B.PcA)} mmHg, plazma onkotik basıncı (πc) ${fmt(P.piC)} → ${fmt(B.piC)} mmHg<br>${ARW} ${mline('Jsys', P.Jsys, B.Jsys)}<br>${up ? 'Fazla süzülen sıvıyı lenf damarları geri taşır; kapasite aşılırsa dokuda ödem birikir.' : 'Filtrasyon azaldı ya da geçici olarak doku sıvısı damara geri çekildi (otomatik transfüzyon).'}`, tabs: ['cap'] });
  }
  return out;
}
function stepsC(job) {
  const P = job.P0, B = job.snaps.B || job.P0, C = job.snaps.C, out = [];
  const L = [];
  if (chg('BV', B.BV, C.BV)) L.push(`${mline('BV', B.BV, C.BV)} — ${C.BV > B.BV ? 'böbrek Na⁺ ve su tuttu (aldosteron, ADH, susama ile su alımı)' : 'böbrek fazla Na⁺ ve suyu attı (basınç natriürezisi, ANP)'}.`);
  if (chg('urine', B.urine, C.urine)) L.push(mline('urine', B.urine, C.urine));
  if (C.dVi >= 150) L.push(`<b>Periferik ödem</b>: dokularda +${fmt(C.dVi)} ml fazla sıvı birikti (filtrasyon, lenfin taşıyabileceğinden fazla).`);
  if (C.dVlung >= 40) L.push(`<b>Akciğer ödemi</b>: akciğer dokusunda +${fmt(C.dVlung)} ml sıvı → O₂ alımı bozulur (SpO₂ ${fmt(B.SaO2)} → ${fmt(C.SaO2)}%).`);
  ['renin', 'angII', 'aldo', 'adh', 'anp'].forEach(k => { if (chg(k, B[k], C[k])) L.push(mline(k, B[k], C[k])); });
  if (Math.abs(C.MAP - P.MAP) >= 6) L.push('Basınç uzun süre farklı kalırsa baroreseptörler yeni düzeye ayarlanır (resetting); bu yüzden uzun süreli basınç kontrolünü böbrek yapar.');
  if (!L.length) L.push('Günler içinde ek bir değişiklik olmadı; sistem kısa vadeli dengede kaldı.');
  out.push({ kind: 'ph', title: 'Günler sonra — böbrek, hacim ve ödem', html: '<ul>' + L.map(x => `<li>${x}</li>`).join('') + '</ul>', tabs: C.dVi >= 150 || C.dVlung >= 40 ? ['cap', 'reflex'] : ['reflex'] });
  return out;
}
const KEYS_R = ['HR', 'SBP', 'DBP', 'MAP', 'CO', 'SV', 'EDV', 'EF', 'CVP', 'LAP', 'TPR', 'SaO2', 'CPP', 'PR', 'QRS', 'QTc', 'S', 'V', 'BV', 'Hct', 'Jsys', 'dVi', 'dVlung'];
function resultSteps(job) {
  const P = job.P0, R = job.snaps.C || job.snaps.B, A = job.snaps.A, out = [];
  let html = rtab(KEYS_R, P, R, true) || 'Önemli bir değişiklik yok.';
  if (A && !job.onlyC && Math.abs(A.MAP - P.MAP) >= 4) {
    const fix = clamp((R.MAP - A.MAP) / (P.MAP - A.MAP) * 100, -200, 200);
    html += `<div style="margin-top:5px">İlk anda MAP ${fmt(P.MAP)} → ${fmt(A.MAP)} mmHg olmuştu; ${fix > 5 ? `vücut bu değişikliğin <b>%${fmt(fix)}</b>'ini düzeltti` : 'vücut bu değişikliği düzeltemedi'}${job.snaps.C ? ' (günler içinde)' : ''}.</div>`;
  }
  const tabs = TABS.filter(t => STU.tabChg[t.id]).map(t => t.id);
  html += `<div class="note" style="margin-top:5px">Değerler artık bu yeni dengede sabit kalacak.${tabs.length ? ' Değişiklik olan sekmeler turuncu çerçeveli:' : ''}</div>`;
  out.push({ kind: 'res', title: job.snaps.C ? 'Sonuç — günler sonraki yeni denge' : 'Sonuç — yeni denge (dakikalar sonra)', html, tabs });
  return out;
}

/* ---------- üst şerit ---------- */
function sBanner() {
  const el = $('sBanner'); if (!el) return;
  const job = STU.job;
  if (job && !job.finished) {
    const st = job.stage;
    const s1 = job.onlyC ? '' : `<span>${st === 'start' ? '<span class="busy-dot"></span>' : '✓'} İlk etki</span>`;
    const s2 = job.onlyC ? '' : `<span>${st === 'B' || st === 'C' ? '✓' : (st === 'A' ? '<span class="busy-dot"></span>' : '○')} Sinir sistemi ve hormonlar</span>`;
    const s3 = job.long ? `<span>${st === 'C' ? '✓' : (st === 'B' || job.onlyC) ? '<span class="busy-dot"></span>' : '○'} Günler sonra</span>` : '';
    el.className = 'sbanner busy';
    el.innerHTML = `<span class="lbl">Vücut yanıt veriyor…</span>${s1}${s2}${s3}<a class="go reset-g" href="#console">Konsolda adım adım izle</a>`;
    return;
  }
  el.className = 'sbanner';
  const L = STU.lastResult;
  if (!L || !L.job || L.job.silent) { el.innerHTML = `<span class="lbl">Öğrenci modu</span><span>Basit kontrollerden birine bas. Sonuç adım adım hesaplanır, sonra değerler yeni dengede sabit kalır.</span>`; return; }
  const ks = ['HR', 'MAP', 'SBP', 'CO', 'SV', 'CVP', 'TPR', 'SaO2', 'CPP', 'QRS', 'QTc', 'Jsys', 'dVi', 'BV'].filter(k => chg(k, L.P0[k], L.R[k])).slice(0, 7);
  const title = L.job.title || (L.job.preset ? L.job.preset.n : L.job.onlyC ? 'Günler sonra' : L.job.changes.map(x => x.c.t + ': ' + x.c.lv[x.to][0]).join(', '));
  el.innerHTML = `<span class="lbl">Sonuç</span><span class="note">${title}</span>${ks.map(k => { const up = L.R[k] > L.P0[k]; return `<span class="dchip ${up ? 'up' : 'dn'}" title="${KM[k][1]}">${KM[k][0]} ${fv(k, L.P0[k])}→${fv(k, L.R[k])} ${up ? '↑' : '↓'}</span>`; }).join('') || '<span class="note">belirgin değişiklik yok</span>'}
    ${!L.job.snaps.C ? '<button class="btn" id="sLong">⏩ Günler sonra ne olur?</button>' : ''}<a class="go reset-g" href="#console">Konsolda açıklama</a>`;
  const b = $('sLong'); if (b) b.onclick = () => startJob({ onlyC: true });
}

/* ---------- mod geçişi ---------- */
function stuInit(opt) {
  opt = opt || {};
  SCL.forEach(c => { const i = detectLevel(eng.p, c); STU.target[c.id] = i; STU.applied[c.id] = i; });
  STU.bvT = STU.bvA = 0;
  { const c = SCL.find(x => x.id === 'bv'); const dv = eng.bloodVolume() - 5028; let bi = 2, bd = 1e9; c.lv.forEach((l, i) => { if (Math.abs(l[1] - dv) < bd) { bd = Math.abs(l[1] - dv); bi = i; } }); STU.target.bv = STU.applied.bv = bi; STU.bvT = STU.bvA = c.lv[bi][1]; }
  paintSC();
  // mevcut durumu dondurulmuş dengeye oturt
  const e0 = eng;
  if (STU.job) STU.job.dead = true;
  STU.job = null; STU.tw = null;
  // ilk kurulumda bir kez senkron (≈1 s)
  const out = ST.settleSync(e0, () => {}, {});
  eng = out.B.eng; audioReset();
  STU.base = eng; STU.cur = out.B.snap; STU.disp = Object.assign({}, out.B.snap);
  if (opt.normal || !STU.normal) { STU.normal = out.B.snap; STU.normalEng = eng.clone(); }
  STU.tabChg = {}; paintTabs();
  STU.lastResult = null; sBanner();
}
function setMode(m, silent) {
  const on = m === 'student';
  document.querySelectorAll('#modeSeg .segb').forEach(b => b.setAttribute('aria-pressed', b.dataset.m === m));
  try { localStorage.setItem('kvs_mode', m); } catch (e) {}
  if (on === STU.on && !silent) return;
  STU.on = on;
  document.body.classList.toggle('student', on);
  if (on) { eng.speed = 1; $('speed').value = '1'; if (paused) $('pause').click(); $('sBanner').innerHTML = '<span class="busy-dot"></span> Öğrenci modu hazırlanıyor…'; setTimeout(() => { if (STU.on) stuInit({}); }, 40); }
  else {
    if (STU.job) STU.job.dead = true; STU.job = null;
    eng.hold = { auto: false, hum: false, fluid: false }; eng.speed = 1;
    syncControls();
    TABS.forEach(t => { const b = $('tab_' + t.id); if (b) b.classList.remove('chg'); });
  }
}
/* ui.js kancaları */
function stuPreset(p) {
  if (p.act && p.act.some(a => a === 'valsalva' || a === 'carotid')) {
    setMode('expert');
    logWhy({ t: 'Uzman moduna geçildi', c: ['Bu senaryo (' + p.n + ') saniye saniye değişen bir manevra', 'zaman içindeki seyri uzman modunda canlı izlenir'], r: '' });
    return false;
  }
  if (STU.job) STU.job.dead = true;
  // normal dengeden başla
  const base = STU.normalEng.clone();
  eng = base;
  const mut = (e) => {
    if (p.set) for (const k in p.set) e.set(k, p.set[k]);
    if (p.act) p.act.forEach(a => { if (a === 'hem500') e.instantVolume(-500); else if (a === 'hem1000') e.instantVolume(-1000); else if (a === 'transf') e.instantVolume(500); else if (a === 'cryst') { const s = e.s; s.plasma += 1000; s.Vsv += 1000; e.updateDerived(); } });
  };
  SCL.forEach(c => { STU.applied[c.id] = c.norm; });
  STU.bvA = STU.bvT = 0;
  const tmp = { p: Object.assign({}, E.DEFAULTS, p.set || {}) };
  SCL.forEach(c => { STU.target[c.id] = detectLevel(tmp.p, c); });
  STU.tabChg = {};
  startJob({ preset: p, mutate: mut, baseEng: base, P0: STU.normal, long: !!p.speed });
  // uygulandıktan sonra hedef = uygulanmış
  SCL.forEach(c => { STU.applied[c.id] = STU.target[c.id]; });
  paintSC();
  return true;
}
function stuCase(cs) {
  if (STU.job) STU.job.dead = true;
  const base = STU.normalEng.clone(); eng = base;
  const mut = (e) => { if (cs.set) for (const k in cs.set) e.set(k, cs.set[k]); if (cs.act) cs.act.forEach(a => { if (a === 'hem500') e.instantVolume(-500); else if (a === 'hem1000') e.instantVolume(-1000); }); };
  const tmp = Object.assign({}, E.DEFAULTS, cs.set || {});
  SCL.forEach(c => { const i = detectLevel(tmp, c); STU.target[c.id] = i; STU.applied[c.id] = i; });
  STU.bvA = STU.bvT = 0; STU.tabChg = {}; paintTabs();
  startJob({ mutate: mut, baseEng: base, P0: STU.normal, long: !!cs.speed, silent: true, title: 'Vaka' });
  paintSC();
}
function stuReset() {
  if (!STU.on) return;
  if (STU.job) STU.job.dead = true; STU.job = null;
  eng = STU.normalEng ? STU.normalEng.clone() : eng;
  SCL.forEach(c => { STU.target[c.id] = c.norm; STU.applied[c.id] = c.norm; });
  STU.bvT = STU.bvA = 0;
  STU.base = eng; STU.cur = STU.normal; STU.disp = Object.assign({}, STU.normal); STU.tw = null;
  STU.tabChg = {}; paintTabs(); paintSC(); STU.lastResult = null; sBanner();
}
function stuTick(now) {
  if (!STU.on) return;
  tickJob(now); tickTween(now); tickReveal(now); updNumsStudent();
}
function buildStudent() {
  buildSControls();
  TABS.forEach(t => { const p = $('pane_' + t.id); if (p && !$('ss_' + t.id)) p.insertAdjacentHTML('afterbegin', `<div class="sstrip" id="ss_${t.id}"></div>`); });
  document.querySelectorAll('#modeSeg .segb').forEach(b => b.addEventListener('click', () => setMode(b.dataset.m)));
  $('conClear').addEventListener('click', () => { $('conBody').innerHTML = ''; });
  $('conBody').innerHTML = `<div class="centry"><div class="ch">Nasıl kullanılır?</div><div class="csteps"><div class="cst"><div class="no">1</div><div class="tx">Basit kontrollerden bir etkeni seç (ör. <b>Kan volümü → Kanama</b>).</div></div><div class="cst"><div class="no">2</div><div class="tx">Önce <b>ilk etki</b>, sonra <b>sinir sistemi ve hormon yanıtı</b> hesaplanır; monitördeki sayılar yeni değerlere yavaşça gelir ve orada <b>sabit kalır</b>.</div></div><div class="cst"><div class="no">3</div><div class="tx">Burada hangi reseptörün, hangi merkezin, hangi hormonun çalıştığı adım adım yazar. Turuncu çerçeveli sekmelerde değişiklik vardır.</div></div></div></div>`;
}
