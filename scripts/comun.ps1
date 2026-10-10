# Funciones compartidas por los scripts de la demo. No se ejecuta solo.
# Compatible con Windows PowerShell 5.1 y PowerShell 7.

$ErrorActionPreference = 'Stop'

$Raiz        = Split-Path -Parent $PSScriptRoot
$Contenedor  = 'jenkins-demo'
$DirConfig   = Join-Path $Raiz 'config'
$ArchConfig  = Join-Path $DirConfig 'azure.env'
$DirRepo     = Join-Path $Raiz 'repo-demo'
$DirPlantilla = Join-Path $Raiz 'app-plantilla'

# Nombres fijos de los recursos en Azure (todo vive en un único grupo de recursos)
$ResourceGroup = 'rg-demo-nube'
$EnvName       = 'env-demo-nube'
$AppName       = 'app-demo-nube'

function Paso([string]$texto) {
    Write-Host ""
    Write-Host "==> $texto" -ForegroundColor Cyan
}

function Info([string]$texto) { Write-Host "    $texto" -ForegroundColor Gray }
function Exito([string]$texto) { Write-Host "    $texto" -ForegroundColor Green }
function Aviso([string]$texto) { Write-Host "    $texto" -ForegroundColor Yellow }

function Fallar([string]$texto) {
    Write-Host ""
    Write-Host "ERROR: $texto" -ForegroundColor Red
    exit 1
}

# ¿Está corriendo el contenedor de Jenkins?
function Test-Jenkins {
    # (en Windows PowerShell 5.1 redirigir stderr con 'Stop' activo corta el script)
    $ErrorActionPreference = 'Continue'
    $estado = docker inspect -f '{{.State.Running}}' $Contenedor 2>$null
    return ($LASTEXITCODE -eq 0 -and $estado -eq 'true')
}

function Assert-Jenkins {
    if (-not (Test-Jenkins)) {
        Fallar "Jenkins no está corriendo. Ejecutar primero .\1-iniciar-jenkins.ps1"
    }
}

# 'az' = Azure CLI. No hace falta instalarla en Windows: se usa la que viene
# dentro del contenedor de Jenkins, que además comparte la sesión con el pipeline.
# Si el comando falla, se corta el script.
function az {
    docker exec $Contenedor az @args
    if ($LASTEXITCODE -ne 0) { Fallar "Falló el comando: az $($args -join ' ')" }
}

# Igual que 'az' pero no corta el script si falla: devuelve un objeto con Ok y Salida.
function Invoke-AzIntento {
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $salida = docker exec $Contenedor az @args 2>&1 | ForEach-Object { "$_" }
    $ok = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $anterior
    return [pscustomobject]@{ Ok = $ok; Salida = ($salida -join "`n") }
}

function Assert-LoginAzure {
    $r = Invoke-AzIntento account show --query name -o tsv
    if (-not $r.Ok) {
        Fallar "Jenkins no tiene sesión iniciada en Azure. Ejecutar .\2-login-azure.ps1"
    }
    return $r.Salida.Trim()
}

# Escribe un archivo de texto en UTF-8 sin BOM y con fin de línea LF
# (lo van a leer programas Linux dentro del contenedor).
function Write-ArchivoLinux([string]$ruta, [string]$contenido) {
    $contenido = $contenido -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($ruta, $contenido, (New-Object System.Text.UTF8Encoding $false))
}

function Read-ConfigAzure {
    if (-not (Test-Path $ArchConfig)) {
        Fallar "No existe config\azure.env. Ejecutar primero .\3-crear-infra.ps1"
    }
    $cfg = @{}
    foreach ($linea in Get-Content $ArchConfig) {
        if ($linea -match '^\s*([A-Z_]+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2].Trim() }
    }
    return $cfg
}
