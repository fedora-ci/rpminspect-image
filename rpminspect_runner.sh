#!/bin/bash

# Usage:
# ./rpminspect_runner.sh $TASK_ID $RELEASE_ID $TEST_NAME
#
# The script recognizes following environment variables:
# CONFIG - path to the rpminspect config file
# UPDATES_TAG - koji tag where to look for previous builds
# DEFAULT_RELEASE_STRING - release string to use in case builds
#                          don't have them (e.g.: missing ".fc34")
# RPMINSPECT_WORKDIR - workdir where to cache downloaded builds
# RPMINSPECT_CLEANUP - remove downloaded rpms after testing

set -e

trap fix_rc EXIT SIGINT SIGSEGV
fix_rc() {
    retval=$?
    # rpminspect status codes:
    # RI_INSPECTION_SUCCESS = 0,   /* inspections passed */
    # RI_INSPECTION_FAILURE = 1,   /* inspections failed */
    # RI_PROGRAM_ERROR = 2         /* program errored in some way */
    #
    # These status codes need to be translated into tmt status codes,
    # so tmt can correctly recognize failures, errors, and successes.
    if [ ${retval} -gt 2 ]; then
        # something unexpected happened — treat it as an infra error
        exit 2
    fi
    exit $retval
}

config=${CONFIG:-/usr/share/rpminspect/fedora.yaml}

task_id=$1
release_id=$2
test_name=$3

# Koji tag where to look for previous builds;
# For example: "f34-updates"
updates_tag=${UPDATES_TAG:-${release_id}-updates}

# In case there is no dist tag (like ".fc34") in the package name,
# rpminspect doesn't know which test configuration to use
default_release_string=${DEFAULT_RELEASE_STRING:-${release_id}}


get_name_from_nvr() {
    # Extract package name (N) from NVR.
    # Params:
    # $1: NVR
    local nvr=$1
    # Pfff... close your eyes here...
    name=$(echo $nvr | sed 's/^\(.*\)-\([^-]\{1,\}\)-\([^-]\{1,\}\)$/\1/')
    echo -n ${name}
}

get_after_build() {
    # Convert task id to NVR.
    # Params:
    # $1: task id
    local task_id=$1
    after_build=$(koji taskinfo $task_id | grep Build | awk -F' ' '{ print $2 }')
    echo -n ${after_build}
}

get_before_build() {
    # Find previous build for given NVR.
    # The assumption is that the given NVR is not tagged in the "updates_tag".
    # If the NVR is tagger in the "updates_tag", then it has to be the latest NVR
    # for that packages in that tag.
    # Params:
    # $1: NVR
    # $2: Koji tag where to look for older builds
    local after_build=$1
    local updates_tag=$2
    local package_name=$(get_name_from_nvr $after_build)
    before_build=$(koji list-tagged --latest --inherit --quiet ${updates_tag} ${package_name} | awk -F' ' '{ print $1 }')
    if [ "${before_build}" == "${after_build}" ]; then
        latest_two=$(koji list-tagged --latest-n 2 --inherit --quiet ${updates_tag} ${package_name} | awk -F' ' '{ print $1 }')
        for nvr in $latest_two; do
            if [ "${nvr}" != "${after_build}" ]; then
                before_build=${nvr}
                break
            fi
        done
    fi
    echo -n ${before_build}
}


after_build=$(get_after_build $task_id)
before_build=$(get_before_build $after_build $updates_tag)

workdir="${RPMINSPECT_WORKDIR:-/var/tmp/rpminspect/}${task_id}-${before_build}"
downloaded_file=${workdir}/downloaded

mkdir -p ${workdir}

# Download and cache packages, if not downloaded already
if [ ! -f ${downloaded_file} ]; then
    rpminspect -c ${config} -v -w ${workdir} -f ${after_build} | grep -v '^Downloading '
    if [ ${before_build} != ${after_build} ]; then
        rpminspect -c ${config} -v -w ${workdir} -f ${before_build} | grep -v '^Downloading '
    fi
    touch ${downloaded_file}
fi


echo "Comparing ${after_build} with older ${before_build} found in the \"${updates_tag}\" Koji tag."
echo
echo "Test description:"

test_description=$(rpminspect -l -v | awk -v RS= -v ORS='\n\n' "/${test_name}\n/")

echo "${test_description}"
echo
echo "======================================== Test Output ========================================"

rpminspect -V
rpminspect -c ${config} --arches x86_64,noarch,src --release=${default_release_string} --tests=${test_name} ${before_build} ${after_build}

# Cleanup downloaded rpms
[ -n "$RPMINSPECT_CLEANUP" ] && find ${workdir} -name *.rpm -delete
