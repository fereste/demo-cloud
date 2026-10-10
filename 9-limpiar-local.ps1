# Paso extra: deja la computadora como si la demo nunca se hubiera ejecutado (SOLO lo local).
#
#   .\9-limpiar-local.ps1            -> pide confirmación y borra todo lo local de la demo
#   .\9-limpiar-local.ps1 -Forzar    -> sin pedir confirmación
#   .\9-limpiar-local.ps1 -Cache     -> además vacía la caché de construcción de Docker, para que la
#                                       próxima vez la imagen de Jenkins se construya desde cero (tarda más)
#
# Borra:  contenedores (Jenkins y de prueba), volumen de Jenkins (con la sesión de Azure), red demo-net,
#         imágenes (Jenkins, de la aplicación y las base que descarga la demo), carpetas repo-demo y config.
# NO toca: nada de Azure (para eso está .\8-destruir-infra.ps1) ni otros contenedores, imágenes o
#          volúmenes de Docker que no sean de la demo.
param([switch]$Forzar, [switch]$Cache)
. "$PSScriptRoot\scripts\comun.ps1"

# En Windows PowerShell 5.1 los mensajes que los comandos de Docker escriben por stderr cortarían el script
$ErrorActionPreference = 'Continue'

function Test-Docker {
    docker info *> $null
    return ($LASTEXITCODE -eq 0)
}

# ---------------------------------------------------------------------------
Paso "Esto va a borrar de ESTA computadora todo lo de la demo"
Info "- Contenedores: $Contenedor y los de prueba (prueba-N)"
Info "- Volumen de Jenkins (se pierde el login de Azure y el historial de builds)"
Info "- Red demo-net"
Info "- Imágenes: Jenkins (demo-nube-jenkins), de la aplicación (demo-app) y las base (jenkins, nginx, quickstart)"
Info "- Carpetas repo-demo y config"
if ($Cache) { Info "- Caché de construcción de Docker (de TODOS los proyectos)" }
Info "No toca Azure ni lo que no sea de la demo."

if (-not (Test-Docker)) {
    Fallar "Docker no está corriendo. Abrir Docker Desktop y volver a ejecutar este script."
}

# ¿Quedan recursos en Azure? Si se borra el volumen se pierde la sesión y ya no se pueden borrar desde acá.
if (Test-Jenkins) {
    $login = Invoke-AzIntento account show --query name -o tsv
    if ($login.Ok) {
        $existe = (Invoke-AzIntento group exists -n $ResourceGroup).Salida.Trim()
        if ($existe -eq 'true') {
            Write-Host ""
            Aviso "ATENCIÓN: el grupo de recursos '$ResourceGroup' sigue existiendo en Azure y consume crédito."
            Aviso "Conviene ejecutar primero .\8-destruir-infra.ps1 (después de borrar lo local ya no se puede desde acá)."
        }
    }
} elseif (Test-Path $ArchConfig) {
    Write-Host ""
    Aviso "Hay una configuración de Azure guardada (config\azure.env) pero Jenkins no está corriendo:"
    Aviso "si los recursos de Azure siguen creados, hay que borrar el grupo '$ResourceGroup' desde el portal."
}

if (-not $Forzar) {
    Write-Host ""
    $respuesta = Read-Host "¿Seguro que querés borrar todo lo local? (s/N)"
    if ($respuesta -notmatch '^(s|si|sí|y|yes)$') {
        Write-Host "Cancelado. No se borró nada."
        exit 0
    }
}

# ---------------------------------------------------------------------------
Paso "Deteniendo y borrando los contenedores"
Push-Location $Raiz
try {
    docker compose down --volumes --remove-orphans 2>&1 | ForEach-Object { Info "$_" }
} finally { Pop-Location }
# Por si el contenedor se creó a mano o con otro proyecto de compose, y los de la etapa "3. Probar"
$contenedores = @(docker ps -aq --filter "name=^/?$Contenedor$") + @(docker ps -aq --filter "name=^/?prueba-[0-9]+$") | Where-Object { $_ }
if ($contenedores) { docker rm -f $contenedores *> $null }
Exito "OK"

# ---------------------------------------------------------------------------
Paso "Borrando el volumen y la red"
$volumenes = @(docker volume ls -q --filter "name=jenkins_home") | Where-Object { $_ -match '^demo-nube[_-]jenkins_home$|^jenkins_home$' }
foreach ($v in $volumenes) { docker volume rm -f $v *> $null; Info "Volumen $v borrado" }
if (-not $volumenes) { Info "El volumen de Jenkins ya estaba borrado." }
if (docker network ls -q --filter "name=^demo-net$") {
    docker network rm demo-net *> $null
    if ($LASTEXITCODE -eq 0) { Info "Red demo-net borrada" }
    else { Aviso "La red demo-net la está usando otro contenedor: no se borró." }
}
Exito "OK"

# ---------------------------------------------------------------------------
Paso "Borrando las imágenes"
# Se borran por nombre y sin --force: si otro proyecto usa una imagen base (por ejemplo nginx), Docker se niega y se respeta.
$patrones = '^demo-nube-jenkins:', '/demo-app:', '^demo-app:', '^jenkins/jenkins:', '^nginx:stable-alpine$',
            '^mcr\.microsoft\.com/k8se/quickstart:'
$imagenes = @(docker images --format '{{.Repository}}:{{.Tag}}') | Where-Object { $img = $_; $patrones | Where-Object { $img -match $_ } }
$borradas = 0
foreach ($img in $imagenes) {
    docker rmi $img *> $null
    if ($LASTEXITCODE -eq 0) { $borradas++ } else { Aviso "No se borró $img (la usa otro contenedor)." }
}
Info "$borradas imagen(es) borrada(s)."
if ($Cache) {
    Info "Vaciando imágenes sin nombre y la caché de construcción de Docker..."
    docker image prune -f *> $null
    docker builder prune -af *> $null
}
Exito "OK"

# ---------------------------------------------------------------------------
Paso "Borrando las carpetas generadas (repo-demo y config)"
foreach ($carpeta in @($DirRepo, $DirConfig)) {
    if (Test-Path $carpeta) {
        try {
            Remove-Item -Recurse -Force $carpeta -ErrorAction Stop
            Info "$carpeta borrada"
        } catch {
            Aviso "No se pudo borrar $carpeta (¿está abierta en un editor o terminal?). Cerrarla y borrarla a mano."
        }
    }
}
Exito "OK"

# ---------------------------------------------------------------------------
Paso "Verificación"
$quedan = @(docker ps -a --format '{{.Names}}' | Where-Object { $_ -match "^$Contenedor$|^prueba-" }) +
          @(docker volume ls -q | Where-Object { $_ -match 'jenkins_home' }) +
          @(docker images --format '{{.Repository}}:{{.Tag}}' | Where-Object { $_ -match 'demo-nube-jenkins|/demo-app:|^demo-app:' })
if ($quedan.Count -eq 0 -and -not (Test-Path $DirRepo) -and -not (Test-Path $DirConfig)) {
    Exito "Todo limpio."
} else {
    Aviso "Quedaron restos: $($quedan -join ', ')"
}

Write-Host ""
Write-Host "Listo. Para empezar de cero: .\0-verificar-requisitos.ps1  y después  .\1-iniciar-jenkins.ps1" -ForegroundColor Green
Write-Host "(La primera vez Jenkins tarda varios minutos: tiene que volver a construir la imagen.)"
