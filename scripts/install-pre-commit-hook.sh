#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_hook="${repo_root}/.githooks/pre-commit"
git_dir="$(git -C "$repo_root" rev-parse --absolute-git-dir)"
hooks_dir="${git_dir}/hooks"
installed_hook="${hooks_dir}/pre-commit"

if [[ ! -f "$source_hook" ]]; then
    echo "ERROR: Hook source not found: $source_hook" >&2
    exit 1
fi

if [[ -e "$installed_hook" ]]; then
    echo "ERROR: A pre-commit hook already exists at $installed_hook; refusing to overwrite it." >&2
    exit 1
fi

mkdir -p "$hooks_dir"
cp "$source_hook" "$installed_hook"
chmod 700 "$installed_hook"
echo "Installed Gitleaks pre-commit hook in $hooks_dir"
