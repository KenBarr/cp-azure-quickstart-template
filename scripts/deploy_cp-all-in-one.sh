#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
location="eastus"
seedFileULI="result.json"
username="admin"
workspace_id=""


while getopts "l:u:w:" opt; do
  case "$opt" in
  l)  location=$OPTARG
    ;;
  s)  seedFileULI=$OPTARG
    ;;
  u)  username=$OPTARG
    ;;
  w)  workspace_id=$OPTARG
    ;;
  esac
done

shift $((OPTIND-1))
[ "$1" = "--" ] && shift

echo "`date` location=$location , seedFileULI=$seedFileULI, $username=$username , workspace_id=$workspace_id  , Leftovers: $@"

home_dir=$PWD
echo "Starting in directy ${home_dir}"

#Install the git jq for json parsing
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum -y install git jq

echo "`date` INFO: Validating Docker is up and running"
# Determine first if cp-all-in-one is a valid docker registry uri
## First make sure Docker is actually up
docker_running=""
loop_guard=10
loop_count=0
while [ ${loop_count} != ${loop_guard} ]; do
  docker_running=`service docker status | grep -o running`
  if [ ${docker_running} != "running" ]; then
    ((loop_count++))
    echo "`date` WARN: Tried to launch cp-all-in-one but Docker in state ${docker_running}"
    sleep 5
  else
    echo "`date` INFO: Docker in state ${docker_running}"
    break
  fi
done

LOG_OPT=""
logging_config=""
if [[ ${workspace_id} != "" ]]; then
  echo "`date` INFO: Setting up workspace logging if needed"
  SYSLOG_CONF="/etc/opt/microsoft/omsagent/${workspace_id}/conf/omsagent.d/syslog.conf"
  SYSLOG_PORT=""
  if [ -f ${SYSLOG_CONF} ]; then
    echo "`date` INFO: Configuration file for syslog found"
    SYSLOG_PORT=$(sed -n 's/.*port \(.*\).*/\1/p' $SYSLOG_CONF)
  fi
  if [[ ${SYSLOG_PORT} == "" ]]; then
    echo "`date` INFO: Default syslog port to 25224"
    SYSLOG_PORT="25224"
  fi
  echo "`date` INFO: Configuring logging on syslog port ${SYSLOG_PORT}"
  LOG_OPT="--log-driver syslog --log-opt syslog-format=rfc3164 --log-opt syslog-address=udp://127.0.0.1:$SYSLOG_PORT"
  logging_config="\
    --env logging_debug_output=all \
    --env logging_debug_format=graylog \
    --env logging_command_output=all \
    --env logging_command_format=graylog \
    --env logging_system_output=all \
    --env logging_system_format=graylog \
    --env logging_event_output=all \
    --env logging_event_format=graylog \
    --env logging_kernel_output=all \
    --env logging_kernel_format=graylog"
fi

echo "`date` INFO: Installing docker-compose"
usermod -a -G docker ${username}
curl -L https://github.com/docker/compose/releases/download/1.25.5/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "`date` INFO: Gettting Confluent all-in-one"
cd /tmp
git clone https://github.com/confluentinc/cp-all-in-one
cd cp-all-in-one
git checkout 5.5.1-post


echo "`date` INFO: Setting up all-in-one service"
tee /etc/systemd/system/cp-all-in-one.service <<-EOF
[Unit]
  Description=cp-all-in-one
  Requires=docker.service
  After=docker.service
[Service]
  Restart=always
  ExecStart=/usr/local/bin/docker-compose -f /tmp/cp-all-in-one/cp-all-in-one/docker-compose.yml up -d
  ExecStop=/usr/local/bin/docker-compose -f /tmp/cp-all-in-one/cp-all-in-one/docker-compose.yml down
[Install]
  WantedBy=default.target
EOF

echo "`date` INFO: Start the cp-all-in-one containers"
#systemctl daemon-reload
#systemctl enable cp-all-in-one
#systemctl start cp-all-in-one

cd /tmp/cp-all-in-one/cp-all-in-one/
docker-compose up -d

echo "`date` INFO: Fixing advertised listeners"

broker_running=""
loop_guard=10
loop_count=0
while [ ${loop_count} != ${loop_guard} ]; do
  broker_running=`docker ps -f name=broker | grep -o broker`
  if [ ${broker_running} != "broker" ]; then
    ((loop_count++))
    echo "`date` WARN: Tried to launch cp-all-in-one but Broker not yet up"
    sleep 30
  else
    echo "`date` INFO: Kafka Broker is running"
    docker exec broker "sed" "-i" "s/localhost/${HOSTNAME}.${location}.cloudapp.azure.com/" "/etc/kafka/kafka.properties"
    break
  fi
done

cd $home_dir

chmod +x ./populate_kafka.sh
IFS='/'
read -ra SEED_FILE_URL <<< "$seedFileULI"
SEED_FILE_INDEX=`echo ${#SEED_FILE_URL[@]}`
((SEED_FILE_INDEX--))
SEED_FILE=${SEED_FILE_URL[${SEED_FILE_INDEX}]}

./populate_kafka.sh -f ./${SEED_FILE}
echo "`date` INFO: cp-all-in-one bringup complete"
