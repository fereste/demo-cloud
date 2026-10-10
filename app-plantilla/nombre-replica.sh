#!/bin/sh
# Se ejecuta una vez cada vez que arranca un contenedor (lo llama el entrypoint de la imagen de nginx).
# Le pone a la página el nombre de ESTA réplica.
#
# En Azure Container Apps (modo express) el hostname es el mismo en todas las réplicas ("adc-sandbox"),
# así que no sirve para distinguirlas. Se usa el nombre que informa la plataforma si existe y,
# si no, un identificador al azar que se genera al arrancar (distinto en cada réplica).
if [ -n "$CONTAINER_APP_REPLICA_NAME" ]; then
  NOMBRE="$CONTAINER_APP_REPLICA_NAME"
else
  NOMBRE="replica-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
sed -i "s|__REPLICA__|$NOMBRE|g" /usr/share/nginx/html/index.html
echo "nombre-replica.sh: esta réplica se llama $NOMBRE"
