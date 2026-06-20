#!/bin/sh
set -e

if [ "$1" = 'frankenphp' ] || [ "$1" = 'php' ] || [ "$1" = 'bin/console' ]; then
    if [ ! -f vendor/autoload.php ] || [ ! -f vendor/autoload_runtime.php ]; then
        composer install --prefer-dist --no-progress --no-interaction
    fi

    if grep -q ^DATABASE_URL= .env; then
        echo 'Waiting for database to be ready...'
        ATTEMPTS_LEFT_TO_REACH_DATABASE=60
        until [ $ATTEMPTS_LEFT_TO_REACH_DATABASE -eq 0 ] || DATABASE_ERROR=$(php bin/console dbal:run-sql -q "SELECT 1" 2>&1); do
            if [ $? -eq 255 ]; then
                ATTEMPTS_LEFT_TO_REACH_DATABASE=0
                break
            fi
            sleep 1
            ATTEMPTS_LEFT_TO_REACH_DATABASE=$((ATTEMPTS_LEFT_TO_REACH_DATABASE - 1))
            echo "Still waiting for database to be ready. $ATTEMPTS_LEFT_TO_REACH_DATABASE attempts left."
        done

        if [ $ATTEMPTS_LEFT_TO_REACH_DATABASE -eq 0 ]; then
            echo 'The database is not up or not reachable:'
            echo "$DATABASE_ERROR"
            exit 1
        fi

        echo 'The database is now ready and reachable'

        if [ "$(find ./migrations -maxdepth 1 -iname '*.php' -print -quit)" ]; then
            if [ "${APP_ENV:-}" = "test" ]; then
                echo 'Skipping auto migrations in test environment.'
            else
                php bin/console doctrine:migrations:migrate --no-interaction
            fi
        fi
    fi

    setfacl -R -m u:www-data:rwX -m u:"$(whoami)":rwX var
    setfacl -dR -m u:www-data:rwX -m u:"$(whoami)":rwX var

    echo 'PHP app ready!'
fi

exec docker-php-entrypoint "$@"
