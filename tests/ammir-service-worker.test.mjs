import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';

const source = fs.readFileSync('sw.js', 'utf8');
const listeners = {};
const cacheStore = new Map();
const deletedCaches = [];
const cacheApi = {
  async open(name) {
    if (!cacheStore.has(name)) cacheStore.set(name, new Map());
    const entries = cacheStore.get(name);
    return {
      async addAll(paths) { for (const path of paths) entries.set(path, { url: path, cached: true }); },
      async put(key, value) { entries.set(key, value); }
    };
  },
  async keys() { return [...cacheStore.keys()]; },
  async delete(name) { deletedCaches.push(name); return cacheStore.delete(name); },
  async match(key) {
    for (const entries of cacheStore.values()) if (entries.has(key)) return entries.get(key);
    return undefined;
  }
};
const self = {
  location: { origin: 'https://app.ammirbuild.com' },
  clients: { async claim() { self.claimed = true; } },
  async skipWaiting() { self.skipped = true; },
  addEventListener(name, callback) { listeners[name] = callback; }
};
vm.runInNewContext(source, { self, caches: cacheApi, URL, fetch: async () => { throw new Error('unexpected network request'); } });

function eventFor(request) {
  return {
    request,
    respondWith(value) { this.responsePromise = Promise.resolve(value); },
    waitUntil(value) { this.waitPromise = Promise.resolve(value); }
  };
}
const response = (url, type = 'text/html') => ({
  ok: true, url, headers: { get: name => name.toLowerCase() === 'content-type' ? type : null },
  clone() { return response(url, type); }
});

// Explicitly execute lifecycle promises with observable event objects.
const installEvent = { waitUntil(p) { this.promise = p; } };
listeners.install(installEvent);
await installEvent.promise;
assert.equal(self.skipped, true, 'install must activate the updated shell without waiting for a tab close');
assert.ok([...cacheStore.keys()].includes('ammir-shell-v11-shell-only'), 'install must create the versioned shell cache');
assert.ok(cacheStore.get('ammir-shell-v11-shell-only').has('/index.html'), 'install must pre-cache the offline app shell');

cacheStore.set('old-cache', new Map([['/private', { cached: true }]]));
const activateEvent = { waitUntil(p) { this.promise = p; } };
listeners.activate(activateEvent);
await activateEvent.promise;
assert.deepEqual(deletedCaches, ['old-cache'], 'activation must remove superseded caches');
assert.equal(self.claimed, true, 'activation must claim existing clients');

let networkCalls = 0;
const onlineFetch = async request => { networkCalls++; return response(request.url); };
const navEvent = eventFor({ method: 'GET', mode: 'navigate', url: 'https://app.ammirbuild.com/' });
vm.runInNewContext(source, { self, caches: cacheApi, URL, fetch: onlineFetch });
listeners.fetch(navEvent);
const navResponse = await navEvent.responsePromise;
assert.equal(navResponse.ok, true, 'online navigation must use the network');
await Promise.resolve();
assert.ok(cacheStore.get('ammir-shell-v11-shell-only').has('/index.html'), 'successful root HTML must refresh the shell cache');

const offlineFetch = async () => { throw new Error('offline'); };
vm.runInNewContext(source, { self, caches: cacheApi, URL, fetch: offlineFetch });
const offlineNav = eventFor({ method: 'GET', mode: 'navigate', url: 'https://app.ammirbuild.com/' });
listeners.fetch(offlineNav);
assert.ok(await offlineNav.responsePromise, 'offline root navigation must fall back to the cached app shell');

const postEvent = eventFor({ method: 'POST', mode: 'cors', url: 'https://app.ammirbuild.com/api/submit' });
listeners.fetch(postEvent);
assert.equal(postEvent.responsePromise, undefined, 'POST requests must never be intercepted or queued by the service worker');
const externalEvent = eventFor({ method: 'GET', mode: 'cors', url: 'https://project.supabase.co/rest/v1/private' });
listeners.fetch(externalEvent);
assert.equal(externalEvent.responsePromise, undefined, 'cross-origin authenticated data must never be cached by this service worker');
const dynamicEvent = eventFor({ method: 'GET', mode: 'cors', url: 'https://app.ammirbuild.com/api/private-records' });
listeners.fetch(dynamicEvent);
assert.equal(dynamicEvent.responsePromise, undefined, 'same-origin dynamic/private endpoints must not be cached');
const assetEvent = eventFor({ method: 'GET', mode: 'cors', url: 'https://app.ammirbuild.com/ammar-marketplace.js' });
listeners.fetch(assetEvent);
assert.ok(assetEvent.responsePromise, 'known shell assets must remain cache-first for offline startup');

console.log('AMMIR service-worker lifecycle, offline shell, and cache-boundary tests passed.');
