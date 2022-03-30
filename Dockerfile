# Stage 1:
# - Copy Shaarli sources
# - Build documentation
FROM python:3.10.4 AS docs
WORKDIR /usr/src/app/shaarli
RUN git clone --depth 1 https://github.com/shaarli/Shaarli.git /usr/src/app/shaarli \
  && pip install --no-cache-dir --quiet mkdocs==1.2.3 \
  && mkdocs build --clean

# Stage 2:
# - Resolve PHP dependencies with Composer
FROM composer:2.2.9 AS composer
COPY --from=docs /usr/src/app/shaarli /app/shaarli
WORKDIR /app/shaarli
RUN composer --prefer-dist --no-dev install

# Stage 3:
# - Frontend dependencies
FROM node:12-alpine AS node
WORKDIR /shaarli
COPY --from=composer /app/shaarli /shaarli
RUN yarn install \
  && yarn cache clean \
  && yarn run build \
  && rm -rf node_modules

# Stage 4:
# - Shaarli image
FROM alpine:3.15.1 AS runner

RUN apk upgrade --no-cache libretls \
  && apk --no-cache add \
  ca-certificates=20211220-r0 \
  nginx=1.20.2-r0 \
  php7=7.4.28-r0 \
  php7-ctype=7.4.28-r0 \
  php7-curl=7.4.28-r0 \
  php7-fpm=7.4.28-r0 \
  php7-gd=7.4.28-r0 \
  php7-iconv=7.4.28-r0 \
  php7-intl=7.4.28-r0 \
  php7-json=7.4.28-r0 \
  php7-mbstring=7.4.28-r0 \
  php7-openssl=7.4.28-r0 \
  php7-session=7.4.28-r0 \
  php7-xml=7.4.28-r0 \
  php7-simplexml=7.4.28-r0 \
  s6=2.11.0.0-r0

COPY --from=docs /usr/src/app/shaarli/.docker/nginx.conf /etc/nginx/nginx.conf
COPY --from=docs /usr/src/app/shaarli/.docker/php-fpm.conf /etc/php7/php-fpm.conf
COPY --from=docs /usr/src/app/shaarli/.docker/services.d /etc/services.d

RUN rm -rf /etc/php7/php-fpm.d/www.conf \
  && sed -i 's/post_max_size.*/post_max_size = 10M/' /etc/php7/php.ini \
  && sed -i 's/upload_max_filesize.*/upload_max_filesize = 10M/' /etc/php7/php.ini \
  && sed -i 's/80;/8080;/' /etc/nginx/nginx.conf

WORKDIR /var/www
COPY --from=node /shaarli shaarli

RUN chown -R nginx:nginx . \
  && sed -i 's/128M/512M/' /var/www/shaarli/init.php \
  && ln -sf /dev/stdout /var/log/nginx/shaarli.access.log \
  && ln -sf /dev/stderr /var/log/nginx/shaarli.error.log

EXPOSE 8080

ENTRYPOINT ["/bin/s6-svscan", "/etc/services.d"]
