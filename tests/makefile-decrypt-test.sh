#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/bin" "$fixture/private"
printf 'encrypted fixture\n' > "$fixture/private/config.nix.age"
printf 'known-good config\n' > "$fixture/private/config.nix"

cat > "$fixture/bin/age" <<'EOF'
#!/usr/bin/env bash
if [[ "${AGE_TEST_FAIL:-}" == 1 ]]; then
  printf 'partial output\n'
  exit 1
fi
printf 'replacement config\n'
EOF
chmod +x "$fixture/bin/age"

make_args=(
  -f "$repo/Makefile"
  decrypt
  "PRIVATE_DIR=$fixture/private"
  "AGE_KEY=$fixture/dummy-key"
)

if PATH="$fixture/bin:$PATH" AGE_TEST_FAIL=1 make "${make_args[@]}"; then
  echo 'decrypt unexpectedly succeeded with a failing age command' >&2
  exit 1
fi
grep -Fxq 'known-good config' "$fixture/private/config.nix"
if find "$fixture/private" -maxdepth 1 -name '.config.nix.*' | grep -q .; then
  echo 'failed decrypt left a temporary file behind' >&2
  exit 1
fi

PATH="$fixture/bin:$PATH" make "${make_args[@]}"
grep -Fxq 'replacement config' "$fixture/private/config.nix"
[[ $(stat -f '%Lp' "$fixture/private/config.nix" 2>/dev/null || stat -c '%a' "$fixture/private/config.nix") == 600 ]]

echo 'Makefile decrypt tests passed'
