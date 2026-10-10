# Paso 2: inicia sesión en Azure con la cuenta del profesor (Azure for Students).
# La sesión queda guardada dentro de Jenkins: la usan tanto los scripts como el pipeline.
# Hay que hacerlo una vez; la sesión dura semanas (si vence, se vuelve a ejecutar este script).
. "$PSScriptRoot\scripts\comun.ps1"
Assert-Jenkins

Paso "Inicio de sesión en Azure"
Info "Se va a mostrar un código. Abrir https://microsoft.com/devicelogin en el navegador,"
Info "pegar el código e ingresar con la cuenta institucional que tiene Azure for Students."
Write-Host ""
docker exec -it $Contenedor az login --use-device-code --output none
if ($LASTEXITCODE -ne 0) { Fallar "No se pudo iniciar sesión." }

Paso "Eligiendo la suscripción"
$subs = (Invoke-AzIntento account list --query "[?state=='Enabled'].{id:id, nombre:name}" -o json).Salida | ConvertFrom-Json
if (-not $subs) { Fallar "La cuenta no tiene suscripciones activas. ¿Está activado Azure for Students?" }

$elegida = $subs | Where-Object { $_.nombre -match 'Student' } | Select-Object -First 1
if (-not $elegida) {
    if (@($subs).Count -eq 1) {
        $elegida = $subs
    } else {
        Write-Host ""
        $i = 1
        foreach ($s in $subs) { Write-Host "  [$i] $($s.nombre)"; $i++ }
        $n = Read-Host "Número de la suscripción a usar"
        $elegida = @($subs)[[int]$n - 1]
    }
}
az account set --subscription $elegida.id
Exito "Usando la suscripción: $($elegida.nombre)"

Write-Host ""
Write-Host "Siguiente paso: .\3-crear-infra.ps1" -ForegroundColor Green
