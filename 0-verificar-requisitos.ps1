# Paso 0: verifica que la computadora tenga lo necesario para la demo.
# Requisitos: Docker Desktop (corriendo, con contenedores Linux) y Git.
. "$PSScriptRoot\scripts\comun.ps1"
$ErrorActionPreference = 'Continue'
$todoOk = $true

Paso "PowerShell"
Exito "Versión $($PSVersionTable.PSVersion)"

Paso "Git"
if (Get-Command git -ErrorAction SilentlyContinue) {
    Exito (git --version)
} else {
    Aviso "No se encontró Git. Instalar con:  winget install --id Git.Git -e"
    $todoOk = $false
}

Paso "Docker"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Aviso "No se encontró Docker. Instalar Docker Desktop: https://www.docker.com/products/docker-desktop/"
    $todoOk = $false
} else {
    $os = docker info --format '{{.OSType}}' 2>$null
    if ($LASTEXITCODE -ne 0) {
        Aviso "Docker está instalado pero no está corriendo. Abrir Docker Desktop y esperar a que diga 'Engine running'."
        $todoOk = $false
    } elseif ($os -ne 'linux') {
        Aviso "Docker está en modo contenedores Windows. Cambiar a 'Linux containers' desde el ícono de Docker Desktop."
        $todoOk = $false
    } else {
        Exito "Docker corriendo (servidor $(docker version --format '{{.Server.Version}}' 2>$null))"
    }
}

Paso "Puerto 8080 (Jenkins)"
$ocupado = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($ocupado -and -not (Test-Jenkins)) {
    Aviso "El puerto 8080 está ocupado por otro programa. Cerrarlo antes de iniciar Jenkins."
    $todoOk = $false
} else {
    Exito "Disponible"
}

Paso "Internet (Azure y Docker Hub)"
foreach ($sitio in 'https://management.azure.com', 'https://registry-1.docker.io/v2/') {
    try {
        Invoke-WebRequest -Uri $sitio -UseBasicParsing -TimeoutSec 10 -Method Head | Out-Null
        Exito "$sitio accesible"
    } catch {
        # Estos sitios responden 400/401 sin credenciales: eso igual significa que hay conexión
        if ($_.Exception.Response) { Exito "$sitio accesible" }
        else { Aviso "No se pudo conectar a $sitio"; $todoOk = $false }
    }
}

Write-Host ""
if ($todoOk) {
    Write-Host "Todo listo. Siguiente paso: .\1-iniciar-jenkins.ps1" -ForegroundColor Green
} else {
    Write-Host "Hay requisitos pendientes (ver avisos en amarillo)." -ForegroundColor Yellow
}
