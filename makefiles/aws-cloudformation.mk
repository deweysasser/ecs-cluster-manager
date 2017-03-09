######################################################################
# Create AWS stacks and tasks
######################################################################

# the project we're working in
PROJECT=$(notdir $(CURDIR))

# A prefix applied to all resources so different users/contexts do not
# step on each other
PREFIX?=$(PROJECT)-$(USER)-sandbox

# The AWS profile to use 
PROFILE?=sandbox

# AWS command
AWS=aws --profile $(PROFILE)

# Where to store runtime state
CFSTATE=$(STATE)/$(PROFILE)
$(STATE):: $(CFSTATE)

# Default targets
all:: $(foreach s,$(wildcard *.cf),$(CFSTATE)/$(PREFIX)-$(notdir $s))

SCRIPTS=makefiles/scripts

AWSCLI_VERSION_REQUIRED=1.11.51
include aws-version.mk



# How to turn a .params files into a command line set of
# cloudformation parameters


######################################################################
# How to build stacks
######################################################################

$(CFSTATE)/$(PREFIX)-%.cf: $(CFSTATE)

$(CFSTATE)/$(PREFIX)-%.cf: %.cf %.params $(CFSTATE) 
	bash $(SCRIPTS)/create-stack.sh --prefix "${PREFIX}" --profile $(PROFILE) --stack-name $(PREFIX)-$* --file $< --params $*.params
	@touch $@

%.params:
	touch $@

######################################################################
# How to destroy stacks
######################################################################

delete/%.cf: $(CFSTATE)  | destroy-services
	test -f $(CFSTATE)/$(PREFIX)-$(notdir $@) && ( $(AWS) cloudformation delete-stack --stack-name $(PREFIX)-$(basename $*) ; $(AWS) cloudformation wait stack-delete-complete --stack-name $(PREFIX)-$(basename $*) )|| true
	-rm $(CFSTATE)/$(PREFIX)-$(notdir $@)

# Destroy is a speical case -- it's a very dangerous operation, so only allow it if we explitictly confirm
ifeq ($(CONFIRM),yes)
destroy: $(foreach s,$(wildcard *.cf),delete/$s)
else
destroy: 
	@echo "WARNING:  'make destroy' is dangerous."
	@echo "It will delete all stack resources *INCLUDING* buckets and file systems with data"
	@printf "\nDestroy would delete the following stacks: $(foreach s,$(wildcard *.cf),\n   - $(PREFIX)-$(subst .cf,,$s))\n\n"
	@echo "You must run it with:"
	@echo "  make $(MAKEFLAGS) destroy CONFIRM=yes"
endif

######################################################################
# Templates for various types
######################################################################

templates: templates/stack.template
templates/stack.template:
	mkdir -p $(dir $@)
	$(AWS) cloudformation create-stack --generate-cli-skeleton > $@

######################################################################
# Generate the state capture directory and pre-populate it
######################################################################

$(CFSTATE)::  $(CFSTATE)/.cloudformation-inspect

$(CFSTATE)/.cloudformation-inspect:
	@mkdir -p $(dir $@)
	@echo "Locating existing stacks"
	@for stack in $$($(AWS) --output text cloudformation describe-stacks --query "Stacks[*].StackName" | tr -d '\r'); do echo  "  - " $$stack; touch $(dir $@)/$$stack.cf; done
	@touch $@


# Print general info
info::
	@echo PROJECT = $(PROJECT)
	@echo AWS CLI version = $(AWSCLI_VERSION)


test:
	echo $(call PARAMETERS,ecs-cluster.params)

aws-version.mk: AWSCLI_VERSION=$(shell aws --version 2>&1 | awk 'BEGIN{RS=" "; FS="/"};/aws/{print $$2}') 
aws-version.mk:
	@if [ $$(printf "%s\n%s" $(AWSCLI_VERSION_REQUIRED)  $(AWSCLI_VERSION) | sort -V | head -n 1) != $(AWSCLI_VERSION_REQUIRED) ] ; then \
	 echo  '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' ;\
	 echo Please upgrade aws cli to at least version $(AWSCLI_VERSION_REQUIRED); \
	echo Your version: $(AWSCLI_VERSION) ;\
	 echo  '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' ;\
	 exit 1; \
	fi
	echo AWSCLI_VERSION=$(AWSCLI_VERSION) > $@
