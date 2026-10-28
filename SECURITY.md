# Security Policy

## Supported Versions

PulseBar is actively maintained on the latest `1.x` release branch[cite: 3]. Security updates and patches are applied to the following versions:

| Version | Supported          | macOS Compatibility |
| ------- | ------------------ | ------------------- |
| `1.0.x` | :white_check_mark: | macOS 14.0+         |
| `< 1.0` | :x:                | Unsupported         |

---

## Security & Privacy Architecture

PulseBar is designed with a local-first, zero-telemetry architecture:

* **Zero External Network Calls:** PulseBar never transmits system metrics, hardware identifiers, or usage telemetry over the internet. All network interface monitoring (`getifaddrs`) strictly reads local byte counters (`ifi_ibytes` and `ifi_obytes`) from the Darwin kernel[cite: 3].
* **Unprivileged Kernel & IOKit Access:** CPU (`host_processor_info`), memory (`host_statistics64`), battery (`IOPSCopyPowerSourcesInfo`), and GPU (`IOAccelerator`) metrics are queried using standard unprivileged user-space APIs without requiring root (`sudo`) permissions or kernel extensions[cite: 3].
* **Local Preference Storage:** User settings (slot configurations, polling intervals, and theme preferences) are stored locally in standard macOS `UserDefaults`[cite: 3].

---

## Reporting a Vulnerability

If you discover a security vulnerability, memory leak, or privilege issue within PulseBar, please report it responsibly rather than opening a public GitHub issue:

1. **GitHub Private Vulnerability Reporting:** Navigate to the [**Security** tab](https://github.com/RyzerG/PulseBar/security/advisories/new) of this repository and click **Report a vulnerability** to open a private advisory.
2. **What to Include:**
   * A clear description of the issue and potential impact.
   * Steps to reproduce the behavior (including your macOS version and Mac architecture—Apple Silicon or Intel).
   * Any relevant crash logs, `sample` traces, or proof-of-concept code.

### Response Timeline

* **Initial Acknowledgment:** Within **48 hours** of submission.
* **Status Update & Triage:** Within **5 business days** after confirming the issue.
* **Patch & Disclosure:** Once a fix is verified and merged into `main`, a security advisory and credit (if desired) will be published alongside the release.