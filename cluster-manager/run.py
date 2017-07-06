#!/usr/local/bin/python

import boto3
import os
import sys
import argparse
import time
import traceback

def ecs_client():
    return boto3.client("ecs")

# function from https://github.com/miketheman/ecs-host-service-scale/blob/master/lambda_function.py

def adjust_service_desired_count(ecs_client, cluster, service):
    running_service = ecs_client.describe_services(cluster=cluster, services=[service])

    if not running_service["services"]:
        print("SKIP: Service '{service}' not found in cluster '{cluster}'".format(cluster=cluster, service=service))
        return

    desired_task_count = running_service["services"][0]["desiredCount"]

    clusters = ecs_client.describe_clusters(clusters=[cluster])
    registered_instances = clusters["clusters"][0]["registeredContainerInstancesCount"]

    if desired_task_count != registered_instances:
        print("Adjusting cluster '{}' to run {} tasks of service '{}'".format(
            cluster, registered_instances, service
        ))
        response = ecs_client.update_service(
            cluster=cluster,
            service=service,
            desiredCount=registered_instances,
        )

        print(response)
        return response

    # Do nothing otherwise
    print("SKIP: Cluster {} has {} desired tasks for {} registered instances.".format(
        cluster, desired_task_count, registered_instances
    ))
    return

# WARNING:  untested in this context
def lambda_handler(event, context):
    if not event:
        raise ValueError("No event provided.")

    if event["source"] != "aws.ecs":
        raise ValueError("Function only supports input from events with a source type of: aws.ecs")

    service = os.getenv('ECS_SERVICE_ARN')
    if not service:
        raise ValueError("Need to set `ECS_SERVICE_ARN` env var to serviceArn.")

    # Determine if this event is one that we care about
    if event["detail-type"] != "ECS Container Instance State Change":
        print("SKIP: Function operates only on ECS Container Instance State Change events.")
        return

    # Valid event, and one we are interested in
    cluster = event["detail"]["clusterArn"]
    adjust_service_desired_count(ecs_client(), cluster, service)
    print("DONE")


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("--cluster", help="Cluster name or ARN", default=os.environ.get('CLUSTER', ''))
    parser.add_argument("--services", help="Service name or  ARN", default=os.environ.get('SERVICES', '').split(' '), nargs="+") 
    parser.add_argument("--once", help="Run only once", action='store_true', default=False)

    args = parser.parse_args()

    if not args.cluster:
        print "Either --cluster must be specified or CLUSTER environment variable must be set"
        sys.exit(1)

    if not args.services:
        print "Either --services must be specified or SERVICES environment variable must be set"
        sys.exit(1)

    print "In Cluster '%s', managing:" % args.cluster
    print "  " + "\n  ".join(args.services)
    

    while True:
        try:
            for service in args.services:
                adjust_service_desired_count(ecs_client(), args.cluster, service)
        except Exception as e:
            print "Exception adjusting service"
            print traceback.format_exc()
        if args.once:
            break
        time.sleep(60)
    
    
if __name__ == "__main__":
    main()
