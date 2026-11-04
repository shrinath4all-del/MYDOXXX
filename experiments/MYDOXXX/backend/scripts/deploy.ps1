param([switch]$Deploy)
$ErrorActionPreference = 'Stop'
$BackendRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ExperimentProject = 'mydoxxx-dev-261102'
$ExperimentAccount = 'shrinath4all@gmail.com'

Push-Location -LiteralPath $BackendRoot
try {
    & node (Join-Path $PSScriptRoot 'verify-isolation.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'Project isolation validation failed.' }
    if (-not $Deploy) {
        Write-Output "Validation passed for $ExperimentProject. Use -Deploy to publish its guarded functions."
        return
    }
    $CurrentNodeMajor = (& node -p 'process.versions.node.split(".")[0]')
    if ($CurrentNodeMajor -ne '22') { throw 'Use Node.js 22 before deploying this Node.js 22 backend.' }
    & npx -y firebase-tools@latest deploy --only functions --project $ExperimentProject --account $ExperimentAccount --non-interactive
    if ($LASTEXITCODE -ne 0) { throw 'Firebase deployment did not finish successfully. Read its output before retrying.' }
}
finally { Pop-Location }

