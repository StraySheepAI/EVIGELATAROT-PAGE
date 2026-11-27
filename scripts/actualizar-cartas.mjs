// Actualiza data/cartas.js a partir de la planilla "EVIGILA · Cartas de la página" (Google Drive).
// Uso: node scripts/actualizar-cartas.mjs            → lee la planilla publicada
//      node scripts/actualizar-cartas.mjs archivo.csv → lee un CSV local (para probar)
import { readFile, writeFile } from 'node:fs/promises';

const SHEET_ID = '1Nq7H1LifXOQmwF8UzlTEl9QObYZh5wckSd0Abshez_I';
const CSV_URL = `https://docs.google.com/spreadsheets/d/${SHEET_ID}/export?format=csv`;
const OUT = new URL('../data/cartas.js', import.meta.url);
const CAMPOS_OBLIGATORIOS = ['id', 'name', 'family', 'image'];
const MINIMO_DE_CARTAS = 30; // si la planilla viene rota o casi vacía, no se publica nada

function parseCSV(text) {
  const rows = []; let row = []; let field = ''; let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (ch === '"') inQuotes = false;
      else field += ch;
    } else if (ch === '"') inQuotes = true;
    else if (ch === ',') { row.push(field); field = ''; }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(field); rows.push(row); row = []; field = '';
    } else field += ch;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  return rows.filter(r => r.some(v => v.trim() !== ''));
}

const source = process.argv[2];
let csv;
if (source) csv = await readFile(source, 'utf8');
else {
  const res = await fetch(CSV_URL, { redirect: 'follow' });
  if (!res.ok) throw new Error(`No se pudo leer la planilla (HTTP ${res.status}). ¿Está compartida como "Cualquier persona con el enlace"?`);
  csv = await res.text();
  if (csv.trimStart().startsWith('<')) throw new Error('La planilla devolvió una página en vez de datos. ¿Está compartida como "Cualquier persona con el enlace"?');
}

const [header, ...rows] = parseCSV(csv);
const cols = header.map(h => h.trim());
for (const c of CAMPOS_OBLIGATORIOS) if (!cols.includes(c)) throw new Error(`Falta la columna "${c}" en la planilla.`);

const cartas = rows.map((r, n) => {
  const carta = {};
  cols.forEach((c, i) => {
    const v = (r[i] ?? '').trim();
    if (!c || v === '') return; // vacío = la página usa su texto por defecto
    if (c === 'id' && /^\d+$/.test(v)) { carta.id = v.padStart(3, '0'); return; } // Sheets convierte 000 en 0
    carta[c] = c === 'keywords' ? v.split('|').map(s => s.trim()).filter(Boolean) : v;
  });
  for (const c of CAMPOS_OBLIGATORIOS) if (!carta[c]) throw new Error(`La fila ${n + 2} no tiene "${c}".`);
  return carta;
});
if (cartas.length < MINIMO_DE_CARTAS) throw new Error(`La planilla tiene solo ${cartas.length} cartas; no se actualiza la página.`);
const ids = new Set();
for (const c of cartas) { if (ids.has(c.id)) throw new Error(`El id "${c.id}" está repetido.`); ids.add(c.id); }

const js = '// Datos de las cartas de EVIGILA. Se generan desde la planilla "EVIGILA · Cartas de la página" en Drive.\n' +
  '// No editar a mano: editá la planilla y corré scripts/actualizar-cartas.mjs (o la acción de GitHub).\n' +
  'window.EVIGILA_CARTAS = ' + JSON.stringify(cartas, null, 2) + ';\n';
await writeFile(OUT, js);
console.log(`Listo: ${cartas.length} cartas escritas en data/cartas.js`);
