param(
    [string]$Fpc = 'fpc',
    [Parameter(Mandatory = $true)][string]$IndyRoot
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $indy = (Resolve-Path -LiteralPath $IndyRoot).Path
    New-Item -ItemType Directory -Force '.build' | Out-Null
    & $Fpc "-Fu$indy/Lib/System" "-Fu$indy/Lib/Core" "-Fu$indy/Lib/Protocols" `
        "-Fi$indy/Lib/System" '-FU.build' '-FERelease' 'Source/pCallTelegramApi.lpr'
    if ($LASTEXITCODE -ne 0) { throw 'Free Pascal build failed' }
} finally {
    Pop-Location
}
