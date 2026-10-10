# Contexto del proyecto: Demo Nube + DevOps

Materia **Virtualización de Hardware**, Ingeniería en Informática, UNLaM. El autor (Fernando) es docente de la materia. Todo el material, los mensajes de los scripts y la documentación van **en español (rioplatense neutro)**.

## Qué es y por qué existe

Es la demo práctica de la clase de **cloud computing**, que viene después de la clase de **DevOps**. Reemplaza a la demo anterior, que tenía estos problemas:

- Hacía un Static Web App en Azure + GitHub Actions y una Web App con contenedores + GHCR.
- Solo funcionaba con las cuentas personales de Fernando, así que él tenía que dar esa clase en todas las comisiones.
- Tenía demasiados pasos y era difícil de seguir para alumnos sin experiencia en cloud ni CI/CD.
- Los portales de Azure y GitHub cambian seguido, y había que revisar la demo cada cuatrimestre.

### Requisitos de la nueva demo (definidos por Fernando)

- Fácil de entender para alguien que no está en el tema.
- Reproducible de cuatrimestre a cuatrimestre.
- Que la pueda hacer **cualquier profesor** con su propia cuenta: sin nada preconfigurado y sin compartir cuentas.
- Tiene que usar una **nube pública** (se eligió **Azure**) y un **sistema CI/CD** (se eligió **Jenkins** en un contenedor local; si resulta demasiado complejo se puede cambiar más adelante, por ejemplo por Gitea + Actions).
- Los recursos se crean desde **PowerShell**, no desde el portal web.
- Entorno del profesor: **computadora con Windows + Docker Desktop**, con unos **60 minutos** de demo.
- Se despliega **solo un contenedor**. No hay sitio estático.
- Entregables: carpeta con scripts, guía para el profesor (`GUIA-PROFESOR.md`) y diagrama de apoyo (`diagrama-flujo.svg`).

## Arquitectura

```
git commit (repo-demo, local) --hook post-commit--> Jenkins (contenedor local)
  1. Preparar          lee /demo-config/azure.env y verifica la sesión de az
  2. Construir imagen  docker build (Docker del host vía socket)
  3. Probar            docker run en la red demo-net + pruebas/prueba.sh (curl)
  4. Publicar          az acr login + docker push  -> Azure Container Registry (Basic)
  5. Desplegar         az containerapp registry set + update --image -> Azure Container Apps
```

- La página es nginx. Muestra la versión (número de build), la fecha del build y el nombre de la réplica (lo pone `nombre-replica.sh` al arrancar cada contenedor: usa `CONTAINER_APP_REPLICA_NAME` si existe y si no un id al azar; el hostname no sirve porque en Express es siempre `adc-sandbox`), para que se vea el balanceo al escalar.
- La app tiene `min-replicas 0` (escala a cero) y `max 3`, con 0.25 vCPU / 0.5 Gi.
- El environment de Container Apps se crea con `--logs-destination none`, para no tener costo de Log Analytics.

## Mapa de archivos

| Archivo | Rol |
|---|---|
| `0-verificar-requisitos.ps1` | Chequea Docker (modo Linux), Git, el puerto 8080 y la conectividad. |
| `1-iniciar-jenkins.ps1 [-RepoNuevo]` | Copia `app-plantilla/` a `repo-demo/`, hace `git init` (rama main, identidad local), instala el hook `post-commit` y corre `docker compose up -d --build`. Después espera a que Jenkins responda. |
| `2-login-azure.ps1` | Hace `az login --use-device-code` **dentro del contenedor** y elige la suscripción (prefiere la que tenga "Student" en el nombre). |
| `3-crear-infra.ps1 [-Region x]` | Registra los providers, detecta las regiones permitidas y crea RG → ACR → env → app. La app se crea con una imagen inicial (`demo-app:inicial`, copia de la quickstart) subida al ACR y con la credencial del registro en el mismo `create` (ver bug Express). Verifica la credencial y escribe `config/azure.env`. Es idempotente: reutiliza lo que ya existe. |
| `4-escalar.ps1 -Replicas N` | Cambia min/max réplicas y lista las réplicas. |
| `5-ver-historial.ps1` | Muestra los tags del ACR, las revisiones de la app y `git log`. |
| `8-destruir-infra.ps1 [-Todo]` | Corre `az group delete --no-wait`. Con `-Todo`, además hace `compose down --volumes` y borra `repo-demo`. |
| `9-limpiar-local.ps1 [-Forzar] [-Cache]` | Borra SOLO lo local de la demo: contenedores (`jenkins-demo`, `prueba-N`), volumen `demo-nube_jenkins_home`, red `demo-net`, imágenes (`demo-nube-jenkins`, `*/demo-app`, y las base jenkins/nginx/quickstart, sin `-f` para respetar las que use otro proyecto), `repo-demo` y `config`. Avisa si el grupo de Azure sigue existiendo. **Nunca usa `docker system prune`** (en la computadora de Fernando hay otros proyectos). `-Cache` suma `image prune` + `builder prune`. Nota: `compose down --rmi local` NO borra `demo-nube-jenkins:1` porque tiene tag explícito. |
| `scripts/comun.ps1` | Constantes y helpers: `Paso/Info/Exito/Aviso/Fallar`, `Test-Jenkins`, función **`az`** (wrapper de `docker exec jenkins-demo az ...` que corta el script si falla), `Invoke-AzIntento` (igual pero devuelve `{Ok, Salida}` sin cortar), `Write-ArchivoLinux` (UTF-8 sin BOM + LF) y `Read-ConfigAzure`. |
| `docker-compose.yml` | Servicio `jenkins-demo`: `user: root`, puerto `127.0.0.1:8080`. Monta el volumen `jenkins_home`, `/var/run/docker.sock`, `./repo-demo:/repo` y `./config:/demo-config:ro`. Usa la red `demo-net` (nombre fijo). |
| `jenkins/Dockerfile` | Jenkins **2.568.3-jdk21** (fijado) + docker-ce-cli + buildx + **Azure CLI vía pip en venv** (`/opt/az`) + `safe.directory '*'`. Variables de entorno: `AZURE_CONFIG_DIR=/var/jenkins_home/.azure`, `AZURE_CORE_LOGIN_EXPERIENCE_V2=off`. Propiedades Java: `ALLOW_LOCAL_CHECKOUT=true`, `NOTIFY_COMMIT_ACCESS_CONTROL=disabled-for-polling` y sin asistente inicial. |
| `jenkins/plugins.txt` | configuration-as-code, job-dsl, workflow-aggregator, git, pipeline-utility-steps, pipeline-stage-view, pipeline-graph-view, timestamper. |
| `jenkins/casc.yaml` | Usuario `profe`/`demo` y el job `demo-nube` (Job DSL): pipeline desde SCM `file:///repo`, rama `*/main`, `pollSCM('')` (solo para que funcione notifyCommit) y `lightweight(false)`. |
| `app-plantilla/` | Plantilla de la app: `Dockerfile` (nginx:stable-alpine, ARG VERSION/FECHA estampados con sed), `nombre-replica.sh` (se copia a `/docker-entrypoint.d/`), `nginx.conf` (no-store, `/salud`), `sitio/index.html` (zonas marcadas "CAMBIAR ACÁ"), `pruebas/prueba.sh`, `Jenkinsfile` y `.gitattributes`. |
| `repo-demo/`, `config/` | Se generan en tiempo de ejecución. **No se distribuyen.** |
| `GUIA-PROFESOR.md` | Requisitos, preparación, guion de la clase de 60 min, relación con el programa, cuentas de Azure, problemas frecuentes y mantenimiento. |
| `diagrama-flujo.svg` | Diagrama de 1600x900 para proyectar. |

## Decisiones y sus motivos (no revertir sin consultar)

- **Azure CLI solo dentro del contenedor de Jenkins.** Así el profesor no instala nada más, hay un único login y el pipeline comparte la sesión con los scripts. Los scripts del host llaman `docker exec jenkins-demo az ...` a través de la función `az` de `comun.ps1`.
- **Login por device code** en lugar de service principal. Muchas cuentas universitarias no pueden registrar apps en Entra.
- **Build local de la imagen.** Azure for Students **no permite ACR Tasks** (`az acr build`).
- **Detección de regiones.** Azure for Students limita a unas 5 regiones distintas por cuenta. El script lee la política (`az policy assignment list --disable-scope-strict-match`), la cruza con las regiones de `Microsoft.App` y prueba en orden; si aparece `RequestDisallowedByAzure`, pasa a la siguiente región.
- **Azure CLI por pip.** El repo apt de Microsoft no soportaba Debian trixie (base de las imágenes de Jenkins).
- **ACR con admin user** y credencial cargada en la app con `az containerapp registry set`. Se eligió por simplicidad frente a managed identity + AcrPull.
- **Repo git local con hook** en lugar de GitHub: no hay cuentas ni dependencia de portales. El hook llama a `http://localhost:8080/git/notifyCommit?url=file:///repo`.
- **El primer build se lanza a mano** ("Construir ahora") después de `3-crear-infra.ps1`.
- **Prueba que falla a propósito en la clase**: se borra la línea que menciona "UNLaM" en `index.html`. Después se arregla con `git revert --no-edit HEAD`.

## Convenciones técnicas importantes

- **Los `.ps1` van en UTF-8 CON BOM y CRLF.** Sin BOM, Windows PowerShell 5.1 muestra mal los acentos. Después de editar un `.ps1`, re-normalizar la codificación.
- **Compatibles con Windows PowerShell 5.1 y PowerShell 7.**
- **`ErrorActionPreference`:** `comun.ps1` pone `Stop`. En PS 5.1, redirigir el stderr de un comando nativo (`2>$null`, `2>&1`) con `Stop` activo **corta el script**. Por eso esos bloques ponen `$ErrorActionPreference = 'Continue'` en el scope local (ver `Test-Jenkins`, `Invoke-AzIntento` y los bloques de git/compose).
- **Comillas en queries JMESPath:** no usar comillas dobles anidadas en los argumentos de `az`, porque PS 5.1 las rompe al pasarlas a un nativo. Usar comillas simples dentro de la query.
- **Archivos que lee Linux** (`azure.env`, el hook, `Jenkinsfile`, `*.sh`, `Dockerfile`, `*.conf`) van con **LF y sin BOM**. Para escribirlos desde PowerShell usar `Write-ArchivoLinux`. El `.gitattributes` del repo fuerza `eol=lf`.
- **Los `sh` del Jenkinsfile corren en `/bin/sh` (dash):** solo sintaxis POSIX.
- **Las rutas son de Windows** (`.git\hooks\post-commit`, `Join-Path` con `\`). En Linux, pwsh las interpreta distinto: tenerlo en cuenta al probar en Linux.

## Cómo probar

- **Sintaxis de PowerShell:**
  `[System.Management.Automation.Language.Parser]::ParseFile(<ruta>, [ref]$null, [ref]$errores)` para cada `.ps1`.
- **Lógica de los scripts sin Azure:** poner en el PATH un `docker` falso que registre las llamadas y devuelva respuestas preparadas para `exec jenkins-demo az ...`. Así ya se probaron `3-crear-infra.ps1`, `4-escalar.ps1` y `8-destruir-infra.ps1`, incluyendo una región rechazada que pasa a la siguiente. Reemplazar `Start-Process` por una función vacía.
- **`prueba.sh`:** servir `sitio/` con `python -m http.server`, con un archivo `salud` que contenga "OK", y correr `sh pruebas/prueba.sh http://localhost:PUERTO` con la página correcta y con la línea UNLaM borrada.
- **Prueba real (pendiente):** en la computadora de Fernando, con Docker Desktop, correr los pasos 0→8 completos (el 9 es opcional). **Nunca se hizo una pasada completa contra Azure real desde el entorno de desarrollo:** solo Fernando la corrió, y así apareció el bug que sigue.

## Estado actual / historial de problemas

- **Bug reportado:** en la etapa 5 aparecía `Authentication failed when pulling container image 'acrdemo....azurecr.io/demo-app:3'. Provide 'registryCredentials'...`. La app no tenía (o tenía mal) la credencial del ACR.
  - **Causa real (verificada en Azure el 2026-10-09):** el environment se crea en modo **Express** (`properties.environmentMode: Express`, visible con api-version 2026-07-01; la CLI 2.90 no tiene flag para elegirlo). En Express:
    1. `az containerapp registry set` (y un PATCH REST) **descarta la entrada de `registries`** si la app no usa una imagen de ese registro (guarda el secreto, pero `registries` queda `null`). Como la app arrancaba con `mcr.microsoft.com/k8se/quickstart`, la credencial nunca quedaba, y el primer deploy fallaba.
    2. Cuando un tag falla al descargarse, **ese tag queda "envenenado"**: reintentarlo falla aunque la credencial ya esté bien; un tag nuevo funciona.
    3. No admite `--revision-suffix` (las revisiones se llaman `<app>--latest`).
  - Hipótesis descartada: las attestations de Docker Desktop (OCI index con manifiesto `unknown/unknown`). Se probó una imagen con attestations y desplegó bien; se quitó `--provenance=false` del Jenkinsfile.
  - **Corrección:** `3-crear-infra.ps1` construye `demo-app:inicial` (`FROM mcr.microsoft.com/k8se/quickstart:latest`) dentro del contenedor, la sube al ACR y crea la app con esa imagen y `--registry-server/--registry-username/--registry-password` en el mismo `create`. Si la app existe sin la credencial, la borra y la recrea. Probado en Azure: create + `registry set` + `update --image` con tag nuevo (lo que hace el Jenkinsfile) → OK. El script modificado en sí no se corrió completo.
  - **Segundo fallo (2026-10-10):** la etapa 5 falló en `az containerapp registry set` con `504 PolicyEvaluationTimeout` (error transitorio de Azure, política de la suscripción). La app ya tenía la credencial, así que ese paso sobraba. El Jenkinsfile ahora solo hace `registry set` si falta el servidor en `registries`, y envuelve `registry set` y `update` en `reintentar` (hasta 4 intentos, esperas de 20/40/60 s). También hace `set +x` alrededor de la contraseña para que no aparezca en el log. Probada la etapa 5 contra Azure real (camino "ya tiene la credencial"); el camino de reintento solo se probó con comandos falsos en dash.
  - Alternativa documentada por Microsoft para Express: identidad administrada **user-assigned** + AcrPull (la system-assigned no está soportada en Express).
  - Recordatorio: `repo-demo/Jenkinsfile` es una **copia**. Los cambios en `app-plantilla/Jenkinsfile` hay que copiarlos y commitearlos en `repo-demo` (o recrear con `-RepoNuevo`).
- **Riesgos abiertos:**
  - Algunas organizaciones bloquean el login por device code con Conditional Access.
  - Según Microsoft, Azure for Students es solo para estudiantes, no para docentes. La alternativa recomendada en la guía es pay-as-you-go: el ACR Basic cuesta unos USD 5/mes (prorrateado por día) y Container Apps entra en la cuota gratuita.
  - Container Apps en frío tarda unos segundos (escala a cero).
- **Ideas pendientes / posibles:**
  - Slides de apoyo además del SVG.
  - Cambiar Jenkins por Gitea + Actions si resulta pesado.
  - Fijar la versión de azure-cli en el Dockerfile.

## Forma de trabajar esperada

- Antes de cambiar el diseño, explicar el motivo y consultar. Para fixes puntuales, avanzar directamente.
- Después de editar, probar lo que se pueda probar localmente. Decir con claridad qué se probó y qué no.
- Mantener `GUIA-PROFESOR.md` sincronizada con los scripts: nombres de pasos, parámetros y troubleshooting.
