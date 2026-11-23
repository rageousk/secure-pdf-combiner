# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| 3.3 | Yes |
| 3.2 and older | No |

## Reporting a vulnerability

Please report vulnerabilities privately rather than opening a public issue.

The intended path is [GitHub private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) / [Security Advisories](https://docs.github.com/en/code-security/security-advisories) on this repository.

**This must be enabled in the repository settings** (Code security and analysis / Private vulnerability reporting). That is a settings change and needs the repository owner's approval. It is not enabled by staging these files alone.

Until that setting is turned on, there is no in-repo private reporting form.
Do not file a public issue for a security problem.

Once private vulnerability reporting is enabled, submit reports from the
Security Advisories page on this repository:

https://github.com/rageousk/secure-pdf-combiner/security/advisories

An alternative contact email can be added to this file later if the owner
wants one.

## Release hashes

Verify the published script against this SHA256 before you run it.

| File | SHA256 |
| --- | --- |
| `secure-pdf-combiner-v3.3.ps1` | `15078c8a11842edd6caf42c658bb5b38ca3195ab13425eec69b3f947574c27d5` |

On Windows PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 .\secure-pdf-combiner-v3.3.ps1
```
