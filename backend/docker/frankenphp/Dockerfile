FROM dunglas/frankenphp:1-php8.5-alpine

ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

RUN apk add --no-cache \
    curl \
    zip \
    unzip \
    linux-headers \
    && install-php-extensions \
    pdo_pgsql \
    intl \
    opcache \
    sodium \
    zip \
    redis

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

ENV APP_ENV=prod
ENV APP_DEBUG=0

COPY . /app
COPY docker/frankenphp/php.ini /usr/local/etc/php/conf.d/app.ini
COPY docker/frankenphp/Caddyfile /etc/caddy/Caddyfile

RUN composer install --no-dev --optimize-autoloader

EXPOSE 80 443 443/udp

CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
