// The playground's script: loads GPKit's module, hands it the pasted text, the place and the time, and shows its
// JSON answers. Every figure shown is GPKit's; the page only formats them (and subtracts two of GPKit's times for a
// duration and an age). No request but the page's own files; nothing stored.
'use strict';

const EXAMPLES = {
  iss: 'ISS (ZARYA)\n1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    10\n2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05\n',
  omm: 'OBJECT_NAME,OBJECT_ID,EPOCH,MEAN_MOTION,ECCENTRICITY,INCLINATION,RA_OF_ASC_NODE,ARG_OF_PERICENTER,MEAN_ANOMALY,EPHEMERIS_TYPE,CLASSIFICATION_TYPE,NORAD_CAT_ID,ELEMENT_SET_NO,REV_AT_EPOCH,BSTAR,MEAN_MOTION_DOT,MEAN_MOTION_DDOT\nISS (ZARYA),1998-067A,1998-11-20T06:49:59.999808,16.05064833,.0125362,51.5908,168.3788,86.4185,359.7454,0,U,25544,1,0,0,-.3657E-4,.11563E-4\n',
  alpha5: 'SARAMAGO\n1 A0000U 26067CY  26195.90649229  .00004770  00000+0  22159-3 0  9994\n2 A0000  97.4593 154.0970 0005590 270.5113  89.5482 15.20467281 15911\n',
  molniya: 'MOLNIYA 2-14\n1 08195U 75081A   06176.33215444  .00000099  00000-0  11873-3 0   813\n2 08195  64.1586 279.0717 6877146 264.7651  20.2257  2.00491383225656\n',
  refused: 'ISS (ZARYA)\n1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    11\n2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05\n',
};
// [name, latitude, longitude, height in metres, roughly]
const CITIES = [
  ['London', 51.5074, -0.1278, 11], ['New York', 40.7128, -74.006, 10], ['São Paulo', -23.5505, -46.6333, 760],
  ['Nairobi', -1.2921, 36.8219, 1795], ['Tokyo', 35.6762, 139.6503, 40], ['Sydney', -33.8688, 151.2093, 58],
];

const $ = (id) => document.getElementById(id);
const enc = new TextEncoder();
const dec = new TextDecoder();
let gp = null;            // the module's exports
let text = { value: null, ptr: 0, len: 0 };
let chosen = 0;           // the index of the element set shown
let epochUnix = null;     // its epoch, seconds from 1970
let ticker = null;

// WASI, as far as a reactor with no files and no clock needs: every call says "not supported" but these few
const ENOSYS = 52, EBADF = 8;
function wasi(memory) {
  const view = () => new DataView(memory().buffer);
  const no = () => ENOSYS;
  return {
    args_sizes_get: (c, s) => { view().setUint32(c, 0, true); view().setUint32(s, 0, true); return 0; },
    environ_sizes_get: (c, s) => { view().setUint32(c, 0, true); view().setUint32(s, 0, true); return 0; },
    args_get: () => 0, environ_get: () => 0,
    fd_prestat_get: () => EBADF, fd_prestat_dir_name: () => EBADF, fd_fdstat_get: () => EBADF,
    fd_write: (fd, iovs, n, written) => {
      const v = view(); let total = 0, out = '';
      for (let i = 0; i < n; i++) {
        const p = v.getUint32(iovs + 8 * i, true), l = v.getUint32(iovs + 8 * i + 4, true);
        out += dec.decode(new Uint8Array(memory().buffer, p, l)); total += l;
      }
      console.warn('GPKit:', out); v.setUint32(written, total, true); return 0;
    },
    random_get: (p, l) => { crypto.getRandomValues(new Uint8Array(memory().buffer, p, l)); return 0; },
    proc_exit: (code) => { throw new Error('the module stopped (' + code + ')'); },
    clock_res_get: no, clock_time_get: no, fd_close: no, fd_read: no, fd_seek: no, path_open: no, poll_oneoff: no,
  };
}

async function load() {
  let memory = null;
  const imports = { wasi_snapshot_preview1: wasi(() => memory) };
  const response = fetch('gpkit-playground.wasm');
  let made;
  try { made = await WebAssembly.instantiateStreaming(response, imports); }
  catch { made = await WebAssembly.instantiate(await (await response).arrayBuffer(), imports); }
  gp = made.instance.exports; memory = gp.memory;
  gp._initialize();
}

function answer(size) {
  const at = gp.gpkit_answer();
  return JSON.parse(dec.decode(new Uint8Array(gp.memory.buffer, at, size)));
}
function setText(value) {
  if (text.value === value) return;
  if (text.ptr) gp.gpkit_free(text.ptr);
  const bytes = enc.encode(value);
  const ptr = gp.gpkit_alloc(bytes.length);
  new Uint8Array(gp.memory.buffer, ptr, bytes.length).set(bytes);
  text = { value, ptr, len: bytes.length };
}
const place = () => [Number($('lat').value), Number($('lon').value), Number($('height').value) || 0];
const nowAt = (t) => answer(gp.gpkit_now(text.ptr, text.len, chosen, ...place(), t));

// formatting only
const fixed = (x, n) => (x === null || x === undefined) ? '–' : Number(x).toFixed(n);
const utc = (unix) => new Date(unix * 1000).toISOString().replace('T', ' ').slice(0, 19) + ' UTC';
const local = (unix) => new Date(unix * 1000).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'medium' });
const when = (unix) => `${local(unix)} <span class="utc">(${utc(unix)})</span>`;
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
function refusal(r) {
  return `<p class="refusal"><strong>GPKit refuses it: ${esc(r.kind)}.</strong> ${esc(r.message)}` +
    (r.line ? ` (line ${r.line} of the text)` : '') + '</p>';
}
const row = (name, value) => `<tr><th scope="row">${name}</th><td>${value}</td></tr>`;

function showRead() {
  setText($('text').value);
  const a = answer(gp.gpkit_read(text.ptr, text.len));
  const out = $('read');
  epochUnix = null;
  if (a.refusal) { out.innerHTML = `<p>Read as ${esc(a.format)}.</p>` + refusal(a.refusal); return false; }
  const sets = a.entries.filter((e) => e.set);
  if (chosen >= sets.length) chosen = 0;
  let html = `<p>Read as ${esc(a.format)}: ${sets.length} element set${sets.length === 1 ? '' : 's'}` +
    (a.entries.length > sets.length ? `, ${a.entries.length - sets.length} refused` : '') + '.</p>';
  for (const e of a.entries) if (e.refusal) html += refusal(e.refusal);
  if (sets.length > 1) {
    html += '<p><label for="which">Show</label> <select id="which">' +
      sets.map((e) => `<option value="${e.index}"${e.index === chosen ? ' selected' : ''}>${esc(e.set.object_name ?? e.set.catalog_number)}</option>`).join('') + '</select></p>';
  }
  const e = sets.find((x) => x.index === chosen);
  if (e) {
    const s = e.set;
    html += '<table>' + row('Name', esc(s.object_name ?? '–')) + row('Catalog number', esc(s.catalog_number ?? '–')) +
      row('International designator', esc(s.object_id ?? '–')) + row('Epoch', esc(s.epoch)) +
      row('Mean motion, revolutions a day', esc(s.mean_motion)) + row('Eccentricity', esc(s.eccentricity)) +
      row('Inclination, degrees', esc(s.inclination)) + row('Right ascension of the node, degrees', esc(s.right_ascension)) +
      row('Argument of pericentre, degrees', esc(s.argument_of_pericenter)) + row('Mean anomaly, degrees', esc(s.mean_anomaly)) +
      row('B*', esc(s.bstar)) + '</table>';
    html += e.tle.refusal ? '<p>The TLE GPKit would write:</p>' + refusal(e.tle.refusal)
      : `<p>The TLE GPKit writes for it:</p><pre>${esc(e.tle.line1)}\n${esc(e.tle.line2)}</pre>`;
    epochUnix = s.epoch_unix;
  }
  out.innerHTML = html;
  const which = $('which');
  if (which) which.addEventListener('change', () => { chosen = Number(which.value); update(); });
  return Boolean(e);
}

const from = () => document.querySelector('input[name="from"]:checked').value;
const start = () => (from() === 'now' || epochUnix === null) ? Date.now() / 1000 : epochUnix;

function showNow() {
  const a = nowAt(start());
  if (a.problem || a.failure) { $('now').innerHTML = `<p class="refusal">${esc(a.problem ?? a.failure.message)}</p>`; return; }
  const l = a.look, b = a.beneath, s = a.light;
  $('now').innerHTML = `<p>${when(a.time.unix)}${epochUnix !== null ? `, ${fixed((a.time.unix - epochUnix) / 86400, 2)} days from the epoch` : ''}</p><table>` +
    row('Azimuth, degrees', fixed(l.azimuth, 2)) + row('Elevation, degrees', fixed(l.elevation, 2)) +
    row('Range, km', fixed(l.range, 1)) + row('Range rate, km/s', fixed(l.range_rate, 3)) +
    row('Beneath it', `${fixed(b.latitude, 3)}° N, ${fixed(b.longitude, 3)}° E, ${fixed(b.altitude, 1)} km up`) +
    row('Your sky', esc(s.sky) + `, the Sun ${fixed(s.sun_elevation, 1)}° up`) +
    row('Sunlit', s.sunlit ? 'yes' : 'no') + row('Can be seen', s.can_be_seen ? 'yes' : 'no') + '</table>';
}

let passes = [];
function showPasses() {
  const a = answer(gp.gpkit_passes(text.ptr, text.len, chosen, ...place(), start(), 86400, Number($('above').value) || 0));
  passes = a.passes ?? [];
  let html = a.problem ? `<p class="refusal">${esc(a.problem)}</p>` : '';
  if (!a.problem && passes.length === 0) html += '<p>No pass above that elevation in these 24 hours.</p>';
  if (passes.length) {
    html += '<table class="passes"><caption>Times in your browser\'s time zone, UTC beside them</caption><thead><tr><th scope="col">Rises</th><th scope="col">Highest</th><th scope="col">Sets</th><th scope="col">Minutes</th><th scope="col">Can be seen</th><th scope="col"><span class="sr">Sky chart</span></th></tr></thead><tbody>';
    passes.forEach((p, i) => {
      const c = p.culmination;
      html += `<tr><td>${p.rise ? when(p.rise.time.unix) : 'already up'}</td>` +
        `<td>${c ? `${when(c.time.unix)}, ${fixed(c.look.elevation, 1)}° up at ${fixed(c.look.azimuth, 0)}°` : '–'}</td>` +
        `<td>${p.set ? when(p.set.time.unix) : 'still up'}</td>` +
        `<td>${p.rise && p.set ? fixed((p.set.time.unix - p.rise.time.unix) / 60, 1) : '–'}</td>` +
        `<td>${p.visible ? `from ${local(p.visible.start.unix)} to ${local(p.visible.end.unix)}` : 'no'}</td>` +
        `<td>${p.rise && p.set ? `<button type="button" data-chart="${i}">Sky chart</button>` : ''}</td></tr>`;
    });
    html += '</tbody></table>';
  }
  if (a.failure) html += `<p class="refusal">The search stopped: ${esc(a.failure.failure?.message ?? '')}</p>`;
  $('passes').innerHTML = html;
  $('chart').innerHTML = '';
}

// one pass as a sky chart: GPKit's look every few seconds from rise to set, the zenith at the centre, north up
function showChart(i) {
  const p = passes[i], t0 = p.rise.time.unix, t1 = p.set.time.unix, n = 60, r = 140, c = 160;
  const pt = (az, el) => { const d = r * (90 - Math.max(el, 0)) / 90, a = az * Math.PI / 180; return [c + d * Math.sin(a), c - d * Math.cos(a)]; };
  const path = [];
  for (let k = 0; k <= n; k++) {
    const a = nowAt(t0 + (t1 - t0) * k / n);
    if (a.look) path.push(pt(a.look.azimuth, a.look.elevation).map((x) => x.toFixed(1)).join(','));
  }
  const ring = (el) => `<circle cx="${c}" cy="${c}" r="${r * (90 - el) / 90}" class="ring"/>`;
  const [hx, hy] = pt(p.culmination.look.azimuth, p.culmination.look.elevation);
  $('chart').innerHTML = `<figure><svg viewBox="0 0 320 320" role="img" aria-label="The pass from ${esc(local(t0))} to ${esc(local(t1))}, highest ${fixed(p.culmination.look.elevation, 1)} degrees: the table above says the same">` +
    ring(0) + ring(30) + ring(60) +
    `<text x="${c}" y="14" class="dir">N</text><text x="${c}" y="316" class="dir">S</text><text x="312" y="${c + 4}" class="dir">E</text><text x="8" y="${c + 4}" class="dir">W</text>` +
    `<polyline points="${path.join(' ')}" class="track"/><circle cx="${hx}" cy="${hy}" r="4" class="top"/></svg>` +
    `<figcaption>The pass rising at ${esc(local(t0))}, drawn as on a map: the centre is straight up, the edge the horizon, north at the top and east to the right; rings at 0°, 30° and 60° up.</figcaption></figure>`;
}

function update() {
  clearInterval(ticker); ticker = null;
  if (!showRead()) { $('now').innerHTML = ''; $('passes').innerHTML = ''; $('chart').innerHTML = ''; return; }
  showNow(); showPasses();
  if (from() === 'now') {
    const calm = matchMedia('(prefers-reduced-motion: reduce)').matches;
    ticker = setInterval(() => { if (!document.hidden) showNow(); }, calm ? 10000 : 1000);
  }
}

function start_() {
  const city = $('city');
  CITIES.forEach(([name], i) => city.add(new Option(name, String(i))));
  const pick = () => { const [, la, lo, h] = CITIES[Number(city.value)]; $('lat').value = la; $('lon').value = lo; $('height').value = h; };
  city.addEventListener('change', () => { pick(); update(); });
  pick();
  document.querySelectorAll('[data-example]').forEach((b) => b.addEventListener('click', () => {
    $('text').value = EXAMPLES[b.dataset.example]; chosen = 0; update();
  }));
  let typing = null;
  $('text').addEventListener('input', () => { clearTimeout(typing); typing = setTimeout(() => { chosen = 0; update(); }, 300); });
  for (const id of ['lat', 'lon', 'height', 'above']) $(id).addEventListener('change', update);
  document.querySelectorAll('input[name="from"]').forEach((r) => r.addEventListener('change', update));
  $('passes').addEventListener('click', (e) => { const b = e.target.closest('[data-chart]'); if (b) showChart(Number(b.dataset.chart)); });
  $('text').value = EXAMPLES.iss;
  update();
}

load().then(() => { $('status').textContent = 'GPKit is loaded: it runs in this page.'; start_(); })
  .catch((e) => { $('status').textContent = 'GPKit could not be loaded here: ' + e.message; });
