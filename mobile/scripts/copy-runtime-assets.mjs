import { cp, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const mobileDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repoDir = resolve(mobileDir, '..');
const distDir = resolve(mobileDir, 'dist');
await mkdir(distDir, { recursive: true });

const runtimeFiles = [
  'ammar-marketplace.js',
  'ammir-identity.css',
  'icon.svg',
  'icon-192.png',
  'icon-512.png',
  'manifest.webmanifest',
  'sw.js'
];

for (const file of runtimeFiles) {
  await cp(resolve(repoDir, file), resolve(distDir, file));
}

await cp(
  resolve(mobileDir, 'native/native-shell.css'),
  resolve(distDir, 'native-shell.css')
);

console.log('Copied AMMIR runtime assets required by the existing HTML entry point.');
