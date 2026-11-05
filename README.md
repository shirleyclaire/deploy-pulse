# Deploy Pulse

A Spring Boot 3 dashboard that exposes live deployment metadata (version, Git SHA, pod/node info, uptime) via a REST API and a self-contained dark-themed frontend.

## Secret scanning

[Gitleaks](https://github.com/gitleaks/gitleaks) is integrated into the Jenkins pipeline and scans every build for accidentally committed secrets such as API keys, tokens, and passwords. If a secret is detected the build fails immediately, preventing the secret from being promoted to any downstream environment. The configuration lives in [`.gitleaks.toml`](.gitleaks.toml) at the repo root and extends Gitleaks' built-in ruleset with no extra allowlists, so all default rules are enforced without exception.

