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
    git -C "$desktop" submodule update --init --checkout -- engine
    (
        cd "$desktop/engine"
        version=$(sed -n 's/^[[:space:]]*\.version = "\(.*\)",$/\1/p' build.zig.zon)
        commit=$(git rev-parse --short=7 HEAD)
        "$zig" build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos.26.0 \
            "-Dversion=${version:?Missing engine version}+${commit}" --prefix "$derived_data/engine"
    )
fi

xcodebuild -project "$desktop/Synth.xcodeproj" -scheme Synth -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived_data" \
    "SYNTH_ENGINE=$engine" "$@" build

printf '%s\n' "$derived_data/Build/Products/Release/Synth.app"
