# Imagen de Jenkins preconfigurada para la demo de Nube + DevOps
# (Virtualización de Hardware - UNLaM)
#
# Incluye:
#   - Jenkins LTS (versión fijada para que la demo sea reproducible)
#   - Docker CLI (usa el Docker del host a través del socket)
#   - Azure CLI (para hablar con Azure desde el pipeline y desde los scripts)
#   - Plugins necesarios + configuración como código (JCasC)
#
# Para actualizar Jenkins, cambiar JENKINS_VERSION por otra LTS (ver https://www.jenkins.io/changelog-stable/)
ARG JENKINS_VERSION=2.568.3
FROM jenkins/jenkins:${JENKINS_VERSION}-jdk21

USER root

# Docker CLI (instrucciones oficiales de https://www.jenkins.io/doc/book/installing/docker/)
RUN apt-get update && apt-get install -y --no-install-recommends lsb-release ca-certificates curl gnupg && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Azure CLI instalada con pip en un entorno virtual.
# Se eligió este método porque funciona sin importar la versión de Debian
# que use la imagen base de Jenkins (el repo apt de Microsoft a veces tarda en soportar versiones nuevas).
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv && \
    python3 -m venv /opt/az && \
    /opt/az/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/az/bin/pip install --no-cache-dir azure-cli && \
    ln -s /opt/az/bin/az /usr/local/bin/az && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Git: aceptar el repositorio montado desde Windows aunque tenga otro dueño
RUN git config --system --add safe.directory '*'

# La configuración de Azure CLI (el login) se guarda en el volumen de Jenkins, así sobrevive reinicios
ENV AZURE_CONFIG_DIR=/var/jenkins_home/.azure
# Sin el selector interactivo de suscripción al hacer login (la elige el script) y sin telemetría
ENV AZURE_CORE_LOGIN_EXPERIENCE_V2=off \
    AZURE_CORE_COLLECT_TELEMETRY=false \
    AZURE_CORE_ONLY_SHOW_ERRORS=true

USER jenkins

# Plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Configuración como código: usuario, seguridad y el job de la demo
COPY casc.yaml /usr/share/jenkins/ref/casc.yaml
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc.yaml

# - Saltear el asistente inicial
# - Permitir que el job use un repositorio git local (file:///repo)
# - Permitir que el hook post-commit avise a Jenkins sin token
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false \
 -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true \
 -Dhudson.plugins.git.GitStatus.NOTIFY_COMMIT_ACCESS_CONTROL=disabled-for-polling"
