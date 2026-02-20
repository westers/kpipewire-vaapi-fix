#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"
version_glob="${VERSION_GLOB:-+vaapi4}"
watch_seconds="${WATCH_SECONDS:-120}"

run_build=1
run_install=1
run_restart=1
run_watch=1
force_libx264=0
clear_force_encoder=0

usage() {
    cat <<'EOF'
Usage: ./smoke-test.sh [options]

Options:
  --no-build            Skip ./build.sh
  --no-install          Skip dpkg install step
  --no-restart          Skip service restart
  --no-watch            Skip log follow
  --force-libx264       Set KPIPEWIRE_FORCE_ENCODER=libx264 for this test run
  --clear-force-encoder Unset KPIPEWIRE_FORCE_ENCODER before restart
  --watch-seconds N
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build) run_build=0 ;;
        --no-install) run_install=0 ;;
        --no-restart) run_restart=0 ;;
        --no-watch) run_watch=0 ;;
        --force-libx264) force_libx264=1 ;;
        --clear-force-encoder) clear_force_encoder=1 ;;
        --watch-seconds)
            shift
            watch_seconds="${1:-}"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
    shift
done

if command -v rg >/dev/null 2>&1; then
    filter_cmd=(rg -i)
else
    filter_cmd=(grep -Ei)
fi

log_pattern='Using PipeWire H264 encoder profile|Forcing encoder|libx264|profile|Started Plasma session|Closing session|Listening for connections|Cannot create children|sequence gap|desynchronized|No matching damage metadata|queue overflow|Failed receiving filtered frame|Filter queue is full|ERRINFO|Broken pipe|fake input'

cd "${repo_dir}"

if (( run_build )); then
    SKIP_BUILD_DEPS="${SKIP_BUILD_DEPS:-1}" ./build.sh
fi

if (( run_install )); then
    sudo dpkg -i \
        debs/libkpipewire-data_*"${version_glob}"*.deb \
        debs/libkpipewire6_*"${version_glob}"*.deb \
        debs/libkpipewiredmabuf6_*"${version_glob}"*.deb \
        debs/libkpipewirerecord6_*"${version_glob}"*.deb \
        debs/qml6-module-org-kde-pipewire_*"${version_glob}"*.deb \
        debs/libkpipewire-dev_*"${version_glob}"*.deb
fi

if (( clear_force_encoder )); then
    systemctl --user unset-environment KPIPEWIRE_FORCE_ENCODER
fi

if (( force_libx264 )); then
    systemctl --user set-environment KPIPEWIRE_FORCE_ENCODER=libx264
fi

if (( run_restart )); then
    systemctl --user restart xdg-desktop-portal plasma-xdg-desktop-portal-kde app-org.kde.krdpserver
fi

echo
echo "Current encoder override:"
systemctl --user show-environment | "${filter_cmd[@]}" '^KPIPEWIRE_FORCE_ENCODER=' || echo "KPIPEWIRE_FORCE_ENCODER not set"

echo
echo "Recent KRDP log summary:"
journalctl --user -n 80 -o cat -u app-org.kde.krdpserver -u plasma-xdg-desktop-portal-kde | "${filter_cmd[@]}" "${log_pattern}" || true

if (( run_watch )); then
    echo
    echo "Watching logs for ${watch_seconds}s..."
    timeout "${watch_seconds}"s \
        journalctl --user -f -o cat -u app-org.kde.krdpserver -u plasma-xdg-desktop-portal-kde \
        | "${filter_cmd[@]}" "${log_pattern}" || true
fi
