# EasyCrypto — Copilot Instructions

## Terminal execution
- ALWAYS run terminal commands unsandboxed in this workspace (`requestUnsandboxedExecution=true`).
- The `arrive` CLI lives in a sandbox-hidden `$HOME` path and only resolves via an interactive shell, e.g. `zsh -ic 'arrive <command>'`.
- Simulator and `xcodebuild` commands also require unsandboxed access.
