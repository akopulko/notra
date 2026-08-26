#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(git -C "$script_dir/.." rev-parse --show-toplevel)"
hook_path="$repo_root/.git/hooks/pre-commit"

cat > "$hook_path" <<'HOOK'
#!/bin/sh
set -eu

repo_root="$(git rev-parse --show-toplevel)"
exec "$repo_root/Scripts/check_privacy.sh"
HOOK

chmod +x "$hook_path"
printf '%s\n' "Installed pre-commit hook: ${hook_path}"
