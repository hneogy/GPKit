// node playground/test/equal.mjs MODULE.wasm REFERENCE.json: the playground's module, run under Node's WASI, makes
// every call playground-reference made natively, with the same arguments, and each answer is held to the native one:
//
//   exactly:  the answer's shape, every string (refusals, formats, names, the TLE written, every UTC time), every time
//             in seconds (`unix`, `epoch_unix`) and every integer (catalog numbers, indexes, line numbers), so the same
//             sets are read, the same refusals given and the same passes found at the same instants;
//   within TOLERANCE: every other number (angles in degrees, distances in km, speeds in km/s). The module's maths
//             library is not the native one, so sin, cos and atan2 can part in the last bits: measured 2026-11-10
//             against macOS arm64, the widest gap was 7e-12 (an azimuth's degrees, a range's km); the bound is 100
//             times that.
//
// Exit 1 at the first answer outside that, 0 when every call agrees; the widest gap for each kind of number is printed.
import { readFileSync } from 'node:fs';
import { WASI } from 'node:wasi';

const TOLERANCE = 1e-9;
const [module, referencePath] = process.argv.slice(2);
const reference = JSON.parse(readFileSync(referencePath, 'utf8'));
const wasi = new WASI({ version: 'preview1', args: [], env: {}, returnOnExit: true });
const { instance } = await WebAssembly.instantiate(readFileSync(module), { wasi_snapshot_preview1: wasi.wasiImport });
wasi.initialize(instance);
const gp = instance.exports;
const enc = new TextEncoder(), dec = new TextDecoder();

const pointers = {};
function text(name) {
  if (!(name in pointers)) {
    const bytes = enc.encode(reference.texts[name]);
    const at = gp.gpkit_alloc(bytes.length);
    new Uint8Array(gp.memory.buffer, at, bytes.length).set(bytes);
    pointers[name] = [at, bytes.length];
  }
  return pointers[name];
}
const answer = (size) => dec.decode(new Uint8Array(gp.memory.buffer, gp.gpkit_answer(), size));
const exactKey = (key) => key === 'unix' || key === 'epoch_unix';

const widest = {};
let identical = 0, numbers = 0, parted = 0;
// null when x (here) and y (natively) agree as above, else where and how they part
function compare(x, y, path, key) {
  if (typeof x === 'number' && typeof y === 'number') {
    numbers++;
    if (x === y) return null;
    if (exactKey(key) || (Number.isInteger(x) && Number.isInteger(y))) return `${path}: ${x} here, ${y} natively, which must be equal`;
    const gap = Math.abs(x - y), kind = path.replace(/\[\d+\]/g, '[]');
    parted++;
    widest[kind] = Math.max(widest[kind] ?? 0, gap);
    return gap <= TOLERANCE ? null : `${path}: ${x} here, ${y} natively, ${gap} apart, above ${TOLERANCE}`;
  }
  if (Array.isArray(x) !== Array.isArray(y) || typeof x !== typeof y || (x === null) !== (y === null)) return `${path}: ${JSON.stringify(x)} here, ${JSON.stringify(y)} natively`;
  if (x === null || typeof x !== 'object') return x === y ? null : `${path}: ${JSON.stringify(x)} here, ${JSON.stringify(y)} natively`;
  const keys = Array.isArray(x) ? [...Array(Math.max(x.length, y.length)).keys()] : [...new Set([...Object.keys(x), ...Object.keys(y)])];
  for (const k of keys) {
    if (!(k in x) || !(k in y)) return `${path}[${k}]: ${k in x ? 'only here' : 'only natively'}`;
    const d = compare(x[k], y[k], Array.isArray(x) ? `${path}[${k}]` : `${path}.${k}`, Array.isArray(x) ? key : k);
    if (d) return d;
  }
  return null;
}

const counts = { read: 0, now: 0, passes: 0 };
for (const c of reference.calls) {
  const [at, length] = text(c.text);
  const args = c.args.map(Number);
  const size = c.call === 'read' ? gp.gpkit_read(at, length)
    : c.call === 'now' ? gp.gpkit_now(at, length, ...args)
    : gp.gpkit_passes(at, length, ...args);
  const got = answer(size);
  counts[c.call]++;
  if (got === c.answer) { identical++; continue; }
  const d = compare(JSON.parse(got), JSON.parse(c.answer), '$', null);
  if (d) {
    console.error(`DIFFERENT: ${c.call} on ${c.text} (${c.args.join(', ')}): ${d}`);
    process.exit(1);
  }
}
console.log(`the module under Node's WASI agrees with the native answers: ${reference.calls.length} calls (${counts.read} read, ` +
  `${counts.now} now, ${counts.passes} passes), ${identical} of them byte for byte; ${numbers} numbers, ${parted} parting ` +
  `in the last bits, none by more than ${TOLERANCE}; shapes, strings, times and integers all equal`);
for (const [kind, gap] of Object.entries(widest).sort((a, b) => b[1] - a[1])) console.log(`  widest ${kind}: ${gap.toExponential(2)}`);
