import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const mobileDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repoDir = resolve(mobileDir, '..');
const webDir = resolve(mobileDir, 'web');

const requiredFiles = [
  'index.html',
  'ammar-marketplace.js',
  'ammir-identity.css',
  'icon.svg',
  'icon-192.png',
  'icon-512.png',
  'manifest.webmanifest',
  'sw.js'
];

await rm(webDir, { recursive: true, force: true });
await mkdir(webDir, { recursive: true });

for (const file of requiredFiles) {
  await cp(resolve(repoDir, file), resolve(webDir, file));
}

await cp(resolve(mobileDir, 'native/native-bridge.js'), resolve(webDir, 'native-bridge.js'));
await cp(resolve(mobileDir, 'native/native-shell.css'), resolve(webDir, 'native-shell.css'));
await cp(resolve(repoDir, 'icon.svg'), resolve(mobileDir, 'assets/logo.svg'));

const indexPath = resolve(webDir, 'index.html');
let html = await readFile(indexPath, 'utf8');

if (!html.includes('viewport-fit=cover')) {
  html = html.replace(
    /<meta name="viewport" content="([^"]*)">/i,
    '<meta name="viewport" content="$1, viewport-fit=cover">'
  );
}

if (!html.includes('native-shell.css')) {
  html = html.replace(
    '</head>',
    '  <link rel="stylesheet" href="/native-shell.css">\n</head>'
  );
}

if (!html.includes('native-bridge.js')) {
  html = html.replace(
    '</body>',
    '  <script type="module" src="/native-bridge.js"></script>\n</body>'
  );
}

if (!html.includes('native-bridge.js') || !html.includes('native-shell.css')) {
  throw new Error('Could not attach the native mobile layer to index.html.');
}

await writeFile(indexPath, html, 'utf8');
console.log('AMMIR web bundle prepared for Capacitor.');