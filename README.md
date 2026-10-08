# next-on-demand-unstable-cache-bailout-repro

With `cacheComponents: true`, a page whose cache entry is past its `expire` returns HTTP 500 on the next request. Next regenerates it as if it were an on-demand revalidation, `unstable_cache` then skips the cache (including the prerender resume data cache), the final prerender pass does new I/O, and the render bails out with `NEXT_STATIC_GEN_BAILOUT`.

No custom cache handler: this uses the default file-system cache.

## The app

`app/page.js` is a static page that:

- reads data through `unstable_cache` around a `fetch` (real network I/O, `cache: "no-store"`), and
- renders a `"use cache"` component with `cacheLife({ stale: 30, revalidate: 60, expire: 300 })`, which gives the route `expire: 300`.

## Run it

```sh
pnpm install
./repro.sh          # control, then aged
PORT=4600 ./repro.sh aged
```

`repro.sh` builds, optionally ages `.next/server/app/*.{html,rsc,meta}` to 30 minutes ago (past `expire`), runs `next start`, requests `/` three times and prints the status codes plus the relevant server log lines. Waiting 5 minutes after the build instead of aging the files has the same effect.

## Output, next@16.4.0

```text
== control: next Next.js v16.4.0
request 1: HTTP 200 x-nextjs-cache=HIT
request 2: HTTP 200 x-nextjs-cache=HIT
request 3: HTTP 200 x-nextjs-cache=HIT
-- server log (errors):

== aged: next Next.js v16.4.0
request 1: HTTP 500 x-nextjs-cache=
request 2: HTTP 200 x-nextjs-cache=HIT
request 3: HTTP 200 x-nextjs-cache=HIT
-- server log (errors):
[repro] loader ran 2026-10-08T13:41:35.203Z
Error: Route "/": Next.js encountered uncached or runtime data during prerendering.
[repro] loader ran 2026-10-08T13:41:35.242Z
⨯ Error: 
  code: 'NEXT_STATIC_GEN_BAILOUT'
```

## Output, next@16.5.0-canary.3

```text
== control: next Next.js v16.5.0-canary.3
request 1: HTTP 200 x-nextjs-cache=HIT
request 2: HTTP 200 x-nextjs-cache=HIT
request 3: HTTP 200 x-nextjs-cache=HIT
-- server log (errors):

== aged: next Next.js v16.5.0-canary.3
request 1: HTTP 500 x-nextjs-cache=
request 2: HTTP 200 x-nextjs-cache=HIT
request 3: HTTP 200 x-nextjs-cache=HIT
-- server log (errors):
[repro] loader ran 2026-10-08T13:41:55.102Z
Error: Route "/": Next.js encountered uncached or runtime data during prerendering.
[repro] loader ran 2026-10-08T13:41:55.143Z
⨯ Error: 
  code: 'NEXT_STATIC_GEN_BAILOUT'
```

The control (fresh build output) serves HIT. With aged output, the first request is a 500. The `unstable_cache` loader runs twice for that one request, once in the prospective pass and once more in the final pass, which is the uncached I/O the bailout complains about.

## Why

1. `build/templates/app-page-runtime.js` (16.4.0 L737-739; `packages/next/src/build/templates/app-page.ts` on canary):
   ```js
   if (previousIncrementalCacheEntry?.isStale === -1) { isOnDemandRevalidate = true; }
   ```
2. `server/web/spec-extension/unstable-cache.js` (16.4.0 L152) only reads the cache when `!workStore.isOnDemandRevalidate && !incrementalCache.isOnDemandRevalidate`. So during that regeneration it skips `incrementalCache.get` and also the prerender resume data cache the prospective pass just filled.
3. The final prerender pass calls the loader again, the I/O doesn't finish within the final pass, the hole is outside `<Suspense>`, and since past-expire regeneration is blocking, the error becomes the response: HTTP 500.

In a larger app on next@16.3.8, either of these patches to the built `next` made aged pages return 200 (not yet tried against this repro):

- Treat `isStale === -1` as a blocking render (`fallbackMode = BLOCKING_STATIC_RENDER`) without setting `isOnDemandRevalidate`.
- Drop the `!isOnDemandRevalidate` condition from `unstable_cache`'s cache read.
