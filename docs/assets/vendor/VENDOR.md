# Vendored scripts

Self-hosted so the pages make no request to any outside site. Files are the
`dist` builds from the npm tarballs, byte for byte, except that the trailing
`sourceMappingURL` comment is removed from lenis.min.js (no map is shipped).
Licence notices are kept.

| File | Package | sha256 of the file |
|---|---|---|
| gsap/gsap.min.js | gsap 3.15.1 (Standard 'no charge' licence, see gsap/LICENSE.txt) | 3d1bea374ab1b703cc5c4105358eec63c4465efdc573931dc116e34a0a190c1b |
| gsap/ScrollTrigger.min.js | gsap 3.15.1 (Standard 'no charge' licence, see gsap/LICENSE.txt) | b5bb360661f478f0ff6ffa11500d8ce5e2b6aaf6f7288237cdca3aac9548035a |
| lenis/lenis.min.js | lenis 1.3.27 (MIT, see lenis/LICENSE.txt) | 07020831fc52c75dc556473f50ddbf993ca65f1b920394ebd04dfd8c1824d952 |

Tarballs (npm registry, fetched 2026-11-11):

- gsap-3.15.1.tgz  sha256 c70a3bcf656015f32b4f6456e686034564c90d64280db535cfbd84de4497d988
- lenis-1.3.27.tgz sha256 0a2437de050959246edd645a2ffa8b50a6ff6b80d98f6d960f1b4557a4c4209e

To update: `npm pack gsap@<v> lenis@<v>`, copy the same three `dist` files, re-read
both licences, and update this table. The page degrades to a static, complete
version if any of these fail to load (see docs/assets/home.js).
