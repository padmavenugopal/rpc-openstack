#!/usr/bin/env bash
#
# Copyright 2014-2017, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

## Shell Opts ----------------------------------------------------------------
set -euv
set -o pipefail

## Vars ----------------------------------------------------------------------
# NOTE(cloudnull): See comment further down, but this should be removed later.
export MARKER="/tmp/deploy-rpc-commit.complete"

export SCRIPT_PATH="$(readlink -f $(dirname ${0}))"

## Functions -----------------------------------------------------------------
source "${SCRIPT_PATH}/functions.sh"

## Main ----------------------------------------------------------------------

# NOTE(cloudnull): Drop a marker after Deploying RPC-OpenStack and check for
#                  it's existance. This is here because our CIT gating system
#                  calls this script a mess of times with different
#                  environment variables instead of leveraging a stable
#                  interface and controlling the systems code paths within
#                  a set of well known and understanable test scripts.
#                  Because unwinding this within the CIT gate is impossible
#                  at this time and there's no stable interface to consume
#                  we check for and drop a marker file once the basic AIO
#                  has been created. If the marker is found we skip trying to
#                  build everything again.
# NOTE(cloudnull): Remove this when we have a sane test interface.
if [ "${DEPLOY_AIO}" != false ] && [[ -f "${MARKER}" ]]; then
  echo "RPC-O has already been deployed, remove \"${MARKER}\" to run again."
  exit 0
fi

# Generate the secrets required for the deployment.
if [[ ! -f "/etc/openstack_deploy/user_rpco_secrets.yml" ]]; then
  cp ${SCRIPT_PATH}/../etc/openstack_deploy/user_rpco_secrets.yml.example /etc/openstack_deploy/user_rpco_secrets.yml
fi

for file_name in user_secrets.yml user_rpco_secrets.yml; do
  if [[ -f "/etc/openstack_deploy/${file_name}" ]]; then
    python /opt/openstack-ansible/scripts/pw-token-gen.py --file "/etc/openstack_deploy/${file_name}"
  fi
done

# Begin the RPC installation by uploading images and creating flavors and
# deploying ELK.
pushd "${SCRIPT_PATH}/../playbooks"
  # Deploy and configure the ELK stack
  openstack-ansible site-logging.yml
  # Create default VM images and flavors
  openstack-ansible site-openstack.yml
popd

pushd /opt/rpc-maas/playbooks
  # Deploy and configure RAX MaaS
  if [ "${DEPLOY_MAAS}" != false ]; then
    if [ "${DEPLOY_TELEGRAF}" != false ]; then
      # Set the rpc_maas vars.
      if [[ ! -f "/etc/openstack_deploy/user_rpco_maas_variables.yml" ]]; then
        envsubst < \
          ${SCRIPT_PATH}/../etc/openstack_deploy/user_rpco_maas_variables.yml.example > \
          /etc/openstack_deploy/user_rpco_maas_variables.yml
      fi

      # If influx port and IP are set enable the variable
      sed -i 's|^# influx_telegraf_targets|influx_telegraf_targets|g' /etc/openstack_deploy/user_rpco_maas_variables.yml
    fi
    # Run the rpc-maas setup process
    openstack-ansible site.yml
  fi
popd

## Drop the RPC-OpenStack marker file.
touch ${MARKER}
