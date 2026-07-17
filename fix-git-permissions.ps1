[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GIT_MASTER = '1'

$repoRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$buildScriptPath = Join-Path $repoRoot 'build.sh'
$wrtCorePath = Join-Path $repoRoot 'wrt_core'

if (-not (Test-Path -LiteralPath $buildScriptPath -PathType Leaf)) {
    throw "File not found: $buildScriptPath"
}

if (-not (Test-Path -LiteralPath $wrtCorePath -PathType Container)) {
    throw "Directory not found: $wrtCorePath"
}

$gitRootOutput = & git -C $repoRoot rev-parse --show-toplevel 2>$null
$gitRootExitCode = $LASTEXITCODE
if ($gitRootExitCode -ne 0) {
    throw "Unable to locate the Git repository: $repoRoot"
}

$gitRoot = (Resolve-Path -LiteralPath $gitRootOutput.Trim()).Path
if ($gitRoot -ine $repoRoot) {
    throw "The script directory is not the root of a Git repository: $repoRoot"
}

$targetFiles = @(
    $buildScriptPath
    Get-ChildItem -LiteralPath $wrtCorePath -File -Recurse -Force | ForEach-Object { $_.FullName }
)

$relativePaths = @(
    $targetFiles | ForEach-Object {
        $_.Substring($repoRoot.Length).TrimStart('\', '/').Replace('\', '/')
    }
)

if ($relativePaths.Count -eq 0) {
    Write-Host 'No target files found.'
    return
}

$updateIndexArguments = @(
    '-C', $repoRoot,
    'update-index',
    '--chmod=+x',
    '--'
) + $relativePaths

if (-not $PSCmdlet.ShouldProcess(($relativePaths -join ', '), 'Set executable bit in Git index')) {
    return
}

& git @updateIndexArguments
if ($LASTEXITCODE -ne 0) {
    throw 'git update-index failed.'
}

$rawChanges = @(
    & git -C $repoRoot diff --cached --raw --no-renames --format= -- $relativePaths
)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect staged permission changes.'
}

$permissionChangePaths = @(
    $rawChanges | ForEach-Object {
        if ($_ -match '^:(\d{6}) (\d{6}) ([0-9a-f]+) ([0-9a-f]+) [A-Z]\t(.+)$' -and
            $Matches[1] -ne $Matches[2] -and
            $Matches[3] -eq $Matches[4]) {
            $Matches[5]
        }
    }
)

if ($permissionChangePaths.Count -eq 0) {
    Write-Host 'No permission changes detected; no commit created.'
    return
}

$commitArguments = @(
    '-C', $repoRoot,
    'commit',
    '-m', 'fix: fix permission',
    '--'
) + $permissionChangePaths

if ($PSCmdlet.ShouldProcess(($permissionChangePaths -join ', '), 'Commit permission changes')) {
    & git @commitArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'git commit failed.'
    }
}
