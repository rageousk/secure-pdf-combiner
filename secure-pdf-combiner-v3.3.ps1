<#
.SYNOPSIS
    Secure pypdf PDF Combiner V3.3 - merge PDFs in a chosen order, safely.

.DESCRIPTION
    Merges two or more PDFs from one folder into a single PDF and checks that
    the result has exactly the expected number of pages.

    What makes it "secure" (the short version):
      * Dependencies are pinned to exact versions AND SHA256 hashes. pip will
        refuse any file whose hash does not match, so a tampered or swapped
        package on the index cannot be installed.
      * Packages are installed once. Later runs skip pip entirely unless the
        pinned set changes or the environment is broken. (Faster, too.)
      * The pinned versions are checked against the OSV vulnerability database
        BEFORE anything is installed, and again every few days.
      * Python always runs with -I (isolated mode), so PYTHONPATH, PYTHON*
        environment variables and the user site-packages folder cannot inject
        code into the merge.
      * The embedded merger script is hash-checked before every run.
      * Nothing is ever overwritten: an existing Combined.pdf is kept and the
        new file gets the next free name, e.g. "Combined (2).pdf".
      * The temporary output is removed even if you press Ctrl+C.

.PARAMETER InputFolder
    Folder that contains the PDFs. If omitted, you are asked for it.

.PARAMETER Order
    Merge order as numbers from the listed files, e.g. "3,1,2" or "1-3,5".
    If omitted, you are asked for it.

.PARAMETER Audit
    Force the vulnerability check now, even if it ran recently.

.PARAMETER SkipAudit
    Skip the vulnerability check (for offline use). Not recommended.

.PARAMETER Reinstall
    Delete and rebuild the private Python environment.

.PARAMETER MaxFileSizeMB
    Refuse any single input PDF larger than this. 0 disables the limit.

.PARAMETER MaxPagesPerFile
    Refuse any single input PDF with more pages than this. 0 disables the limit.

.EXAMPLE
    .\secure-pdf-combiner-v3.3.ps1

.EXAMPLE
    .\secure-pdf-combiner-v3.3.ps1 -InputFolder 'D:\Scans' -Order '2,1,3'
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive console tool: colored status text is meant for the person at the keyboard, not the pipeline.')]
[CmdletBinding()]
param(
    [string]$InputFolder,
    [string]$Order,
    [switch]$Audit,
    [switch]$SkipAudit,
    [switch]$Reinstall,
    [ValidateRange(0, 1048576)][int]$MaxFileSizeMB = 2048,
    [ValidateRange(0, 10000000)][int]$MaxPagesPerFile = 50000
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
$ScriptVersion      = "3.3"
$OutputBaseName     = "Combined"          # output is Combined.pdf, Combined (2).pdf, ...
$MinimumPython      = [version]"3.10"     # pypdf 7.x requires Python 3.10+
$AuditIntervalDays  = 7                   # re-check OSV at least this often
$OsvBatchUrl        = "https://api.osv.dev/v1/querybatch"

if (-not $env:LOCALAPPDATA) {
    Write-Host "LOCALAPPDATA is not set. This script is meant for Windows." -ForegroundColor Red
    exit 1
}

$AppFolder        = Join-Path $env:LOCALAPPDATA "SecurePdfCombiner"
$VenvFolder       = Join-Path $AppFolder "venv"
$VenvPython       = Join-Path $VenvFolder "Scripts\python.exe"
$RequirementsFile = Join-Path $AppFolder "requirements.txt"
$StateFile        = Join-Path $AppFolder "install-state.json"
$MergerScript     = Join-Path $AppFolder "merge-pdfs.py"
$TemporaryOutput  = $null

# UTF-8 without a byte-order mark, so file bytes (and their hashes) are the
# same on Windows PowerShell 5.1 and PowerShell 7.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------
# Pinned dependencies (the single source of truth)
#
# Each hash is the SHA256 of the py3-none-any wheel published on PyPI, taken
# from https://pypi.org/pypi/<name>/<version>/json and re-checked by
# downloading the wheel. pypdf has no required dependencies on Python 3.11+;
# on Python 3.10 it needs typing_extensions, hence the environment marker.
#
# To upgrade: change the version, paste the new wheel hash, run once.
# The script notices the change, audits the new set, and reinstalls.
# ---------------------------------------------------------------------------
$RequirementsText = @'
# Pinned, hash-locked dependencies for Secure PDF Combiner.
# Installed with: pip install --require-hashes --only-binary=:all: --no-deps
pypdf==7.1.1 --hash=sha256:04c5680d4b4cfa04ab505b09393fc949860c34a4dad6565284d11a2f5c3ce8b1
typing_extensions==4.16.0 ; python_version < "3.11" --hash=sha256:481caa481374e813c1b176ada14e97f1f67a4539ce9cfeb3f350d78d6370c2e8
'@
$PinnedPypdfVersion = "7.1.1"

# ---------------------------------------------------------------------------
# Embedded merger (Python). Written once to the app folder, then verified by
# SHA256 before every run so a modified copy is never executed.
# ---------------------------------------------------------------------------
$PythonCode = @'
"""Merge PDFs in the given order and verify the page count of the result.

Usage:
    python -I merge-pdfs.py [--max-pages N] -- OUTPUT INPUT1 INPUT2 [...]
"""

import argparse
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter

MIN_INPUTS = 2


def open_pdf(path, max_pages):
    """Open one input PDF once, run sanity checks, and return (reader, pages)."""
    if not path.is_file():
        msg = f"Input PDF not found: {path}"
        raise FileNotFoundError(msg)

    reader = PdfReader(path, strict=False)
    if reader.is_encrypted:
        msg = f"Encrypted or password-protected PDF is not supported: {path.name}"
        raise RuntimeError(msg)

    count = len(reader.pages)
    if count < 1:
        msg = f"PDF has no readable pages: {path.name}"
        raise RuntimeError(msg)
    if max_pages and count > max_pages:
        msg = f"{path.name} has {count} pages; the limit is {max_pages}."
        raise RuntimeError(msg)
    return reader, count


def main(argv):
    """Merge argv inputs into the output path and check the page count."""
    parser = argparse.ArgumentParser(description="Merge PDFs and verify page count.")
    parser.add_argument("--max-pages", type=int, default=0)
    parser.add_argument("output", type=Path)
    parser.add_argument("inputs", type=Path, nargs="+")
    args = parser.parse_args(argv)

    if len(args.inputs) < MIN_INPUTS:
        parser.error("at least two input PDFs are required")

    expected_pages = 0
    writer = PdfWriter()
    try:
        for path in args.inputs:
            # Each file is parsed once and the same reader is appended,
            # instead of parsing it a second time inside append(path).
            reader, page_count = open_pdf(path, args.max_pages)
            print(f"Adding: {path.name} ({page_count} pages)", flush=True)
            writer.append(reader)
            expected_pages += page_count

        # "xb" = create exclusively: fail rather than overwrite an existing file.
        with args.output.open("xb") as output_stream:
            writer.write(output_stream)
    finally:
        writer.close()

    if args.output.stat().st_size <= 0:
        msg = "The output PDF is empty."
        raise RuntimeError(msg)

    actual_pages = len(PdfReader(args.output, strict=False).pages)
    if actual_pages != expected_pages:
        msg = f"Validation failed: expected {expected_pages} pages, got {actual_pages}."
        raise RuntimeError(msg)

    print(f"Validation passed: {actual_pages} pages.", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    # Top-level handler on purpose: print one clean line instead of a
    # traceback, including RecursionError/MemoryError from hostile PDFs.
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(1)
'@

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Format-FileSize {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ("{0:N2} TB" -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return ("{0:N0} bytes" -f $Bytes)
}

function Read-YesNo {
    param([string]$Prompt)
    while ($true) {
        $Answer = Read-Host $Prompt
        if ($null -eq $Answer) { $Answer = "" }
        $Answer = $Answer.Trim()
        if ($Answer -match "^[Yy]$") { return $true }
        if ($Answer -match "^[Nn]$") { return $false }
        Write-Host "Please enter Y or N." -ForegroundColor Yellow
    }
}

function Get-Sha256Hex {
    # SHA256 of a byte array, as uppercase hex (same format as Get-FileHash).
    param([byte[]]$Bytes)
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($Sha.ComputeHash($Bytes))).Replace("-", "")
    }
    finally {
        $Sha.Dispose()
    }
}

function Invoke-VenvPython {
    # Runs the venv's python.exe in isolated mode (-I = -E -s -P):
    # ignores PYTHON* variables, the user site-packages folder, and does not
    # put the current directory on sys.path. Native stderr output must not be
    # turned into a terminating error on Windows PowerShell 5.1, so the
    # preference is relaxed for the call; callers check $LASTEXITCODE.
    param([string[]]$Arguments)
    $OldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $VenvPython -I @Arguments
    }
    finally {
        $ErrorActionPreference = $OldPreference
    }
}

function Get-PinnedPackage {
    # Turns "name==version ..." lines of the requirements text into objects.
    param([string]$Text)
    foreach ($Line in ($Text -split "`r?`n")) {
        if ($Line -match '^\s*([A-Za-z0-9_.\-]+)==([^\s;]+)') {
            [pscustomobject]@{ Name = $Matches[1]; Version = $Matches[2] }
        }
    }
}

function Invoke-OsvAudit {
    # Asks the OSV database (osv.dev, the same data pip-audit uses) whether
    # any pinned version has a known vulnerability. Returns finding strings.
    param([object[]]$Packages)
    $Queries = @(
        foreach ($Package in $Packages) {
            @{ package = @{ name = $Package.Name; ecosystem = "PyPI" }; version = $Package.Version }
        }
    )
    $Body = @{ queries = $Queries } | ConvertTo-Json -Depth 6
    $Response = Invoke-RestMethod -Uri $OsvBatchUrl -Method Post -Body $Body `
        -ContentType "application/json" -TimeoutSec 20

    $Findings = @()
    for ($i = 0; $i -lt $Packages.Count; $i++) {
        $Result = $Response.results[$i]
        if ($null -ne $Result -and $Result.PSObject.Properties["vulns"]) {
            foreach ($Vuln in $Result.vulns) {
                $Findings += "$($Packages[$i].Name) $($Packages[$i].Version): $($Vuln.id)"
            }
        }
    }
    return $Findings
}

function Read-InstallState {
    if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json) }
    catch { return $null }
}

function Save-InstallState {
    param([string]$RequirementsHash, [string]$PythonVersion, [long]$LastAuditUnix)
    $State = [ordered]@{
        RequirementsSha256 = $RequirementsHash
        VenvPythonVersion  = $PythonVersion
        PypdfVersion       = $PinnedPypdfVersion
        LastAuditUnix      = $LastAuditUnix
    }
    [System.IO.File]::WriteAllText($StateFile, ($State | ConvertTo-Json), $Utf8NoBom)
}

function ConvertTo-MergeOrder {
    # Parses "3,1,2" or "1-3,5" into a list of distinct numbers.
    # Throws a friendly message if the text is not valid.
    param([string]$Text, [int]$MaxNumber)
    if ($null -eq $Text -or -not $Text.Trim()) { throw "No order was entered." }

    $Numbers = New-Object System.Collections.Generic.List[int]
    foreach ($Part in ($Text -split ",")) {
        $CleanPart = $Part.Trim()
        if ($CleanPart -match '^(\d+)\s*-\s*(\d+)$') {
            $From = [int]$Matches[1]; $To = [int]$Matches[2]
            $Step = 1
            if ($To -lt $From) { $Step = -1 }
            for ($n = $From; $n -ne ($To + $Step); $n += $Step) { $Numbers.Add($n) }
        }
        elseif ($CleanPart -match '^\d+$') {
            $Numbers.Add([int]$CleanPart)
        }
        else {
            throw "'$CleanPart' is not a valid whole number or range."
        }
    }

    foreach ($n in $Numbers) {
        if ($n -lt 1 -or $n -gt $MaxNumber) { throw "PDF number $n does not exist." }
    }
    if ($Numbers.Count -lt 2) { throw "Select at least two PDFs." }
    if (@($Numbers | Sort-Object -Unique).Count -ne $Numbers.Count) {
        throw "Each selected PDF number can appear only once."
    }
    return , $Numbers.ToArray()
}

function Get-UniqueOutputPath {
    # Combined.pdf, or Combined (2).pdf, Combined (3).pdf, ... if taken.
    param([string]$Folder)
    $Candidate = Join-Path $Folder "$OutputBaseName.pdf"
    $Number = 2
    while (Test-Path -LiteralPath $Candidate) {
        $Candidate = Join-Path $Folder ("{0} ({1}).pdf" -f $OutputBaseName, $Number)
        $Number++
    }
    return $Candidate
}

function Clear-TemporaryOutput {
    # Python may still hold the file for a moment after Ctrl+C.
    param([string]$Path)
    for ($Attempt = 0; $Attempt -lt 10; $Attempt++) {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        try { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop; return }
        catch { Start-Sleep -Milliseconds 300 }
    }
}

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "             SECURE pypdf PDF COMBINER V$ScriptVersion" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

try {
    # --- 1. Python -----------------------------------------------------------
    Write-Host "[1/8] Checking Python..." -ForegroundColor Yellow
    if ($null -eq (Get-Command py -ErrorAction SilentlyContinue)) {
        throw "The Windows Python launcher 'py' was not found. Install Python 3.10+ from python.org."
    }

    $BaseVersionText = & py -3 -I -c "import sys; print('%d.%d.%d' % sys.version_info[:3])"
    if ($LASTEXITCODE -ne 0 -or -not $BaseVersionText) {
        throw "Python was found but could not be started."
    }
    if ([version]$BaseVersionText -lt $MinimumPython) {
        throw "Python $BaseVersionText is too old. Python $MinimumPython or newer is required."
    }
    Write-Host "Python found: $BaseVersionText" -ForegroundColor Green

    # --- 2. Private environment ---------------------------------------------
    Write-Host ""
    Write-Host "[2/8] Checking isolated PDF environment..." -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath $AppFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $AppFolder -Force | Out-Null
    }

    $RequirementsHash = Get-Sha256Hex -Bytes $Utf8NoBom.GetBytes($RequirementsText)
    $State = Read-InstallState

    $VenvPythonVersion = $null
    if (-not $Reinstall -and (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        $VenvPythonVersion = Invoke-VenvPython -Arguments @("-c", "import sys; print('%d.%d.%d' % sys.version_info[:3])")
        if ($LASTEXITCODE -ne 0 -or -not $VenvPythonVersion -or [version]$VenvPythonVersion -lt $MinimumPython) {
            Write-Host "The existing environment is broken or too old; rebuilding it." -ForegroundColor Yellow
            $VenvPythonVersion = $null
        }
    }

    if ($null -eq $VenvPythonVersion) {
        if (Test-Path -LiteralPath $VenvFolder) {
            Remove-Item -LiteralPath $VenvFolder -Recurse -Force
        }
        Write-Host "Creating the dedicated PDF environment..."
        & py -3 -I -m venv $VenvFolder
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
            throw "Python could not create the isolated environment."
        }
        $VenvPythonVersion = Invoke-VenvPython -Arguments @("-c", "import sys; print('%d.%d.%d' % sys.version_info[:3])")
        $State = $null   # fresh environment: nothing installed yet
    }

    # The environment "matches" when the recorded install used exactly this
    # pinned set on exactly this Python. Only then can pip be skipped.
    $StateMatches = ($null -ne $State) -and
        ($State.RequirementsSha256 -eq $RequirementsHash) -and
        ($State.VenvPythonVersion -eq $VenvPythonVersion)
    Write-Host "Isolated PDF environment ready (Python $VenvPythonVersion)." -ForegroundColor Green

    # --- 3. Vulnerability check (before installing) --------------------------
    Write-Host ""
    Write-Host "[3/8] Checking pinned packages for known vulnerabilities..." -ForegroundColor Yellow
    $PinnedPackages = @(Get-PinnedPackage -Text $RequirementsText)
    $NowUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $LastAuditUnix = 0
    if ($null -ne $State -and $State.PSObject.Properties["LastAuditUnix"]) {
        $LastAuditUnix = [long]$State.LastAuditUnix
    }

    $AuditReason = $null
    if ($SkipAudit) { $AuditReason = $null }
    elseif ($Audit) { $AuditReason = "requested with -Audit" }
    elseif (-not $StateMatches) { $AuditReason = "the pinned package set is new or changed" }
    elseif (($NowUnix - $LastAuditUnix) -gt ($AuditIntervalDays * 86400)) {
        $AuditReason = "the last check is older than $AuditIntervalDays days"
    }

    if ($SkipAudit) {
        Write-Host "Skipped (-SkipAudit)." -ForegroundColor Yellow
    }
    elseif ($null -eq $AuditReason) {
        $DaysAgo = [math]::Floor(($NowUnix - $LastAuditUnix) / 86400)
        Write-Host "Last check passed $DaysAgo day(s) ago; next check within $AuditIntervalDays days." -ForegroundColor Green
    }
    else {
        Write-Host "Querying osv.dev because $AuditReason..."
        # Windows PowerShell 5.1 may default to old TLS versions.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $Findings = $null
        try {
            $Findings = @(Invoke-OsvAudit -Packages $PinnedPackages)
        }
        catch {
            if (-not $StateMatches) {
                # Fail closed: never install an unchecked set.
                throw "The vulnerability database could not be reached: $($_.Exception.Message) Use -SkipAudit to install without the check (not recommended)."
            }
            Write-Host "Could not reach osv.dev ($($_.Exception.Message)). Continuing with the already-installed, previously checked packages." -ForegroundColor Yellow
        }

        if ($null -ne $Findings) {
            if ($Findings.Count -gt 0) {
                foreach ($Finding in $Findings) { Write-Host "  $Finding" -ForegroundColor Red }
                throw "Known vulnerabilities were reported for the pinned packages. Update the pins (see https://osv.dev) before merging."
            }
            $LastAuditUnix = $NowUnix
            foreach ($Package in $PinnedPackages) {
                Write-Host "  $($Package.Name) $($Package.Version): no known vulnerabilities" -ForegroundColor Green
            }
        }
    }

    # --- 4. Install (only when needed) and verify -----------------------------
    Write-Host ""
    Write-Host "[4/8] Checking required packages..." -ForegroundColor Yellow
    $InstalledVersion = $null
    if ($StateMatches) {
        $InstalledVersion = Invoke-VenvPython -Arguments @("-c", "import pypdf; print(pypdf.__version__)")
        if ($LASTEXITCODE -ne 0 -or $InstalledVersion -ne $PinnedPypdfVersion) {
            Write-Host "Installed packages do not match the pins; reinstalling." -ForegroundColor Yellow
            $StateMatches = $false
        }
    }

    if (-not $StateMatches) {
        [System.IO.File]::WriteAllText($RequirementsFile, $RequirementsText, $Utf8NoBom)
        # --require-hashes : every file must match its pinned SHA256
        # --only-binary    : wheels only, so no package build code ever runs
        # --no-deps        : install exactly the pinned list, nothing else
        Invoke-VenvPython -Arguments @(
            "-m", "pip", "install",
            "--require-hashes", "--only-binary=:all:", "--no-deps",
            "--no-input", "--disable-pip-version-check",
            "-r", $RequirementsFile
        )
        if ($LASTEXITCODE -ne 0) {
            throw "The pinned packages could not be installed (exit code $LASTEXITCODE)."
        }

        $InstalledVersion = Invoke-VenvPython -Arguments @("-c", "import pypdf; print(pypdf.__version__)")
        if ($LASTEXITCODE -ne 0 -or $InstalledVersion -ne $PinnedPypdfVersion) {
            throw "pypdf $PinnedPypdfVersion could not be imported after installation."
        }
    }
    else {
        Write-Host "Pinned packages already installed; skipping pip." -ForegroundColor Green
    }
    Save-InstallState -RequirementsHash $RequirementsHash -PythonVersion $VenvPythonVersion -LastAuditUnix $LastAuditUnix
    Write-Host "pypdf: $InstalledVersion (hash-pinned)" -ForegroundColor Green

    # --- 5. Folder -----------------------------------------------------------
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "[5/8] SELECT PDF FOLDER" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan

    if ($InputFolder) {
        $InputFolder = $InputFolder.Trim().Trim('"').Trim("'")
        if (-not (Test-Path -LiteralPath $InputFolder -PathType Container)) {
            throw "Folder not found: $InputFolder"
        }
    }
    else {
        Write-Host "Paste the full path to the folder containing your PDFs."
        Write-Host "Examples:" -ForegroundColor DarkGray
        Write-Host 'C:\Users\YourName\Documents\PDFs' -ForegroundColor DarkGray
        Write-Host 'D:\Documents\PDFs-To-Combine' -ForegroundColor DarkGray
        Write-Host 'H:\My Drive\Folder\PDFs' -ForegroundColor DarkGray
        Write-Host ""
        while ($true) {
            $InputFolder = Read-Host "Folder path"
            if ($null -eq $InputFolder) { $InputFolder = "" }
            $InputFolder = $InputFolder.Trim().Trim('"').Trim("'")
            if (-not $InputFolder) {
                Write-Host "No folder path was entered. Try again." -ForegroundColor Red
                continue
            }
            if (-not (Test-Path -LiteralPath $InputFolder -PathType Container)) {
                Write-Host "Folder not found: $InputFolder" -ForegroundColor Red
                continue
            }
            break
        }
    }
    $InputFolder = (Resolve-Path -LiteralPath $InputFolder).Path
    Write-Host "Folder accepted: $InputFolder" -ForegroundColor Green

    # --- 6. Find PDFs --------------------------------------------------------
    Write-Host ""
    Write-Host "[6/8] Finding PDFs..." -ForegroundColor Yellow
    $PreviousOutputPattern = '^' + [regex]::Escape($OutputBaseName) + '( \(\d+\))?\.pdf$'
    $PdfFiles = @(
        Get-ChildItem -LiteralPath $InputFolder -File -Filter "*.pdf" |
        Where-Object {
            # -Filter "*.pdf" can also match ".pdfx" etc. on Windows; be exact.
            $_.Extension -eq ".pdf" -and
            $_.Name -notmatch $PreviousOutputPattern -and
            $_.Name -notlike "*.tmp.pdf"
        } |
        Sort-Object Name
    )

    if ($PdfFiles.Count -lt 2) {
        throw "At least two usable PDF files are required in this folder."
    }

    Write-Host "Found $($PdfFiles.Count) PDF files." -ForegroundColor Green
    Write-Host ""
    Write-Host "AVAILABLE PDFs" -ForegroundColor Cyan
    for ($i = 0; $i -lt $PdfFiles.Count; $i++) {
        $SizeText = Format-FileSize -Bytes $PdfFiles[$i].Length
        Write-Host ("[{0}] {1} ({2})" -f ($i + 1), $PdfFiles[$i].Name, $SizeText)
    }

    if ($Order) {
        $OrderNumbers = ConvertTo-MergeOrder -Text $Order -MaxNumber $PdfFiles.Count
    }
    else {
        Write-Host ""
        Write-Host "Enter at least two numbers in the exact merge order." -ForegroundColor Yellow
        Write-Host "Example 1,2,3 merges PDFs 1, 2, and 3."
        Write-Host "Example 5,4,1 merges only PDFs 5, 4, and 1."
        Write-Host "Example 1-4,6 merges PDFs 1 to 4, then 6."
        while ($true) {
            try {
                $OrderNumbers = ConvertTo-MergeOrder -Text (Read-Host "PDF order") -MaxNumber $PdfFiles.Count
                break
            }
            catch {
                Write-Host "$($_.Exception.Message) Try again." -ForegroundColor Red
            }
        }
    }

    $OrderedPdfFiles = @(foreach ($SelectedNumber in $OrderNumbers) { $PdfFiles[$SelectedNumber - 1] })

    # --- 7. Preflight --------------------------------------------------------
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "[7/8] PREFLIGHT CHECK" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "Final merge order:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $OrderedPdfFiles.Count; $i++) {
        Write-Host ("{0}. {1}" -f ($i + 1), $OrderedPdfFiles[$i].Name)
    }

    if ($MaxFileSizeMB -gt 0) {
        $TooBig = @($OrderedPdfFiles | Where-Object { $_.Length -gt ([long]$MaxFileSizeMB * 1MB) })
        if ($TooBig.Count -gt 0) {
            throw "$($TooBig[0].Name) is larger than the $MaxFileSizeMB MB per-file limit (see -MaxFileSizeMB)."
        }
    }

    $SelectedBytes = [double]($OrderedPdfFiles | Measure-Object -Property Length -Sum).Sum
    $SelectedSizeText = Format-FileSize -Bytes $SelectedBytes
    $RequiredFreeBytes = [math]::Max($SelectedBytes * 2, $SelectedBytes + 512MB)

    $OutputFile = Get-UniqueOutputPath -Folder $InputFolder
    Write-Host ""
    Write-Host "Selected PDFs: $($OrderedPdfFiles.Count)" -ForegroundColor Cyan
    Write-Host "Total input: $SelectedSizeText" -ForegroundColor Cyan
    Write-Host "Output: $OutputFile" -ForegroundColor Cyan
    if ((Split-Path -Leaf $OutputFile) -ne "$OutputBaseName.pdf") {
        Write-Host "($OutputBaseName.pdf already exists and will be kept untouched.)" -ForegroundColor Yellow
    }

    $FreeBytes = $null
    try {
        $PathRoot = Split-Path -Path $InputFolder -Qualifier
        if ($PathRoot) {
            $PSDrive = Get-PSDrive -Name $PathRoot.TrimEnd(':', '\') -ErrorAction Stop
            if ($null -ne $PSDrive.Free) { $FreeBytes = [double]$PSDrive.Free }
        }
    }
    catch {
        $FreeBytes = $null   # e.g. UNC paths have no drive letter
    }

    if ($null -ne $FreeBytes) {
        Write-Host "Free disk: $(Format-FileSize -Bytes $FreeBytes)" -ForegroundColor Cyan
        Write-Host "Safety target: $(Format-FileSize -Bytes $RequiredFreeBytes)" -ForegroundColor Cyan
        if ($FreeBytes -lt $RequiredFreeBytes) {
            throw "Not enough free disk space for the safety target."
        }
        Write-Host "Disk-space check passed." -ForegroundColor Green
    }
    else {
        Write-Host "Free space could not be measured for this location." -ForegroundColor Yellow
        Write-Host "Make sure the destination has adequate free space." -ForegroundColor Yellow
    }

    if ($SelectedBytes -ge 1GB) {
        Write-Host ""
        Write-Host "LARGE MERGE WARNING" -ForegroundColor Yellow
        Write-Host "The selected input is at least 1 GB." -ForegroundColor Yellow
        Write-Host "Close unnecessary applications before continuing." -ForegroundColor Yellow
    }

    Write-Host ""
    if (-not (Read-YesNo -Prompt "Continue with this merge? Type Y or N")) {
        Write-Host "Merge cancelled. No files were changed." -ForegroundColor Yellow
        exit 0
    }

    # --- 8. Merge ------------------------------------------------------------
    Write-Host ""
    Write-Host "[8/8] Combining and validating PDFs..." -ForegroundColor Yellow

    # Write the merger once; afterwards only verify it. Run it only if the
    # bytes on disk are exactly the bytes embedded in this script.
    $MergerBytes = $Utf8NoBom.GetBytes($PythonCode)
    $MergerHash = Get-Sha256Hex -Bytes $MergerBytes
    if (-not (Test-Path -LiteralPath $MergerScript -PathType Leaf) -or
        (Get-FileHash -LiteralPath $MergerScript -Algorithm SHA256).Hash -ne $MergerHash) {
        [System.IO.File]::WriteAllBytes($MergerScript, $MergerBytes)
    }
    if ((Get-FileHash -LiteralPath $MergerScript -Algorithm SHA256).Hash -ne $MergerHash) {
        throw "The merger script failed its integrity check and was not run."
    }

    # Hidden temp file in the destination folder, so the final step is a
    # same-volume rename. Set before Python starts so 'finally' can clean it.
    $TemporaryOutput = Join-Path $InputFolder (".{0}_{1}_{2}.tmp.pdf" -f $OutputBaseName, $PID, [guid]::NewGuid().ToString("N").Substring(0, 12))

    $InputPaths = @($OrderedPdfFiles | ForEach-Object { $_.FullName })
    Invoke-VenvPython -Arguments (@($MergerScript, "--max-pages", "$MaxPagesPerFile", "--", $TemporaryOutput) + $InputPaths)
    if ($LASTEXITCODE -ne 0) {
        throw "pypdf stopped with exit code $LASTEXITCODE."
    }

    if (-not (Test-Path -LiteralPath $TemporaryOutput -PathType Leaf) -or
        (Get-Item -LiteralPath $TemporaryOutput).Length -le 0) {
        throw "The validated temporary PDF is missing or empty."
    }

    # No -Force: if something created the output name meanwhile, stop
    # instead of overwriting it.
    Move-Item -LiteralPath $TemporaryOutput -Destination $OutputFile

    $FinalSizeText = Format-FileSize -Bytes (Get-Item -LiteralPath $OutputFile).Length

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "                         SUCCESS" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "PDFs combined: $($OrderedPdfFiles.Count)" -ForegroundColor Green
    Write-Host "Input size: $SelectedSizeText" -ForegroundColor Green
    Write-Host "Output size: $FinalSizeText" -ForegroundColor Green
    Write-Host "Created: $OutputFile" -ForegroundColor Cyan
    Write-Host "The output passed page-count validation." -ForegroundColor Green
    Write-Host "Your original PDFs were not changed." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "                       MERGE STOPPED" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    # Runs on success, on error, and on Ctrl+C.
    if ($TemporaryOutput) {
        Clear-TemporaryOutput -Path $TemporaryOutput
    }
}
