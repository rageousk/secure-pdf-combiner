# Secure PDF Combiner v3.3

A Windows PowerShell script that merges two or more PDFs from one folder into a
single PDF, in the order you choose, using the Python library pypdf.

Script file: `secure-pdf-combiner-v3.3.ps1`

SHA256 (v3.3): `15078c8a11842edd6caf42c658bb5b38ca3195ab13425eec69b3f947574c27d5`

## Get it

Download `secure-pdf-combiner-v3.3.ps1` from this repository, or clone it:

```powershell
git clone https://github.com/rageousk/secure-pdf-combiner.git
```

Repository: https://github.com/rageousk/secure-pdf-combiner

## Verify the script

Before you run a copy you downloaded, check that its SHA256 matches the hash
above:

```powershell
Get-FileHash .\secure-pdf-combiner-v3.3.ps1 -Algorithm SHA256
```

The digest should be:

```text
15078c8a11842edd6caf42c658bb5b38ca3195ab13425eec69b3f947574c27d5
```

If the file is in another folder, pass that full path to `Get-FileHash`
instead. Editing the script changes this hash; the value above matches only
the unmodified v3.3 file.

## What it does

You point the script at a folder, pick the PDFs and their order, and it creates
`Combined.pdf` in that same folder (or `Combined (2).pdf`, `Combined (3).pdf`,
and so on if that name is already taken). It checks that the result has
exactly as many pages as the inputs combined. Your original PDFs are never
changed. On the first run it sets up a private Python environment in your user
profile and installs a pinned, hash-checked copy of pypdf (and, on Python
3.10, typing_extensions). Later runs reuse that environment and skip the
install.

If the selected input is at least 1 GB, the script prints a large-merge
warning before the confirmation prompt.

## Requirements

- **Windows.** The script requires `LOCALAPPDATA` and exits with
  `LOCALAPPDATA is not set. This script is meant for Windows.` if it is
  missing. It does not check the Windows version.
- **Windows PowerShell 5.1** (built into Windows) or **PowerShell 7**. The
  script has no `#Requires -Version` statement. A comment in the script says
  it uses UTF-8 without a BOM so file bytes (and their hashes) are the same
  on both.
- **Python 3.10 or newer**, with the Windows `py` launcher. Either:
  - Install from https://www.python.org/downloads/ and keep the
    "py launcher" option checked in the installer, or
  - As one convenient option (not run by the script):
    `winget install Python.Python.3.12` in a terminal.
  - The script checks with `py -3`, so the newest Python 3 the launcher finds
    is the one used.
- **Internet access** on the first run (and whenever the pinned packages change):
  - `pypi.org` / `files.pythonhosted.org` to download the pinned wheels.
  - `api.osv.dev` for the vulnerability check (also re-checked every 7 days,
    or immediately if you pass `-Audit`).
  - After setup, merging works offline. If osv.dev cannot be reached on a
    later run and the already-installed packages were previously checked, the
    script warns and continues. If the pinned set is new or changed and
    osv.dev cannot be reached, the script stops rather than install an
    unchecked set, unless you pass `-SkipAudit`.
- The script installs only under your user profile
  (`%LOCALAPPDATA%\SecurePdfCombiner`). It does not request administrator
  rights. Installing Python itself is separate and may still need them.
- Disk space:
  - Estimate: about 20 to 30 MB for the private Python environment (not
    measured by the script; actual size depends on your Python install).
  - In the destination folder, the script wants free space of at least
    twice the total input size, or the input size plus 512 MB, whichever is
    larger. It stops before merging if there is less. If free space cannot be
    measured (for example some UNC paths), it warns and continues only after
    you confirm.

The script does not install Python for you. Installing Python needs a signed
installer and sometimes admin rights, so that step is left to you on purpose.

## Quick start

1. Get the script (see [Get it](#get-it)) into a folder, for example
   `C:\Tools`, and [verify the hash](#verify-the-script).

2. Allow the downloaded script to run. Pick one:

   ```powershell
   # Remove the "downloaded from the internet" mark once:
   Unblock-File C:\Tools\secure-pdf-combiner-v3.3.ps1

   # Or bypass the execution policy for this single run only:
   powershell -ExecutionPolicy Bypass -File C:\Tools\secure-pdf-combiner-v3.3.ps1
   ```

3. Run it:

   ```powershell
   cd C:\Tools
   .\secure-pdf-combiner-v3.3.ps1
   ```

4. Answer the prompts:
   - **Folder path**: paste the folder that holds your PDFs. Quotes around
     the path are fine.
   - **PDF order**: type the numbers from the list in the order you want,
     for example `3,1,2` or `1-4,6`.
   - **Continue with this merge? Type Y or N**: review the preflight summary
     and type `Y`.

The script runs in 8 steps: check Python, check the private environment,
vulnerability check, check packages, select folder, find PDFs, preflight
check, combine and validate.

## Parameters and non-interactive use

All parameters are optional. If `-InputFolder` or `-Order` is left out, the
script asks for it. The final Y/N confirmation is always asked.

| Parameter | Type | Default | What it does |
|---|---|---|---|
| `-InputFolder` | string | (prompt) | Folder that contains the PDFs. If the folder does not exist, the script stops instead of asking again. |
| `-Order` | string | (prompt) | Merge order using the numbers shown in the file list. Commas separate items; ranges like `1-4` are allowed, and reverse ranges like `4-1` work too. Each number may appear only once, and at least two PDFs are required. |
| `-Audit` | switch | off | Force the vulnerability check now, even if it ran recently. |
| `-SkipAudit` | switch | off | Skip the vulnerability check (for offline use). Not recommended. |
| `-Reinstall` | switch | off | Delete and rebuild the private Python environment. |
| `-MaxFileSizeMB` | int (0 to 1048576) | 2048 | Refuse any single input PDF larger than this many MB. `0` disables the limit. |
| `-MaxPagesPerFile` | int (0 to 10000000) | 50000 | Refuse any single input PDF with more pages than this. `0` disables the limit. |

The numbers in `-Order` refer to the file list, which is sorted by file name.
Run once interactively, or look at the folder sorted by name, to know which
number is which file.

Examples:

```powershell
# Fully prompted
.\secure-pdf-combiner-v3.3.ps1

# Folder and order given; only the Y/N confirmation is asked
.\secure-pdf-combiner-v3.3.ps1 -InputFolder 'D:\Scans' -Order '2,1,3'

# Ranges: files 1 to 4, then 6
.\secure-pdf-combiner-v3.3.ps1 -InputFolder 'D:\Scans' -Order '1-4,6'

# Force a fresh vulnerability check
.\secure-pdf-combiner-v3.3.ps1 -Audit

# Offline machine that was set up earlier (not recommended for first install)
.\secure-pdf-combiner-v3.3.ps1 -SkipAudit

# Rebuild the private environment (for example after upgrading Python)
.\secure-pdf-combiner-v3.3.ps1 -Reinstall

# Allow a very large scan, and turn off the page limit
.\secure-pdf-combiner-v3.3.ps1 -MaxFileSizeMB 8192 -MaxPagesPerFile 0

# Built-in help
Get-Help .\secure-pdf-combiner-v3.3.ps1 -Full
```

## What it creates on disk

In `%LOCALAPPDATA%\SecurePdfCombiner` (usually
`C:\Users\<you>\AppData\Local\SecurePdfCombiner`):

| Item | Purpose |
|---|---|
| `venv\` | Private Python virtual environment with pypdf installed. |
| `requirements.txt` | The pinned package list with SHA256 hashes, as used for the install. |
| `install-state.json` | Hash of the pinned list, the environment's Python version, the pypdf version, and the time of the last vulnerability check. Used to skip reinstalling. |
| `merge-pdfs.py` | The embedded Python merger. Written once, then hash-checked before every run. |

In the PDF folder you chose:

- The output file: `Combined.pdf`. If that name is taken, the new file is
  named `Combined (2).pdf`, then `Combined (3).pdf`, and so on. Existing
  files are never overwritten.
- Files named `Combined.pdf` or `Combined (N).pdf`, and any `*.tmp.pdf`,
  are left out of the input list so earlier results are not merged by
  accident.
- While merging, a temporary file named like
  `.Combined_<processid>_<random>.tmp.pdf`. It is renamed to the final name
  after validation, or deleted if the merge fails or you press Ctrl+C.

The script does not touch the registry, scheduled tasks, startup items, or any
system folder. It only writes under `%LOCALAPPDATA%\SecurePdfCombiner` and in
the folder you selected.

### Uninstall

1. Delete the folder `%LOCALAPPDATA%\SecurePdfCombiner`:

   ```powershell
   Remove-Item -Recurse -Force "$env:LOCALAPPDATA\SecurePdfCombiner"
   ```

2. Delete the `.ps1` file. Python itself stays installed; remove it from
   Windows Settings > Apps if you no longer want it.

## Security design

- **Hash-pinned packages.** pypdf is pinned to an exact version and the SHA256
  of its wheel file. pip installs with `--require-hashes`, so a file whose
  hash does not match is refused, even if the package index served it.
- **No package setup code runs.** `--only-binary=:all:` allows wheels only.
  Source packages, which can run arbitrary build code during install, are
  never used. `--no-deps` installs exactly the pinned list and nothing else.
- **Vulnerability check before install.** The pinned versions are sent to the
  OSV database (`api.osv.dev`, the same data pip-audit uses) before anything
  is installed. Only package names and version numbers are sent. The check
  runs when the pinned set is new or changed, when the last check is older
  than 7 days, or when you pass `-Audit`. If any known vulnerability is
  reported, the script stops. On a first install or pin change, if osv.dev
  cannot be reached, the script stops rather than install unchecked packages
  (unless you pass `-SkipAudit`).
- **No reinstall on every run.** The install is skipped while the pinned list,
  the environment's Python version, and the installed pypdf version all
  match. pip is not upgraded on each run. This is also where most of the speed
  gain over v3.2 comes from.
- **Merger integrity check.** The Python merger is embedded in the script.
  Its SHA256 is compared with `merge-pdfs.py` on disk before every run; a
  modified file is rewritten, and if it still does not match, it is not run.
- **Python isolation.** Every Python call uses `-I` (isolated mode). This
  ignores `PYTHONPATH` and other `PYTHON*` variables, ignores the user
  site-packages folder, and keeps the current folder off the import path.
  Only the private environment's `python.exe` runs the merger.
- **No overwrite.** The output gets the next free `Combined (N).pdf` name, the
  merger creates its output file exclusively, and the final rename does not
  use `-Force`.
- **Cleanup.** The temporary file is removed in a `finally` block, so it also
  runs on errors and on Ctrl+C.
- **File caps and clean failures.** Per-file size and page limits
  (`-MaxFileSizeMB`, `-MaxPagesPerFile`). Each PDF is parsed once. Python's
  recursion limit is left at its default, and a malformed PDF ends with one
  clear error line instead of a crash.
- **TLS 1.2** is enabled for the OSV request so Windows PowerShell 5.1 is not
  left on an older default.

### What it does NOT protect against

- **A hash is not a publisher identity.** The hash proves you got the exact
  file that was pinned. It does not prove who built it. If a bad release
  were pinned, the hash would faithfully install it.
- **Hostile PDFs.** pypdf still parses whatever PDFs you give it. A
  deliberately crafted PDF could hit a pypdf bug. Be careful with PDFs from
  people you do not trust. The script does not claim to sanitize PDF
  JavaScript or other active content.
- **pip configuration is still read.** `pip.ini` and `PIP_*` environment
  variables still apply (so company proxies keep working). The hashes still
  protect what gets installed. Isolated mode (`-I`) does not pass
  `--isolated` to pip.
- **Encrypted PDFs are not supported.** Password-protected PDFs are refused,
  not unlocked.
- **Your own account.** Anything already running as you can change files in
  your profile, including the private environment. The script does not
  defend against malware already on the machine.

## Updating the pinned packages

The pins live in one block near the top of the script, `$RequirementsText`,
plus the `$PinnedPypdfVersion` variable used to verify the install.

1. Find the new pypdf version and its wheel hash from PyPI:

   ```powershell
   $v = "7.1.1"   # replace with the new version
   $info = Invoke-RestMethod "https://pypi.org/pypi/pypdf/$v/json"
   $info.urls | Where-Object { $_.filename -like "*py3-none-any.whl" } |
       Select-Object filename, @{n="sha256"; e={ $_.digests.sha256 }}
   ```

   The same information is on the "Download files" page at
   `https://pypi.org/project/pypdf/<version>/#files`.

2. Check the new version's requirements on that page (`Requires: Python`
   and required dependencies). pypdf 7.1.1 needs Python 3.10+ and only needs
   `typing_extensions` on Python 3.10. If a new version adds dependencies,
   pin each one with its own hash, because `--no-deps` will not fetch them.

3. Edit the script:
   - Change the `pypdf==...` line and its `--hash=sha256:...` value in
     `$RequirementsText`.
   - Change `$PinnedPypdfVersion` to the same version.
   - Update `typing_extensions` the same way if needed.

4. Optional: confirm the new version has no known issues at
   `https://osv.dev/list?ecosystem=PyPI&q=pypdf`.

5. Run the script. It notices the pinned list changed, runs the vulnerability
   check, and reinstalls. No `-Reinstall` needed.

Current pins in v3.3 (these SHA256 values are the ones embedded in the script;
they also match the `py3-none-any` wheel digests published on the PyPI JSON
API):

| Package | Version | Installed when | Wheel SHA256 |
|---|---|---|---|
| pypdf | 7.1.1 | always | `04c5680d4b4cfa04ab505b09393fc949860c34a4dad6565284d11a2f5c3ce8b1` |
| typing_extensions | 4.16.0 | Python 3.10 only (`python_version < "3.11"`) | `481caa481374e813c1b176ada14e97f1f67a4539ce9cfeb3f350d78d6370c2e8` |

Note: editing the script changes its own SHA256, so the hash at the top of
this README only matches the unmodified v3.3 file.

## Troubleshooting

Errors are shown under a red `MERGE STOPPED` banner. Errors from the Python
merger first print a line starting with `ERROR:`, followed by
`pypdf stopped with exit code 1.`

| Message | Cause | Fix |
|---|---|---|
| `... cannot be loaded because running scripts is disabled on this system` | PowerShell execution policy. | Use `Unblock-File` or `powershell -ExecutionPolicy Bypass -File ...` (see Quick start). |
| `LOCALAPPDATA is not set. This script is meant for Windows.` | Not running on Windows, or a broken user profile. | Run it on Windows in a normal user session. |
| `The Windows Python launcher 'py' was not found. Install Python 3.10+ from python.org.` | Python or the `py` launcher is missing. | Install Python with the py launcher option, or `winget install Python.Python.3.12`, then open a new terminal. |
| `Python was found but could not be started.` | The `py` launcher exists but no working Python 3 is behind it. | Run `py -3 --version` to see the problem; reinstall Python if needed. |
| `Python X.Y.Z is too old. Python 3.10 or newer is required.` | Newest Python 3 found is older than 3.10. | Install Python 3.10 or newer. |
| `The existing environment is broken or too old; rebuilding it.` (yellow) | The private environment no longer starts, often after uninstalling or upgrading Python. | Nothing to do; the script rebuilds it. |
| `Python could not create the isolated environment.` | `py -3 -m venv` failed (disk full, permissions, antivirus). | Check free space and that you can write to `%LOCALAPPDATA%`; try `-Reinstall`. |
| `The vulnerability database could not be reached: ... Use -SkipAudit to install without the check (not recommended).` | No internet, firewall, or proxy blocking `api.osv.dev` during a first install or pin change. | Allow access to `api.osv.dev`, or knowingly use `-SkipAudit`. |
| `Could not reach osv.dev (...). Continuing with the already-installed, previously checked packages.` (yellow) | Offline on a later run when packages were already checked. | Nothing to do; the check is retried next run. |
| `Known vulnerabilities were reported for the pinned packages. Update the pins (see https://osv.dev) before merging.` | OSV lists an advisory for a pinned version (IDs are printed above). | Update the pins (see "Updating the pinned packages"). |
| `The pinned packages could not be installed (exit code N).` | Download blocked, or a hash mismatch (`THESE PACKAGES DO NOT MATCH THE HASHES`). | Check internet/proxy access to PyPI. If you edited the pins, re-check the hash. A mismatch on an unedited script means the download was not the expected file; do not bypass it. |
| `Installed packages do not match the pins; reinstalling.` (yellow) | The environment was changed outside the script. | Nothing to do; the script reinstalls. |
| `pypdf 7.1.1 could not be imported after installation.` | Install looked successful but pypdf will not load. | Run with `-Reinstall`. |
| `Folder not found: <path>` | Wrong path, or a drive that is not mounted. | Check the path; paste it without extra characters. |
| `At least two usable PDF files are required in this folder.` | Fewer than two `.pdf` files, after leaving out `Combined.pdf`, `Combined (N).pdf`, and `*.tmp.pdf`. | Put at least two PDFs in the folder, or rename inputs that are named `Combined.pdf` / `Combined (N).pdf`. |
| `No order was entered.` / `'x' is not a valid whole number or range.` | Empty or malformed order. | Use numbers and ranges separated by commas, like `3,1,2` or `1-4,6`. |
| `PDF number N does not exist.` | Number outside the listed range. | Use only numbers shown in the list. |
| `Select at least two PDFs.` | Only one file chosen. | Choose two or more. |
| `Each selected PDF number can appear only once.` | Duplicate in the order (ranges count too). | Remove the duplicate. |
| `<file> is larger than the N MB per-file limit (see -MaxFileSizeMB).` | Input exceeds the size cap. | Raise `-MaxFileSizeMB`, or use `0` to disable. |
| `Not enough free disk space for the safety target.` | Free space below the target shown in the preflight. | Free up space on that drive. |
| `Free space could not be measured for this location.` (yellow) | Network share or path without a drive letter. | Make sure the destination has room; the merge still proceeds after you confirm. |
| `The merger script failed its integrity check and was not run.` | `merge-pdfs.py` could not be written correctly (antivirus, disk, or something rewriting it). | Check antivirus logs and disk; delete `merge-pdfs.py` and run again. |
| `ERROR: RuntimeError: Encrypted or password-protected PDF is not supported: <file>` | An input PDF is encrypted. | Save an unencrypted copy (for example "Print to PDF") and use that. |
| `ERROR: RuntimeError: PDF has no readable pages: <file>` | Empty or damaged PDF. | Repair or replace the file. |
| `ERROR: RuntimeError: <file> has N pages; the limit is M.` | Input exceeds the page cap. | Raise `-MaxPagesPerFile`, or use `0` to disable. |
| `ERROR: FileNotFoundError: Input PDF not found: <path>` | The file was moved or deleted after it was listed. | Run again. |
| `ERROR: PdfStreamError: ...` or another pypdf error | Damaged or non-standard PDF. | Open and re-save the PDF in a viewer, then retry. |
| `ERROR: RuntimeError: Validation failed: expected N pages, got M.` | Output page count does not match the inputs. | Nothing is written to the final name. Retry; if it repeats, one input is likely damaged. |
| `pypdf stopped with exit code N.` | Follows any merger error above. | See the `ERROR:` line printed just before it. |
| `The validated temporary PDF is missing or empty.` | Temp file vanished, often removed by antivirus or a sync tool. | Pause cloud sync for the folder or exclude it from scanning, then retry. |
| Move error after validation | Something created the same output name during the merge. | Run again; the script picks the next free name. |

## History

The current release is v3.3. This repository also includes:

- [history/original-v3.2.ps1](history/original-v3.2.ps1) - the previous version
- [history/v3.2-to-v3.3.diff](history/v3.2-to-v3.3.diff) - the changes from v3.2 to v3.3

v3.2 is superseded and unsupported, kept only for comparison; do not run it.

**v3.3**

- pypdf pinned to an exact version with a SHA256 hash; installed with
  `--require-hashes --only-binary=:all: --no-deps` from a requirements file
  the script writes.
- Install happens once; later runs skip pip unless the pins or Python change,
  the environment breaks, or `-Reinstall` is used. No more pip upgrade on every
  run.
- pip-audit removed. In v3.2 it was installed with unpinned dependencies.
  Replaced by a direct OSV lookup of the pinned versions, run before install,
  on pin changes, every 7 days, or with `-Audit`. New `-SkipAudit` for offline
  use.
- Python 3.10+ required (needed by pypdf 7.x); checked up front.
- Merger script is written once and hash-checked before every run, instead of
  being rewritten and deleted each time.
- Merger parses each PDF once instead of twice; the raised recursion limit is
  removed; per-file size and page caps added.
- Existing `Combined.pdf` is kept; new output goes to `Combined (N).pdf`.
- Temporary file cleanup moved to `finally`, so it also runs on Ctrl+C.
- All Python calls use isolated mode (`-I`).
- New optional parameters: `-InputFolder`, `-Order` (with ranges), `-Audit`,
  `-SkipAudit`, `-Reinstall`, `-MaxFileSizeMB`, `-MaxPagesPerFile`.
  `Get-Help` works (the script has comment-based help).
- Only exact `.pdf` extensions are listed.

**v3.2**

- Created a venv in `%LOCALAPPDATA%\SecurePdfCombiner`, upgraded pip and
  installed the latest pypdf and pip-audit on every run, ran pip-audit, then
  merged the chosen PDFs into `Combined.pdf` with page-count validation.
  An existing `Combined.pdf` was replaced after the new file passed
  validation (`Move-Item -Force`).

## License and security

This project is released under the [MIT License](LICENSE).
Copyright (c) 2026 Sahil Kamboj.

To report a vulnerability, see [SECURITY.md](SECURITY.md).
