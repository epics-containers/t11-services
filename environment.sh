#!/bin/bash

# a bash script to source in order to set up your command line to in order
# to work with the t11 IOCs and Services.

# check we are sourced
if [ "$0" = "$BASH_SOURCE" ]; then
    echo "ERROR: Please source this script"
    exit 1
fi

echo "Loading environment for t11 IOC Instances and Services ..."

#### SECTION 1. Environment variables ##########################################

export EC_CLI_BACKEND="K8S"
# the namespace to use for kubernetes deployments
export EC_TARGET=t11-beamline
# the git repo for this project
export EC_SERVICES_REPO=https://github.com/epics-containers/t11-services
# declare your centralised log server Web UI
export EC_LOG_URL="https://graylog2.diamond.ac.uk/search?rangetype=relative&fields=message%2Csource&width=1489&highlightMessage=&relative=172800&q=pod_name%3A{service_name}*"

#### SECTION 2. Install ec #####################################################

# check if epics-containers-cli (ec command) is installed
if ! ec --version &> /dev/null; then
    echo "ERROR: Please set up a virtual environment and: 'pip install edge-containers-cli'"
    return 1
fi

# enable shell completion for ec commands
source <(ec --show-completion ${SHELL})

# environment modules exist only inside DLS: elsewhere the module commands
# in section 3 do nothing, and kubectl uses its current context
unset _ec_no_module
if ! command -v module > /dev/null 2>&1; then
    function module { :; }
    _ec_no_module=true
fi


#### SECTION 3. Configure Kubernetes Cluster ###################################


# the following configures kubernetes inside DLS.

module unload argus > /dev/null
module load argus > /dev/null
# set the default namespace for kubectl and helm (for convenience only)
kubectl config set-context --current --namespace=t11-beamline
# make sure the user has provided credentials
kubectl version


# enable shell completion for k8s tools
if [ -n "$ZSH_VERSION" ]; then SHELL=zsh; fi
# drop the no-op module command that section 2 defines outside DLS
if [ -n "${_ec_no_module:-}" ]; then unset -f module; unset _ec_no_module; fi
source <(helm completion $(basename ${SHELL}))
source <(kubectl completion $(basename ${SHELL}))
