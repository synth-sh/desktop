#!/bin/sh
set -eu

desktop=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
derived_data=${SYNTH_DERIVED_DATA:-"$desktop/DerivedData"}
zig=${ZIG:-zig}

xcodegen generate --spec "$desktop/project.yml"

mkdir -p "$derived_data"
derived_data=$(CDPATH='' cd -- "$derived_data" && pwd)
engine=${SYNTH_ENGINE:-"$derived_data/engine/bin/synth"}

if [ -z "${SYNTH_ENGINE:-}" ]; then
    engine_source="$derived_data/engine-source"
    revision=$(cat "$desktop/Engine.commit")
    if [ ! -d "$engine_source/.git" ]; then
        git init -q "$engine_source"
    fi
    if ! git -C "$engine_source" cat-file -e "$revision^{commit}" 2>/dev/null; then
        git -C "$engine_source" fetch --no-tags --depth=1 https://github.com/synth-sh/synth.git "$revision"
    fi
    git -C "$engine_source" checkout --quiet --detach "$revision"
    (
        cd "$engine_source"
        "$zig" build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos.26.0 --prefix "$derived_data/engine"
    )
fi

xcodebuild -project "$desktop/Synth.xcodeproj" -scheme Synth -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived_data" \
    "SYNTH_ENGINE=$engine" "$@" build

printf '%s\n' "$derived_data/Build/Products/Release/Synth.app"
