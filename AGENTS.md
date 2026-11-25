# AirPods Buddy development guide

Read SKILL.md and docs/agent.md first. Source, actual installed version, and public Release are separate. Follow the documentation for Windows connection and audio, privacy logging, design, local transactional build and rollback. Avoid touching other platform work. Real user logs, local settings, secrets, personal paths and raw screenshots must not enter the repository. Do not reset Bluetooth or remove pairings automatically. A successful request is not proof of link, playback or audible sound. Validate changes offline and on real hardware as applicable; report failed and unverified cases. Public Release requires explicit authorization for the specific version and subsequent website/download verification. Prefer local builds.

Noise control and a high-fidelity earbud microphone need a kernel driver channel on Windows. Do not add Winsock or WinRT workarounds; see docs/14. This public file is a short guide for contributors. The repository owner keeps fuller working notes locally and they are not published.

Current candidate: 1.9.39 (built, not installed; not a public Release). Public release: 1.9.24. See docs/roadmap.md and reference/maintenance/.
