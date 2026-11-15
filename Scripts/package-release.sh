#!/bin/bash
set -euo pipefail

app=$1
archive=$2

: "${DEVELOPER_ID_CERTIFICATE:?Set DEVELOPER_ID_CERTIFICATE}"
: "${DEVELOPER_ID_CERTIFICATE_PASSWORD:?Set DEVELOPER_ID_CERTIFICATE_PASSWORD}"
: "${NOTARY_API_KEY:?Set NOTARY_API_KEY}"
: "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID}"
: "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID}"

umask 077
signing_dir=$(mktemp -d)
keychain="$signing_dir/release.keychain-db"
cleanup() {
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -rf "$signing_dir"
}
trap cleanup EXIT

keychain_password=$(openssl rand -hex 32)
printf '%s' "$DEVELOPER_ID_CERTIFICATE" | base64 -D > "$signing_dir/developer-id.p12"
security create-keychain -p "$keychain_password" "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$signing_dir/developer-id.p12" -k "$keychain" \
    -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null

# codesign requires the signing keychain on the search list even with --keychain.
existing_keychains=$(security list-keychains -d user)
search_keychains=("$keychain")
while IFS='"' read -r _ existing _; do
    if [ -n "$existing" ] && [ "$existing" != "$keychain" ]; then
        search_keychains+=("$existing")
    fi
done <<< "$existing_keychains"
security list-keychains -d user -s "${search_keychains[@]}"

identity=$(security find-identity -v -p codesigning "$keychain" |
    awk '/"Developer ID Application:/ { print $2; exit }')
if [ -z "$identity" ]; then
    echo "No valid Developer ID Application identity found." >&2
    exit 1
fi

codesign --force --timestamp --options runtime --keychain "$keychain" --sign "$identity" \
    "$app/Contents/Helpers/synth"
codesign --force --timestamp --options runtime --keychain "$keychain" --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

printf '%s' "$NOTARY_API_KEY" > "$signing_dir/notary.p8"
ditto -c -k --keepParent "$app" "$signing_dir/notarize.zip"
xcrun notarytool submit "$signing_dir/notarize.zip" --wait --timeout 30m \
    --key "$signing_dir/notary.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
    --output-format json > "$signing_dir/notary.json"
status=$(plutil -extract status raw "$signing_dir/notary.json")
if [ "$status" != "Accepted" ]; then
    submission=$(plutil -extract id raw "$signing_dir/notary.json")
    xcrun notarytool log "$submission" --key "$signing_dir/notary.p8" \
        --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
    exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

ditto -c -k --keepParent "$app" "$archive"
