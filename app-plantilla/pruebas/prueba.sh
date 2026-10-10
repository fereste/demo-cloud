#!/bin/sh
# Pruebas automáticas de la aplicación.
# Jenkins las ejecuta contra un contenedor de prueba ANTES de desplegar en la nube.
# Si alguna falla, el pipeline se detiene y la versión rota nunca llega a Azure.
#
# Uso: sh pruebas/prueba.sh http://host:puerto

URL="$1"
FALLAS=0

ok()    { echo "  [OK]    $1"; }
falla() { echo "  [FALLA] $1"; FALLAS=$((FALLAS + 1)); }

echo "Probando la aplicación en $URL"

# Esperar a que el contenedor de prueba arranque (hasta ~10 segundos)
i=0
until curl -fs "$URL/salud" > /dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 20 ]; then break; fi
  sleep 0.5
done

# Prueba 1: el health check responde
if curl -fs "$URL/salud" | grep -q "OK"; then
  ok "El health check /salud responde OK"
else
  falla "El health check /salud no responde"
fi

# Prueba 2: la página principal responde con código HTTP 200
CODIGO=$(curl -s -o /tmp/pagina.html -w "%{http_code}" "$URL/")
if [ "$CODIGO" = "200" ]; then
  ok "La página principal responde (HTTP 200)"
else
  falla "La página principal respondió HTTP $CODIGO"
fi

# Prueba 3 (requisito del "cliente"): la página tiene que mencionar a la UNLaM
if grep -q "UNLaM" /tmp/pagina.html; then
  ok "La página menciona a la UNLaM"
else
  falla "La página NO menciona a la UNLaM (requisito obligatorio)"
fi

# Prueba 4: la página tiene un título principal (<h1>)
if grep -q "<h1>" /tmp/pagina.html; then
  ok "La página tiene un título principal"
else
  falla "La página no tiene título principal <h1>"
fi

echo ""
if [ "$FALLAS" -gt 0 ]; then
  echo "RESULTADO: $FALLAS prueba(s) fallida(s). NO se despliega."
  exit 1
fi
echo "RESULTADO: todas las pruebas pasaron."
