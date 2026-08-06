#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "bundle content verification failed: $*"
  exit 1
}

[[ $# -eq 1 ]] || fail "usage: $0 APP_BUNDLE"
app_bundle="$1"
[[ -d "$app_bundle/Contents" ]] || fail "invalid app bundle: $app_bundle"
binary="$app_bundle/Contents/MacOS/estrobo"
[[ -x "$binary" ]] || fail "main executable not found: $binary"

for forbidden_pattern in \
  '*.swift' '*.m' '*.mm' '*.c' '*.cc' '*.cpp' '*.cxx' '*.h' '*.hh' '*.hpp' \
  '*.s' '*.asm' '*.py' '*.pyc' '*.rb' '*.php' '*.pl' '*.sh' '*.bash' '*.zsh' \
  '*.js' '*.jsx' '*.ts' '*.tsx' '*.java' '*.kt' '*.kts' '*.go' '*.rs' '*.cs' \
  'Makefile' 'CMakeLists.txt' \
  '*.p12' '*.pfx' '*.key' '*.pem' '*.cer' '*.mobileprovision' \
  '*.zip' '*.dmg' '*.pkg' '*.apk' '*.ipa' '*.tar' '*.tgz' '*.gz' \
  '*.bz2' '*.xz' '*.7z' '*.rar' \
  '*.o' '*.a' '*.dylib' '*.so' '*.lock' '*.lockfile' '*.af~lock~' \
  'Package.resolved' 'Podfile.lock' 'Cartfile.resolved' \
  'package-lock.json' 'pnpm-lock.yaml' 'yarn.lock' '.DS_Store'; do
  forbidden_path="$(/usr/bin/find "$app_bundle" -iname "$forbidden_pattern" -print -quit)"
  [[ -z "$forbidden_path" ]] || fail "forbidden bundle content: $forbidden_path"
done

for forbidden_directory in \
  Tests Test __tests__ PoC GodoxBLEPoC Sources Source src \
  Build Dist DerivedData .build .swiftpm .git node_modules .venv venv \
  '*.app' '*.dSYM' '*.xcarchive' '*.xcodeproj' '*.xcworkspace'; do
  forbidden_path="$(/usr/bin/find "$app_bundle/Contents" -type d -iname "$forbidden_directory" -print -quit)"
  [[ -z "$forbidden_path" ]] || fail "forbidden bundle directory: $forbidden_path"
done

unexpected_executable="$(/usr/bin/find "$app_bundle/Contents" -type f -perm -111 ! -path "$binary" -print -quit)"
[[ -z "$unexpected_executable" ]] || fail "unexpected executable in bundle: $unexpected_executable"

print "Bundle contents verified: $app_bundle"
