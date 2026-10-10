# Paso 3: crea la infraestructura en Azure SIN usar el portal web.
#
#   Grupo de recursos          rg-demo-nube     "carpeta" que agrupa todo (para borrarlo junto al final)
#   Azure Container Registry   acrdemo<xxxx>    registro privado de imágenes Docker (como un Docker Hub propio)
#   Container Apps Environment env-demo-nube    la "plataforma" donde corren los contenedores (PaaS)
#   Container App              app-demo-nube    nuestra aplicación, con URL pública HTTPS
#
# Tarda ~5 minutos. Se puede ejecutar en vivo en la clase o antes.
#   .\3-crear-infra.ps1                      -> elige sola una región permitida
#   .\3-crear-infra.ps1 -Region brazilsouth  -> fuerza una región
param([string]$Region)
. "$PSScriptRoot\scripts\comun.ps1"
Assert-Jenkins
$sub = Assert-LoginAzure
Info "Suscripción: $sub"

# Si ya se creó antes, se reutilizan los mismos nombres
$cfgPrevia = @{}
if (Test-Path $ArchConfig) { $cfgPrevia = Read-ConfigAzure }

# ---------------------------------------------------------------------------
Paso "Habilitando los servicios necesarios en la suscripción (solo tarda la primera vez)"
az provider register --namespace Microsoft.ContainerRegistry --wait
az provider register --namespace Microsoft.App --wait
Exito "Listo"

# ---------------------------------------------------------------------------
Paso "Buscando regiones donde la suscripción puede crear recursos"
# Las suscripciones Azure for Students solo permiten ~5 regiones, distintas para cada cuenta.
# Se leen de la política asignada a la suscripción y se cruzan con las regiones de Container Apps.
$preferidas = 'brazilsouth','eastus','eastus2','southcentralus','centralus','westus2','westus3',
              'canadacentral','northcentralus','westus','mexicocentral','chilecentral',
              'northeurope','westeurope','uksouth','francecentral','swedencentral'

$candidatas = @()
if ($Region) {
    $candidatas = @($Region.ToLower())
} else {
    $permitidas = @()
    $pol = Invoke-AzIntento policy assignment list --disable-scope-strict-match --query "[].parameters" -o json
    if ($pol.Ok) {
        foreach ($p in ($pol.Salida | ConvertFrom-Json)) {
            if (-not $p) { continue }
            foreach ($prop in $p.PSObject.Properties) {
                if ($prop.Name -match 'ocation|egion' -and $prop.Value.value -is [array]) {
                    $permitidas += $prop.Value.value
                }
            }
        }
    }
    $caps = ((Invoke-AzIntento provider show -n Microsoft.App --query "resourceTypes[?resourceType=='managedEnvironments'].locations[]" -o json).Salida |
             ConvertFrom-Json) | ForEach-Object { ($_ -replace '\s', '').ToLower() }
    if (-not $caps) { $caps = $preferidas }   # si no se pudo consultar, no filtrar

    if ($permitidas.Count -gt 0) {
        $permitidas = $permitidas | ForEach-Object { $_.ToLower() } | Select-Object -Unique
        Info "Regiones permitidas por la suscripción: $($permitidas -join ', ')"
        $candidatas = @($preferidas | Where-Object { $permitidas -contains $_ -and $caps -contains $_ }) +
                      @($permitidas | Where-Object { $preferidas -notcontains $_ -and $caps -contains $_ })
    }
    if ($candidatas.Count -eq 0) {
        Info "No se pudo leer la política de regiones: se prueban las regiones más comunes."
        $candidatas = @($preferidas | Where-Object { $caps -contains $_ })
    }
}
if ($cfgPrevia.REGION) { $candidatas = @($cfgPrevia.REGION) + @($candidatas | Where-Object { $_ -ne $cfgPrevia.REGION }) }
Info "Orden de prueba: $($candidatas -join ', ')"

function Test-ErrorDeRegion([string]$texto) {
    return ($texto -match 'RequestDisallowedByAzure|RequestDisallowedByPolicy|LocationNotAvailable|NoRegisteredProviderFound|not available|disallowed|SkuNotAvailable|location')
}

# ---------------------------------------------------------------------------
Paso "Grupo de recursos: $ResourceGroup"
$existe = (Invoke-AzIntento group exists -n $ResourceGroup).Salida.Trim()
if ($existe -eq 'true') {
    Info "Ya existe, se reutiliza."
} else {
    $creado = $false
    foreach ($reg in $candidatas) {
        $r = Invoke-AzIntento group create -n $ResourceGroup -l $reg -o none
        if ($r.Ok) { $creado = $true; break }
    }
    if (-not $creado) { Fallar "No se pudo crear el grupo de recursos:`n$($r.Salida)" }
}
Exito "OK"

# ---------------------------------------------------------------------------
if (-not $cfgPrevia.ACR_NAME) {
    # Si una ejecución anterior se cortó antes de guardar config\azure.env, se reutiliza el registro que haya en el grupo
    $acrExistente = Invoke-AzIntento acr list -g $ResourceGroup --query "[0].name" -o tsv
    if ($acrExistente.Ok -and $acrExistente.Salida.Trim()) { $cfgPrevia.ACR_NAME = $acrExistente.Salida.Trim() }
}
if ($cfgPrevia.ACR_NAME) {
    $AcrName = $cfgPrevia.ACR_NAME
} else {
    # El nombre del registro tiene que ser único en todo Azure: se le agrega un sufijo al azar
    $sufijo  = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    $AcrName = "acrdemo$sufijo"
}

Paso "Registro de imágenes (Azure Container Registry): $AcrName"
$region = $null
$acr = Invoke-AzIntento acr show -n $AcrName -g $ResourceGroup --query location -o tsv
if ($acr.Ok) {
    $region = $acr.Salida.Trim()
    Info "Ya existe (región $region), se reutiliza."
} else {
    foreach ($reg in $candidatas) {
        Info "Probando región $reg..."
        $r = Invoke-AzIntento acr create -n $AcrName -g $ResourceGroup -l $reg --sku Basic --admin-enabled true -o none
        if ($r.Ok) { $region = $reg; break }
        if (-not (Test-ErrorDeRegion $r.Salida)) { Fallar "No se pudo crear el registro:`n$($r.Salida)" }
        Aviso "Región $reg no permitida para esta suscripción."
    }
    if (-not $region) { Fallar "Ninguna región funcionó. Probar indicando una región: .\3-crear-infra.ps1 -Region <region>" }
}
$AcrServer = "$AcrName.azurecr.io"
Exito "OK ($AcrServer, región $region)"

# ---------------------------------------------------------------------------
Paso "Entorno de Container Apps: $EnvName (tarda 2-4 minutos)"
$envOk = Invoke-AzIntento containerapp env show -n $EnvName -g $ResourceGroup --query name -o tsv
if ($envOk.Ok) {
    Info "Ya existe, se reutiliza."
} else {
    # Sin Log Analytics para no generar costos extra
    az containerapp env create -n $EnvName -g $ResourceGroup -l $region --logs-destination none -o none
}
Exito "OK"

# ---------------------------------------------------------------------------
Paso "Aplicación: $AppName"
# La app necesita credenciales para descargar imágenes de nuestro registro privado
az acr update -n $AcrName --admin-enabled true -o none
$pass = (Invoke-AzIntento acr credential show -n $AcrName --query "passwords[0].value" -o tsv).Salida.Trim()
if (-not $pass) { Fallar "No se pudo obtener la credencial del registro $AcrName." }

function Get-RegistrosApp {
    return (Invoke-AzIntento containerapp show -n $AppName -g $ResourceGroup --query "properties.configuration.registries[].server" -o tsv).Salida
}

$crear = $true
$appOk = Invoke-AzIntento containerapp show -n $AppName -g $ResourceGroup --query name -o tsv
if ($appOk.Ok) {
    if ((Get-RegistrosApp) -match [regex]::Escape($AcrServer)) {
        Info "Ya existe, se reutiliza."
        $crear = $false
    } else {
        Aviso "Ya existe pero sin la credencial del registro: se vuelve a crear."
        az containerapp delete -n $AppName -g $ResourceGroup --yes -o none
    }
}

if ($crear) {
    # Azure solo guarda la credencial del registro si la app ya usa una imagen de ESE registro.
    # Por eso se copia a nuestro registro una imagen de ejemplo de Microsoft y la app se crea con
    # esa imagen y la credencial juntas. El pipeline de Jenkins después la reemplaza por la nuestra.
    $imagenInicial = "$AcrServer/demo-app:inicial"
    Info "Subiendo la imagen inicial $imagenInicial..."
    docker exec $Contenedor sh -c "echo FROM mcr.microsoft.com/k8se/quickstart:latest | docker build -q -t $imagenInicial -" | Out-Null
    if ($LASTEXITCODE -ne 0) { Fallar "No se pudo construir la imagen inicial." }
    az acr login -n $AcrName | Out-Null
    docker exec $Contenedor docker push -q $imagenInicial | Out-Null
    if ($LASTEXITCODE -ne 0) { Fallar "No se pudo subir la imagen inicial al registro $AcrServer." }

    # min-replicas 0 = "escala a cero": si nadie la usa no consume (ni cobra) CPU.
    az containerapp create -n $AppName -g $ResourceGroup --environment $EnvName `
        --image $imagenInicial `
        --registry-server $AcrServer --registry-username $AcrName --registry-password $pass `
        --ingress external --target-port 80 `
        --cpu 0.25 --memory 0.5Gi --min-replicas 0 --max-replicas 3 -o none
}
if ((Get-RegistrosApp) -notmatch [regex]::Escape($AcrServer)) { Fallar "La aplicación quedó sin la credencial del registro $AcrServer." }

$fqdn = (Invoke-AzIntento containerapp show -n $AppName -g $ResourceGroup --query properties.configuration.ingress.fqdn -o tsv).Salida.Trim()
$url = "https://$fqdn"
Exito "OK"

# ---------------------------------------------------------------------------
Paso "Guardando la configuración para Jenkins (config\azure.env)"
Write-ArchivoLinux $ArchConfig @"
# Generado por 3-crear-infra.ps1 - lo lee el pipeline de Jenkins
RESOURCE_GROUP=$ResourceGroup
REGION=$region
ACR_NAME=$AcrName
ACR_LOGIN_SERVER=$AcrServer
APP_NAME=$AppName
APP_URL=$url
"@
Exito "OK"

Write-Host ""
Write-Host "Infraestructura lista." -ForegroundColor Green
Write-Host "  URL pública de la aplicación: $url" -ForegroundColor Green
Write-Host "  (por ahora muestra una página de ejemplo de Microsoft; el primer build de Jenkins publica la nuestra)"
Write-Host ""
Write-Host "Siguiente paso: en Jenkins, abrir el job 'Demo Nube + DevOps' y hacer clic en 'Construir ahora'." -ForegroundColor Green
Start-Process $url
