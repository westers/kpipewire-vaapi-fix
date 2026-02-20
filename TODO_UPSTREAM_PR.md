# TODO: Upstream MR Follow-up (KPipeWire)

Last updated: 2026-02-20

## Current State

- Repo: `/home/westers/dev/rdp/kpipewire-vaapi-fix`
- Branch: `main`
- HEAD: `e3b65244367e63cb65a72cc5d855fd6fbfb3cbc1`
- GitHub remote: `git@github.com:westers/kpipewire-vaapi-fix.git` (pushed)
- KDE upstream tracked as `kde` remote (`https://invent.kde.org/plasma/kpipewire.git`)
- Existing MR draft text: `UPSTREAM_MR_DRAFT.md`

## Important Context

This repo is a Debian patch-stack/build helper repo, not a normal git branch on
top of `plasma/kpipewire`. You cannot open a clean upstream MR directly from
this history.

Create a real upstream branch from `kde/master`, then port/apply patch content.

## Patch Set To Port Upstream

Apply in order:

1. `patches/01-fix-vaapi-hw-frames-ctx.patch`
2. `patches/02-add-color-range-support.patch`
3. `patches/03-fix-software-encoder-filter-graph.patch`
4. `patches/04-damage-metadata-encoded-stream.patch`
5. `patches/05-honor-h264-profile-in-libx264-fallback.patch`

## Resume Steps

1. Authenticate to Invent from a shell with working credentials.
2. Create/clone your Invent fork of `kpipewire`.
3. Branch from upstream `master`.
4. Port/apply the five patches above as clean commits.
5. Build/test and validate:
   - software fallback forced to libx264 reports `profile Main` when KRDP requests Main.
6. Open MR against `plasma/kpipewire:master`.
7. Use `UPSTREAM_MR_DRAFT.md` as MR body base.

## Quick Validation Command

```bash
./smoke-test.sh --no-build --force-libx264 --watch-seconds 120
```

