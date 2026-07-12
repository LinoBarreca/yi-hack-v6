# Vendored web UI libraries

The full web UI uses a few third-party libraries. **They are not committed to
git**: like every other module source in this project (toolchain, busybox
tarball, …) they are **downloaded at build time and cached** in this directory.
`compile.www` verifies the cached copies against pinned sha256 checksums and
(re)fetches them only when missing or corrupted — normal rebuilds are offline.

`scripts/fetch_www_vendor.sh` is the single source of truth for versions,
upstream URLs and checksums; run it manually to prefetch (e.g. before building
on a machine without internet) or to verify:

    scripts/fetch_www_vendor.sh                 # fetch + verify
    scripts/fetch_www_vendor.sh --verify-only   # verify the cached copies

| File | Library | Version | Upstream |
|---|---|---|---|
| `bootstrap.min.css` | Bootstrap | 5.3.8 | https://github.com/twbs/bootstrap (MIT) |
| `bootstrap.bundle.min.js` | Bootstrap (incl. Popper) | 5.3.8 | https://github.com/twbs/bootstrap (MIT) |
| `alpine.min.js` | Alpine.js | 3.15.0 | https://github.com/alpinejs/alpine (MIT) |

The files are the unmodified upstream release artifacts (minified as upstream
ships them; only *our* HTML/CSS/JS ships unminified). There is deliberately no
Node/bundler build step: the build container is x86_64-emulated via qemu, where
heavy tooling is slow and fragile, so the web pipeline stays dependency-free.

To bump a version: edit VERSION + SHA256 in `scripts/fetch_www_vendor.sh`,
delete the cached files here, rebuild `www`.
