#!/usr/bin/env bash
# Remote production deploy for the Fall Guardian API.
#
# Executed on the production host by .github/workflows/api-deploy.yaml:
#   ssh host "bash -s -- <deploy_path> <env_file> <image_ref>" < scripts/deploy-api-remote.sh
#
# Flow:
#   1. remember the image currently running the `app` service (rollback target)
#   2. pull the new image
#   3. run Doctrine migrations with the NEW image in a one-off container
#   4. start the new containers
#   5. probe /health; on failure restore the previous image and exit non-zero
#
# Schema changes are NOT rolled back. Migrations must therefore be backward
# compatible with the previously deployed code (expand/contract): add columns
# and tables first, ship code that uses them, and drop old structures only in
# a later release. See backend/api/docs/OVH_GITHUB_ACTIONS_DEPLOYMENT.md.
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <deploy_path> <env_file> <image_ref>" >&2
    exit 64
fi

deploy_path=$1
env_file=$2
new_image=$3

health_attempts=${HEALTH_ATTEMPTS:-36}
health_interval_seconds=${HEALTH_INTERVAL_SECONDS:-5}

cd "$deploy_path"

compose() {
    docker compose --env-file "$env_file" -f compose.prod.yaml "$@"
}

probe_health() {
    local attempt
    for attempt in $(seq 1 "$health_attempts"); do
        if compose exec -T app curl -fsS http://localhost/health >/dev/null 2>&1; then
            echo "Health probe passed (attempt ${attempt}/${health_attempts})."
            return 0
        fi
        sleep "$health_interval_seconds"
    done
    return 1
}

dump_diagnostics() {
    compose ps || true
    compose logs --tail=100 app || true
}

previous_container=$(compose ps -q app 2>/dev/null || true)
previous_image=""
if [ -n "$previous_container" ]; then
    previous_image=$(docker inspect --format '{{.Config.Image}}' "$previous_container" 2>/dev/null || true)
fi
echo "Previous API image: ${previous_image:-<none>}"
echo "Target API image:   ${new_image}"

export API_IMAGE="$new_image"

echo "==> Pulling images"
compose pull

echo "==> Running database migrations with the new image"
compose run --rm migrate \
    php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration

echo "==> Starting new containers"
compose up -d --no-build --remove-orphans

echo "==> Probing health"
if probe_health; then
    echo "Deployed ${new_image}."
    exit 0
fi

echo "::error::Health probe failed for ${new_image}." >&2
dump_diagnostics

if [ -z "$previous_image" ] || [ "$previous_image" = "$new_image" ]; then
    echo "::error::No previous image to roll back to." >&2
    exit 1
fi

echo "==> Rolling containers back to ${previous_image} (database schema is not rolled back)"
export API_IMAGE="$previous_image"
compose up -d --no-build --remove-orphans
if probe_health; then
    echo "::error::Rolled back to ${previous_image}; deploy of ${new_image} failed." >&2
else
    echo "::error::Rollback to ${previous_image} is also unhealthy. Manual intervention required." >&2
    dump_diagnostics
fi
exit 1
