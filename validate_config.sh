#!/bin/bash

#
# Simple validation of field names & references in Solr setup files
#
# Caveat: This does not handle comments in XML properly
#

function usage() {
    echo "Usage: ./validate_config.sh <solrconfig> <schema>"
    exit
}

CONFIG="$1"
if [ -z $2 ]; then
    SCHEMA=`dirname "$CONFIG"`/schema.xml
else
    SCHEMA="$2"
fi
if [ ! -s "$CONFIG" ]; then
    echo "Error: No solr config '$CONFIG'"
    usage
fi
if [ ! -s "$SCHEMA" ]; then
    echo "Error: No solr schema '$SCHEMA'"
    usage
fi

# Should ideally remove comments, but for not it just makes the file single-line
function pipe_xml() {
    cat "$1" | tr '\n' ' ' 
}

# Extracts all field names from schema
function get_field_names() {
    pipe_xml "$SCHEMA" | grep -o "<\(dynamic\)\?[fF]ield[^>]\+name=\"[^_][^\"]*\"[^>]\+>" | sed 's/.*name=\"\([^\"]\+\).*/\1/'
}

# Extracts all fieldtypes from schema
function get_field_types() {
    pipe_xml "$SCHEMA" | grep -o "<fieldType[^>]\+name=\"[^_][^\"]*\"[^>]\+>" | sed 's/.*name=\"\([^\"]\+\).*/\1/'
}

# Checks that schema fields references existing fieldTypes
function check_schema_fields() {
    local SFIELDS=`cat "$SCHEMA" | tr '\n' ' ' | grep -o "<\(dynamic\)\?[fF]ield [^>]*>"`
    while read -r SFIELD; do
        local DESIGNATION=`echo "$SFIELD" | sed 's/<\([^ ]\+\).*/\1/'`
        local NAME=`echo "$SFIELD" | sed 's/.*name=\"\([^"]\+\)\".*/\1/'`
        local TYPE=`echo "$SFIELD" | sed 's/.*type=\"\([^"]\+\)\".*/\1/'`
        if [ "." == ".`echo \"$TYPES\" | grep $TYPE`" ]; then
            echo "   Solr schema entry $DESIGNATION with name '$NAME' referenced fieldType '$TYPE', which is not defined in schema"
            VALERROR=true
        fi
    done <<< "$SFIELDS"
}

# Checks that copyFields in schema references existing fields
function check_schema_copy_fields() {
    local SFIELDS=`pipe_xml "$SCHEMA" | grep -o "<copyField [^>]*>"`
    while read -r SFIELD; do
        local SOURCE=`echo "$SFIELD" | sed 's/.*source=\"\([^"]\+\)\".*/\1/'`
        local DEST=`echo "$SFIELD" | sed 's/.*dest=\"\([^"]\+\)\".*/\1/'`
        if [ "." == ".`echo \"$FIELDS\" | grep $SOURCE`" ]; then
            echo "   Solr schema copyField from '$SOURCE' to '$DEST' is invalid as the source is not defined in schema"
            VALERROR=true
        fi
        if [ "." == ".`echo \"$FIELDS\" | grep $DEST`" ]; then
            echo "   Solr schema copyField from '$SOURCE' to '$DEST' is invalid as the destination is not defined in schema"
            VALERROR=true
        fi
    done <<< "$SFIELDS"
}

# Checks that all fields used by the parameter exists in $FIELDS
# Input:  parameter-key regexp
# Sample: [^\"]*[.]\?qf
function check_config_fields() {
    local KEY="$1"
    VALERROR=false

    local PARAMS=`pipe_xml "$CONFIG" | grep -o "<[^>]\+name=\"${KEY}\"[^>]*>[^<]*</[^>]\+>" | sed -e 's/[ ,]\+/ /g' -e 's/\^[0-9.]\+//g'`
    while read -r PARAM; do
        local KEY=`echo "$PARAM" | sed 's/<[^>]*name=\"\([^\"]\+\)\".*/\1/'`
        local CFIELDS=`echo "$PARAM" | sed 's/[^>]*>\([^<]\+\).*/\1/'`
        for CFIELD in $CFIELDS; do
            if [ "." == ".`echo \"$FIELDS\" | grep $CFIELD`" ]; then
                echo "   Solr config param '$KEY' referenced field '$CFIELD', which is not defined in schema"
                VALERROR=true
            fi
        done
    done <<< "$PARAMS"
}

# echo "Processing config $CONFIG and schema $SCHEMA"

FIELDS=`get_field_names`
TYPES=`get_field_types`
# solr schema validation
echo "Checking schema fields and dynamicFields"
check_schema_fields
echo "Checking schema copyFields"
check_schema_copy_fields
exit

# solr config validation
echo "Checking .*qf"
check_config_fields "[^\"]*[.]\?qf"
echo "Checking facet.field"
check_config_fields "facet[.]field"
echo "Checking facet.range"
check_config_fields "facet[.]range"
echo "Checking .*.fl"
check_config_fields "[^\"]*[.]fl"
echo "Checking facet.pivot"
check_config_fields "facet[.]pivot"
echo "Checking .*hl.alternateField"
check_config_fields "[^\"]*hl[.]alternateField"

if [ "false" == "$VALERROR" ]; then
    echo "Done with no errors detected"
fi