/* ===================== SENARYOLAR, VAKALAR, AÇIKLAMALAR ===================== */
(function (global) {
'use strict';

/* --- Hazır senaryolar: varsayılanlara dönülür, sonra set + act uygulanır --- */
const PRESETS = [
  { g: 'Temel', id: 'normal', n: 'Normal istirahat', set: {}, note: '120/80 mmHg, KH ~70, CO ~5 L/dk, EDV 120–130 ml.' },
  { g: 'Temel', id: 'exercise', n: 'Egzersiz (orta-ağır)', set: { exercise: 0.7 }, note: 'Merkezi komut + kas metabolik vazodilatasyonu: KH ve CO ↑, TPR ↓.' },
  { g: 'Temel', id: 'stand', n: 'Sırtüstünden ayağa kalkma', set: { posture: 'standing' }, note: 'Venöz göllenme → barorefleks.' },
  { g: 'Temel', id: 'fever', n: 'Ateş (39,5 °C)', set: { temp: 39.5 }, note: 'Kalp hızı ve deri akımı ↑.' },
  { g: 'Temel', id: 'thyro', n: 'Hipertiroidi', set: { thyroid: 2.1 }, note: 'Kalp hızı, VO₂ ve debi ↑.' },
  { g: 'Temel', id: 'stress', n: 'Heyecan / stres', set: { emotion: 0.8 } },

  { g: 'Hacim ve kan', id: 'hem500', n: 'Kanama 500 ml (%10)', act: ['hem500'] },
  { g: 'Hacim ve kan', id: 'hem1000', n: 'Kanama 1000 ml (%20)', act: ['hem1000'] },
  { g: 'Hacim ve kan', id: 'hemRefill', n: 'Kanama 1000 ml + 1 saat izlem (60×)', act: ['hem1000'], speed: 60, note: 'Transkapiller geri dolum, RAAS, ADH ve susama; hematokrit seyrelir.' },
  { g: 'Hacim ve kan', id: 'cryst', n: '+1000 ml kristaloid (Bainbridge, ödem eğilimi)', act: ['cryst'] },
  { g: 'Hacim ve kan', id: 'anemia', n: 'Anemi (Hct %22)', set: { hct: 22 } },
  { g: 'Hacim ve kan', id: 'poly', n: 'Polisitemi (Hct %62)', set: { hct: 62 } },
  { g: 'Hacim ve kan', id: 'visc', n: 'Hiperviskozite (fibrinojen ↑, deformabilite ↓)', set: { fibrinogen: 7, deform: 0.4 } },

  { g: 'Şok', id: 'shockHypo', n: 'Hipovolemik şok (2000 ml)', act: ['hem1000', 'hem1000'] },
  { g: 'Şok', id: 'shockCardio', n: 'Kardiyojenik şok (anterior MI)', set: { mi: 'ant', contractility: 0.6 } },
  { g: 'Şok', id: 'shockSeptic', n: 'Septik şok', set: { sepsis: 0.9, temp: 39.6 } },
  { g: 'Şok', id: 'shockAna', n: 'Anafilaktik şok', set: { anaphylaxis: 0.85 } },
  { g: 'Şok', id: 'tamp', n: 'Obstrüktif: kalp tamponadı', set: { tamponade: 14 } },
  { g: 'Şok', id: 'ptx', n: 'Obstrüktif: tansiyon pnömotoraks', set: { pneumo: 0.85 } },
  { g: 'Şok', id: 'pe', n: 'Obstrüktif: masif pulmoner emboli', set: { pe: 0.85 } },

  { g: 'Kalp', id: 'as', n: 'Aort stenozu', set: { AS: 0.85 } },
  { g: 'Kalp', id: 'ar', n: 'Aort yetersizliği', set: { AR: 0.75 } },
  { g: 'Kalp', id: 'ms', n: 'Mitral stenoz', set: { MS: 0.85 } },
  { g: 'Kalp', id: 'mr', n: 'Mitral yetersizliği', set: { MR: 0.7 } },
  { g: 'Kalp', id: 'lvh', n: 'Hipertansif sol ventrikül hipertrofisi', set: { hypertrophy: 'LVH', stiffness: 1.8 } },
  { g: 'Kalp', id: 'rvh', n: 'Pulmoner stenoz → sağ ventrikül hipertrofisi', set: { hypertrophy: 'RVH' } },
  { g: 'Kalp', id: 'lhf', n: 'Sol kalp yetmezliği (10 dk izlem)', set: { contractility: 0.42 }, speed: 600 },
  { g: 'Kalp', id: 'miAnt', n: 'Anterior MI', set: { mi: 'ant' } },
  { g: 'Kalp', id: 'miInf', n: 'İnferior MI', set: { mi: 'inf' } },
  { g: 'Kalp', id: 'angina', n: 'Koroner darlık + egzersiz (angina)', set: { corStenosis: 0.72, exercise: 0.5 } },

  { g: 'Ritim ve ileti', id: 'brady', n: 'Sinüs bradikardisi (vagal ↑)', set: { vagOffset: 0.45 } },
  { g: 'Ritim ve ileti', id: 'tachy', n: 'Sinüs taşikardisi (sempatik ↑)', set: { sympOffset: 0.45, vagOffset: -0.3 } },
  { g: 'Ritim ve ileti', id: 'af', n: 'Atriyal fibrilasyon', set: { rhythm: 'af' } },
  { g: 'Ritim ve ileti', id: 'fl', n: 'Atriyal flatter (2:1)', set: { rhythm: 'flutter' } },
  { g: 'Ritim ve ileti', id: 'vt', n: 'Ventriküler taşikardi', set: { rhythm: 'vt' } },
  { g: 'Ritim ve ileti', id: 'vf', n: 'Ventriküler fibrilasyon', set: { rhythm: 'vf' } },
  { g: 'Ritim ve ileti', id: 'av1', n: '1. derece AV blok', set: { avBlock: '1' } },
  { g: 'Ritim ve ileti', id: 'av2a', n: '2. derece Mobitz I (Wenckebach)', set: { avBlock: '2a' } },
  { g: 'Ritim ve ileti', id: 'av2b', n: '2. derece Mobitz II', set: { avBlock: '2b' } },
  { g: 'Ritim ve ileti', id: 'av3', n: '3. derece (komplet) AV blok', set: { avBlock: '3' } },
  { g: 'Ritim ve ileti', id: 'lbbb', n: 'Sol dal bloğu', set: { bbb: 'L' } },
  { g: 'Ritim ve ileti', id: 'rbbb', n: 'Sağ dal bloğu', set: { bbb: 'R' } },
  { g: 'Ritim ve ileti', id: 'ves', n: 'Sık ventriküler ekstrasistol', set: { ves: 0.25 } },

  { g: 'Elektrolit ve ilaç', id: 'hyperK', n: 'Hiperkalemi (7,2)', set: { K: 7.2 } },
  { g: 'Elektrolit ve ilaç', id: 'hyperK2', n: 'Ağır hiperkalemi (8,8) – iletim kaybı', set: { K: 8.8 } },
  { g: 'Elektrolit ve ilaç', id: 'hypoK', n: 'Hipokalemi (2,5)', set: { K: 2.5 } },
  { g: 'Elektrolit ve ilaç', id: 'hyperCa', n: 'Hiperkalsemi', set: { Ca: 3.4 } },
  { g: 'Elektrolit ve ilaç', id: 'hypoCa', n: 'Hipokalsemi', set: { Ca: 1.6 } },
  { g: 'Elektrolit ve ilaç', id: 'hyperMg', n: 'Hipermagnezemi', set: { Mg: 5 } },
  { g: 'Elektrolit ve ilaç', id: 'vera', n: 'Verapamil', set: { verapamil: 0.8 } },
  { g: 'Elektrolit ve ilaç', id: 'dilt', n: 'Diltiazem', set: { diltiazem: 0.8 } },
  { g: 'Elektrolit ve ilaç', id: 'nif', n: 'Nifedipin (refleks taşikardi)', set: { nifedipine: 0.8 } },
  { g: 'Elektrolit ve ilaç', id: 'bb', n: 'β-bloker', set: { betaBlock: 0.8 } },
  { g: 'Elektrolit ve ilaç', id: 'dig', n: 'Digoksin', set: { digoxin: 0.5 } },
  { g: 'Elektrolit ve ilaç', id: 'digTox', n: 'Digoksin + hipokalemi (toksisite)', set: { digoxin: 0.8, K: 3.0 } },
  { g: 'Elektrolit ve ilaç', id: 'naIC', n: 'Na⁺ kanal blokeri (IC)', set: { naBlock: 0.8, naClass: 'IC' } },
  { g: 'Elektrolit ve ilaç', id: 'kTdp', n: 'K⁺ kanal blokeri + hipokalemi (TdP riski)', set: { kBlock: 0.8, K: 3.0 } },
  { g: 'Elektrolit ve ilaç', id: 'atr', n: 'Atropin', set: { atropine: 0.9 } },
  { g: 'Elektrolit ve ilaç', id: 'na', n: 'Noradrenalin infüzyonu', set: { noradrenaline: 0.6 } },
  { g: 'Elektrolit ve ilaç', id: 'adr', n: 'Adrenalin infüzyonu (düşük doz)', set: { adrenaline: 0.35 } },
  { g: 'Elektrolit ve ilaç', id: 'ntg', n: 'Nitrat (venodilatasyon, preload ↓)', set: { nitrate: 0.8 } },
  { g: 'Elektrolit ve ilaç', id: 'acei', n: 'ACE inhibitörü (6 sa izlem)', set: { acei: 0.9 }, speed: 3600 },
  { g: 'Elektrolit ve ilaç', id: 'diur', n: 'Diüretik (6 sa izlem)', set: { diuretic: 0.8 }, speed: 3600 },

  { g: 'Refleks ve manevra', id: 'vals', n: 'Valsalva manevrası (4 faz)', act: ['valsalva'] },
  { g: 'Refleks ve manevra', id: 'csm', n: 'Karotis sinüs masajı', act: ['carotid'] },
  { g: 'Refleks ve manevra', id: 'denerv', n: 'Baroreseptör kaybı + ayağa kalkma', set: { baroOn: false, posture: 'standing' } },
  { g: 'Refleks ve manevra', id: 'cht', n: 'Yüksek tuz → kronik HT, baro resetting (günler)', set: { salt: 2.6 }, speed: 21600 },
  { g: 'Refleks ve manevra', id: 'rvht', n: 'Renovasküler (sekonder) HT', set: { renalStenosis: 0.6 }, speed: 3600 },

  { g: 'Kapiller ve ödem', id: 'standEd', n: 'Hareketsiz ayakta durma (bacak ödemi)', set: { posture: 'standing' }, speed: 600 },
  { g: 'Kapiller ve ödem', id: 'lhfEd', n: 'Sol KY → akciğer ödemi', set: { contractility: 0.38 }, speed: 600 },
  { g: 'Kapiller ve ödem', id: 'rhfEd', n: 'Sağ KY → periferik ödem, asit', set: { pe: 0.4, venExtra: 8 }, speed: 3600 },
  { g: 'Kapiller ve ödem', id: 'nephro', n: 'Nefrotik sendrom', set: { albumin: 1.8 }, speed: 3600 },
  { g: 'Kapiller ve ödem', id: 'cirr', n: 'Karaciğer sirozu', set: { albumin: 2.3, venExtra: 6 }, speed: 3600 },
  { g: 'Kapiller ve ödem', id: 'preg', n: 'Gebelik ödemi (ven basısı)', set: { venExtra: 12 }, speed: 3600 },
  { g: 'Kapiller ve ödem', id: 'malnut', n: 'Proteinden yoksun beslenme', set: { albumin: 2.0 }, speed: 3600 },
  { g: 'Kapiller ve ödem', id: 'burn', n: 'Ağır yanık', set: { perm: 3.5, albumin: 3.0 }, speed: 600 },
  { g: 'Kapiller ve ödem', id: 'infl', n: 'İnflamasyon (geçirgenlik ↑)', set: { perm: 2.5 }, speed: 600 },
  { g: 'Kapiller ve ödem', id: 'lymph', n: 'Lenf nodu diseksiyonu (lenfödem)', set: { lymph: 0.15, venExtra: 4 }, speed: 3600 },
  { g: 'Kapiller ve ödem', id: 'filar', n: 'Elefantiazis (W. bancrofti)', set: { lymph: 0.06, venExtra: 4 }, speed: 3600 },
  { g: 'Kapiller ve ödem', id: 'classic', n: 'Klasik Starling modelini göster', set: { starling: 'classic' } },

  { g: 'Akciğer, gaz, beyin', id: 'alt', n: 'Yükseklik hipoksisi (PaO₂ 50)', set: { PaO2: 50 } },
  { g: 'Akciğer, gaz, beyin', id: 'hypox', n: 'Ağır hipoksemi (PaO₂ 36)', set: { PaO2: 36 } },
  { g: 'Akciğer, gaz, beyin', id: 'hcap', n: 'Hiperkapni (PaCO₂ 65)', set: { PaCO2: 65 } },
  { g: 'Akciğer, gaz, beyin', id: 'hvent', n: 'Hiperventilasyon (PaCO₂ 25)', set: { PaCO2: 25 } },
  { g: 'Akciğer, gaz, beyin', id: 'icp', n: 'İntrakraniyal basınç ↑ → Cushing', set: { ICP: 55 } },
  { g: 'Akciğer, gaz, beyin', id: 'amp', n: 'Bacak amputasyonu (paralel yatak kaybı)', set: { amputation: true } },
];

/* --- Vaka modu --- */
const CASES = [
  { t: 'Trafik kazası', v: '28 yaşında erkek, motosiklet kazası, femur kırığı. Soğuk ve soluk, huzursuz.', act: ['hem1000', 'hem1000'],
    o: ['Hipovolemik şok', 'Septik şok', 'Kardiyojenik şok', 'Anafilaktik şok'], a: 0,
    e: 'Kan kaybı → venöz dönüş ve ön yük ↓ → SV ve CO ↓ → MAP ↓. Baroreseptör deşarjı azalır, sempatik aktivite artar: taşikardi, TPR ↑, venokonstriksiyon. CVP ve PCWP düşüktür; kapiller basınç düştüğü için interstisyel sıvı damar içine geçer (geri dolum).', r: 'B10.3, B10.10' },
  { t: 'Göğüs ağrısı', v: '64 yaşında, sigara içen erkek. 1 saattir sıkıştırıcı göğüs ağrısı, terleme. Akciğer bazallerinde raller.', set: { mi: 'ant', contractility: 0.65 },
    o: ['Masif pulmoner emboli', 'Anterior MI ve kardiyojenik şok', 'Perikard tamponadı', 'Aort stenozu'], a: 1,
    e: 'V1–V4\'te ST elevasyonu, EF ↓, LV diyastol sonu basıncı ve LAP ↑, akciğer kapiller basıncı ↑ (raller). Kontraktilite kaybı Frank–Starling eğrisini aşağı kaydırır; CO ↓ → sempatik yanıt.', r: 'B6.4, B8.12, B9.6' },
  { t: 'Ateşli, sıcak cilt', v: '71 yaşında kadın, 2 gündür idrar yolu enfeksiyonu, bugün konfüzyon. Cilt sıcak, nabız hızlı.', set: { sepsis: 0.9, temp: 39.4 },
    o: ['Hipovolemik şok', 'Kardiyojenik şok', 'Septik (dağılımsal) şok', 'Nörojenik senkop'], a: 2,
    e: 'Yaygın vazodilatasyon → TPR belirgin ↓. CO normal ya da yüksektir; kapiller geçirgenlik artışıyla sıvı damar dışına kaçar. Laktat yükselir.', r: 'B10.10' },
  { t: 'Arı sokması', v: 'Bahçede arı sokan 35 yaşında kadın; yaygın kızarıklık, nefes darlığı, baş dönmesi.', set: { anaphylaxis: 0.85 },
    o: ['Anafilaktik şok', 'Vazovagal senkop', 'Tansiyon pnömotoraks', 'Hipoglisemi'], a: 0,
    e: 'Alerjik mediyatörler → vazodilatasyon (TPR ↓) ve venöz göllenme (ön yük ↓) + geçirgenlik ↑. Baroreseptör taşikardisi eşlik eder.', r: 'B10.10, B9.6' },
  { t: 'Bıçaklanma', v: '22 yaşında erkek, sol göğüse bıçak yarası. Boyun venleri dolgun, kalp sesleri derinden.', set: { tamponade: 14 },
    o: ['Hipovolemik şok', 'Kalp tamponadı', 'Sol kalp yetmezliği', 'Sepsis'], a: 1,
    e: 'Perikard basıncı tüm odaların dolumunu engeller: CVP ve LAP yükselir ve birbirine yaklaşır, EDV ve SV düşer. İnspirasyonda sistolik basınç belirgin düşer (pulsus paradoksus).', r: 'B10.10' },
  { t: 'Ani nefes darlığı', v: 'Kalça protezinden 5 gün sonra ani nefes darlığı ve göğüs ağrısı.', set: { pe: 0.85 },
    o: ['Masif pulmoner emboli', 'Anterior MI', 'Mitral stenoz', 'Anafilaksi'], a: 0,
    e: 'Pulmoner damar direnci ↑ → pulmoner arter basıncı ve sağ ventrikül art yükü ↑; sol kalbe dönüş ↓ (LAP düşük) → CO ↓. PaO₂ düşer.', r: 'B7.10, B10.10' },
  { t: 'Kafa travması', v: 'Merdivenden düşen 58 yaşında erkek; bilinci giderek bulanıyor, solunumu düzensiz.', set: { ICP: 55 },
    o: ['Hipovolemik şok', 'Cushing refleksi (ICP ↑)', 'Septik şok', 'Karotis sinüs hipersensitivitesi'], a: 1,
    e: 'ICP ↑ → CPP = MAP − ICP ↓ → beyin sapı iskemisi → güçlü sempatik yanıt, arter basıncı ↑. Yükselen basınç baroreseptörleri uyarır → refleks bradikardi. Hipertansiyon + bradikardi + düzensiz solunum = Cushing triadı.', r: 'B10.5' },
  { t: 'Diyaliz seansını kaçıran hasta', v: 'Kronik böbrek yetmezliği olan 66 yaşında erkek, iki diyaliz seansını kaçırmış; halsizlik.', set: { K: 7.4 },
    o: ['Hipokalemi', 'Hiperkalemi', 'Hiperkalsemi', 'Digoksin etkisi'], a: 1,
    e: 'Hücre dışı K⁺ ↑ → istirahat potansiyeli daha az negatif → Na⁺ kanallarının inaktivasyonu → faz 0 ve iletim yavaşlar: sivri T, geniş QRS, P dalgası küçülür, PR uzar.', r: 'B1.6' },
  { t: 'Kas güçsüzlüğü', v: 'Uzun süredir yüksek doz diüretik kullanan kadın; kas krampları ve çarpıntı.', set: { K: 2.5, diuretic: 0.6 },
    o: ['Hipokalemi', 'Hiperkalemi', 'Hipermagnezemi', 'Hipokalsemi'], a: 0,
    e: 'Hipokalemide repolarizasyon yavaşlar: faz 2–3 uzar, QT uzar, T düzleşir, U dalgası belirginleşir; aritmi riski artar.', r: 'B1.6, B3.1' },
  { t: 'Senkop', v: '79 yaşında kadın, birkaç kez bayılma. Nabız çok yavaş ve düzenli.', set: { avBlock: '3' },
    o: ['Sinüs bradikardisi', '1. derece AV blok', '3. derece (komplet) AV blok', 'Atriyal fibrilasyon'], a: 2,
    e: 'Atriyal uyarılar ventriküle hiç geçmez; P dalgaları QRS\'ten bağımsızdır. Distal odak (idiyoventriküler, ~35/dk, geniş QRS) pacemaker olur. Düşük hız → CO ↓; diyastol uzun olduğu için SV ve nabız basıncı büyüktür.', r: 'B3.6' },
  { t: 'Çarpıntı', v: '70 yaşında erkek, ani başlayan düzensiz çarpıntı.', set: { rhythm: 'af' },
    o: ['Atriyal flatter', 'Atriyal fibrilasyon', 'Ventriküler taşikardi', 'Sinüs aritmisi'], a: 1,
    e: 'P dalgası yok, ince fibrilasyon dalgaları ve tamamen düzensiz RR. AV düğümün refrakter dönemi ventrikül hızını sınırlar. Atriyal katkı (~%15) kaybolur.', r: 'B3.6, B4.2' },
  { t: 'Efor dispnesi', v: '82 yaşında erkek, merdiven çıkarken göğüs ağrısı ve baş dönmesi. Sağ 2. aralıkta sert sistolik üfürüm.', set: { AS: 0.85 },
    o: ['Mitral yetersizliği', 'Aort stenozu', 'Aort yetersizliği', 'Mitral stenoz'], a: 1,
    e: 'Dar kapak art yükü artırır: sol ventrikül basıncı aort basıncını belirgin aşar (gradyan), ESV ↑, EF ↓. Türbülan akım sistolik üfürüm yapar (en iyi aort odağında).', r: 'B5.5, B6.6' },
  { t: 'Göz kapaklarında şişlik', v: '9 yaşında çocuk, sabahları gözlerinde şişlik, idrarı köpüklü.', set: { albumin: 1.7 }, speed: 3600,
    o: ['Nefrotik sendrom', 'Sağ kalp yetmezliği', 'Lenf tıkanıklığı', 'İnflamasyon'], a: 0,
    e: 'Albümin kaybı → plazma onkotik basıncı ↓ → net filtrasyon ↑. Lenf kapasitesi aşılınca ödem gelişir; damar içi hacim azalır, RAAS aktive olur.', r: 'B9.3, B9.6' },
  { t: 'Dağcı', v: '4500 metreye çıkan 30 yaşında dağcı; nefes darlığı, çarpıntı.', set: { PaO2: 50 },
    o: ['Hipoksemi: kemorefleks + hipoksik pulmoner vazokonstriksiyon', 'Anemi', 'Masif PE', 'Sol kalp yetmezliği'], a: 0,
    e: 'PaO₂ < 60 mmHg periferik kemoreseptörleri uyarır: ventilasyon ve sempatik aktivite ↑. Akciğerde alveoler hipoksi vazokonstriksiyon yapar → pulmoner arter basıncı ↑ (sistemik damarların tersine).', r: 'B8.9, B10.4' },
  { t: 'İlaç zehirlenmesi', v: 'Bilinmeyen sayıda "tansiyon ve ritim" hapı içen 45 yaşında kadın; baş dönmesi.', set: { verapamil: 1 },
    o: ['β-agonist zehirlenmesi', 'Verapamil (KKB) zehirlenmesi', 'Nifedipin', 'Atropin'], a: 1,
    e: 'L tipi Ca²⁺ kanal blokajı: SA düğümde faz 4 eğimi ↓ (KH ↓), AV iletim yavaşlar (PR ↑), kontraktilite ↓, damarlar genişler → hipotansiyon.', r: 'B1.7' },
  { t: 'Yaşlı hipertansif', v: '78 yaşında kadın, sistolik basınç yüksek, diyastolik düşük.', set: { arterialStiff: 0.98 },
    o: ['Aort yetersizliği', 'Arteriyel kompliyans azalması (izole sistolik HT)', 'Anemi', 'Hipertiroidi'], a: 1,
    e: 'Büyük arterlerin kompliyansı azalınca aynı atım hacmi daha büyük basınç artışı yapar: sistolik ve nabız basıncı ↑, Windkessel tamponlaması zayıflar, diyastolik basınç düşer.', r: 'B7.8, B8.2' },
  { t: 'Soluk genç kadın', v: '24 yaşında kadın, aşırı adet kanamaları, yorgunluk; sistolik akım üfürümü.', set: { hct: 21 },
    o: ['Polisitemi', 'Anemi', 'Aort stenozu', 'Hipotiroidi'], a: 1,
    e: 'Hematokrit ↓ → viskozite ↓ → TPR ↓; O₂ içeriği ↓ → doku hipoksisi, vazodilatasyon ve kompansatuar CO artışı. Hız artışı Reynolds sayısını büyütür (akım üfürümü).', r: 'B7.8' },
  { t: 'Ani akciğer ödemi', v: 'MI sonrası 3. gün ani nefes darlığı; apekste yeni holosistolik üfürüm, aksillaya yayılıyor.', set: { MR: 0.75 },
    o: ['Aort stenozu', 'Mitral yetersizliği (papiller kas rüptürü)', 'Perikardit', 'Pulmoner emboli'], a: 1,
    e: 'Sistolde kan sol atriyuma kaçar: LAP ve pulmoner kapiller basınç ↑ (akciğer ödemi), ileri debi ↓. Toplam SV ve EF yüksek görünür.', r: 'B5.5, B9.6' },
  { t: 'Geniş nabız basıncı', v: '50 yaşında erkek, "boynunda atım hissi", diyastolik üfürüm (Erb odağı).', set: { AR: 0.75 },
    o: ['Aort yetersizliği', 'Mitral stenoz', 'Arteriyovenöz fistül', 'Aort stenozu'], a: 0,
    e: 'Diyastolde kanın ventriküle geri kaçması diyastolik basıncı düşürür, artan EDV (Frank–Starling) büyük SV ve yüksek sistolik basınç yapar: nabız basıncı çok büyük.', r: 'B5.5, B8.4' },
  { t: 'Travma sonrası nefes darlığı', v: 'Kaburga kırığı olan hasta; tek taraflı solunum sesleri azalmış, trakea kaymış, boyun venleri dolgun.', set: { pneumo: 0.85 },
    o: ['Tansiyon pnömotoraks', 'Hipovolemi', 'Septik şok', 'Akut MI'], a: 0,
    e: 'Toraks içi pozitif basınç venöz dönüşü engeller (sağ atriyum basıncı ↑, dolum ↓) → CO ↓; akciğer kollapsı PaO₂\'yi düşürür.', r: 'B10.10' },
  { t: 'Senkop öncesi', v: 'Diyabetik otonom nöropatisi olan hasta; ayağa kalkınca baş dönmesi.', set: { baroOn: false, posture: 'standing' },
    o: ['Ortostatik hipotansiyon (baroreseptör refleksi yok)', 'Vazovagal reaksiyon', 'Aort stenozu', 'Hiperkalemi'], a: 0,
    e: 'Ayakta venöz göllenme ön yükü düşürür; barorefleks çalışmazsa kalp hızı ve TPR artmaz → MAP ve CPP düşer.', r: 'B10.3' },
];

/* --- "Neden?" açıklamaları --- */
const up = (a, b) => b > a;
const W = {
  posture: (a, b) => b === 'standing' ? { t: 'Ayağa kalktı', c: ['Yerçekimi alt ekstremite ve splanknik venlerde ~400 ml kanı göllendirir', 'venöz dönüş ve EDV ↓', 'Frank–Starling ile SV ↓', 'MAP ↓', 'karotis/aort baroreseptör deşarjı ↓', 'NTS → sempatik ↑, vagal ↓', 'KH ↑, TPR ↑, venokonstriksiyon', 'MAP saniyeler içinde toparlanır'], r: 'B10.3' }
                                     : { t: 'Sırtüstü yattı', c: ['Göllenen kan merkeze döner', 'EDV ve SV ↑', 'baroreseptör deşarjı ↑', 'KH ve TPR normale iner'], r: 'B10.3' },
  exercise: (a, b) => ({ t: up(a, b) ? 'Egzersiz arttı' : 'Egzersiz azaldı', c: up(a, b) ? ['Merkezi komut: vagal ↓, sempatik ↑ (baroreseptör set noktası yukarı kayar)', 'KH ↑, kontraktilite ↑', 'kasta adenozin, CO₂, H⁺, K⁺ ↑ → metabolik vazodilatasyon (aktif hiperemi)', 'paralel yatak direnci ↓ → TPR ↓', 'kas ve solunum pompası venöz dönüşü artırır', 'CO 3–4 kat ↑; MAP orta derecede ↑', 'VO₂ ↑ → CvO₂ ↓'] : ['Merkezi komut ve metabolik dilatasyon geriler', 'KH, CO ↓; TPR ↑'], r: 'B6.2, B7.9, B8.9' }),
  emotion: (a, b) => ({ t: 'Heyecan/stres ' + (up(a, b) ? '↑' : '↓'), c: ['Limbik sistem → hipotalamus → vazomotor merkez', 'sempatik ↑, vagal ↓', 'KH ↑, kontraktilite ↑', 'adrenal medulladan epinefrin'], r: 'B6.2' }),
  temp: (a, b) => ({ t: up(a, b) ? 'Ateş yükseldi' : 'Vücut sıcaklığı düştü', c: up(a, b) ? ['SA düğüm faz 4 eğimi ↑ (~10 atım/dk/°C)', 'deri damarlarında dilatasyon (ısı kaybı)', 'VO₂ ↑ → CO ↑', 'S3 duyulabilir (hiperdinamik dolaşım)'] : ['Faz 4 eğimi ↓ → bradikardi', 'deri vazokonstriksiyonu', 'AP süresi uzar'], r: 'B6.2' }),
  thyroid: (a, b) => ({ t: 'Tiroid hormonu ' + (up(a, b) ? '↑' : '↓'), c: up(a, b) ? ['β-reseptör duyarlılığı ve SA düğüm hızı ↑', 'VO₂ ↑, metabolik vazodilatasyon', 'CO ↑, nabız basıncı ↑'] : ['KH ve VO₂ ↓', 'CO ↓'], r: 'B6.2' }),
  arterialStiff: (a, b) => ({ t: 'Arteriyel sertlik ' + (up(a, b) ? '↑ (kompliyans ↓)' : '↓ (kompliyans ↑)'), c: up(a, b) ? ['C = ΔV/ΔP ↓', 'aynı atım hacmi daha büyük basınç artışı yapar', 'sistolik ve nabız basıncı ↑', 'Windkessel etkisi zayıflar → diyastolik basınç ↓', 'sol ventrikül art yükü ↑'] : ['Aort sistolde daha çok kan depolar', 'nabız basıncı ↓'], r: 'B7.8, B8.2' }),
  hct: (a, b) => ({ t: up(a, b) ? 'Hematokrit arttı (polisitemi yönü)' : 'Hematokrit azaldı (anemi yönü)', c: up(a, b) ? ['viskozite (η) ↑', 'Poiseuille: R = 8Lη/πr⁴ → TPR ↑', 'CO ↓; O₂ içeriği ↑', 'Reynolds sayısı ↓'] : ['viskozite ↓ → TPR ↓', 'O₂ içeriği ↓ → doku hipoksisi', 'metabolik vazodilatasyon + sempatik → KH ve CO ↑', 'akım hızı ↑, Re ↑ → akım üfürümü'], r: 'B7.4, B7.8' }),
  fibrinogen: (a, b) => ({ t: 'Fibrinojen ' + (up(a, b) ? '↑' : '↓'), c: ['Eritrosit agregasyonu ' + (up(a, b) ? '↑' : '↓'), 'özellikle düşük kayma hızında viskozite ' + (up(a, b) ? '↑' : '↓'), 'TPR ' + (up(a, b) ? '↑' : '↓')], r: 'B7.8' }),
  deform: (a, b) => ({ t: 'Eritrosit deformabilitesi ' + (up(a, b) ? '↑' : '↓'), c: up(a, b) ? ['viskozite ↓'] : ['eritrositler kapillerden zor geçer', 'viskozite ↑ → TPR ↑', 'diyabet, HT, periferik arter hastalığında görülür'], r: 'B7.8' }),
  albumin: (a, b) => ({ t: 'Plazma albümini ' + (up(a, b) ? '↑' : '↓'), c: up(a, b) ? ['plazma onkotik basıncı (πc) ↑', 'net filtrasyon ↓, interstisyel sıvı damara çekilir'] : ['πc ↓ (26 → daha düşük mmHg)', 'NFB = (Pc + πif) − (πc + Pif) ↑', 'filtrasyon ↑ → lenf akımı ↑', 'lenf kapasitesi aşılınca ödem', 'damar içi hacim ↓ → RAAS, ADH ↑ (Na⁺/su tutulumu)'], r: 'B9.3, B9.6' }),
  salt: (a, b) => ({ t: 'Tuz/su alımı ' + (up(a, b) ? '↑' : '↓'), c: up(a, b) ? ['hücre dışı sıvı ve kan hacmi ↑', 'venöz dönüş ve CO ↑ → MAP ↑', 'basınç natriürezi ile atılım artana kadar basınç yükselir', 'renin ↓', 'süreklilikte baroreseptörler yeni basınca ayarlanır (resetting)'] : ['hacim ↓ → renin, AngII, aldosteron ↑'], r: 'B10.8' }),
  K: (a, b) => b > 5.2 ? { t: 'Hiperkalemi (K⁺ ' + b + ')', c: ['E_K daha az negatif → istirahat potansiyeli depolarize olur', 'Na⁺ kanallarının inaktivasyonu ↑ → faz 0 eğimi ve iletim hızı ↓', 'QRS genişler, P küçülür, PR uzar', 'repolarizasyon hızlanır → sivri, dar T', 'çok yüksekte iletim kaybı, sinüs dalgası, VF/asistoli'], r: 'B1.6' }
    : b < 3.5 ? { t: 'Hipokalemi (K⁺ ' + b + ')', c: ['E_K daha negatif, membran eşikten uzaklaşır', 'repolarizasyon yavaşlar → faz 2–3 uzar', 'QT uzar, T düzleşir, U dalgası', 'aritmi riski (digoksin toksisitesi artar)'], r: 'B1.6' } : { t: 'K⁺ normal aralıkta (' + b + ')', c: ['AP ve EKG normale döner'], r: 'B1.6' },
  Na: (a, b) => ({ t: (b > 145 ? 'Hipernatremi' : b < 135 ? 'Hiponatremi' : 'Na⁺ normal') + ' (' + b + ')', c: ['Na⁺ gradyanı ve E_Na değişir', 'faz 0 yükselme hızı/genliği ' + (up(a, b) ? '↑' : '↓'), 'ozmolalite → ADH ' + (up(a, b) ? '↑' : '↓')], r: 'B1.6' }),
  Ca: (a, b) => ({ t: (up(a, b) ? 'Ca²⁺ arttı' : 'Ca²⁺ azaldı') + ' (' + b + ')', c: up(a, b) ? ['L tipi kanaldan giriş ve CICR ↑', 'kasılma gücü ↑', 'plato kısalır → QT kısalır'] : ['Ca²⁺ girişi ↓ → kalp gevşek kalır (kontraktilite ↓)', 'ST/QT uzar'], r: 'B1.5, B1.6' }),
  Mg: (a, b) => ({ t: 'Magnezyum ' + (up(a, b) ? '↑' : '↓') + ' (' + b + ')', c: b > 2.5 ? ['L tipi Ca²⁺ kanallarının inhibisyonu ↑', 'Ca²⁺ girişi ↓ → miyokard deprese', 'AV iletim yavaşlar, KH ↓'] : ['Mg²⁺ normale yakın'], r: 'B1.6' }),
  naBlock: (a, b, e) => ({ t: 'Na⁺ kanal blokeri (' + e.p.naClass + ') ' + (up(a, b) ? '↑' : '↓'), c: ['Etki faz 0\'da: hızlı Na⁺ akımı ↓', 'faz 0 eğimi ve iletim hızı ↓', 'QRS genişler', e.p.naClass === 'IA' ? 'IA: AP ve ERP uzar → QT ↑' : e.p.naClass === 'IB' ? 'IB: AP kısalır (iskemik dokuda etkin)' : 'IC: QRS belirgin genişler, AP süresi değişmez', 'taşiaritmilerde antiaritmik'], r: 'B1.7' }),
  kBlock: (a, b) => ({ t: 'K⁺ kanal blokeri ' + (up(a, b) ? '↑' : '↓'), c: ['Etki faz 3\'te: gecikmiş düzeltici K⁺ akımı ↓', 'repolarizasyon gecikir → APD ve ERP ↑', 'QT uzar', 'hipokalemi ile birlikteyse torsades riski'], r: 'B1.7' }),
  verapamil: (a, b) => ({ t: 'Verapamil ' + (up(a, b) ? '↑' : '↓'), c: ['L tipi Ca²⁺ kanal blokajı (kalbe seçici)', 'SA düğüm faz 4 ve faz 0 yavaşlar → KH ↓', 'AV düğüm iletimi ↓ → PR ↑, AV refrakterliği ↑', 'CICR ↓ → kontraktilite ↓ (Frank–Starling eğrisi aşağı)', 'hafif periferik vazodilatasyon → MAP ↓'], r: 'B1.7, B6.4' }),
  diltiazem: (a, b) => ({ t: 'Diltiazem ' + (up(a, b) ? '↑' : '↓'), c: ['L tipi Ca²⁺ blokajı (ara profil)', 'AV iletim ↓, KH ↓', 'belirgin koroner vazodilatasyon', 'kontraktilite hafif ↓'], r: 'B1.7' }),
  nifedipine: (a, b) => ({ t: 'Nifedipin ' + (up(a, b) ? '↑' : '↓'), c: ['Dihidropiridin: damar düz kası L tipi kanalına seçici', 'arteriyol dilatasyonu → TPR ve art yük ↓', 'MAP ↓ → baroreseptör refleksi', 'refleks taşikardi, kontraktilite korunur/↑', 'AV iletim etkilenmez'], r: 'B1.7, B10.3' }),
  betaBlock: (a, b) => ({ t: 'β-bloker ' + (up(a, b) ? '↑' : '↓'), c: ['β₁ blokajı: cAMP ↓', 'Iƒ ve L-Ca²⁺ akımı ↓ → faz 4 eğimi ↓ → KH ↓', 'AV iletim ↓ (PR ↑)', 'kontraktilite ↓ (eğri aşağı)', 'böbrekte renin salınımı ↓', 'egzersizde KH yanıtı körelir'], r: 'B1.7, B6.8, B10.9' }),
  digoxin: (a, b, e) => ({ t: 'Digoksin ' + (up(a, b) ? '↑' : '↓'), c: ['Na⁺/K⁺-ATPaz inhibisyonu → hücre içi Na⁺ ↑', 'Na⁺/Ca²⁺ değiştirici ile Ca²⁺ atılımı ↓', 'hücre içi Ca²⁺ ↑ → pozitif inotropi (ESV ↓, EF ↑)', 'vagal tonus ↑ → AV iletim ↓', 'kaşık ST çökmesi, QT kısalır', e.p.K < 3.5 ? 'hipokalemi toksisiteyi artırır!' : 'hipokalemide toksisite riski'], r: 'B1.7' }),
  atropine: (a, b) => ({ t: 'Atropin ' + (up(a, b) ? '↑' : '↓'), c: ['M₂ reseptör blokajı', 'vagal etki kalkar: SA düğüm hiperpolarizasyonu ↓', 'KH ↑, AV iletim hızlanır (PR ↓)', 'barorefleks bradikardisi engellenir'], r: 'B2.2' }),
  noradrenaline: (a, b) => ({ t: 'Noradrenalin ' + (up(a, b) ? '↑' : '↓'), c: ['α₁ → arteriyol ve venokonstriksiyon (TPR ↑, ön yük ↑)', 'β₁ → kontraktilite ↑', 'MAP ↑ → baroreseptör → vagal ↑', 'KH değişmeyebilir ya da düşer (refleks)'], r: 'B8.10, B10.7' }),
  adrenaline: (a, b) => ({ t: 'Adrenalin ' + (up(a, b) ? '↑' : '↓'), c: ['β₁: KH ve kontraktilite ↑', 'β₂: iskelet kası ve koroner vazodilatasyon', 'yüksek dozda α₁ baskın → vazokonstriksiyon', 'net etki doza ve damar yatağına bağlı'], r: 'B8.10, B10.7' }),
  vasopressin: (a, b) => ({ t: 'Vazopressin ' + (up(a, b) ? '↑' : '↓'), c: ['V₂: toplayıcı kanalda su geri emilimi ↑', 'yüksek düzeyde V₁a: vazokonstriksiyon → TPR ↑'], r: 'B10.7' }),
  nitrate: (a, b) => ({ t: 'Nitrat (NO donörü) ' + (up(a, b) ? '↑' : '↓'), c: ['NO → çözünür guanilat siklaz → cGMP ↑ → düz kas gevşer', 'ağırlıklı venodilatasyon → venöz kapasitans ↑', 'ön yük (EDV, LVEDP) ↓ → miyokard O₂ ihtiyacı ↓', 'hafif arteriyol dilatasyonu'], r: 'B8.9, B9.4' }),
  diuretic: (a, b) => ({ t: 'Diüretik ' + (up(a, b) ? '↑' : '↓'), c: ['böbrekten Na⁺ ve su atılımı ↑', 'kan hacmi ve ön yük ↓ (saatler içinde)', 'CO ve MAP ↓', 'renin ↑ (kompansasyon)', 'K⁺ kaybı → hipokalemi riski'], r: 'B10.9' }),
  acei: (a, b) => ({ t: 'ACE inhibitörü ' + (up(a, b) ? '↑' : '↓'), c: ['Anjiyotensin I → II dönüşümü ↓', 'vazokonstriksiyon ↓ → TPR ↓', 'aldosteron ↓ → Na⁺/su tutulumu ↓', 'renin ↑ (negatif feedback kalkar)', 'bradikinin yıkımı ↓'], r: 'B10.8, B10.9' }),
  arb: (a, b) => ({ t: 'AT₁ reseptör blokeri ' + (up(a, b) ? '↑' : '↓'), c: ['Ang II etkisi reseptörde engellenir', 'TPR ↓, aldosteron ↓', 'renin ve Ang II düzeyi ↑'], r: 'B10.9' }),
  sympOffset: (a, b) => ({ t: 'Sempatik tonus ' + (up(a, b) ? '↑' : '↓'), c: up(a, b) ? ['NA → β₁: + krono, + dromo, + batmo, + ino, + lusiyotropi', 'α₁: arteriyol ve ven konstriksiyonu', 'KH, CO, TPR, MAP ↑'] : ['ters etkiler'], r: 'B2.2, B6.8' }),
  vagOffset: (a, b) => ({ t: 'Parasempatik tonus ' + (up(a, b) ? '↑' : '↓'), c: up(a, b) ? ['ACh → M₂ → K⁺ geçirgenliği ↑ → hiperpolarizasyon', 'prepotansiyel eğimi ↓ → KH ↓', 'AV iletim yavaşlar (PR ↑)', 'etki hızlı başlar, hızlı biter'] : ['KH ↑, PR ↓'], r: 'B2.2' }),
  baroOn: (a, b) => ({ t: b ? 'Baroreseptör refleksi açıldı' : 'Baroreseptör refleksi kapatıldı (denervasyon)', c: b ? ['Karotis (IX) ve aort (X) afferentleri → NTS → CVLM → RVLM ve n. ambiguus', 'kısa süreli basınç dalgalanmaları tamponlanır'] : ['Basınç değişiklikleri artık KH ve TPR ile düzeltilmez', 'ayağa kalkma, kanama, ilaçlarla basınç çok daha fazla dalgalanır'], r: 'B10.3' }),
  chemoOn: (a, b) => ({ t: 'Kemoreseptör refleksi ' + (b ? 'açık' : 'kapalı'), c: ['Karotis ve aort cisimcikleri: PaO₂ ↓, PCO₂ ↑, pH ↓ algılanır', 'ventilasyon ↑, sempatik ↑'], r: 'B10.4' }),
  cnsOn: (a, b) => ({ t: 'MSS iskemik yanıtı ' + (b ? 'açık' : 'kapalı'), c: ['CPP < ~60 mmHg → beyin sapında CO₂/H⁺ birikimi', 'çok güçlü sempatik deşarj (acil savunma)'], r: 'B10.5' }),
  cardiopulmOn: (a, b) => ({ t: 'Kardiyopulmoner reseptörler ' + (b ? 'açık' : 'kapalı'), c: ['Atriyum gerilmesi → Bainbridge (KH ↑)', 'ADH ↓ → diürez', 'ANP sekresyonu'], r: 'B10.6' }),
  raasOn: (a, b) => ({ t: 'RAAS ' + (b ? 'açık' : 'kapalı'), c: ['Renal perfüzyon ↓ / makula densaya NaCl ↓ / renal β₁ → renin', 'Ang II: vazokonstriksiyon; aldosteron: Na⁺ tutulumu'], r: 'B10.8' }),
  adhOn: (a, b) => ({ t: 'ADH ve susama ' + (b ? 'açık' : 'kapalı'), c: ['Hipovolemi, hipotansiyon, hiperozmolalite → ADH ↑', 'su geri emilimi ve alımı ↑'], r: 'B10.8' }),
  anpOn: (a, b) => ({ t: 'ANP/BNP ' + (b ? 'açık' : 'kapalı'), c: ['Atriyum/ventrikül gerilmesi → natriürez, diürez, vazodilatasyon', 'RAAS ve ADH baskılanır'], r: 'B10.8' }),
  natriOn: (a, b) => ({ t: 'Basınç natriürezi ' + (b ? 'açık' : 'kapalı'), c: ['Renal perfüzyon basıncı ↑ → Na⁺ ve su atılımı ↑', 'uzun süreli basınç kontrolünün en güçlü mekanizması'], r: 'B10.8' }),
  autoregOn: (a, b) => ({ t: 'Lokal otoregülasyon ' + (b ? 'açık' : 'kapalı'), c: ['Miyojenik (Laplace T = P × r; L tipi Ca²⁺) ve metabolik kontrol', 'beyin, kalp, böbrek akımı 60–160 mmHg arasında sabit tutulur'], r: 'B8.9' }),
  respOn: (a, b) => ({ t: 'Solunum ' + (b ? 'açık' : 'kapalı'), c: ['İnspirasyonda intratorasik basınç ↓ → sağ kalbe venöz dönüş ↑', 'vagal tonus inhibe → KH ↑ (solunumsal sinüs aritmisi)', 'P2 gecikir, A2 erkenleşir → S2 çiftleşmesi'], r: 'B3.6, B5.3' }),
  rhythm: (a, b) => ({ af: { t: 'Atriyal fibrilasyon', c: ['P yok, fibrilasyon dalgaları (300–600/dk)', 'AV düğüm refrakterliği ventrikül hızını sınırlar', 'tamamen düzensiz RR', 'atriyal katkı (~%15) kaybolur → EDV ve SV ↓', 'kısa RR\'lerde diyastol kısalır'], r: 'B3.6, B4.2' },
    flutter: { t: 'Atriyal flatter', c: ['Testere dişi F dalgaları ~300/dk', 'AV düğüm 2:1 iletir → ventrikül ~150/dk'], r: 'B3.6' },
    vt: { t: 'Ventriküler taşikardi', c: ['Ventrikül odağı ~175/dk, geniş QRS', 'AV disosiyasyon; dolum süresi kısa → SV ↓', 'MAP ↓ → sempatik ↑'], r: 'B3.6' },
    vf: { t: 'Ventriküler fibrilasyon', c: ['Organize depolarizasyon yok', 'etkili kasılma ve debi yok → MAP çöker', 'MSS iskemik yanıtı maksimal; defibrilasyon gerekir'], r: 'B3.6' },
    sinus: { t: 'Sinüs ritmi', c: ['SA düğüm → atriyum → AV düğüm → His–Purkinje → ventrikül'], r: 'B2.1' } })[b],
  avBlock: (a, b) => ({ '0': { t: 'AV blok kaldırıldı', c: ['Normal AV iletimi'], r: 'B3.6' },
    '1': { t: '1. derece AV blok', c: ['Her P iletilir ama gecikir: PR > 0,20 s', 'S1 yumuşar (kapak yaprakları kapanmadan önce birbirine yaklaşır)'], r: 'B3.6' },
    '2a': { t: 'Mobitz I (Wenckebach)', c: ['PR giderek uzar', 'bir P iletilmez (QRS düşer)', 'döngü tekrarlar'], r: 'B3.6' },
    '2b': { t: 'Mobitz II', c: ['PR sabit', 'aniden bir P iletilmez', 'daha distal (His) blok; ilerleme riski'], r: 'B3.6' },
    '3': { t: '3. derece (komplet) AV blok', c: ['Hiçbir atriyal uyarı ventriküle geçmez', 'idiyoventriküler kaçış ritmi (~35/dk, geniş QRS)', 'P ve QRS bağımsız', 'uzun diyastol → büyük SV ve nabız basıncı, ama CO ↓', 'baroreseptör: TPR ↑'], r: 'B3.6' } })[b],
  bbb: (a, b) => ({ '0': { t: 'Dal bloğu kalktı', c: ['İki ventrikül eş zamanlı uyarılır, dar QRS'], r: 'B3.6' },
    L: { t: 'Sol dal bloğu', c: ['Uyarı önce sağ ventriküle, sonra sola yayılır', 'QRS > 0,12 s, sol eksen sapması', 'V6\'da geniş R, V1\'de derin S; ST-T diskordan', 'LV gecikir → A2 gecikir (paradoks S2 çiftleşmesi)'], r: 'B3.6' },
    R: { t: 'Sağ dal bloğu', c: ['Sağ ventrikül gecikmeli uyarılır', 'V1\'de rSR\', DI ve V6\'da geniş S', 'sağ eksen eğilimi', 'P2 gecikir → S2 geniş çiftleşir'], r: 'B3.6' } })[b],
  ves: (a, b) => ({ t: 'Ventriküler ekstrasistol ' + (up(a, b) ? '↑' : '↓'), c: ['Erken gelen, geniş ve farklı şekilli QRS', 'sonraki sinüs uyarısı refrakter ventriküle düşer → kompansatuar pause', 'erken atımda dolum az → zayıf nabız'], r: 'B3.6' }),
  contractility: (a, b) => ({ t: 'Kontraktilite ' + (up(a, b) ? '↑ (pozitif inotropi)' : '↓ (negatif inotropi)'), c: up(a, b) ? ['ESPVR dikleşir', 'ESV ↓, SV ve EF ↑', 'Frank–Starling eğrisi yukarı (C eğrisi)'] : ['ESPVR yatıklaşır', 'ESV ↑, SV ve EF ↓', 'LVEDP ve LAP ↑ → pulmoner kapiller basınç ↑', 'CO ↓ → sempatik ↑, RAAS ↑ (sıvı tutulumu)'], r: 'B6.3, B6.7' }),
  hypertrophy: (a, b) => ({ '0': { t: 'Hipertrofi kalktı', c: ['Normal aks ve kompliyans'], r: 'B3.3' },
    LVH: { t: 'Sol ventrikül hipertrofisi', c: ['Kronik art yük (HT) → duvar kalınlaşır', 'kompliyans ↓ → aynı dolum için basınç ↑ (EDPVR dikleşir)', 'atriyal katkı önem kazanır → S4', 'sol eksen sapması, yüksek voltaj'], r: 'B3.3, B5.3, B6.5' },
    RVH: { t: 'Sağ ventrikül hipertrofisi', c: ['Pulmoner kapak stenozu → RV basınç yükü', 'sağ eksen sapması, V1\'de yüksek R'], r: 'B3.3' } })[b],
  stiffness: (a, b) => ({ t: 'Ventrikül sertliği ' + (up(a, b) ? '↑' : '↓'), c: up(a, b) ? ['Kompliyans = ΔV/ΔP ↓', 'aynı EDV için LVEDP ↑', 'erken dolum ↓, atriyal kasılma önem kazanır (S4)', 'LAP ↑ → akciğer kapiller basıncı ↑'] : ['dolum kolaylaşır'], r: 'B6.5' }),
  mi: (a, b) => ({ '0': { t: 'MI kalktı', c: [], r: 'B8.12' },
    ant: { t: 'Anterior MI', c: ['Sol ön inen arter tıkanır → transmural iskemi', 'V1–V4\'te ST elevasyonu', 'LV kontraktilitesi ↓, sertlik ↑', 'EF ↓, LVEDP ↑ → akciğer konjesyonu', 'CK-MB ve troponin yükselir'], r: 'B8.12' },
    inf: { t: 'İnferior MI', c: ['Sağ koroner (PDA) bölgesi', 'DII, DIII, aVF\'de ST elevasyonu, aVL\'de karşılık çökme', 'sağ ventrikül tutulumu olabilir (sağ göğüs derivasyonları)'], r: 'B8.12, B2.4' } })[b],
  corStenosis: (a, b) => ({ t: 'Koroner darlık ' + Math.round(b * 100) + '%', c: ['Seri direnç ↑ (r⁴)', 'koroner akım rezervi ↓', 'O₂ ihtiyacı (KH × SBP × kontraktilite) arzı aşınca iskemi', 'subendokardiyal iskemi → ST çökmesi, kontraktilite ↓', 'taşikardi diyastolü kısaltır → arz daha da ↓'], r: 'B7.9, B8.12' }),
  AS: (a, b) => ({ t: 'Aort stenozu ' + (up(a, b) ? '↑' : '↓'), c: ['Kapak alanı ↓ → çıkış direnci ↑ (art yük ↑)', 'LV–aort basınç gradyanı', 'ESV ↑, SV ↓', 'türbülan çıkış → sistolik crescendo-decrescendo üfürüm (sağ 2. aralık)', 'kronikte konsantrik hipertrofi, S4'], r: 'B5.5, B6.6' }),
  AR: (a, b) => ({ t: 'Aort yetersizliği ' + (up(a, b) ? '↑' : '↓'), c: ['Diyastolde aorttan LV\'ye geri akım', 'diyastolik basınç ↓', 'EDV ↑ → Frank–Starling ile büyük SV → sistolik basınç ↑', 'nabız basıncı çok geniş', 'diyastolik dekresendo üfürüm (Erb odağı)'], r: 'B5.5' }),
  MS: (a, b) => ({ t: 'Mitral stenoz ' + (up(a, b) ? '↑' : '↓'), c: ['Mitral alanı (normal 4–6 cm²) ↓ → diyastolik dolum direnci', 'LAP ↑ → pulmoner venöz/kapiller basınç ↑', 'LV dolumu ve SV ↓', 'diyastolik rulman (apeks) + açılma sesi', 'taşikardide (kısa diyastol) belirgin kötüleşme'], r: 'B5.2, B5.5' }),
  MR: (a, b) => ({ t: 'Mitral yetersizliği ' + (up(a, b) ? '↑' : '↓'), c: ['Sistolde kan LA\'ya kaçar', 'LAP ve v dalgası ↑ → akciğer ödemi', 'ileri debi ↓; toplam SV ve EF yüksek görünür', 'holosistolik üfürüm, apeks → aksilla'], r: 'B5.5' }),
  tamponade: (a, b) => ({ t: 'Perikard basıncı ' + b + ' mmHg', c: ['Tüm odaların transmural dolum basıncı ↓', 'EDV ve SV ↓ → CO ↓', 'CVP ve LAP yükselir, eşitlenir', 'inspirasyonda sistolik basınç düşüşü (pulsus paradoksus)', 'sempatik taşikardi'], r: 'B10.10' }),
  rBrain: (a, b) => bedWhy('Beyin', a, b), rCor: (a, b) => bedWhy('Koroner', a, b), rKidney: (a, b) => bedWhy('Böbrek', a, b),
  rMuscle: (a, b) => bedWhy('İskelet kası', a, b), rSkin: (a, b) => bedWhy('Deri', a, b), rSplanch: (a, b) => bedWhy('Splanknik', a, b),
  amputation: (a, b) => ({ t: b ? 'Bacak amputasyonu' : 'Amputasyon kaldırıldı', c: b ? ['Paralel yataklardan biri dolaşımdan çıkar', '1/Rt = 1/R1 + 1/R2 + … → toplam iletkenlik ↓', 'TPR ↑ (diğer koşullar sabitken)', 'diğer yatakların uyumu etkiyi sınırlar'] : [], r: 'B7.9' }),
  renalStenosis: (a, b) => ({ t: 'Renal arter darlığı ' + Math.round(b * 100) + '%', c: ['Darlık distalinde renal perfüzyon basıncı ↓', 'renin ↑ → Ang II ↑ (TPR ↑) → aldosteron ↑ (Na⁺/su tutulumu)', 'sekonder (renovasküler) hipertansiyon'], r: 'B10.8, B10.9' }),
  sepsis: (a, b) => ({ t: 'Sepsis ' + (up(a, b) ? '↑' : '↓'), c: ['İnflamatuvar mediyatörler, NO → yaygın vazodilatasyon', 'TPR ↓↓', 'kapiller geçirgenlik ↑ → sıvı damar dışına', 'ateş, taşikardi; CO yüksek/normal/düşük', 'laktat ↑'], r: 'B10.10' }),
  anaphylaxis: (a, b) => ({ t: 'Anafilaksi ' + (up(a, b) ? '↑' : '↓'), c: ['Histamin vb. → arteriyol ve ven dilatasyonu', 'TPR ↓, venöz göllenme → ön yük ↓', 'geçirgenlik ↑ → ödem', 'MAP ↓ → refleks taşikardi'], r: 'B10.10' }),
  venTone: (a, b) => ({ t: 'Venöz tonus ' + (up(a, b) ? '↑' : '↓'), c: up(a, b) ? ['Venöz kapasitans ↓ → kan merkeze', 'venöz dönüş, EDV, SV ↑'] : ['Venöz göllenme', 'ön yük ↓'], r: 'B8.5, B8.6' }),
  PaO2: (a, b) => ({ t: 'Arteriyel PO₂ ' + b + ' mmHg', c: b < 60 ? ['Periferik kemoreseptörler (karotis, aort cisimciği) uyarılır', 'ventilasyon ↑, sempatik ↑ → KH ↑', 'sistemik dokularda hipoksik vazodilatasyon', 'akciğerde alveoler hipoksi → vazokonstriksiyon → PAP ↑, RV art yükü ↑', 'SaO₂ ve CaO₂ ↓'] : ['Kemoreseptör uyarısı zayıf/yok', 'SaO₂ ≥ %90'], r: 'B8.9, B10.4' }),
  PaCO2: (a, b) => ({ t: 'PaCO₂ ' + b + ' mmHg', c: up(a, b) ? ['Beyin damarlarında vazodilatasyon (CO₂ en güçlü etken)', 'serebral kan hacmi ↑ → ICP ↑', 'kemoreseptör → ventilasyon ve sempatik ↑', 'asidoz → kontraktilite ↓'] : ['Serebral vazokonstriksiyon', 'serebral akım ve ICP ↓'], r: 'B8.11, B10.4' }),
  ICP: (a, b) => ({ t: 'İntrakraniyal basınç ' + b + ' mmHg', c: b > 20 ? ['CPP = MAP − ICP ↓', 'beyin sapı iskemisi → CO₂/H⁺ birikimi', 'güçlü sempatik → yaygın vazokonstriksiyon → MAP ↑', 'MAP ↑ → baroreseptör → vagal → bradikardi', 'solunum düzensizleşir = Cushing triadı'] : ['CPP normal'], r: 'B10.5' }),
  pe: (a, b) => ({ t: 'Pulmoner emboli ' + (up(a, b) ? '↑' : '↓'), c: ['Pulmoner damar direnci ↑', 'PAP ↑ → RV art yükü ↑ → RV genişler, CVP ↑', 'sol kalbe dönüş ↓ (LAP ↓) → CO ↓', 'ventilasyon-perfüzyon bozukluğu → PaO₂ ↓'], r: 'B7.10, B10.10' }),
  pneumo: (a, b) => ({ t: 'Tansiyon pnömotoraks ' + (up(a, b) ? '↑' : '↓'), c: ['Toraks içi basınç pozitif', 'venöz dönüş engellenir → ön yük ↓', 'CO ↓, CVP ↑', 'akciğer kollapsı → PaO₂ ↓'], r: 'B10.10' }),
  starling: (a, b) => ({ t: b === 'classic' ? 'Klasik Starling modeli' : 'Güncel (glikokaliks) yaklaşım', c: b === 'classic' ? ['Arteriyel uçta filtrasyon (+10), venöz uçta reabsorbsiyon (−9)'] : ['Endotel glikokaliksi temel bariyer', 'çoğu dokuda düşük düzeyde net filtrasyon sürer', 'venöz uçta sürekli reabsorbsiyon yok; fazla sıvıyı lenf taşır', 'ani Pc düşüşünde geçici reabsorbsiyon'], r: 'B9.3' }),
  perm: (a, b) => ({ t: 'Kapiller geçirgenlik ' + (up(a, b) ? '↑' : '↓'), c: ['Kf ↑, proteinler interstisyuma geçer (πif ↑, yansıtma katsayısı ↓)', 'filtrasyon ↑ → ödem', 'inflamasyon, yanık, sepsis, anafilaksi'], r: 'B9.6' }),
  lymph: (a, b) => ({ t: 'Lenfatik kapasite ' + (up(a, b) ? '↑' : '↓'), c: ['Filtre edilen sıvı ve protein lenf ile döner', 'kapasite aşılınca ödem (lenfödem)', 'kanser cerrahisi, elefantiazis'], r: 'B9.5, B9.6' }),
  venExtra: (a, b) => ({ t: 'Ek venöz basınç ' + b + ' mmHg', c: ['Venöz uç ve ortalama kapiller hidrostatik basınç (Pc) ↑', 'net filtrasyon ↑ → ödem', 'gebelikte uterusun venlere basısı, sağ KY'], r: 'B9.6' }),
  naClass: (a, b) => ({ t: 'Na⁺ bloker sınıfı: ' + b, c: [b === 'IA' ? 'IA: orta Na⁺ blokajı + K⁺ blokajı → AP ve QT uzar' : b === 'IB' ? 'IB: hızlı ayrışır, AP kısalır; iskemik ventrikülde etkili' : 'IC: güçlü Na⁺ blokajı, QRS belirgin genişler'], r: 'B1.7' }),
};
function bedWhy(name, a, b) { const k = Math.pow(b, 4); return { t: name + ' arteriyol yarıçapı ×' + b.toFixed(2), c: ['Poiseuille: R ∝ 1/r⁴ → direnç ×' + (1 / k).toFixed(2), 'paralel yatakta akım ' + (b > a ? 'artar' : 'azalır') + ' (aynı ΔP)', 'TPR ' + (b > a ? 'azalır' : 'artar'), 'r yarıya inerse direnç 16 kat artar'], r: 'B7.7, B7.9' }; }
const ACTIONS = {
  hem500: { t: '500 ml kanama', c: ['Kan hacmi ↓ → venöz dönüş ↓ → EDV, SV ↓', 'MAP ↓ → baroreseptör → KH ↑, TPR ↑, venokonstriksiyon', 'kapiller basınç ↓ → interstisyumdan sıvı geri emilir', 'ADH ↑, RAAS ↑ (saatler)'], r: 'B10.3' },
  hem1000: { t: '1000 ml kanama', c: ['Kan hacmi ↓ %20 → CVP, EDV, SV ↓', 'MAP ↓ → güçlü sempatik yanıt: taşikardi, TPR ↑', 'renal perfüzyon ↓ → renin ↑, idrar ↓', 'ADH ve susama ↑', 'geri dolum hematokriti seyreltir'], r: 'B10.3, B10.10' },
  cryst: { t: '1000 ml kristaloid', c: ['Plazma hacmi ↑, plazma proteinleri seyrelir (πc ↓)', 'CVP ↑ → Bainbridge: KH ↑; ANP ↑, ADH ↓', 'filtrasyon ↑ → sıvının ~2/3\'ü interstisyuma geçer', 'basınç natriürezi ile atılım'], r: 'B9.3, B10.6' },
  transf: { t: '500 ml tam kan', c: ['Hem plazma hem eritrosit ↑', 'ön yük ↑ → Frank–Starling', 'O₂ taşıma kapasitesi korunur'], r: 'B6.4' },
  valsalva: { t: 'Valsalva manevrası', c: ['Faz I: intratorasik basınç ↑ → aort sıkışır → basınç ↑, refleks bradikardi', 'Faz II: venöz dönüş ↓ → CO ve basınç ↓ → taşikardi', 'Faz III: zorlanma bırakılınca basınç kısa süre ↓', 'Faz IV: venöz dönüş geri gelir, damarlar dar → basınç overshoot, refleks bradikardi'], r: 'B10.3' },
  carotid: { t: 'Karotis sinüs masajı', c: ['Mekanik uyarı → baroreseptör deşarjı ↑', 'NTS → sempatik ↓, vagal (n. ambiguus) ↑', 'KH ↓, AV iletim yavaşlar, TPR ↓', 'SVT\'de ilk basamak vagal manevra'], r: 'B10.3' },
};

/* --- Şu an etkin mekanizmalar (canlı) --- */
function active(e) {
  const s = e.s, m = s.m, p = e.p, d = e.derived, L = [];
  const add = (lv, h) => L.push({ lv, h });
  const pct = x => Math.round(x * 100);
  if (p.baroOn) { const dir = s.baroB < 0.42 ? 'deşarj ↓ → sempatik ↑' : s.baroB > 0.58 ? 'deşarj ↑ → vagal ↑' : 'denge'; add(s.baroB < 0.35 || s.baroB > 0.65 ? 'w' : 'g', `<b>Baroreseptör</b>: ${dir} (set ${Math.round(s.baroSet)} mmHg)`); }
  else add('c', '<b>Baroreseptör refleksi kapalı</b>');
  add('g', `<b>Otonom</b>: sempatik ${pct(s.S)}% · vagal ${pct(s.Veff)}%`);
  if (s.chemo > 0.15) add('w', `<b>Kemoreseptör</b> uyarısı (PaO₂ ${Math.round(s.PaO2)}, PCO₂ ${p.PaCO2})`);
  if (s.cnsI > 0.1) add('c', `<b>MSS iskemik yanıt</b>: CPP ${Math.round(m.CPP)} mmHg`);
  if (s.cnsI > 0.2 && m.HR < 65 && m.MAP > 100) add('c', '<b>Cushing triadı</b>: HT + bradikardi + düzensiz solunum');
  if (s.bain > 0.15) add('w', `<b>Bainbridge</b>: CVP ${m.CVP.toFixed(1)} → KH ↑`);
  if (Math.abs(s.angII - 1) > 0.25) add(s.angII > 1 ? 'w' : 'g', `<b>RAAS</b>: Ang II ×${s.angII.toFixed(2)}, aldosteron ×${s.aldo.toFixed(2)}`);
  if (Math.abs(s.adhTot - 1) > 0.3) add(s.adhTot > 1 ? 'w' : 'g', `<b>ADH</b> ×${s.adhTot.toFixed(1)}${s.adhTot > 3 ? ' (V₁ vazokonstriksiyon)' : ''}`);
  if (s.anp > 1.3) add('w', `<b>ANP</b> ×${s.anp.toFixed(1)} (atriyum gerilmesi)`);
  const autoreg = ['brain', 'kidney', 'cor', 'muscle'].filter(k => Math.abs(s.rAuto[k] - 1) > 0.06).map(k => ({ brain: 'beyin', kidney: 'böbrek', cor: 'koroner', muscle: 'kas' })[k] + (s.rAuto[k] > 1 ? ' dilatasyon' : ' konstriksiyon'));
  if (autoreg.length) add('g', '<b>Otoregülasyon</b>: ' + autoreg.join(', '));
  if (s.ischemia > 0.3) add('c', `<b>Miyokard iskemisi</b>: O₂ ihtiyacı/arz ${(s.corDemand / Math.max(s.corSupplyMax, 0.05)).toFixed(2)}`);
  if (s.dVi > 1500) add(s.dVi > 4000 ? 'c' : 'w', `<b>Ödem</b>: interstisyel sıvı +${(s.dVi / 1000).toFixed(1)} L`);
  if (s.dVlung > 150) add('c', `<b>Akciğer ödemi</b> (${s.dVlung > 450 ? 'alveoler' : 'interstisyel'}), Pc akciğer ${s.PcL.toFixed(0)} mmHg`);
  if (s.legEdema > 300) add('w', '<b>Bacak ödemi</b> (ayakta hidrostatik basınç)');
  if (s.transReab > 1) add('g', `<b>Transkapiller geri dolum</b>: ${s.transReab.toFixed(1)} ml/dk`);
  if (d.tdpRisk) add('c', '<b>QT uzun – torsades riski</b>');
  if (d.digToxic) add('c', '<b>Digoksin toksisitesi riski</b>');
  if (s.lactate > 3) add('c', `<b>Laktik asidoz</b>: laktat ${s.lactate.toFixed(1)} mmol/L, pH ${s.pH.toFixed(2)}`);
  if (s.urine < 0.35) add('w', `<b>Oligüri</b>: ${Math.round(s.urine * 60)} ml/sa`);
  if (s.remodel > 1.03) add('w', '<b>Vasküler yeniden yapılanma</b> (kronik HT)');
  return L;
}

global.KVSData = { PRESETS, CASES, WHY: W, ACTIONS, active };
})(typeof window !== 'undefined' ? window : globalThis);
