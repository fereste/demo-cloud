# Paso 4 (opcional): muestra la ELASTICIDAD de la nube cambiando la cantidad de réplicas.
#
#   .\4-escalar.ps1 -Replicas 3   -> 3 contenedores atendiendo a la vez (al recargar la página cambia "Servido por la réplica")
#   .\4-escalar.ps1 -Replicas 0   -> vuelve a "escalar a cero" (sin uso no consume nada)
param([ValidateRange(0, 5)][int]$Replicas = 3)
. "$PSScriptRoot\scripts\comun.ps1"
Assert-Jenkins
Assert-LoginAzure | Out-Null
$cfg = Read-ConfigAzure

$max = [Math]::Max($Replicas, 3)
Paso "Escalando la aplicación a $Replicas réplica(s) mínimas (máximo $max)"
az containerapp update -n $cfg.APP_NAME -g $cfg.RESOURCE_GROUP --min-replicas $Replicas --max-replicas $max -o none

if ($Replicas -gt 0) {
    Info "Esperando a que arranquen las réplicas..."
    for ($i = 0; $i -lt 30; $i++) {
        $n = (Invoke-AzIntento containerapp replica list -n $cfg.APP_NAME -g $cfg.RESOURCE_GROUP --query "length(@)" -o tsv).Salida.Trim()
        if ([int]("0$n") -ge $Replicas) { break }
        Start-Sleep -Seconds 3
    }
}

Paso "Réplicas en ejecución ahora"
az containerapp replica list -n $cfg.APP_NAME -g $cfg.RESOURCE_GROUP --query "[].{replica:name, creada:properties.createdTime}" -o table

Write-Host ""
Exito "Recargar la página varias veces (F5): el campo 'Servido por la réplica' va cambiando."
Exito $cfg.APP_URL
Start-Process $cfg.APP_URL
