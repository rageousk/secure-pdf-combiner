# Secure pypdf PDF Combiner V3.2
$ErrorActionPreference = "Stop"

$OutputFileName = "Combined.pdf"
$AppFolder = Join-Path $env:LOCALAPPDATA "SecurePdfCombiner"
$VenvFolder = Join-Path $AppFolder "venv"
$VenvPython = Join-Path $VenvFolder "Scripts\python.exe"
$MergerScript = Join-Path $AppFolder "merge-pdfs.py"
$TemporaryOutput = $null

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

Clear-Host
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "             SECURE pypdf PDF COMBINER V3.2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

try {
    Write-Host "[1/8] Checking Python..." -ForegroundColor Yellow
    $PythonCommand = Get-Command py -ErrorAction SilentlyContinue
    if ($null -eq $PythonCommand) {
        throw "The Windows Python launcher 'py' was not found."
    }

    $PythonVersion = & py --version
    if ($LASTEXITCODE -ne 0) {
        throw "Python was found but could not be started."
    }
    Write-Host "Python found: $PythonVersion" -ForegroundColor Green

    Write-Host ""
    Write-Host "[2/8] Checking isolated PDF environment..." -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath $AppFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $AppFolder -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        Write-Host "Creating the dedicated PDF environment..."
        & py -m venv $VenvFolder
        if ($LASTEXITCODE -ne 0) {
            throw "Python could not create the isolated environment."
        }
    }

    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        throw "The isolated Python environment is incomplete."
    }
    Write-Host "Isolated PDF environment ready." -ForegroundColor Green

    Write-Host ""
    Write-Host "[3/8] Updating required packages..." -ForegroundColor Yellow
    & $VenvPython -m pip install --upgrade pip --disable-pip-version-check
    if ($LASTEXITCODE -ne 0) {
        throw "pip could not be updated."
    }

    & $VenvPython -m pip install --upgrade pypdf pip-audit --disable-pip-version-check
    if ($LASTEXITCODE -ne 0) {
        throw "pypdf or pip-audit could not be installed or updated."
    }

    $PypdfVersion = & $VenvPython -c "import pypdf; print(pypdf.__version__)"
    if ($LASTEXITCODE -ne 0) {
        throw "pypdf could not be imported."
    }

    $AuditVersion = & $VenvPython -m pip_audit --version
    if ($LASTEXITCODE -ne 0) {
        throw "pip-audit could not be started."
    }

    Write-Host "pypdf: $PypdfVersion" -ForegroundColor Green
    Write-Host "pip-audit: $AuditVersion" -ForegroundColor Green

    Write-Host ""
    Write-Host "[4/8] Running the vulnerability audit..." -ForegroundColor Yellow
    $OldPreference = $ErrorActionPreference
    $AuditCode = -1
    try {
        $ErrorActionPreference = "Continue"
        & $VenvPython -m pip_audit --strict --progress-spinner off
        $AuditCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OldPreference
    }

    if ($AuditCode -ne 0) {
        throw "The vulnerability audit did not pass. Exit code: $AuditCode"
    }
    Write-Host "Security audit passed. No known vulnerabilities were reported." -ForegroundColor Green

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "[5/8] SELECT PDF FOLDER" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
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

        $InputFolder = (Resolve-Path -LiteralPath $InputFolder).Path
        break
    }

    Write-Host "Folder accepted: $InputFolder" -ForegroundColor Green
    $OutputFile = Join-Path $InputFolder $OutputFileName
    $RandomPart = Get-Random -Minimum 100000 -Maximum 999999
    $TemporaryOutput = Join-Path $InputFolder ".Combined_${PID}_${RandomPart}.tmp.pdf"

    Write-Host ""
    Write-Host "[6/8] Finding PDFs..." -ForegroundColor Yellow
    $PdfFiles = @(
        Get-ChildItem -LiteralPath $InputFolder -File -Filter "*.pdf" |
        Where-Object {
            $_.Name -ne $OutputFileName -and
            $_.Name -notlike ".Combined_*.tmp.pdf" -and
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
        $Number = $i + 1
        $SizeText = Format-FileSize -Bytes $PdfFiles[$i].Length
        Write-Host ("[{0}] {1} ({2})" -f $Number, $PdfFiles[$i].Name, $SizeText)
    }

    Write-Host ""
    Write-Host "Enter at least two numbers in the exact merge order." -ForegroundColor Yellow
    Write-Host "Example 1,2,3 merges PDFs 1, 2, and 3."
    Write-Host "Example 5,4,1 merges only PDFs 5, 4, and 1."

    while ($true) {
        $OrderInput = Read-Host "PDF order"
        if ($null -eq $OrderInput) { $OrderInput = "" }

        if (-not $OrderInput.Trim()) {
            Write-Host "No order was entered. Try again." -ForegroundColor Red
            continue
        }

        $OrderNumbers = @()
        $ValidOrder = $true

        foreach ($Part in ($OrderInput -split ",")) {
            $CleanPart = $Part.Trim()
            $ParsedNumber = $CleanPart -as [int]

            if ($null -eq $ParsedNumber) {
                Write-Host "'$CleanPart' is not a valid whole number." -ForegroundColor Red
                $ValidOrder = $false
                break
            }

            if ($ParsedNumber -lt 1 -or $ParsedNumber -gt $PdfFiles.Count) {
                Write-Host "PDF number $ParsedNumber does not exist." -ForegroundColor Red
                $ValidOrder = $false
                break
            }

            $OrderNumbers += $ParsedNumber
        }

        if (-not $ValidOrder) { continue }

        if ($OrderNumbers.Count -lt 2) {
            Write-Host "Select at least two PDFs." -ForegroundColor Red
            continue
        }

        $UniqueNumbers = @($OrderNumbers | Sort-Object -Unique)
        if ($UniqueNumbers.Count -ne $OrderNumbers.Count) {
            Write-Host "Each selected PDF number can appear only once." -ForegroundColor Red
            continue
        }

        break
    }

    $OrderedPdfFiles = @(
        foreach ($SelectedNumber in $OrderNumbers) {
            $PdfFiles[$SelectedNumber - 1]
        }
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "[7/8] PREFLIGHT CHECK" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "Final merge order:" -ForegroundColor Cyan

    for ($i = 0; $i -lt $OrderedPdfFiles.Count; $i++) {
        Write-Host ("{0}. {1}" -f ($i + 1), $OrderedPdfFiles[$i].Name)
    }

    $SizeResult = $OrderedPdfFiles | Measure-Object -Property Length -Sum
    $SelectedBytes = [double]$SizeResult.Sum
    $SelectedSizeText = Format-FileSize -Bytes $SelectedBytes

    $RequiredFreeBytesA = $SelectedBytes * 2
    $RequiredFreeBytesB = $SelectedBytes + 512MB
    if ($RequiredFreeBytesA -gt $RequiredFreeBytesB) {
        $RequiredFreeBytes = $RequiredFreeBytesA
    }
    else {
        $RequiredFreeBytes = $RequiredFreeBytesB
    }

    Write-Host ""
    Write-Host "Selected PDFs: $($OrderedPdfFiles.Count)" -ForegroundColor Cyan
    Write-Host "Total input: $SelectedSizeText" -ForegroundColor Cyan
    Write-Host "Output: $OutputFile" -ForegroundColor Cyan

    $FreeSpaceChecked = $false
    try {
        $PathRoot = Split-Path -Path $InputFolder -Qualifier
        if ($PathRoot) {
            $DriveName = $PathRoot.TrimEnd(':', '\')
            $PSDrive = Get-PSDrive -Name $DriveName -ErrorAction Stop
            if ($null -ne $PSDrive.Free) {
                $FreeBytes = [double]$PSDrive.Free
                $FreeSpaceChecked = $true
            }
        }
    }
    catch {
        $FreeSpaceChecked = $false
    }

    if ($FreeSpaceChecked) {
        $FreeText = Format-FileSize -Bytes $FreeBytes
        $RequiredText = Format-FileSize -Bytes $RequiredFreeBytes
        Write-Host "Free disk: $FreeText" -ForegroundColor Cyan
        Write-Host "Safety target: $RequiredText" -ForegroundColor Cyan
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

    if (Test-Path -LiteralPath $OutputFile -PathType Leaf) {
        Write-Host ""
        Write-Host "An existing Combined.pdf was found." -ForegroundColor Yellow
        Write-Host "It will be replaced only after the new PDF passes validation." -ForegroundColor Yellow
    }

    Write-Host ""
    $Proceed = Read-YesNo -Prompt "Continue with this merge? Type Y or N"
    if (-not $Proceed) {
        Write-Host "Merge cancelled. No files were changed." -ForegroundColor Yellow
        exit 0
    }

    Write-Host ""
    Write-Host "[8/8] Combining and validating PDFs..." -ForegroundColor Yellow

    $PythonCode = @'
import os
import sys
from pypdf import PdfReader, PdfWriter

sys.setrecursionlimit(max(sys.getrecursionlimit() * 5, 10000))


def inspect_pdf(path):
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Input PDF not found: {path}")

    reader = PdfReader(path, strict=False)
    if reader.is_encrypted:
        raise RuntimeError(
            "Encrypted or password-protected PDF is not supported: "
            + os.path.basename(path)
        )

    count = len(reader.pages)
    if count < 1:
        raise RuntimeError("PDF has no readable pages: " + os.path.basename(path))
    return count


def main():
    if len(sys.argv) < 4:
        raise RuntimeError("An output path and at least two input PDFs are required.")

    output_path = sys.argv[1]
    input_paths = sys.argv[2:]
    expected_pages = 0
    writer = PdfWriter()

    try:
        for path in input_paths:
            page_count = inspect_pdf(path)
            print(
                f"Adding: {os.path.basename(path)} ({page_count} pages)",
                flush=True,
            )
            writer.append(path)
            expected_pages += page_count

        with open(output_path, "wb") as output_stream:
            writer.write(output_stream)
    finally:
        writer.close()

    if not os.path.isfile(output_path):
        raise RuntimeError("The output PDF was not created.")
    if os.path.getsize(output_path) <= 0:
        raise RuntimeError("The output PDF is empty.")

    check = PdfReader(output_path, strict=False)
    actual_pages = len(check.pages)
    if actual_pages != expected_pages:
        raise RuntimeError(
            f"Validation failed. Expected {expected_pages} pages, "
            f"but found {actual_pages}."
        )

    print(f"Validation passed: {actual_pages} pages.", flush=True)


if __name__ == "__main__":
    main()
'@

    Set-Content -LiteralPath $MergerScript -Value $PythonCode -Encoding UTF8

    if (Test-Path -LiteralPath $TemporaryOutput) {
        Remove-Item -LiteralPath $TemporaryOutput -Force
    }

    $InputPaths = @($OrderedPdfFiles | ForEach-Object { $_.FullName })
    & $VenvPython $MergerScript $TemporaryOutput @InputPaths
    $MergeCode = $LASTEXITCODE

    if ($MergeCode -ne 0) {
        throw "pypdf stopped with exit code $MergeCode."
    }

    if (-not (Test-Path -LiteralPath $TemporaryOutput -PathType Leaf)) {
        throw "The validated temporary PDF was not found."
    }

    $TemporaryFile = Get-Item -LiteralPath $TemporaryOutput
    if ($TemporaryFile.Length -le 0) {
        throw "The validated temporary PDF is empty."
    }

    Move-Item -LiteralPath $TemporaryOutput -Destination $OutputFile -Force

    if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
        throw "The final PDF could not be placed in the destination folder."
    }

    $FinalFile = Get-Item -LiteralPath $OutputFile
    $FinalSizeText = Format-FileSize -Bytes $FinalFile.Length

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

    if ($TemporaryOutput -and (Test-Path -LiteralPath $TemporaryOutput)) {
        Remove-Item -LiteralPath $TemporaryOutput -Force -ErrorAction SilentlyContinue
    }
    exit 1
}
finally {
    if (Test-Path -LiteralPath $MergerScript -PathType Leaf) {
        Remove-Item -LiteralPath $MergerScript -Force -ErrorAction SilentlyContinue
    }
}
