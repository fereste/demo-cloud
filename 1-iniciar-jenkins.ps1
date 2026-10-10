# Paso 1: crea el repositorio git de la demo y levanta Jenkins en un contenedor local.
#
#   .\1-iniciar-jenkins.ps1              -> inicia todo (la primera vez tarda ~5-10 min en construir la imagen)
#   .\1-iniciar-jenkins.ps1 -RepoNuevo   -> además borra el repositorio de la demo y lo vuelve a crear
#                                           desde app-plantilla (para empezar la demo "de cero")
param([switch]$RepoNuevo)
. "$PSScriptRoot\scripts\comun.ps1"

# ---------------------------------------------------------------------------
Paso "Repositorio git de la aplicación (carpeta repo-demo)"

if ($RepoNuevo -and (Test-Path $DirRepo)) {
    Info "Borrando el repositorio anterior..."
    # Se vacía la carpeta (sin borrarla) porque puede estar montada en el contenedor de Jenkins
    Get-ChildItem -Force $DirRepo | Remove-Item -Recurse -Force
}

if (Test-Path (Join-Path $DirRepo '.git')) {
    Info "Ya existe, se usa el actual (usar -RepoNuevo para recrearlo)."
} else {
    New-Item -ItemType Directory -Force -Path $DirRepo | Out-Null
    Copy-Item -Recurse -Force (Join-Path $DirPlantilla '*') $DirRepo
    Copy-Item -Force (Join-Path $DirPlantilla '.gitattributes') $DirRepo

    Push-Location $DirRepo
    try {
        $ErrorActionPreference = 'Continue'   # git escribe mensajes informativos por stderr
        git init --quiet
        git symbolic-ref HEAD refs/heads/main   # la rama se llama "main"
        # Identidad local del repo (no toca la configuración global del profesor)
        git config user.name  "Profesor"
        git config user.email "profesor@demo.local"
        git config core.autocrlf false
        git add -A
        git commit --quiet -m "Versión inicial de la aplicación"
        $ErrorActionPreference = 'Stop'
    } finally { Pop-Location }

    # Hook: después de cada commit le avisa a Jenkins que hay cambios (así el pipeline arranca solo)
    $hook = @'
#!/bin/sh
# Avisa a Jenkins que hay un commit nuevo. Si Jenkins no está corriendo, no pasa nada.
curl -s -m 5 "http://localhost:8080/git/notifyCommit?url=file:///repo" > /dev/null 2>&1 || true
'@
    Write-ArchivoLinux (Join-Path $DirRepo '.git\hooks\post-commit') $hook
    Exito "Repositorio creado con el primer commit."
}

New-Item -ItemType Directory -Force -Path $DirConfig | Out-Null

# ---------------------------------------------------------------------------
Paso "Construyendo y levantando Jenkins (docker compose)"
Info "La primera vez descarga y construye la imagen: puede tardar varios minutos."
Push-Location $Raiz
try {
    $ErrorActionPreference = 'Continue'
    docker compose up -d --build
    $codigo = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
} finally { Pop-Location }
if ($codigo -ne 0) { Fallar "docker compose no pudo levantar Jenkins (ver mensajes arriba)." }

# ---------------------------------------------------------------------------
Paso "Esperando a que Jenkins responda en http://localhost:8080"
$listo = $false
for ($i = 0; $i -lt 90; $i++) {
    try {
        $r = Invoke-WebRequest -Uri 'http://localhost:8080/login' -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -eq 200) { $listo = $true; break }
    } catch { }
    Start-Sleep -Seconds 2
}
if (-not $listo) { Fallar "Jenkins no respondió a tiempo. Ver logs con:  docker logs jenkins-demo" }

Exito "Jenkins listo:  http://localhost:8080   (usuario: profe / contraseña: demo)"
Start-Process 'http://localhost:8080/job/demo-nube/'

Write-Host ""
Write-Host "Siguiente paso: .\2-login-azure.ps1" -ForegroundColor Green
