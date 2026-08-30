#!/bin/sh
# =============================================================================
# Shared GW_MAME pak assembly - used by deploy.sh and package.sh
#
# Assembles the runnable pak directory:
#   out/GW_MAME.pak/
#     mame              - native MAME 0.223 binary (aarch64)
#     lib/libSDL2-2.0.so.0
#     launch.sh         - NextUI launcher
#     cfg/*.cfg         - control scheme + per-game view presets (shipped, so
#                         no userdata seeding needed; resets on pak update)
#     README.md, LICENSE
#
# Requires from the caller: BUILD_ROOT, OUT_DIR, REPO_ROOT, and a log()
# function.
# =============================================================================

assemble_pak() {
    local pak_dir="${OUT_DIR}/GW_MAME.pak"
    log "Assembling GW_MAME.pak..."
    rm -rf "${pak_dir}"
    mkdir -p "${pak_dir}/lib" "${pak_dir}/cfg"
    cp "${OUT_DIR}/mame" "${pak_dir}/mame"
    cp "${OUT_DIR}/lib/libSDL2-2.0.so.0" "${pak_dir}/lib/"
    cp "${BUILD_ROOT}/launch.sh" "${pak_dir}/launch.sh"
    cp "${BUILD_ROOT}/cfg/"*.cfg "${pak_dir}/cfg/"
    cp "${BUILD_ROOT}/pak-README.md" "${pak_dir}/README.md"
    cp "${REPO_ROOT}/LICENSE" "${pak_dir}/LICENSE"
    chmod +x "${pak_dir}/launch.sh" "${pak_dir}/mame"
    log "Pak contents:"
    ls -lh "${pak_dir}/" "${pak_dir}/lib/" "${pak_dir}/cfg/"
}