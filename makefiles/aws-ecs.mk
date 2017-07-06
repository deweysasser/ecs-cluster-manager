# Export all make variables as environment variables

TASK_PREFIX?=$(PREFIX)-

ECS=aws --profile $(PROFILE) ecs
ECSTEXT=aws --profile $(PROFILE) --output text ecs

# Directory to track deployed state
SERVICESTATE=$(STATE)/$(PROFILE)/$(CLUSTER)
TASKSTATE=$(STATE)/$(PROFILE)

# Calculate the targets we need to update -- i.e. calculate the names of
# all *targets* by examining the sources
TASKDEFS=$(wildcard *.taskdef)
SERVICES=$(wildcard *.service) $(foreach x, $(wildcard *.service.template),$(basename $x))
AUTOCREATE_TASKDEFS=$(shell grep -l AUTOCREATE.SERVICE $(TASKDEFS))


ECS_TARGETS=$(foreach s,$(SERVICES),$(SERVICESTATE)/$t) $(foreach t,$(TASKDEFS),$(TASKSTATE)/$(TASK_PREFIX)$t) $(foreach s,$(AUTOCREATE_TASKDEFS),$(SERVICESTATE)/$(subst .taskdef,.autoservice,$s))

all:: $(ECS_TARGETS)

# How to deploy a task
$(TASKSTATE)/$(TASK_PREFIX)%.taskdef: %.taskdef 
	$(ECS) register-task-definition --family "$(TASK_PREFIX)$*" --cli-input-json file://$< --query "taskDefinition.[family,revision]"
	@touch $@

# Deploy an autocreated service
$(SERVICESTATE)/%.autoservice: NAME=$(notdir $(basename $@))
$(SERVICESTATE)/%.autoservice: $(TASKSTATE)/$(TASK_PREFIX)%.taskdef
	if [ -f $(SERVICESTATE)/$(NAME).autoservice ] ; then \
	  echo "Updating autoservice $(NAME)" ;\
	   $(ECS) update-service --service $(NAME) --task-definition $(TASK_PREFIX)$(NAME) --desired-count 1 --cluster $(CLUSTER)  --query "service.deployments[0].{desired:desiredCount,running:runningCount}" ;\
	else \
	  echo "Creating autoservice $(NAME)" ;\
	   $(ECS) create-service --service-name $(NAME) --cluster $(CLUSTER) --task-definition $(TASK_PREFIX)$(NAME) --desired-count 1 ; \
	fi
	touch $@ $(SERVICESTATE)/$(NAME).service 

define drain-service
	   $(ECS) update-service --service $(NAME) --desired-count 0 --cluster $(CLUSTER)  --query "service.deployments[0].{desired:desiredCount,running:runningCount}"; \
	   while [ $$($(ECS) describe-services --cluster $(CLUSTER) --services $(NAME) --query "services[0].deployments[0].runningCount" | tr -d "\r") -ne 0 ] ; do echo "Waiting for service to stop"; $(ECS) describe-services --cluster $(CLUSTER) --services $(NAME) --query "services[0].deployments[0].{desired:desiredCount,running:runningCount}"; sleep 5s; done;
endef

# How to deploy a service
$(SERVICESTATE)/%.service: NAME=$(notdir $(basename $@))
$(SERVICESTATE)/%.service: %.service $(TASKSTATE)/$(TASK_PREFIX)%.taskdef
	@mkdir -p $(dir $@)
	@if [ -f $@ ] ; then \
	  echo "Updating service $(NAME)" ;\
	  $(ECS) update-service --service $(NAME) --cluster $(CLUSTER) --cli-input-json file://$< --query "service.[serviceArn,taskDefinition]" ;\
	  else \
	  echo "Creating service $(NAME)" ;\
	  $(ECS) create-service --cluster $(CLUSTER) --service-name "$(NAME)" --cli-input-json file://$< --query "service.[serviceArn,taskDefinition]" ;\
	fi
	@touch $@


templates: service.template taskdef.template

service.template:
	$(ECS) create-service --generate-cli-skeleton > $@

taskdef.template:
	$(ECS) register-task-definition --generate-cli-skeleton > $@

cleanup:: $(foreach v,$(shell echo *.taskdef),cleanup/$v)

cleanup/%.taskdef:
	@echo "Cleaning $*.taskdef"
	@$(ECSTEXT) list-task-definitions --family-prefix $(notdir $*) | awk '{print $$2}' | head -n -3 | xargs -r -n 1 $(ECSTEXT) deregister-task-definition --query "['remove',taskDefinition.[family,':',revision]]" --task-definition; 

drain/%.service:
	echo "Draining $(notdir $@)"
	@test -f $(SERVICESTATE)/$(notdir $@) && $(ECS) update-service --service $(notdir $*) --desired-count 0 --cluster $(CLUSTER) --query "service.[desiredCount]" || true

remove/%.service: drain/%.service
	echo "Removing $(notdir $@)"
	@test -f $(SERVICESTATE)/$(notdir $@) && $(ECS) delete-service --service $(notdir $*) --cluster $(CLUSTER) --query "service.serviceArn" && sleep 20s || true
	@rm -f $(SERVICESTATE)/$(notdir $@) $(SERVICESTATE)/$(notdir $*).autoservice

destroy-services: $(foreach x,$(SERVICES),remove/$x) $(foreach x,$(wildcard *.service.template),remove/$(basename $x)) $(foreach x,$(AUTOCREATE_TASKDEFS),remove/$(basename $x).service)
	@rm $(SERVICESTATE)/.services-recorded

ifeq ($(CONFIRM),yes)
destroy: destroy-services
endif


# Load the initial state

#ifneq ($(wildcard $(SERVICESTATE)), $(SERVICESTATE))
$(STATE):: $(SERVICESTATE)/.services-recorded $(TASKSTATE)/.taskdefs-recorded
#endif

$(SERVICESTATE)/.services-recorded:
	@mkdir -p $(dir $@)
	@echo "Inspecting defined services"
	@for arn in $$( $(ECSTEXT) list-services --cluster ${CLUSTER} | tr -d '\r' | cut -f 2); do \
	   name=$$(echo $$arn | cut -d / -f 2 | cut -d : -f 1 ) ;\
	    echo "  - " $$name ;\
	    touch $(dir $@)/$$name.service ;\
	done
	@touch $@

$(TASKSTATE)/.taskdefs-recorded:
	@mkdir -p $(dir $@)
	@echo "Inspecting defined tasks"
	@for name in $$( $(ECSTEXT) list-task-definitions | tr -d '\r' | cut -d / -f 2 | cut -d : -f 1 | sort -u); do \
	    echo "  - " $$name ;\
	    touch $(dir $2)/$$name.taskdef ;\
	done
	@touch $@



info::
	@echo TASKDEFS=$(TASKDEFS)
	@echo AUTOSERVICES=$(AUTOCREATE_TASKDEFS)
	@echo SERVICES=$(SERVICES)
	@echo TARGETS=$(ECS_TARGETS)


