import { access, readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';

const dist = resolve(process.cwd(), 'dist');
const required = [
  'index.html',
  'ammar-marketplace.js',
  'ammir-identity.css',
  'icon.svg',
  'icon-192.png',
  'icon-512.png',
  'manifest.webmanifest',
  'sw.js',
  'native-shell.css'
];

for (const file of required) {
  await access(resolve(dist, file));
}

const html = await readFile(resolve(dist, 'index.html'), 'utf8');
if (!html.includes('viewport-fit=cover')) throw new Error('Safe-area viewport is missing.');
if (!html.includes('native-shell.css')) throw new Error('Native layout stylesheet is not linked.');
if (!html.includes('AMMIR')) throw new Error('AMMIR identity is missing from the built app.');

const assetDir = resolve(dist, 'assets');
const entries = await readdir(assetDir, { withFileTypes: true });
const jsFiles = entries.filter((entry) => entry.isFile() && entry.name.endsWith('.js'));
let bridgeFound = false;

for (const entry of jsFiles) {
  const content = await readFile(resolve(assetDir, entry.name), 'utf8');
  if (content.includes('AMMIRNative') && content.includes('ammirNativeNetworkBanner')) {
    bridgeFound = true;
    break;
  }
}

if (!bridgeFound) throw new Error('Native Capacitor bridge was not bundled.');

console.log('AMMIR native web build verification passed.');
