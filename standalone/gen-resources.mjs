// Готовит ресурсы для standalone-сборок:
//  - out/app.html      — весь www/ в одном HTML (CSS, JS и иконка встроены)
//  - out/app_html.h    — тот же HTML как массив байт для exe
//  - out/app.ico       — иконка Windows (PNG внутри ICO)
// Запуск: node gen-resources.mjs <outDir>   (нужен пакет sharp)
import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);
const sharp = require(process.env.SHARP_PATH || 'sharp');
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const out = path.resolve(process.argv[2] || path.join(root, 'standalone', '.build'));
fs.mkdirSync(out, { recursive: true });

const www = (f) => fs.readFileSync(path.join(root, 'www', f), 'utf8');
const css = www('style.css');
const js = www('app.js');
if (js.includes('</script')) throw new Error('app.js contains </script');
const iconB64 = fs.readFileSync(path.join(root, 'www', 'icon.png')).toString('base64');

let html = www('index.html');
const replaceOnce = (from, to) => {
  if (!html.includes(from)) throw new Error('not found in index.html: ' + from);
  html = html.replace(from, () => to);
};
replaceOnce('<link rel="stylesheet" href="style.css">', `<style>\n${css}\n</style>`);
replaceOnce('<script src="app.js"></script>', `<script>\n${js}\n</script>`);
replaceOnce('<link rel="icon" href="icon.png">', `<link rel="icon" href="data:image/png;base64,${iconB64}">`);
fs.writeFileSync(path.join(out, 'app.html'), html);

const bytes = Buffer.from(html, 'utf8');
let hdr = '// Сгенерировано gen-resources.mjs — не редактировать\n#pragma once\n#include <stddef.h>\n';
hdr += `static const size_t APP_HTML_LEN = ${bytes.length};\nstatic const unsigned char APP_HTML[] = {\n`;
for (let i = 0; i < bytes.length; i += 24) {
  hdr += '  ' + Array.from(bytes.subarray(i, i + 24)).join(',') + ',\n';
}
hdr += '};\n';
fs.writeFileSync(path.join(out, 'app_html.h'), hdr);

// ICO с PNG-кадрами
const sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256];
const src = path.join(root, 'assets', 'icon.png');
const frames = [];
for (const s of sizes) {
  const r = Math.round(s * 0.2);
  const mask = Buffer.from(`<svg width="${s}" height="${s}"><rect width="${s}" height="${s}" rx="${r}" ry="${r}"/></svg>`);
  frames.push(await sharp(src).resize(s, s).composite([{ input: mask, blend: 'dest-in' }]).png().toBuffer());
}
const header = Buffer.alloc(6 + 16 * sizes.length);
header.writeUInt16LE(0, 0); header.writeUInt16LE(1, 2); header.writeUInt16LE(sizes.length, 4);
let offset = header.length;
sizes.forEach((s, i) => {
  const e = 6 + 16 * i;
  header.writeUInt8(s >= 256 ? 0 : s, e);
  header.writeUInt8(s >= 256 ? 0 : s, e + 1);
  header.writeUInt8(0, e + 2); header.writeUInt8(0, e + 3);
  header.writeUInt16LE(1, e + 4); header.writeUInt16LE(32, e + 6);
  header.writeUInt32LE(frames[i].length, e + 8);
  header.writeUInt32LE(offset, e + 12);
  offset += frames[i].length;
});
fs.writeFileSync(path.join(out, 'app.ico'), Buffer.concat([header, ...frames]));
console.log('resources ->', out, `(html ${bytes.length} bytes)`);
