# Demo Nube + DevOps

Virtualización de Hardware · Ingeniería en Informática · UNLaM

Un commit en un repositorio git local dispara un pipeline de **Jenkins** (en un contenedor local) que construye una imagen Docker, la prueba, la sube a **Azure Container Registry** y la despliega en **Azure Container Apps**. Cada profesor la corre con su propia suscripción de Azure, sin usar el portal web ni GitHub.

Requisitos: Windows con Docker Desktop y Git. La guía completa, con el guion de la clase, está en **[GUIA-PROFESOR.md](GUIA-PROFESOR.md)**.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\0-verificar-requisitos.ps1
.\1-iniciar-jenkins.ps1      # Jenkins en http://localhost:8080  (profe / demo)
.\2-login-azure.ps1
.\3-crear-infra.ps1          # después: "Construir ahora" en Jenkins
# ... editar repo-demo\sitio\index.html y hacer git commit ...
.\4-escalar.ps1 -Replicas 3  # opcional
.\5-ver-historial.ps1        # opcional
.\8-destruir-infra.ps1       # ¡siempre al terminar! (primero, mientras Jenkins siga corriendo)
.\9-limpiar-local.ps1        # opcional, DESPUÉS del 8: deja la computadora como nueva (contenedores, imágenes, volúmenes)
```
