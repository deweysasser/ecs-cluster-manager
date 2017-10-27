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

WARNING: When using CloudFormation, it's possible to wedge CF using
this service.  Specifically, if cloudformation is updating one of the
services that this service is also updating, CF will wedge itself with
"service will not stabilize".  

To get out of this situation, wait for CF to timeout (by default --
hours), then trigger a rollback.  When that fails, you can then
trigger another rollback but specify skipping the problematical
service.

I recommend giving your cloudformation stacks a shorter timeout to
make this problem less painful.

Alternatively, do *NOT* use cloudformation for services managed by
this manager.  Cloudformation has a rather static bias.

## Example cluster service

```
  ClusterManagerTask:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: ecs-cluster-manager
      TaskRoleArn: !Ref EcsManagementRole       
      ContainerDefinitions:
      - Name: manager
        Image: deweysasser/ecs-cluster-manager:latest
        MemoryReservation: 16
        Essential: true
        Environment:
          - Name: CLUSTER
            Value: !Ref EcsCluster
          - Name: SERVICES
            Value: !Join [ " ", [ !Ref ProxyService, !Ref LoginService ] ]
          - Name: AWS_DEFAULT_REGION
            Value: !Ref 'AWS::Region'

  ClusterManagerService:
    Type: AWS::ECS::Service
    Properties:
      Cluster: !Ref EcsCluster
      DesiredCount: 1
      TaskDefinition: !Ref ClusterManagerTask
```


## Make Library

This project includes http://github.com/deweysasser/makelib.

See [ToolUse.md] for more information.