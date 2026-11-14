import { access, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const dist = resolve(process.cwd(), 'dist');
const required = [
  'index.html',
  'ammar-marketplace.js',
  'ammir-identity.css',
  'icon.svg',
  'icon-192.png',
  'icon-512.png',
  'native-shell.css'
];

for (const file of required) {
  await access(resolve(dist, file));
}

const html = await readFile(resolve(dist, 'index.html'), 'utf8');
if (!html.includes('viewport-fit=cover')) throw new Error('Safe-area viewport is missing.');
if (!/native-bridge-[^"]+\.js|native-bridge\.js/.test(html)) throw new Error('Native bridge module is missing from the built app.');
if (!html.includes('AMMIR')) throw new Error('AMMIR identity is missing from the built app.');

console.log('AMMIR native web build verification passed.');