#syntax=docker/dockerfile:1

ARG REGISTRY=""
FROM ${REGISTRY}dunglas/frankenphp:1.12.1-php8.5 AS frankenphp_upstream

FROM frankenphp_upstream AS frankenphp_base

WORKDIR /app

ENV PHP_INI_SCAN_DIR=":$PHP_INI_DIR/app.conf.d"

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    acl \
    && rm -rf /var/lib/apt/lists/* \
    && set -eux; \
    install-php-extensions \
    @composer \
    apcu \
    intl \
    opcache \
    pdo_pgsql \
    redis \
    sodium \
    zip

COPY --link .docker/api/frankenphp/conf.d/10-app.ini $PHP_INI_DIR/app.conf.d/
COPY --link --chmod=755 .docker/api/frankenphp/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
COPY --link .docker/api/frankenphp/Caddyfile /etc/caddy/Caddyfile

ENTRYPOINT ["docker-entrypoint"]

HEALTHCHECK --start-period=120s CMD curl -f http://localhost:80/health || exit 1
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]

FROM frankenphp_base AS frankenphp_test

ENV APP_ENV=test

RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

RUN set -eux; \
    install-php-extensions pcov

COPY --link .docker/api/frankenphp/conf.d/20-app.dev.ini $PHP_INI_DIR/app.conf.d/

CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]

FROM frankenphp_base AS frankenphp_dev

ENV APP_ENV=dev \
    XDEBUG_MODE=debug \
    COMPOSER_ALLOW_SUPERUSER=1

RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/* \
    && git config --global --add safe.directory /app

RUN set -eux; \
    install-php-extensions xdebug

COPY --link .docker/api/frankenphp/conf.d/20-app.dev.ini $PHP_INI_DIR/app.conf.d/

CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile", "--watch"]

FROM frankenphp_base AS frankenphp_prod

ENV APP_ENV=prod \
    FRANKENPHP_CONFIG="import worker.Caddyfile" \
    COMPOSER_ALLOW_SUPERUSER=1

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY --link .docker/api/frankenphp/conf.d/20-app.prod.ini $PHP_INI_DIR/app.conf.d/
COPY --link .docker/api/frankenphp/worker.Caddyfile /etc/caddy/worker.Caddyfile

COPY --link composer.* symfony.* ./
RUN set -eux; \
    composer install --no-cache --prefer-dist --no-dev --no-autoloader --no-scripts --no-progress

COPY --link . ./
RUN set -eux; \
    rm -Rf .docker/api/frankenphp; \
    mkdir -p var/cache var/log; \
    composer dump-autoload --classmap-authoritative --no-dev; \
    composer dump-env prod; \
    composer run-script --no-dev post-install-cmd; \
    chmod +x bin/console; sync; \
    unset COMPOSER_ALLOW_SUPERUSER
