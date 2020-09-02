#!/bin/bash

OPTIND=1

input_file='discovery.json'
output_file='result.json'
filter_string=".*"

while getopts “f:i:o:” opt; do
  case $opt in
    f) filter_string=$OPTARG
       ;;
    i) input_file=$OPTARG
       ;;
    o) output_file=$OPTARG
       ;;
  esac
done

shift $((OPTIND-1))
[ "$1" = "--" ] && shift

echo "`date` filter_string=$filter_string , input_file=$input_file , output_file=$output_file , Leftovers: $@"

# Function to add a section to the output file
function add_section() {
    local outputFile="$1"
    local sectionName="$2"
    shift
    shift
    local sectionArray=("$@")
    echo "`date` Adding ${sectionName} into:$outputFile"
    echo "\"${sectionName}\": [" >> $outputFile
    if [[ ! -z "$sectionArray" ]]; then
        for item in ${sectionArray[@]}
        do  
            echo "${item}," >> ${outputFile}
        done
        sed -i '$ s/.$//' ${outputFile}
    fi
    echo "]," >> ${outputFile}
}


echo "`date` Create filtered lists from :$input_file"
topic_array=(`jq < ${input_file} .data.events.topics | jq -c ".[] | select (. | test(\"${filter_string}\"))"`)
totalConnectors=`jq < ${input_file} .data.events.connectors`
associatedConnectors=(`jq < ${input_file} .data.events.connectorToTopicAssociations | jq -c ".[] | select (.topic | test(\"${filter_string}\"))"`)
patterMatchedConnectors=(`echo ${totalConnectors} | jq -c ".[] | select (.name | test(\"${filter_string}\"))"`)
totalConsumerGroups=`jq < ${input_file} .data.events.consumerGroups`
associatedConsumerGroups=(`jq < ${input_file} .data.events.consumerGroupToTopicAssociations | jq -c ".[] | select (.topic | test(\"${filter_string}\"))"`)
patterMatchedConsumerGroups=(`echo ${totalConsumerGroups} | jq -c ".[] | select (.groupId | test(\"${filter_string}\"))"`)
totalSchemas=`jq < ${input_file} .data.events.schemas`
associatedSchemas=(`jq < ${input_file} .data.events.topicToSchemaAssociations | jq -c ".[] | select (.topic | test(\"${filter_string}\"))"`)
patterMatchedSchemas=(`echo ${totalSchems} | jq -c ".[] | select (.name | test(\"${filter_string}\"))"`)

echo "`date` Transposing the pre-ample from input file:$input_file to output file:$output_file"
rm $output_file
touch $output_file
while IFS= read -r line
do
 if [[ $line =~ '"topics": [' ]]; then
    break
else
    echo "$line" >> $output_file
fi
done < "$input_file"


echo "`date` Put filtered Topics into:$output_file"
add_section ${output_file} "topics" ${topic_array[@]}

echo "`date` Put filtered Connectors into:$output_file"
if (( ${#associatedConnectors[@]} > 0 )); then
    # Populate the known connectorNamesList with patterMatchedConnectors
    connectorNamesList=""
    for connector in ${patterMatchedConnectors[@]}
    do  
        connectorNamesList="$connectorNamesList `echo ${connector} | jq .name`"
    done
    for connector in ${associatedConnectors[@]}
    do
        connectorName=`echo $connector | jq .connector`
        # Prevent adding duplicate connectors
        if echo $connectorNamesList | grep -w $connectorName > /dev/null; then
            continue
        else
            connectorNamesList="${connectorNamesList} ${connectorName}"
        fi
        newConnector=`echo $totalConnectors | jq ".[] | select(.name == ${connectorName}) | ." | tr -d ' ' | tr -d '\r' | tr -d '\n'`
        patterMatchedConnectors+=(${newConnector})
    done
fi
add_section ${output_file} "connectors" ${patterMatchedConnector[@]}

echo "`date` Put filtered ConsumerGroups into:$output_file"
if (( ${#associatedConsumerGroups[@]} > 0 )); then
    # Populate the known consumerGroupNamesList with patterMatchedConsumerGroup
    consumerGroupNameList=""
    for consumerGroup in ${patterMatchedConsumerGroups[@]}
    do  
        consumerGroupNameList="$consumerGroupNameList `echo ${consumerGroup} | jq .groupId`"
    done
    for consumerGroup in ${associatedConsumerGroups[@]}
    do
        consumerGroupName=`echo $consumerGroup | jq .consumerGroup`
        # Prevent adding duplicate connectors
        if echo $consumerGroupNameList | grep -w $consumerGroupName > /dev/null; then
            continue
        else
            consumerGroupNameList="${consumerGroupNameList} ${consumerGroupName}"
        fi
        newConsumerGroup=`echo $totalConsumerGroups | jq ".[] | select(.groupId == ${consumerGroupName}) | ." | tr -d ' ' | tr -d '\r' | tr -d '\n'`
        patterMatchedConsumerGroups+=(${newConsumerGroup})
    done
fi
add_section ${output_file} "consumerGroups" ${patterMatchedConsumerGroups[@]}

echo "`date` Put filtered Schemas into:$output_file"
if (( ${#associatedSchemas[@]} > 0 )); then
    # Populate the known schemaIdList with patterMatchedSchemas
    schemaIdList=""
    for schema in ${patterMatchedSchemas[@]}
    do  
        schemaIdList="$schemaIdList `echo ${schema} | jq .schemaId`"
    done
    for schema in ${associatedSchemas[@]}
    do
        schemaName=`echo $schema | jq .schemaId`
        # Prevent adding duplicate connectors
        if echo $schemaIdList | grep -w $schemaName > /dev/null; then
            continue
        else
            schemaIdList="${schemaIdList} ${schemaName}"
        fi
        newSchema=`echo $totalSchemas | jq ".[] | select(.schemaId == ${schemaName}) | ." | tr -d ' ' | tr -d '\r' | tr -d '\n'`
        patterMatchedSchemas+=(${newSchema})
        keySchemaName=`echo $schema | jq .keySchemaId`
        if [[ ${keySchemaName} != "null" ]]; then
            # Prevent adding duplicate connectors
            if echo $schemaIdList | grep -w $keySchemaName > /dev/null; then
                continue
            else
                schemaIdList="${schemaIdList} ${keySchemaName}"
            fi        
            keySchema=`echo $totalSchemas | jq ".[] | select(.schemaId == ${keySchemaName}) | ." | tr -d ' ' | tr -d '\r' | tr -d '\n'`
            patterMatchedSchemas+=(${keySchema})
        fi
    done
fi
add_section ${output_file} "schemas" ${patterMatchedSchemas[@]}

echo "`date` Put filtered Connectors to Topics associations into:$output_file"
add_section ${output_file} "connectorToTopicAssociations" ${associatedConnectors[@]}

echo "`date` Put filtered ConsumerGroups to Topics associations into:$output_file"
add_section ${output_file} "consumerGroupToTopicAssociations" ${associatedConsumerGroups[@]}

echo "`date` Put filtered Schemas to Topics associations into:$output_file"
add_section ${output_file} "topicToSchemaAssociations" ${associatedSchemas[@]}
sed -i '$ s/.$//' ${output_file}

echo "`date` Transposing the post-amble into:$output_file"
tail -n 7 $input_file >> ${output_file}

mv ${output_file} /tmp/temp.json
jq < /tmp/temp.json > ${output_file}