#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
config_file="${repo_root}/.gitleaks.toml"
git_dir="$(git -C "$repo_root" rev-parse --absolute-git-dir)"
marker=".deploy-pulse-secret-scan-test"

if [[ -n "${GITLEAKS_BIN:-}" ]]; then
    gitleaks_bin="$GITLEAKS_BIN"
elif command -v gitleaks >/dev/null 2>&1; then
    gitleaks_bin="$(command -v gitleaks)"
elif [[ -x "${repo_root}/gitleaks.exe" ]]; then
    gitleaks_bin="${repo_root}/gitleaks.exe"
else
    echo "ERROR: Install Gitleaks, set GITLEAKS_BIN, or provide gitleaks.exe in the repository root." >&2
    exit 1
fi

if command -v openssl >/dev/null 2>&1; then
    fake_key="$(openssl rand -hex 32)"
elif command -v od >/dev/null 2>&1; then
    fake_key="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
else
    echo "ERROR: OpenSSL or od is required to generate a random fake key." >&2
    exit 1
fi

if [[ ! "$fake_key" =~ ^[[:xdigit:]]{64}$ ]]; then
    echo "ERROR: Fake-key generation did not return 64 hexadecimal characters." >&2
    exit 1
fi

if [[ ! -f "$config_file" ]]; then
    echo "ERROR: Gitleaks config not found: $config_file" >&2
    exit 1
fi

test_repo="$(mktemp -d "${git_dir}/deploy-pulse-gitleaks-test.XXXXXX")"
report_file="${test_repo}/gitleaks-report.json"
git init --quiet "$test_repo"
git -C "$test_repo" checkout --quiet -b "test/gitleaks-$$"
git -C "$test_repo" config user.name "Deploy Pulse Secret Scan Test"
git -C "$test_repo" config user.email "secret-scan-test@invalid.example"
cp "$config_file" "$test_repo/.gitleaks.toml"
printf '%s\n' "deploy-pulse-secret-scan-test-v1" > "${test_repo}/${marker}"
git -C "$test_repo" add .gitleaks.toml "$marker"
git -C "$test_repo" commit --quiet -m "Add temporary scanner test config"

cat > "${test_repo}/fake-secrets.env" <<FAKE_SECRETS
api_key = "${fake_key}"
AZURE_CLIENT_SECRET = "${fake_key}"
AccountKey=${fake_key}
FAKE_SECRETS
printf '%s=%s\n' 'SharedAccessSignature' "sv=2026-01-01&sig=${fake_key}" \
    >> "${test_repo}/fake-secrets.env"
printf 'https://example.invalid/container?sv=2026-01-01&sig=%s\n' "$fake_key" \
    > "${test_repo}/fake-sas-url.txt"
git -C "$test_repo" add fake-secrets.env fake-sas-url.txt
cp "${repo_root}/.githooks/pre-commit" "${test_repo}/.git/hooks/pre-commit"
chmod 700 "${test_repo}/.git/hooks/pre-commit"

hook_log="${test_repo}/pre-commit-test.log"
hook_status=0
GITLEAKS_BIN="$gitleaks_bin" git -C "$test_repo" commit --quiet \
    -m "Verify the staged-content hook" > "$hook_log" 2>&1 || hook_status=$?
if [[ "$hook_status" -eq 0 ]] || ! grep -Eq "leaks found: [1-9][0-9]*" "$hook_log"; then
    echo "FAIL: The local pre-commit hook did not block the staged fake values." >&2
    echo "Run: bash scripts/cleanup-secret-scan-test.sh \"$test_repo\"" >&2
    exit 1
fi

# The hook test above must reject the staged values; bypass it only in this isolated
# repository so the history-scanning test can verify the same fake commit.
git -C "$test_repo" -c core.hooksPath=/dev/null commit --quiet \
    -m "Add generated fake key for scanner test"

echo "Scanning a throwaway Git branch for one randomly generated fake key."
scan_status=0
(
    cd "$test_repo"
    "$gitleaks_bin" detect \
        --source . \
        --config .gitleaks.toml \
        --redact \
        --report-format json \
        --report-path gitleaks-report.json
) || scan_status=$?

if [[ "$scan_status" -eq 0 ]]; then
    echo "FAIL: Gitleaks accepted the committed fake key." >&2
    echo "Run: bash scripts/cleanup-secret-scan-test.sh \"$test_repo\"" >&2
    exit 1
fi

expected_rules=(
    generic-assignment-secret
    azure-storage-account-key
    azure-storage-shared-access-signature
    azure-storage-sas-query-signature
)
if [[ "$scan_status" -ne 1 ]] || [[ ! -f "$report_file" ]]; then
    echo "FAIL: Gitleaks failed, but did not report the expected custom rule." >&2
    echo "Run: bash scripts/cleanup-secret-scan-test.sh \"$test_repo\"" >&2
    exit 1
fi
for rule_id in "${expected_rules[@]}"; do
    if ! grep -Fq "$rule_id" "$report_file"; then
        echo "FAIL: Gitleaks did not report custom rule $rule_id." >&2
        echo "Run: bash scripts/cleanup-secret-scan-test.sh \"$test_repo\"" >&2
        exit 1
    fi
done

echo "PASS: The pre-commit hook blocked staged fake values, and history scanning rejected the committed fake values using all four custom rules."
echo "Temporary repo: $test_repo"
echo "Redacted test report: $report_file"
echo "Remove the test repository and its Git history with:"
echo "  bash scripts/cleanup-secret-scan-test.sh \"$test_repo\""
