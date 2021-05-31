ARCHIVED
========

This project is no longer maintained.  

This was a work-around for ECS's lack of a major feature (like, come on, folks, how could you miss this?  And leave it out for so long?)

In any case, ECS now has [daemon tasks](https://aws.amazon.com/about-aws/whats-new/2018/06/amazon-ecs-adds-daemon-scheduling/) and this hack is unnecessary.

---



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

WARNING
-------

When using CloudFormation, it's possible to wedge CF using
this service.  Specifically, if cloudformation is updating one of the
services that this service is also updating, CF will wedge itself with
"service will not stabilize".  

To work around this issue, stop the cluster manager service during
cloudformation updates. (If you have cluster-manager defined in
cloudformation it will restore it as part of the update).

Alternatively, for all managed services, you can removed the
`DesiredCount` parameter.  Note that doing this provides a bootstrap
problem as `DesiredCount` is required when creating a new service.

If you do manage to wedge cloudformation, simply turn off the
cluster-manager service until the update completes.  If you cannot do
that or for some reason it does not work, wait for CF to timeout (by
default -- hours) or cancel the update, then trigger a rollback.  If
this fails, you can then trigger another rollback but specify skipping
the problematical service.

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
