# Paso 5 (opcional): muestra el historial de versiones desplegadas en la nube.
# Cada deploy del pipeline crea una "revisión" nueva en Azure Container Apps.
. "$PSScriptRoot\scripts\comun.ps1"
Assert-Jenkins
Assert-LoginAzure | Out-Null
$cfg = Read-ConfigAzure

Paso "Imágenes guardadas en el registro ($($cfg.ACR_NAME))"
az acr repository show-tags -n $cfg.ACR_NAME --repository demo-app --orderby time_desc -o table

Paso "Revisiones de la aplicación en Azure Container Apps"
az containerapp revision list -n $cfg.APP_NAME -g $cfg.RESOURCE_GROUP --all `
    --query "[].{revision:name, creada:properties.createdTime, activa:properties.active, imagen:properties.template.containers[0].image}" -o table

Paso "Commits en el repositorio"
git -C $DirRepo log --oneline -10
