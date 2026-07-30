// Porta JS di lib/core/utils/elevation_processor.dart.
//
// Serve agli script di manutenzione del catalogo, che girano in Node e non
// possono usare la classe Dart. La logica DEVE restare identica: se l'app e lo
// script calcolassero il dislivello in modo diverso avremmo di nuovo due
// numeri per lo stesso percorso, che e' il problema che stiamo chiudendo.
//
// Validata contro l'implementazione Dart reale su 355 sentieri del catalogo
// (vedi scripts/validate_elevation_port.cjs): deve combaciare al metro.
//
// Se modifichi elevation_processor.dart, rilancia la validazione.

/// Preset per attività, allineati a ElevationProcessor.forActivity().
const PRESET = {
  cycling:      { hysteresisThreshold: 3.0, smoothingWindow: 7, maxElevationChangePerPoint: 30.0, medianWindow: 11 },
  trailrunning: { hysteresisThreshold: 3.0, smoothingWindow: 7, maxElevationChangePerPoint: 40.0, medianWindow: 11 },
  _default:     { hysteresisThreshold: 4.0, smoothingWindow: 7, maxElevationChangePerPoint: 50.0, medianWindow: 11 },
};

function forActivity(activityType) {
  const k = String(activityType || '').toLowerCase();
  return PRESET[k] || PRESET._default;
}

/// Divisione intera troncata: l'equivalente di `~/` in Dart.
const idiv = (a, b) => Math.trunc(a / b);

function applyMedianFilter(e, windowSize) {
  if (e.length <= windowSize) return e.slice();
  const w = windowSize % 2 === 1 ? windowSize : windowSize + 1;
  const halfW = idiv(w, 2);
  const result = e.slice();
  for (let i = halfW; i < e.length - halfW; i++) {
    const win = e.slice(i - halfW, i + halfW + 1).sort((a, b) => a - b);
    result[i] = win[idiv(win.length, 2)];
  }
  return result;
}

function removeSpikes(e, cfg) {
  if (e.length < 3) return e.slice();
  const maxCh = cfg.maxElevationChangePerPoint;
  const result = e.slice();
  for (let i = 1; i < e.length - 1; i++) {
    // ATTENZIONE: prev viene da `result` (effetto a cascata sulle correzioni
    // già fatte) mentre curr e next vengono dall'array ORIGINALE. E' cosi'
    // anche nel Dart: cambiarlo cambierebbe i numeri.
    const prev = result[i - 1];
    const curr = e[i];
    const next = e[i + 1];
    const dPrev = Math.abs(curr - prev);
    const dNext = Math.abs(curr - next);
    const dPrevNext = Math.abs(next - prev);

    if (dPrev > maxCh && dNext > maxCh && dPrevNext < maxCh) {
      result[i] = (prev + next) / 2;
      continue;
    }
    if (dPrev > maxCh * 0.7) {
      const windowSize = Math.min(cfg.smoothingWindow, e.length);
      const start = Math.max(0, i - idiv(windowSize, 2));
      const end = Math.min(e.length, i + idiv(windowSize, 2) + 1);
      const win = e.slice(start, end).sort((a, b) => a - b);
      const median = win[idiv(win.length, 2)];
      if (Math.abs(curr - median) > maxCh * 0.5) result[i] = median;
    }
  }
  return result;
}

function applySmoothing(e, cfg) {
  if (e.length <= cfg.smoothingWindow) return e.slice();
  const halfWindow = idiv(cfg.smoothingWindow, 2);
  const result = new Array(e.length).fill(0);
  for (let i = 0; i < e.length; i++) {
    let sum = 0, tot = 0;
    for (let j = -halfWindow; j <= halfWindow; j++) {
      const idx = i + j;
      if (idx >= 0 && idx < e.length) {
        const weight = halfWindow + 1 - Math.abs(j); // triangolare
        sum += e[idx] * weight;
        tot += weight;
      }
    }
    result[i] = sum / tot;
  }
  return result;
}

/// Isteresi a riferimento mobile: registra gain/loss solo all'inversione che
/// supera la soglia. E' il punto che rende il calcolo indipendente dalla
/// densita' di campionamento.
function calculateWithHysteresis(e, cfg) {
  if (e.length < 2) return { gain: 0, loss: 0 };
  const th = cfg.hysteresisThreshold;
  let totalGain = 0, totalLoss = 0;
  let reference = e[0];
  let direction = 0;
  let extreme = e[0];

  for (let i = 1; i < e.length; i++) {
    const current = e[i];
    if (direction === 0) {
      const diff = current - reference;
      if (diff > th) { direction = 1; extreme = current; }
      else if (diff < -th) { direction = -1; extreme = current; }
    } else if (direction === 1) {
      if (current > extreme) extreme = current;
      else if (extreme - current > th) {
        totalGain += extreme - reference;
        reference = extreme;
        direction = -1;
        extreme = current;
      }
    } else {
      if (current < extreme) extreme = current;
      else if (current - extreme > th) {
        totalLoss += reference - extreme;
        reference = extreme;
        direction = 1;
        extreme = current;
      }
    }
  }
  if (direction === 1) {
    const lastGain = extreme - reference;
    if (lastGain > th) totalGain += lastGain;
  } else if (direction === -1) {
    const lastLoss = reference - extreme;
    if (lastLoss > th) totalLoss += lastLoss;
  }
  return { gain: totalGain, loss: totalLoss };
}

/// Equivalente di ElevationProcessor.process(): accetta quote nullable.
/// Ritorna { elevationGain, elevationLoss, minElevation, maxElevation, punti }
/// oppure null se non ci sono quote valide.
function process(rawElevations, activityType) {
  const cfg = forActivity(activityType);
  const valid = [];
  for (const v of rawElevations) {
    if (v !== null && v !== undefined && Number.isFinite(v)) valid.push(v);
  }
  if (valid.length === 0) return null;
  if (valid.length === 1) {
    return { elevationGain: 0, elevationLoss: 0, minElevation: valid[0], maxElevation: valid[0], punti: 1 };
  }

  const medianFiltered = cfg.medianWindow > 0 ? applyMedianFilter(valid, cfg.medianWindow) : valid;
  const despiked = removeSpikes(medianFiltered, cfg);
  const smoothed = applySmoothing(despiked, cfg);
  const stats = calculateWithHysteresis(smoothed, cfg);

  return {
    elevationGain: stats.gain,
    elevationLoss: stats.loss,
    minElevation: Math.min(...smoothed),
    maxElevation: Math.max(...smoothed),
    punti: valid.length,
  };
}

module.exports = { process, forActivity, PRESET };
