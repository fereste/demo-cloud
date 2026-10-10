# Demo Nube + DevOps — Guía para el profesor

Virtualización de Hardware · Ingeniería en Informática · UNLaM

Esta demo muestra, en unos 60 minutos, cómo un cambio en el código llega solo a una aplicación publicada en la nube pública. Todo se maneja desde PowerShell y Jenkins: no hace falta entrar al portal de Azure ni a GitHub, no hay nada preconfigurado en cuentas ajenas y cualquier profesor puede correrla con su propia suscripción de Azure.

## La idea en una frase

"Somos el equipo de una empresa que tiene una página web. Cada vez que un desarrollador guarda un cambio (commit), una máquina lo construye, lo prueba y, si está todo bien, lo publica en la nube sin que nadie toque nada. Si el cambio está roto, no llega a producción."

## Qué hay en la carpeta

| Archivo / carpeta | Para qué sirve |
|---|---|
| `0-verificar-requisitos.ps1` | Revisa que la computadora tenga Docker y Git funcionando. |
| `1-iniciar-jenkins.ps1` | Crea el repositorio git de la demo (`repo-demo`) y levanta Jenkins en un contenedor. |
| `2-login-azure.ps1` | Inicia sesión en Azure con la cuenta del profesor. |
| `3-crear-infra.ps1` | Crea los recursos en Azure desde la línea de comandos (unos 5 minutos). |
| `4-escalar.ps1` | Opcional: cambia la cantidad de réplicas para mostrar elasticidad. |
| `5-ver-historial.ps1` | Opcional: muestra la trazabilidad commit → build → imagen → revisión. |
| `8-destruir-infra.ps1` | Borra todo lo creado en Azure al terminar. Necesita que Jenkins siga corriendo (usa su Azure CLI). |
| `9-limpiar-local.ps1` | Opcional, siempre DESPUÉS del 8: borra todo lo local (contenedores, volumen, imágenes, carpetas generadas) para repetir la demo desde cero. |
| `app-plantilla/` | La aplicación de ejemplo (página web en nginx + Dockerfile + pruebas + Jenkinsfile). No se toca: se copia a `repo-demo`. |
| `jenkins/` | Imagen de Jenkins con Docker CLI, Azure CLI, plugins y el job ya configurado (configuración como código). |
| `docker-compose.yml` | Define el contenedor de Jenkins. |
| `diagrama-flujo.svg` | Diagrama del flujo para proyectar antes de la demo. |

Hay dos cosas que se crean solas y no hace falta distribuir: `repo-demo/` (el repositorio de la demo) y `config/azure.env` (los nombres de los recursos que se crearon en Azure).

## Qué se ve funcionando

```
 Profesor              Jenkins (contenedor local)                     Azure (nube pública)
 ────────              ──────────────────────────                     ────────────────────
 edita index.html
 git commit  ───────►  1. Preparar
                       2. Construir imagen (docker build)
                       3. Probar (levanta la imagen y le corre pruebas)
                          └─ si falla: se corta acá, producción no cambia
                       4. Publicar imagen  ─────────────────────────►  Azure Container Registry
                       5. Desplegar        ─────────────────────────►  Azure Container Apps
                                                                        └─ https://app-demo-nube.<...>.azurecontainerapps.io
```

Los servicios de Azure que se usan son dos. **Azure Container Registry (ACR)** es un registro privado de imágenes Docker, como un Docker Hub propio. **Azure Container Apps** es una plataforma (PaaS) donde se le entrega una imagen y la nube se encarga de ejecutarla, darle una URL pública con HTTPS, balancear la carga entre réplicas y escalarla; incluso puede escalar a cero cuando nadie la usa.

## Requisitos

La computadora necesita Windows 10/11 con **Docker Desktop** (en modo contenedores Linux, que es el modo por defecto) y **Git para Windows** (`winget install --id Git.Git -e`). No hace falta instalar Azure CLI: viene dentro del contenedor de Jenkins. Se necesitan unos 4 GB libres de disco para la imagen de Jenkins y conexión a internet.

También hace falta una **suscripción de Azure propia**. Los scripts funcionan con cualquier tipo de suscripción; ver la sección "Qué cuenta de Azure usar" más abajo.

## Preparación (una sola vez por computadora, ~20 minutos, antes de la clase)

1. Descomprimir la carpeta, por ejemplo en `C:\demo-nube-devops`.
2. Abrir **PowerShell** (no PowerShell ISE) en esa carpeta y habilitar los scripts para esa ventana:

   ```powershell
   cd C:\demo-nube-devops
   Get-ChildItem -Recurse | Unblock-File
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

   `Set-ExecutionPolicy -Scope Process` hay que repetirlo cada vez que se abre una ventana nueva de PowerShell.

3. `.\0-verificar-requisitos.ps1` y resolver lo que aparezca en amarillo.
4. `.\1-iniciar-jenkins.ps1`. La primera vez construye la imagen de Jenkins (entre 5 y 10 minutos según la conexión). Al terminar abre `http://localhost:8080`; el usuario es `profe` y la contraseña `demo`.
5. `.\2-login-azure.ps1`. Muestra un código: abrir https://microsoft.com/devicelogin, pegar el código y entrar con la cuenta de Azure. La sesión queda guardada dentro de Jenkins y dura semanas.
6. Recomendado: hacer una pasada completa de la demo (pasos 3 a 8 del guion) para verificar que todo anda con esa cuenta, y al final ejecutar `.\8-destruir-infra.ps1`.

Antes de cada clase alcanza con abrir Docker Desktop. Jenkins arranca solo con Docker; si no, se vuelve a ejecutar `.\1-iniciar-jenkins.ps1`, que tarda segundos porque la imagen ya está construida. Para empezar con un repositorio limpio (sin los commits de la clase anterior) se usa `.\1-iniciar-jenkins.ps1 -RepoNuevo`.

## Guion de la clase (~60 minutos)

Conviene tener abiertas tres ventanas lado a lado: PowerShell, Jenkins (`http://localhost:8080/job/demo-nube/`) y el navegador con la aplicación.

### 1. Presentar el problema (5 min)

Proyectar `diagrama-flujo.svg`. Plantear el escenario: una empresa con una página web, varios desarrolladores y la necesidad de publicar cambios seguido sin romper nada. Preguntar cómo lo harían a mano (copiar archivos por FTP, entrar al servidor, reiniciar...) y qué puede salir mal. La demo automatiza exactamente ese camino.

### 2. Crear la infraestructura en la nube desde la consola (10 min)

```powershell
.\3-crear-infra.ps1
```

Mientras corre, abrir el script y leerlo en voz alta: son comandos `az` comunes, uno por recurso. Conceptos para marcar:

- **Autoservicio bajo demanda**: sin pedirle nada a nadie, en minutos hay infraestructura funcionando, y se crea con un script (base de la *infraestructura como código*).
- **Regiones**: el script busca en qué centros de datos de Azure la suscripción puede crear recursos. Mostrar la línea "Regiones permitidas".
- **Grupo de recursos**: todo queda agrupado para poder borrarlo junto al final.
- **PaaS vs IaaS**: no se creó ninguna máquina virtual. Se entrega un contenedor y la plataforma se ocupa del resto (sistema operativo, parches, balanceo, certificados HTTPS).
- **Pago por uso**: la app tiene `min-replicas 0`, así que si nadie la visita no consume CPU ni cobra.

Al terminar abre la URL pública: se ve una página de ejemplo de Microsoft. Ya hay una aplicación en internet con HTTPS, pero todavía no es la nuestra.

> Si el tiempo es justo, este paso se puede ejecutar antes de la clase y solo mostrar el script.

### 3. El pipeline y el primer despliegue (10 min)

En Jenkins, abrir el job **Demo Nube + DevOps** y hacer clic en **Construir ahora**. Mientras corre (2-3 minutos), mostrar:

- El archivo `repo-demo\Jenkinsfile`: el pipeline también es código y vive en el mismo repositorio que la aplicación (*pipeline como código*).
- `repo-demo\Dockerfile`: la aplicación se empaqueta en una imagen que incluye todo lo que necesita. Es la misma imagen que se prueba localmente y la que corre en la nube.
- Las etapas en la vista del job: Preparar → Construir imagen → Probar → Publicar → Desplegar. Hacer clic en una etapa para ver su salida.

Al terminar, recargar la URL: ahora se ve nuestra página con **Versión 1**, que es el número de build de Jenkins.

> La primera visita después de un rato sin uso puede tardar unos segundos porque la app estaba escalada a cero (*cold start*). Es un buen momento para explicarlo.

### 4. Integración y despliegue continuo en acción (10 min)

Editar la página:

```powershell
notepad .\repo-demo\sitio\index.html
```

Cambiar el color (`--color-fondo`, por ejemplo a `#16a34a`) y el texto del `<h1>`. Guardar y hacer commit:

```powershell
cd repo-demo
git commit -am "Cambio el color y el mensaje de bienvenida"
cd ..
```

Sin tocar nada más, Jenkins arranca un build nuevo: el repositorio tiene un *hook* que le avisa en cada commit. Cuando termina, recargar la página: color nuevo y **Versión 2**. Conceptos para marcar:

- **CI (integración continua)**: cada cambio se construye y prueba automáticamente.
- **CD (despliegue continuo)**: si pasa las pruebas, llega solo a producción.
- **Artefacto inmutable y versionado**: cada build genera una imagen nueva con su número (`demo-app:2`) y no se modifica la anterior.
- **Despliegue sin corte**: Azure levanta la versión nueva y recién después deja de mandar tráfico a la anterior.

### 5. Un cambio roto no llega a producción (8 min)

Contar que "el cliente" exige que la página mencione a la UNLaM, y que por eso hay una prueba automática (`repo-demo\pruebas\prueba.sh`) que lo verifica. Borrar la línea `<p>Virtualización de Hardware &middot; UNLaM</p>` de `index.html` y hacer commit:

```powershell
cd repo-demo
git commit -am "Simplifico la portada"
```

El build falla en la etapa **3. Probar** (queda en rojo) y las etapas 4 y 5 no se ejecutan. Mostrar la salida con `[FALLA] La página NO menciona a la UNLaM`. Recargar la URL: **sigue la versión anterior**, así que los usuarios nunca vieron el error.

Para corregirlo, deshacer el último commit con otro commit (*rollback* por control de versiones):

```powershell
git revert --no-edit HEAD
cd ..
```

El pipeline vuelve a correr, pasa las pruebas y despliega. Conceptos: *quality gate*, detectar el error temprano ("fallar rápido"), rollback, y que el historial queda registrado.

### 6. Elasticidad (7 min)

```powershell
.\4-escalar.ps1 -Replicas 3
```

Azure levanta 3 contenedores iguales. Recargar la página varias veces: el dato **"Servido por la réplica"** va cambiando (cada réplica tiene su propio nombre, que genera al arrancar) porque la nube reparte los pedidos entre réplicas (*balanceo de carga*). Conceptos: escalado horizontal, elasticidad, alta disponibilidad, y que se paga por réplica.

Volver a escalar a cero:

```powershell
.\4-escalar.ps1 -Replicas 0
```

### 7. Trazabilidad (5 min)

```powershell
.\5-ver-historial.ps1
```

Muestra las imágenes guardadas en el registro, las revisiones desplegadas en Azure y los commits. Cada versión en producción se puede rastrear hasta el commit que la generó.

### 8. Cierre y limpieza (5 min)

Repasar el diagrama con lo que se vio. Después:

```powershell
.\8-destruir-infra.ps1
```

Borra el grupo de recursos con todo lo que contiene. Es importante hacerlo siempre para no gastar crédito. Sirve para cerrar con otro concepto: en la nube los recursos se crean y se destruyen en minutos.

## Relación con el programa

| Momento de la demo | Unidad | Conceptos |
|---|---|---|
| Scripts `.ps1` y comandos `az` | 1 | Scripting en PowerShell para automatizar tareas |
| Jenkins y la app en contenedores, Dockerfile, registro | 3 | Contenedores, Docker (imagen, registro, redes), CI/CD, etapas DevOps (build, test, release, deploy) |
| Container Apps escalando réplicas | 3 | Orquestación: la plataforma decide dónde y cuántos contenedores correr |
| Crear infraestructura, regiones, PaaS, escalar, destruir | 5 | Características del cloud (autoservicio, elasticidad, pago por uso), capas IaaS / PaaS, HTTPS/DNS públicos |

## Qué cuenta de Azure usar

Cada profesor usa **su propia suscripción**; no hay que compartir cuentas. Opciones:

- **Pago por uso (pay-as-you-go)** con tarjeta. Es la opción más estable. Si se borran los recursos al terminar, el costo por clase es de centavos de dólar: el registro Basic cuesta alrededor de USD 0,17 por día y Container Apps entra en la cuota gratuita mensual (180.000 vCPU-segundos).
- **Cuenta gratuita de Azure** (crédito inicial por 30 días), que después pasa a pago por uso.
- **Azure for Students**: según Microsoft está pensada para estudiantes, no para docentes, así que hay que confirmar que la cuenta del profesor sea elegible. Si se usa, tener en cuenta dos cosas: restringe las regiones (el script las detecta solo) y no permite *ACR Tasks* (por eso la imagen se construye localmente con Docker y no en la nube).

Si la cuenta tiene varias suscripciones, `2-login-azure.ps1` prefiere la que se llama "Azure for Students" y si no la encuentra pregunta cuál usar.

## Problemas frecuentes

**"No se puede cargar el archivo ... porque la ejecución de scripts está deshabilitada"**: ejecutar `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` en esa ventana.

**El commit no dispara el build**: hacer clic en **Construir ahora** en Jenkins; el resultado es el mismo. Revisar que el commit se haya hecho dentro de `repo-demo` y que Jenkins esté en `http://localhost:8080`. El aviso lo hace el archivo `repo-demo\.git\hooks\post-commit`, que se crea con `1-iniciar-jenkins.ps1`.

**El build falla en "1. Preparar" con "Jenkins no tiene sesión en Azure"**: la sesión venció. Ejecutar `.\2-login-azure.ps1` de nuevo.

**El login con código falla por una política de acceso condicional**: algunas organizaciones bloquean el inicio de sesión con código de dispositivo. Usar una cuenta de otra organización (por ejemplo una cuenta personal con suscripción pay-as-you-go) o pedirle al administrador de la organización que lo habilite.

**"RequestDisallowedByAzure" o región no permitida**: el script prueba varias regiones solo. Si ninguna funciona, ver las permitidas en el portal (Policy → Assignments → "Allowed resource deployment regions") y forzar una: `.\3-crear-infra.ps1 -Region eastus2`.

**El build falla en "5. Desplegar" con "Authentication failed when pulling container image ... Provide 'registryCredentials'"**: la app no tiene cargada la credencial del registro. Azure (en los environments en modo *express*, que es el modo en que Azure creó el environment en las pruebas de octubre de 2026) solo guarda esa credencial si la app ya usa una imagen del registro; por eso `3-crear-infra.ps1` crea la app con una imagen inicial subida a nuestro registro. Solución: volver a ejecutar `.\3-crear-infra.ps1` (detecta que falta la credencial y recrea la app; la URL no cambia) y después **Construir ahora**. Reintentar el mismo build no alcanza: Azure recuerda que esa imagen falló, hace falta un build nuevo (otro número de versión).

**El build falla en "5. Desplegar" con `504 PolicyEvaluationTimeout` o `UnexpectedException`**: es un error pasajero de Azure (tardó demasiado en evaluar las políticas de la suscripción), no un problema de la demo. La etapa 5 ya reintenta sola hasta 4 veces, esperando cada vez más. Si igual falla, hacer clic en **Construir ahora** de nuevo.

**`3-crear-infra.ps1` termina con "La aplicación quedó sin la credencial del registro"**: volver a ejecutarlo; recrea la app. Si se repite, revisar con `docker exec jenkins-demo az containerapp show -n app-demo-nube -g rg-demo-nube --query properties.configuration.registries`.

**La página tarda en cargar la primera vez**: es el *cold start* de escalar a cero. Esperar unos segundos y recargar.

**La página sigue mostrando la versión anterior**: esperar unos 20-30 segundos después de que termine el pipeline (Azure está cambiando de revisión) y recargar.

**El puerto 8080 está ocupado**: cerrar el programa que lo usa, o cambiar el puerto en `docker-compose.yml` (`"127.0.0.1:8081:8080"`) y en el hook `repo-demo\.git\hooks\post-commit`.

**Se quiere empezar de cero en la computadora**: primero `.\8-destruir-infra.ps1` (Azure) y después `.\9-limpiar-local.ps1`, que borra los contenedores, el volumen de Jenkins (con la sesión de Azure), la red, las imágenes de la demo y las carpetas `repo-demo` y `config`, sin tocar otros proyectos de Docker. Pide confirmación (`-Forzar` la saltea) y con `-Cache` también vacía la caché de construcción de Docker, para ensayar el tiempo real del primer arranque. Alternativa corta: `.\8-destruir-infra.ps1 -Todo` borra los recursos de Azure, el contenedor y los datos de Jenkins, el repositorio de la demo y la sesión de Azure.

## Mantenimiento entre cuatrimestres

La demo no depende del portal web de Azure ni de GitHub, así que los cambios de interfaz no la afectan. Lo que puede cambiar con el tiempo es:

- **Versión de Jenkins**: está fijada en `jenkins/Dockerfile` (`JENKINS_VERSION`). Para actualizarla, cambiarla por una LTS reciente y reconstruir con `docker compose build --no-cache`.
- **Azure CLI**: se instala la última versión cuando se construye la imagen. Si algún comando `az` cambia, el error aparece claramente en la salida del script o del pipeline.
- **Regiones o políticas de la suscripción**: el script las detecta en cada ejecución.

Recomendación: al inicio de cada cuatrimestre, un profesor hace una pasada completa y avisa al resto si hubo que ajustar algo.

## Nota de seguridad

Para simplificar la demo, Jenkins corre como `root`, usa el Docker de la computadora, escucha solo en `localhost` y tiene una contraseña fija. Es aceptable para una demo local, no para un servidor real, y vale la pena mencionarlo en clase como contraejemplo.
