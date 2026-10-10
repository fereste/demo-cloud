# Imagen de la aplicación: un servidor web nginx con nuestra página
FROM nginx:stable-alpine

# Datos que Jenkins pasa al construir la imagen
ARG VERSION=local
ARG FECHA=sin-fecha

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY sitio/ /usr/share/nginx/html/

# Estampar la versión y la fecha dentro de la página
RUN sed -i -e "s|__VERSION__|${VERSION}|g" -e "s|__FECHA__|${FECHA}|g" /usr/share/nginx/html/index.html

# Al arrancar cada contenedor, le pone a la página el nombre de la réplica (ver nombre-replica.sh)
COPY nombre-replica.sh /docker-entrypoint.d/40-nombre-replica.sh
RUN chmod +x /docker-entrypoint.d/40-nombre-replica.sh

EXPOSE 80
