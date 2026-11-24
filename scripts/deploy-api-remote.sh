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
#   5. probe /health; if starting containers or the probe fails, restore the
#      previous image and exit non-zero
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

# Only the application services are pulled/recreated; postgres and redis keep
# running untouched during a deploy.
app_services=(app messenger alert_reconciler)
last_image_file=.last-deployed-api-image

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

# Rollback target: the image of the existing app container (even if stopped or
# restarting), else the image recorded by the last successful deploy.
previous_container=$(compose ps -a -q app 2>/dev/null | head -n 1 || true)
previous_image=""
if [ -n "$previous_container" ]; then
    previous_image=$(docker inspect --format '{{.Config.Image}}' "$previous_container" 2>/dev/null || true)
fi
if [ -z "$previous_image" ] && [ -f "$last_image_file" ]; then
    previous_image=$(cat "$last_image_file")
fi
if [ -z "$previous_image" ]; then
    echo "::warning::No previous API image found: automatic rollback is unavailable for this deploy." >&2
fi
echo "Previous API image: ${previous_image:-<none>}"
echo "Target API image:   ${new_image}"

export API_IMAGE="$new_image"

echo "==> Pulling images"
compose pull "${app_services[@]}"

echo "==> Running database migrations with the new image"
compose run --rm migrate \
    php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration

# From here on, a failing `compose up` may already have stopped or recreated
# production containers, so it must not abort via `set -e`: both an `up`
# failure and a failed health probe go through the same diagnostics/rollback.
echo "==> Starting new containers"
if ! compose up -d --no-build --remove-orphans "${app_services[@]}"; then
    echo "::error::Starting containers on ${new_image} failed." >&2
elif echo "==> Probing health" && probe_health; then
    printf '%s\n' "$new_image" > "$last_image_file"
    echo "Deployed ${new_image}."
    exit 0
else
    echo "::error::Health probe failed for ${new_image}." >&2
fi
dump_diagnostics

if [ -z "$previous_image" ] || [ "$previous_image" = "$new_image" ]; then
    echo "::error::No previous image to roll back to. Manual intervention required." >&2
    exit 1
fi

echo "==> Rolling containers back to ${previous_image} (database schema is not rolled back)"
export API_IMAGE="$previous_image"
if ! compose up -d --no-build --remove-orphans "${app_services[@]}"; then
    echo "::error::Rollback to ${previous_image} failed to start containers. Manual intervention required." >&2
    dump_diagnostics
elif probe_health; then
    echo "::error::Rolled back to ${previous_image}; deploy of ${new_image} failed." >&2
else
    echo "::error::Rollback to ${previous_image} is also unhealthy. Manual intervention required." >&2
    dump_diagnostics
fi
exit 1
