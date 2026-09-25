#!/bin/bash

# CI to verify all the instances specified in this repo have valid configs.
# The intention here is to verify that any mounted config folder will work
# with the container image specified in values.yaml
#
# At present this will only work with IOCs because it uses ibek. To support
# other future services that don't use ibek, we will need to add a standard
# entrypoint for validating the config folder mounted at /epics/ioc/config.

ROOT=$(realpath $(dirname ${0}))
set -xe

# Print a summary of every check when the script exits. set -e stops at the
# first failing command, so a failure is always the last step recorded in STEP.
RESULTS=()
STEP="setup"
summary() {
    local rc=$?
    { set +x; } 2>/dev/null
    echo
    echo "==================== ci_verify summary ===================="
    echo "  scope: ${SCOPE:-not reached}"
    local r
    for r in "${RESULTS[@]}"; do echo "  ${r}"; done
    if [[ ${rc} -ne 0 ]]; then
        echo "  FAIL  ${STEP} (exit ${rc})"
        echo "Stopped at the first failure: later checks did not run."
    else
        echo "All checks passed."
    fi
    echo "==========================================================="
}
trap summary EXIT

rm -rf ${ROOT}/.ci_work/
mkdir -p ${ROOT}/.ci_work

# Perform pre-commit checks to ensure techui-builder has validated the synoptic
# and that each instance's ioc.schema.json is up to date.
################################################################################


cd ${ROOT}
# techui-support is a submodule; initialise it for the synoptic checks.
# (runtime support is vendored per instance via 'ibek pattern', not a
#  submodule, so no further submodule init is required for it)
git submodule update --init

# install uv only if it is missing: a local pip may be unable to install it
if ! command -v uv >/dev/null; then
    pip install uv || {
        echo "ERROR: uv not found and pip could not install it." >&2
        echo "Install uv from https://docs.astral.sh/uv/ and re-run." >&2
        exit 1
    }
fi
# a pre-installed uv is reused as-is: >= 0.5.6 is needed (uvx --constraints)
uv --version
# use python 3.13 to ensure latest pydantic
uv venv --python 3.13 --clear
source .venv/bin/activate
uv pip install -r requirements.txt

# run pre-commit checking which tool versions will be used.
uvx pre-commit install
uvx ibek --version
uvx techui-builder --version
STEP="pre-commit"
uvx pre-commit run --all-files --show-diff-on-failure
RESULTS+=("PASS  pre-commit")

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
        RESULTS+=("SKIP  pattern check ${instance_name}")
        continue
    fi

    echo "Checking vendored runtime-support for ${instance_name}"
    STEP="pattern check ${instance_name}"
    ibek pattern check "services/${instance_name}"
    RESULTS+=("PASS  pattern check ${instance_name}")
done
shopt -u nullglob

# Verify the IOC instance definitions
################################################################################
STEP="choose and prepare the services to check"
# if a docker provider is specified, use it
if [[ $DOCKER_PROVIDER ]]; then
    docker=$DOCKER_PROVIDER
# Otherwise use docker if available else use podman
else
    if ! docker version &>/dev/null; then docker=podman; else docker=docker; fi
fi

# On CI runners the working tree is on local disk so :z SELinux relabelling
# works fine. On developer workstations the tree may sit on NFS which does not
# support xattr; disable SELinux labelling instead.
if [[ -n "${CI:-}" ]]; then
    vol_z=":z"
    selinux_opt=""
elif [[ $(basename "${docker}") != "kodman" ]]; then
    vol_z=""
    selinux_opt="--security-opt label=disable"
else
    vol_z=""
    selinux_opt=""
fi

# Choose the services to check
################################################################################
# A manually-run pipeline always checks every service, so it can be used to
# sweep the whole repo on demand. A push to the default branch checks only
# what that push changed, so a green run means that push is good, not that
# every service still is. A branch or merge request checks what has changed
# since the default branch or the MR/PR target. Anything else -- outside CI,
# or a base commit that cannot be fetched (a new branch, a force push) --
# checks every service, since there is nothing to safely diff against.
target=${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-${GITHUB_BASE_REF:-${CI_DEFAULT_BRANCH:-}}}
branch=${CI_COMMIT_BRANCH:-${GITHUB_REF_NAME:-}}
default=${CI_DEFAULT_BRANCH:-}
case ${CI_PIPELINE_SOURCE:-}${GITHUB_EVENT_NAME:-}/$branch/$default/$target in
    web*|*workflow_dispatch*)  REF= ;;                       # manual full run: no base to diff from
    */"$default"/"$default"/*) REF=$CI_COMMIT_BEFORE_SHA ;;  # default branch push: diff from just before this push
    */*/*/?*)                  REF=$target ;;                # branch or MR: diff from its target
    *)                         REF= ;;                       # fallback: nothing to compare against
esac

if [[ -n "${REF}" ]] &&
    git fetch --quiet origin "${REF}" &&
    DIFF_BASE=$(git merge-base HEAD FETCH_HEAD); then
    CHANGED=$(git diff --name-only "${DIFF_BASE}" HEAD)
    # .helm-shared/ (the ioc-instance/ioc-group charts and values.schema.json
    # every service's chart depends on) and services/values.yaml (the values
    # every service's helm template/lint is rendered with) are not any one
    # service's own files. A change to either can affect every service, so
    # treat it the same as a manual full run.
    if echo "${CHANGED}" | grep -qE '^(\.helm-shared/|services/values\.yaml$)'; then
        echo "Shared file changed since ${REF} (${DIFF_BASE}): checking all services"
        SCOPE="all services (shared file changed since ${REF} (${DIFF_BASE:0:8}))"
        SERVICES=$(ls "${ROOT}/services")
    else
        echo "Checking services changed since ${REF} (${DIFF_BASE})"
        SCOPE="services changed since ${REF} (${DIFF_BASE:0:8})"
        SERVICES=$(echo "${CHANGED}" | grep '^services/' | cut -d/ -f2 | sort -u)
    fi
else
    echo "Checking all services"
    SCOPE="all services"
    SERVICES=$(ls "${ROOT}/services")
fi

# Need to make sure values.yaml is included in the ci
cp -L "${ROOT}/services/values.yaml" "${ROOT}/.ci_work/"

# copy the services to check to a temporary location to avoid dirtying the repo
for svc in $SERVICES; do
  # skip values.yaml and deleted services
  [[ -d "${ROOT}/services/$svc" ]] || continue
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
        RESULTS+=("SKIP  ${service_name}")
        continue
    fi

    echo "Validating helm chart for ${service_name}"
    STEP="helm chart ${service_name}"
    $docker run --rm --entrypoint bash \
        $selinux_opt \
        -v "${ROOT}/.ci_work:/services${vol_z}" \
        -v "${ROOT}/.helm-shared:/.helm-shared${vol_z}" \
        alpine/helm:3.14.3 \
        -c "
           helm dependency update /services/$service_name &&
           helm template /services/$service_name --values /services/values.yaml \\
             --values /services/$service_name/values.yaml &&
           helm lint /services/$service_name --values /services/values.yaml \\
             --values /services/$service_name/values.yaml &&
           rm -rf /services/$service_name/charts
        "
    RESULTS+=("PASS  helm chart ${service_name}")

    ### Validate each ioc config ###
    # Skip if subfolder has no config to validate
    if [ ! -f "${service}/config/ioc.yaml" ]; then
        continue
    fi

    # pick_ioc_image.py prints the IOC container image from values.yaml (an
    # ioc-instance.image at any depth, else the only image in the file), or
    # exits with an explanatory error if several images are found and none
    # can be picked out that way.
    STEP="pick IOC image ${service_name}"
    image=$("${ROOT}/pick_ioc_image.py" "${service}/values.yaml")

    if [ -n "${image}" ]; then
        echo "Validating ${service} with ${image}"
        STEP="IOC config ${service_name} (${image})"

        runtime=/tmp/ioc-runtime/$(basename ${service})
        mkdir -p ${runtime}

        # Prefer start.sh --test (generates all runtime assets - st.cmd, db,
        # pvi - exactly as in production, but skips hardware connections and
        # the IOC binary launch).
        # For released images without this test feature, fall back to a plain
        # 'ibek runtime generate2' which only renders the config and
        # never touches start.sh or the IOC binary.
        # Either way, the validation runs under 'timeout' inside the container,
        # so a start.sh that blocks (e.g. 'ibek ioc do-wait' with an unreachable
        # IP) fails fast instead of hanging the job. The timeout does not
        # include the image pull, and when it fires the container's main
        # process exits, so the container stops with it.
        # The probe looks for any mention of --test in start.sh, however
        # start.sh parses its arguments.
        $docker run --rm --entrypoint bash \
            $selinux_opt \
            -v "${service}/config:/epics/ioc/config${vol_z}" \
            "${image}" \
            -c "
            if grep -q -- '--test' /epics/ioc/start.sh; then
                timeout --kill-after=10s 60s /epics/ioc/start.sh --test
            else
                echo 'start.sh has no --test support; falling back to ibek runtime generate2'
                # avoid issues with auto-gen genicam pvi files on the fallback
                # path (ioc-adaravis only) -- start.sh --test handles this itself
                sed -i s/AutoADGenICam/ADGenICam/ /epics/ioc/config/ioc.yaml
                timeout --kill-after=10s 60s ibek runtime generate2 /epics/ioc/config
            fi &&
            cat /epics/runtime/st.cmd
            "
        RESULTS+=("PASS  IOC config ${service_name}")
    else
        RESULTS+=("SKIP  IOC config ${service_name} (no IOC image in values.yaml)")
    fi
done

rm -r ${ROOT}/.ci_work
