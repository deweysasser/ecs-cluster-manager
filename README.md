# ecs-cluster-manager

Manage a Cluster of ECS machines/services

The is a docker image that will monitor an ECS cluster and ensure that
the services specified will be scaled to exactly match the number of
hosts.

It is assumed that the services have a 'distinctInstance' placement
constraint.

See also the [EFS/ECS
cluster](https://github.com/deweysasser/ecs-template) system.

While the "run.py" command could be used stand-alone or with `docker
run`, it is really designed to itself be a service in an ECS cluster
and manage the services for the cluster in which it is running.


## Make Library

This project includes http://github.com/deweysasser/makelib.

See [ToolUse.md] for more information.