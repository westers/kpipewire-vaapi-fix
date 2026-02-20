## Title
KPipeWire: robust damage metadata plumbing and libx264 profile correctness for KRDP fallback

## Summary
This patch stack consolidates VAAPI and software fallback fixes used for KRDP:

- VAAPI hw_frames_ctx initialization order fix
- full color-range support
- software filter graph ordering/syntax fixes
- encoded frame damage metadata plumbing and API exposure
- honor requested H264 profile in libx264 fallback
- force CABAC for Main/High requests so speed presets do not downgrade to
  constrained baseline

## Scope
Repository: `westers/kpipewire-vaapi-fix`
Branch: `main`

Recent commits:

- `674a196` Force CABAC for libx264 main/high profile requests
- `6982f7d` Refresh damage-metadata patch against current patch stack
- `cd35b7c` Honor H264Main in libx264 fallback and refresh patch series
- `10f6336` Add encoded damage-metadata patch and include it in build series
- `5b00a98` Add full color range support and fix filter graph syntax

GitHub compare reference:
`https://github.com/westers/kpipewire-vaapi-fix/compare/10f6336...674a196`

## Validation
- `build.sh` succeeds with patch series through `05`.
- Installed local `+vaapi4` packages and restarted portal/KRDP services.
- Forced software fallback (`KPIPEWIRE_FORCE_ENCODER=libx264`) confirmed:
  - KRDP requests `H264 Main`
  - libx264 now logs `profile Main` instead of constrained baseline.

## Notes
- This shell cannot authenticate to `invent.kde.org`, so MR creation must be
  done from a session with KDE GitLab credentials.
