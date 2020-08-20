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
discovery_file="./result.json"

while getopts "f:" opt; do
  case "$opt" in
  f)  discovery_file=$OPTARG
    ;;
  esac
done

shift $((OPTIND-1))
[ "$1" = "--" ] && shift

echo "`date` discovery_file=$discovery_file ,  Leftovers: $@"


TOPICS=`jq < ${discovery_file} .data.events.topics[] | sed 's/"//g'`
for topic in $TOPICS
do
 docker exec -t broker /usr/bin/kafka-topics --bootstrap-server localhost:9092 --create --topic ${topic}
 docker exec -t broker /usr/bin/kafka-producer-perf-test --producer-props bootstrap.servers=localhost:9092 --topic ${topic} --num-records 100 --throughput -1 --record-size 100   
done


count=0
run=1
while [ $run -eq 1 ]
do
  consumerGroup=`jq < ${discovery_file} .data.events.consumerGroupToTopicAssociations[${count}].consumerGroup | sed 's/"//g'`
  topic=`jq < ${discovery_file} .data.events.consumerGroupToTopicAssociations[${count}].topic | sed 's/"//g'`
  echo "ConsumerGroup: ${count} = ${consumerGroup} Topic = ${topic}"
  if [ "$consumerGroup" == "null" ]; then
    break
  fi
   docker exec -t broker /usr/bin/kafka-consumer-perf-test --bootstrap-server localhost:9092 --topic ${topic} --group ${consumerGroup} --messages 100
  ((count++))
done