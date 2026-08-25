#!/bin/bash

# CI to verify all the instances specified in this repo have valid configs.
# The intention here is to verify that any mounted config folder will work
# with the container image specified in values.yaml
#
# At present this will only work with IOCs because it uses ibek. To support
# other future services that don't use ibek, we will need to add a standard
# entrypoint for validating the config folder mounted at /config.

ROOT=$(realpath $(dirname ${0}))
set -xe
rm -rf ${ROOT}/.ci_work/
mkdir -p ${ROOT}/.ci_work

# Perform pre-commit checks to ensure techui-builder has validated the synoptic
# and that each instance's ioc.schema.json is up to date.
################################################################################


cd ${ROOT}
# techui-support is a submodule; initialise it for the synoptic checks.
# (the old ibek-runtime-streamdevice submodule has been retired in favour of
#  'ibek pattern' vendoring, so no submodule init is required for runtime support)
git submodule update --init

pip install uv
# use python 3.13 to ensure latest pydantic
uv venv --python 3.13 --clear
source .venv/bin/activate
uv pip install -r requirements.txt

# run pre-commit checking which tool versions will be used.
uvx pre-commit install
uvx ibek --version
uvx techui-builder --version
uvx pre-commit run --all-files --show-diff-on-failure

# Determine diff base (also used later to pick the changed services)
if [[ -n "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}" ]]; then
    # GitLab MR
    DIFF_BASE="origin/${CI_MERGE_REQUEST_TARGET_BRANCH_NAME}"
elif [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    # GitHub PR
    DIFF_BASE="origin/${GITHUB_BASE_REF}"
elif git rev-parse HEAD~1 >/dev/null 2>&1; then
    # normal push
    DIFF_BASE="HEAD~1"
else
    # first commit
    DIFF_BASE=$(git hash-object -t tree /dev/null)
fi

# Verify vendored runtime-support integrity for every instance
################################################################################
# Each instance that has vendored patterns carries a runtime-lock.yaml at its
# root recording the sha256 of every vendored file. 'ibek pattern check'
# verifies the on-disk files still match the lock.
#
# A hash mismatch is ALWAYS a hard failure, on every branch: vendored files are
# DO-NOT-EDIT. To deliberately diverge from a pristine vendored file, mark its
# entry in runtime-lock.yaml as 'DIRTY # <reason>' -- a visible, committed opt-in
# that 'ibek pattern check' tolerates. To merely try a throwaway edit, bypass with
# 'git commit --no-verify' and tolerate the red branch CI (a red check does not
# block deploying the branch to a cluster).

shopt -s nullglob
for lock in ${ROOT}/services/*/runtime-lock.yaml; do
    instance_dir=$(dirname "${lock}")
    instance_name=$(basename "${instance_dir}")

    # honour .ci_skip_checks
    checks=${ROOT}/.ci_skip_checks
    if [[ -f "${checks}" ]] && grep -Fxq -- "${instance_name}" "${checks}"; then
        echo "Skipping pattern check for ${instance_name}"
        continue
    fi

    echo "Checking vendored runtime-support for ${instance_name}"
    ibek pattern check "services/${instance_name}"
done
shopt -u nullglob

# Verify the IOC instance definitions
################################################################################
# if a docker provider is specified, use it
if [[ $DOCKER_PROVIDER ]]; then
    docker=$DOCKER_PROVIDER
# Otherwise use docker if available else use podman
else
    if ! docker version &>/dev/null; then docker=podman; else docker=docker; fi
fi

# Get changed services (excluding global values.yaml)
CHANGED_SERVICES=$(git diff --name-only "$DIFF_BASE" HEAD \
  | grep '^services/' \
  | grep -v '^services/values.yaml' \
  | cut -d/ -f2 \
  | sort -u)


# Need to make sure values.yaml is included in the ci
cp -L "${ROOT}/services/values.yaml" "${ROOT}/.ci_work/"

# copy only the changed services to a temporary location to avoid dirtying the repo
for svc in $CHANGED_SERVICES; do
  echo "Preparing service: $svc"
  cp -Lr "${ROOT}/services/$svc" "${ROOT}/.ci_work/"
done

# enable nullglob so * is not taken literally if no services are changed
shopt -s nullglob
for service in ${ROOT}/.ci_work/*/  # */ to skip files
do
    ### Lint each service chart and validate if schema given ###
    service_name=$(basename $service)

    # skip services appearing in .ci_skip_checks
    checks=${ROOT}/.ci_skip_checks
    if [[ -f "${checks}" ]] && grep -Fxq -- "${service_name}" "${checks}"; then
        echo "Skipping ${service_name}"
        continue
    fi

    echo "Validating helm chart for ${service_name}"
    $docker run --rm --entrypoint bash \
        -v ${ROOT}/.ci_work:/services:z \
        -v ${ROOT}/.helm-shared:/.helm-shared:z \
        alpine/helm:3.14.3 \
        -c "
           helm dependency update /services/$service_name &&
           helm template /services/$service_name --values /services/values.yaml \\
             --values /services/$service_name/values.yaml &&
           helm lint /services/$service_name --values /services/values.yaml \\
             --values /services/$service_name/values.yaml &&
           rm -rf /services/$service_name/charts
        "

    ### Validate each ioc config ###
    # Skip if subfolder has no config to validate
    if [ ! -f "${service}/config/ioc.yaml" ]; then
        continue
    fi

    # Get the container image that this service uses from values.yaml if supplied
    image=$(cat ${service}/values.yaml | sed -rn 's/^ +image: (.*)/\1/p')

    if [ -n "${image}" ]; then
        echo "Validating ${service} with ${image}"

        runtime=/tmp/ioc-runtime/$(basename ${service})
        mkdir -p ${runtime}

        # avoid issues with auto-gen genicam pvi files (ioc-adaravis only)
        sed -i s/AutoADGenICam/ADGenICam/ ${service}/config/ioc.yaml

        # This will fail and exit if the ioc.yaml is invalid
        # Also show the startup script we just generated (and verify it exists)
        # 'ibek runtime generate2 /config' reads the whole mounted config folder
        # (ioc.yaml + any vendored/local *.ibek.support.yaml, proto and db) and
        # places the generated runtime (st.cmd, proto, db) under /epics/runtime.
        $docker run --rm --entrypoint bash \
            -v ${service}/config:/config:z \
            ${image} \
            -c "
            ibek runtime generate2 /config  &&
            cat /epics/runtime/st.cmd
            "

    fi
done

rm -r ${ROOT}/.ci_work
