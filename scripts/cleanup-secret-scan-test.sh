#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Usage: bash scripts/cleanup-secret-scan-test.sh <temporary-test-repository>" >&2
    exit 2
fi

test_repo="$(cd -- "$1" 2>/dev/null && pwd -P)" || {
    echo "ERROR: Temporary test repository does not exist." >&2
    exit 1
}
repo_root="$(git rev-parse --show-toplevel)"
git_dir="$(git -C "$repo_root" rev-parse --absolute-git-dir)"
git_dir="$(cd -- "$git_dir" && pwd -P)"
marker="${test_repo}/.deploy-pulse-secret-scan-test"
expected_root="$(git -C "$test_repo" rev-parse --show-toplevel 2>/dev/null || true)"

case "$test_repo" in
    "${git_dir}"/deploy-pulse-gitleaks-test.*) ;;
    *)
        echo "ERROR: Refusing to remove a path outside the expected temporary-test prefix." >&2
        exit 1
        ;;
esac

if [[ ! -f "$marker" ]] || [[ "$(cat "$marker")" != "deploy-pulse-secret-scan-test-v1" ]] \
    || [[ "$expected_root" != "$test_repo" ]]; then
    echo "ERROR: Refusing to remove a directory that is not a verified scanner-test repository." >&2
    exit 1
fi

# Removing this isolated repository deletes the test branch and its complete Git object history.
rm -rf -- "$test_repo"
echo "Removed the temporary test repository, fake key, and its Git history."
