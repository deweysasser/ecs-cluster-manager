#!/bin/bash

# Purpose:  create or update a cloudformation stack

set -e
set -u

OUTPUT=json


while [ -n "$*" ] ; do
    case $1 in
	--prefix) PREFIX="$2"; shift;;
	--profile) PROFILE="$2"; shift;;
	--file) FILE="$2"; shift;;
	--params) PARAMS="$2"; shift;;
	--stack-name) NAME="$2"; shift;;
    esac
    shift
done

test -n "$PROFILE" -a -n "$FILE" -a -n "$NAME" -a -n "$PARAMS" -a -n "$PREFIX"

STANDARD_PARAMETERS="ParameterKey=Prefix,ParameterValue=${PREFIX} ParameterKey=CreatedBy,ParameterValue=${USER}"


# Test if the stack exists
stack_exists() {
    if aws --profile ${PROFILE} cloudformation describe-stacks --stack-name ${NAME} --query Stacks[0].StackStatus  > /dev/null 2>&1 ; then
	return 0
    else
	return 1
    fi
}

# Use change-set capability to determine if there are any updates
# needed to this stack.  This works around Amazon's idiotic insistence
# that updating a state to itself is an error

stack_has_changed() {
    NOW=$(date +%s)

    aws --profile ${PROFILE} cloudformation  create-change-set --capabilities CAPABILITY_IAM  --change-set-name change-${NOW} --stack-name ${NAME} --template-body file://${FILE}  --parameters ${STANDARD_PARAMETERS} $(get_params ${PARAMS})

    aws --profile ${PROFILE} cloudformation wait change-set-create-complete --stack-name ${NAME} --change-set-name change-${NOW}

    if [ "$(aws --profile ${PROFILE} --output text cloudformation describe-change-set --change-set-name change-${NOW} --stack-name ${NAME} --query Status | tr -d '\r')" == "FAILED" ] ; then
	aws --profile ${PROFILE} cloudformation delete-change-set --stack-name ${NAME} --change-set-name change-${NOW}
	return 1
    else
	aws --profile ${PROFILE} cloudformation delete-change-set --stack-name ${NAME} --change-set-name change-${NOW}
	return 0
    fi
}

# given a properties file, turn it into a list of parameters
get_params() {
    perl -n -e 'chop; chop if /\r$/; next if /^#/; print "ParameterKey=$1,ParameterValue=$3\n "if /(.*)(\s*=\s*)(.*)[\s\\r]*?/; ' "$@"
}

# Create the stack.  If the stack already exists, this will fail
create_stack() {
    aws --profile ${PROFILE} cloudformation  create-stack --capabilities CAPABILITY_IAM  --stack-name ${NAME} --template-body file://${FILE}  --parameters ${STANDARD_PARAMETERS} $(get_params ${PARAMS})
    aws --profile ${PROFILE} cloudformation wait stack-create-complete --stack-name ${NAME}
}

# Update the stack.  If the stack does not already exists it is an error.
update_stack() {
    aws --profile ${PROFILE} cloudformation  update-stack --capabilities CAPABILITY_IAM  --stack-name ${NAME} --template-body file://${FILE}  --parameters ${STANDARD_PARAMETERS} $(get_params ${PARAMS})
    aws --profile ${PROFILE} cloudformation wait stack-update-complete --stack-name ${NAME}
}


main() {
	if ! stack_exists; then
	    create_stack
	elif stack_has_changed; then
	    update_stack
	else
		echo "Stack is up to date"
	fi
}

main