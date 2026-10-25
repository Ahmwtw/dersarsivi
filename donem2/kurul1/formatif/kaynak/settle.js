/* =====================================================================
   ÖĞRENCİ MODU — aşamalı denge hesabı (DOM'a dokunmaz)
   A: ilk etki (refleksler devreye girmeden)
   B: sinir sistemi + hormonlar (dakikalar-saatler)
   C: böbrek, sıvı, ödem, baroreseptör ayarı (günler)
   ===================================================================== */
(function (global) {
'use strict';
const E = global.KVSEngine;
const BEDK = ['brain', 'cor', 'kidney', 'muscle', 'skin', 'splanch', 'other'];

function grab(e) {
  const s = e.s, m = s.m, d = e.derived;
  const o = {
    HR: m.HR, SBP: m.SBP, DBP: m.DBP, MAP: m.MAP, CVP: m.CVP, LAP: m.LAP, PAs: m.PAs, PAd: m.PAd, PAm: m.PAm,
    CO: m.CO, SV: m.SV, EDV: m.EDV, ESV: m.ESV, EF: m.EF * 100, LVEDP: m.LVEDP, LVSP: m.LVSP || 0,
    PR: m.PR * 1000, QRS: m.QRS * 1000, QTc: m.QTc * 1000, axis: m.axis,
    TPR: s.TPR * 1000 / 60, PVR: s.PVR * 1000 / 60, SaO2: s.SaO2 * 100, PaO2: s.PaO2, SvO2: s.SvO2 * 100, pH: s.pH, lactate: s.lactate,
    ICP: m.ICP, CPP: m.CPP,
    S: s.S * 100, V: s.V * 100, Sb: s.Sb, epi: s.epi, baro: s.baroB * 100, chemo: s.chemo, cns: s.cnsI, bain: s.bain,
    renin: s.renin, angII: s.angII, aldo: s.aldo, adh: s.adhTot, anp: s.anp, urine: s.urine,
    BV: e.bloodVolume(), Hct: d.hct * 100, visc: d.viscF, alb: d.alb, piC: d.piC,
    Jsys: s.Jsys, Lsys: s.Lsys, PcA: s.PcA, PcV: s.PcV, dVi: s.dVi, dVlung: s.dVlung, legEdema: s.legEdema,
    contr: s.contrNow, venTone: s.V0sv, isch: s.ischemia * 100, renalPP: s.renalPP,
    vRest: d.vRest, apd: d.apd * 1000, naAvail: d.naAvail * 100, saSlope: d.saSlope || 0, Re: m.Re,
    RR: 12 * (1 + 0.8 * s.chemo + 1.3 * e.p.exercise),
  };
  for (const k of BEDK) { o['q_' + k] = s.bedQ[k] || 0; o['_ra_' + k] = s.rAuto[k]; }
  o._Sbase = s.Sbase == null ? 0.25 : s.Sbase; o._V = s.V; o._cnsS = s.cnsS || 0; o._epi = s.epi; o._isch = s.ischemia;
  return o;
}
/* sec saniye çalıştır, son avgSec saniyenin ortalamasını al */
function runAvg(e, sec, avgSec) {
  const step = 0.05;
  for (let t = 0; t < sec - avgSec; t += step) e.advance(step);
  const acc = {}; let n = 0;
  for (let t = 0; t < avgSec; t += step) {
    e.advance(step);
    if ((Math.round(t / step) % 4) === 0) { const g = grab(e); for (const k in g) acc[k] = (acc[k] || 0) + g[k]; n++; }
  }
  for (const k in acc) acc[k] /= n;
  // anlık olması gerekenler
  const g = grab(e); ['BV', 'Hct', 'alb', 'piC', 'renin', 'angII', 'aldo', 'adh', 'anp', 'dVi', 'dVlung', 'legEdema', 'vRest', 'naAvail', 'apd'].forEach(k => acc[k] = g[k]);
  return acc;
}
/* donmuş motoru ortalama otonom duruma oturt (solunum dalgalanması olmadan) */
function freezeAt(e, a) {
  const s = e.s;
  s.Sbase = a._Sbase; s.V = a._V; s.cnsS = a._cnsS; s.epi = a._epi; s.ischemia = a._isch;
  for (const k of BEDK) s.rAuto[k] = a['_ra_' + k];
  e.hold = { auto: true, hum: true, fluid: true }; e.speed = 1;
  return e;
}
/* parçalı çalıştırıcı: iş adımlarını (gen) setTimeout ile böler */
function* plan(base, mutate, opt) {
  opt = opt || {};
  const e = base.clone();
  e.hold = { auto: true, hum: true, fluid: true }; e.speed = 1;
  mutate(e);
  if (opt.onlyC) { yield* longPhase(e); return; }
  // A — ilk etki
  yield { stage: 'A0' };
  const A = runAvg(e, opt.aSec || 7, 2.5);
  const eA = e.clone();
  yield { stage: 'A', snap: A, eng: eA };
  // B — refleksler + hormonlar
  e.hold = { auto: false, hum: false, fluid: true }; e.speed = 400;
  for (let i = 0; i < 6; i++) { runAvg(e, 4, 0.1); yield { stage: 'B0', prog: i / 7 }; }
  const B = runAvg(e, 4, 3);
  const eB = freezeAt(e.clone(), B);
  yield { stage: 'B0', prog: 1 };
  const Bf = runAvg(eB, 3.5, 3); // donmuş motorun kendi ortalaması = ekranda kalacak değerler
  yield { stage: 'B', snap: Bf, eng: eB };
  if (!opt.long) return;
  yield* longPhase(e);
}
function* longPhase(e) {
  // C — uzun vade (böbrek, sıvı, ödem, baroreseptör ayarı)
  e.hold = { auto: false, hum: false, fluid: false }; e.speed = 3000;
  for (let i = 0; i < 10; i++) { runAvg(e, 4, 0.1); yield { stage: 'C0', prog: i / 11 }; }
  e.speed = 600; const C = runAvg(e, 6, 3);
  const eC = freezeAt(e.clone(), C);
  const Cf = runAvg(eC, 3.5, 3);
  yield { stage: 'C', snap: Cf, eng: eC };
}
/* senkron (test için) */
function settleSync(base, mutate, opt) {
  const out = {}; for (const st of plan(base, mutate, opt)) { if (st.snap) out[st.stage] = { snap: st.snap, eng: st.eng }; }
  return out;
}
global.KVSSettle = { grab, runAvg, plan, settleSync, freezeAt };
})(typeof window !== 'undefined' ? window : globalThis);
