# kpipewire VAAPI Fix for KRDP on Kubuntu 26.04

Patches and build script to fix VAAPI hardware-accelerated H.264 encoding in KRDP (KDE Remote Desktop) on Kubuntu 26.04 (Resolute Raccoon).

Without these patches, KRDP fails to use GPU hardware encoding and either falls back to slow CPU-based software encoding (libx264) or fails to encode entirely, resulting in black screens for RDP clients.

## Background

KRDP uses the KPipeWire library to capture the screen via PipeWire and encode it as H.264 for RDP clients. On systems with VA-API capable GPUs (AMD, Intel, or NVIDIA with `nvidia-vaapi-driver`), it attempts hardware encoding through the `h264_vaapi` FFmpeg encoder using DMA-BUF/DRM PRIME for zero-copy GPU buffer sharing.

The version of KPipeWire shipped with Kubuntu 26.04 (6.5.5) has two bugs that break encoding and is missing full color range support:

### Bug 1: VAAPI hw_frames_ctx not set before filter initialization

**KDE Bug:** [515342](https://bugs.kde.org/show_bug.cgi?id=515342)
**Upstream Fix:** [e44782e](https://invent.kde.org/plasma/kpipewire/-/commit/e44782e)

The FFmpeg `buffersrc` filter was being created with `avfilter_graph_create_filter()`, which allocates and initializes the filter in one call. However, the hardware frames context (`hw_frames_ctx`) needs to be set on the filter *before* initialization. Recent versions of FFmpeg enforce this requirement, causing the error:

```
Setting BufferSourceContext.pix_fmt to a HW format requires hw_frames_ctx to be non-NULL!
Failed to create the buffer filter
```

**Fix:** Split filter creation into `avfilter_graph_alloc_filter()` (allocate) → set parameters → `avfilter_init_str()` (initialize).

### Bug 2: Incorrect filter graph order for software encoders

**KDE Bug:** [513077](https://bugs.kde.org/show_bug.cgi?id=513077)
**Upstream Fix:** [d7d1f00](https://invent.kde.org/plasma/kpipewire/-/commit/d7d1f00)

When VAAPI is unavailable and encoding falls back to libx264/openh264 (software), the FFmpeg filter graph had the pixel format conversion (`format=pix_fmts=yuv420p`) applied after the pad/scale filters instead of before. This caused incorrect pixel format handling in the pipeline.

**Fix:** Reorder the filter graph from `pad,format` to `format,pad` and use correct `scale` filter syntax.

### Feature: Full color range encoding support

**KDE Bug:** [507015](https://bugs.kde.org/show_bug.cgi?id=507015)
**Upstream Fix:** [cb00651](https://invent.kde.org/plasma/kpipewire/-/commit/cb00651)

Without color range metadata, FFmpeg-based RDP decoders assume limited range, causing incorrect/washed-out colors. This patch adds a `ColorRange` option that allows KRDP to request full range encoding, which fixes color accuracy for all RDP clients that use FFmpeg for decoding.

## Supported Hardware

The VAAPI patch works with any GPU that exposes VA-API H.264 encode capability:

| GPU Vendor | VA-API Driver | Notes |
|-----------|--------------|-------|
| **AMD** | `radeonsi` (Mesa) | Works out of the box |
| **Intel** | `intel-media-driver` or `i965-va-driver` | Works out of the box |
| **NVIDIA** | `nvidia-vaapi-driver` | Requires the VA-API compatibility layer for NVENC |

Systems without VA-API support will use the libx264 software encoder (also fixed by patches 02, 03, and 05).

## Symptoms (How to Tell if You Need This Fix)

Check your KRDP logs:

```bash
journalctl --user -u app-org.kde.krdpserver.service -b --no-pager | grep -E "hw_frames_ctx|Failed to create the buffer filter|libx264|h264_vaapi|VAAPI"
```

**You need this fix if you see:**
- `Setting BufferSourceContext.pix_fmt to a HW format requires hw_frames_ctx to be non-NULL!`
- `Failed to create the buffer filter`
- VAAPI is detected but encoding falls back to `libx264`
- Black screen when connecting via RDP (in some configurations)

**You do NOT need this fix if you see:**
- `kpipewire_vaapi_logging: VAAPI: ... in use for device "/dev/dri/renderD128"` with no subsequent errors
- No `Failed to create the buffer filter` message
- Working RDP session with hardware encoding

## Dependencies

Install build dependencies:

```bash
sudo apt install build-essential devscripts quilt
```

Enable source packages if not already enabled. Edit `/etc/apt/sources.list.d/ubuntu.sources` and ensure the `Types:` line includes `deb-src`:

```
Types: deb deb-src
```

Then update:

```bash
sudo apt update
```

Install kpipewire build dependencies:

```bash
sudo apt build-dep kpipewire
```

## Building

Clone this repo and run the build script:

```bash
git clone https://github.com/westers/kpipewire-vaapi-fix.git
cd kpipewire-vaapi-fix
./build.sh
```

The script will:
1. Download the kpipewire 6.5.5 source package
2. Apply all patches in `patches/series`
3. Build .deb packages
4. Place them in the `debs/` directory

## Installing

Install all four packages in a single command (dependency ordering matters):

```bash
sudo dpkg -i debs/libkpipewire-data_*.deb debs/libkpipewire6_*.deb debs/libkpipewiredmabuf6_*.deb debs/libkpipewirerecord6_*.deb
```

Restart the services:

```bash
systemctl --user restart xdg-desktop-portal plasma-xdg-desktop-portal-kde app-org.kde.krdpserver
```

> **Note:** If the restart hangs, force-kill and restart:
> ```bash
> killall -9 krdpserver xdg-desktop-portal-kde xdg-desktop-portal
> systemctl --user start xdg-desktop-portal && sleep 2 && systemctl --user start plasma-xdg-desktop-portal-kde && sleep 1 && systemctl --user start app-org.kde.krdpserver
> ```

## Verifying the Fix

After installing and restarting, connect an RDP client and check the logs:

```bash
journalctl --user -u app-org.kde.krdpserver.service --since "5 min ago" --no-pager
```

**Hardware encoding (VAAPI) working:**
```
kpipewire_vaapi_logging: VAAPI: Mesa Gallium driver ... in use for device "/dev/dri/renderD128"
```
No `Failed to create the buffer filter` message should appear after VAAPI detection.

**Software encoding fallback (libx264) working:**
```
[libx264 @ ...] using cpu capabilities: MMX2 SSE2Fast SSSE3 SSE4.2 AVX ...
[libx264 @ ...] profile Main, level ...  # when KRDP requests H264Main
```
This is expected on systems without VA-API. The session should not show a black screen.

## Will This Break?

Kubuntu 26.04 is still in development. This fix may become unnecessary or need updating:

- **kpipewire gets upgraded past 6.5.5:** These are upstream fixes that will likely be included in future kpipewire releases, making this patch unnecessary. Check with `apt-cache policy libkpipewirerecord6` to see if a newer version is available.
- **FFmpeg API changes:** Unlikely to affect these patches since they use stable FFmpeg filter APIs.
- **Patches fail to apply:** If the base kpipewire source changes, the build script will fail at the patch step. The patches are simple enough to manually adapt.

To check if the fix is still needed after a system update:

```bash
# Check current kpipewire version
apt-cache policy libkpipewirerecord6

# If version is still 6.5.5-0ubuntu1, the fix is still needed
# If version is newer, test without the fix first
```

## Reverting

To go back to the stock kpipewire packages:

```bash
sudo apt install --reinstall libkpipewire-data libkpipewire6 libkpipewiredmabuf6 libkpipewirerecord6
systemctl --user restart xdg-desktop-portal plasma-xdg-desktop-portal-kde app-org.kde.krdpserver
```

## References

- [KDE Bug 515342 - VAAPI hw_frames_ctx](https://bugs.kde.org/show_bug.cgi?id=515342)
- [KDE Bug 507015 - Incorrect colors](https://bugs.kde.org/show_bug.cgi?id=507015)
- [KDE Bug 513077 - Software encoder filter graph](https://bugs.kde.org/show_bug.cgi?id=513077)
- [KDE Bug 515950 - KRDP black screen](https://bugs.kde.org/show_bug.cgi?id=515950)
- [Upstream fix e44782e - VAAPI hw_frames_ctx](https://invent.kde.org/plasma/kpipewire/-/commit/e44782e)
- [Upstream fix cb00651 - Full color range](https://invent.kde.org/plasma/kpipewire/-/commit/cb00651)
- [Upstream fix d7d1f00 - Filter graph syntax](https://invent.kde.org/plasma/kpipewire/-/commit/d7d1f00)
- [KPipeWire source](https://invent.kde.org/plasma/kpipewire)
