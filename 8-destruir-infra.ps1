# Paso final: BORRA todos los recursos de Azure de la demo para no consumir crédito.
#
#   .\8-destruir-infra.ps1          -> borra el grupo de recursos en Azure (y con él todo lo que contiene)
#   .\8-destruir-infra.ps1 -Todo    -> además borra Jenkins (contenedor y volumen), el repo local
#                                      y la sesión de Azure. Queda como recién descomprimido.
param([switch]$Todo)
. "$PSScriptRoot\scripts\comun.ps1"

if (Test-Jenkins) {
    $sub = Assert-LoginAzure
    Paso "Borrando el grupo de recursos '$ResourceGroup' de la suscripción '$sub'"
    $existe = (Invoke-AzIntento group exists -n $ResourceGroup).Salida.Trim()
    if ($existe -eq 'true') {
        # --no-wait: Azure lo sigue borrando en segundo plano (tarda unos minutos)
        az group delete -n $ResourceGroup --yes --no-wait
        Exito "Borrado solicitado. Azure termina de eliminarlo en unos minutos."
    } else {
        Info "No existe (ya estaba borrado)."
    }
} else {
    Aviso "Jenkins no está corriendo: no se puede hablar con Azure desde acá."
    Aviso "Borrar a mano el grupo de recursos '$ResourceGroup' desde https://portal.azure.com si todavía existe."
}
if (Test-Path $ArchConfig) { Remove-Item -Force $ArchConfig }

if ($Todo) {
    Paso "Borrando Jenkins, su volumen y el repositorio de la demo"
    Push-Location $Raiz
    try {
        $ErrorActionPreference = 'Continue'
        docker compose down --volumes --rmi local
        $restos = docker ps -aq --filter "name=prueba-"
        if ($restos) { docker rm -f $restos | Out-Null }
        $imagenes = docker images -q --filter "reference=*/demo-app"
        if ($imagenes) { docker rmi -f $imagenes | Out-Null }
        $ErrorActionPreference = 'Stop'
    } finally { Pop-Location }
    if (Test-Path $DirRepo) { Remove-Item -Recurse -Force $DirRepo }
    Exito "Listo. Para volver a empezar: .\1-iniciar-jenkins.ps1"
}
