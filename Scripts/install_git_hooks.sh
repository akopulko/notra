#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(git -C "$script_dir/.." rev-parse --show-toplevel)"
hook_path="$repo_root/.git/hooks/pre-commit"

# Beads or another tool may leave a stale hooksPath override behind. The hook
# installed here must be the hook Git actually runs for every local commit.
git -C "$repo_root" config --local --unset-all core.hooksPath 2>/dev/null || true

cat > "$hook_path" <<'HOOK'
#!/bin/sh
set -eu

repo_root="$(git rev-parse --show-toplevel)"
exec "$repo_root/Scripts/check_privacy.sh"
HOOK

chmod +x "$hook_path"
printf '%s\n' "Installed pre-commit hook: ${hook_path}"
