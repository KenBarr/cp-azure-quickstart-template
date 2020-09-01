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
schema_reg_ip="localhost"
schema_reg_port="8081"
kafka_ip="localhost"
kafka_port="9092"


while getopts "f:i:k:p:q:" opt; do
  case "$opt" in
  f)  discovery_file=$OPTARG
    ;;
  i)  schema_reg_ip=$OPTARG
    ;;
  k)  kafka_ip=$OPTARG
    ;;
  p)  schema_reg_port=$OPTARG
    ;;
  q)  kafka_port=$OPTARG
    ;;
  esac
done

shift $((OPTIND-1))
[ "$1" = "--" ] && shift

echo "`date` discovery_file=$discovery_file , schema_reg_ip=$schema_reg_ip,  schema_reg_port=$schema_reg_port, \
             kafka_ip=$kafka_ip, kafka_port=$kafka_port, Leftovers: $@"


TOPICS=`jq < ${discovery_file} .data.events.topics[] | sed 's/"//g'`
for topic in $TOPICS
do
 docker exec -t broker /usr/bin/kafka-topics --bootstrap-server ${kafka_ip}:${kafka_port} --create --topic ${topic}
 #docker exec -t broker /usr/bin/kafka-producer-perf-test --producer-props bootstrap.servers=localhost:9092 --topic ${topic} --num-records 100 --throughput -1 --record-size 100   
done

count=0
run=1
while [ $run -eq 1 ]
do
  schemaId=`jq < ${discovery_file} .data.events.topicToSchemaAssociations[${count}].schemaId`
  topic=`jq < ${discovery_file} .data.events.topicToSchemaAssociations[${count}].topic | sed 's/"//g'`
  echo "Schema to Topic binding ${count}:  schemaId = ${schemaId} Topic = ${topic}"
  if [ "$schemaId" == "null" ]; then
    break
  fi
  schema=`jq ".data.events.schemas[] | select(.schemaId==${schemaId})" < result.json`
  schema_content=`echo ${schema} | jq .content`
  schema_name=`echo ${schema} | jq .name`
  curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
   --data "{\"schema\": ${schema_content}}" \
   http://${schema_reg_ip}:${chema_reg_port}/subjects/${topic}-value/versions
   ((count++))
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
   docker exec -t broker /usr/bin/kafka-consumer-perf-test --bootstrap-server ${kafka_ip}:${kafka_port} --topic ${topic} --group ${consumerGroup} --messages 1 --timeout 10
  ((count++))
done