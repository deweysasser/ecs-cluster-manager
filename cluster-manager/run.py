#!/usr/bin/env python

import boto3
import os
import sys
import argparse
import time
import traceback
import re

def depaginate(client, op, responseList, **kwargs):
    for page in client.get_paginator(op).paginate(PaginationConfig={'PageSize': 50}, **kwargs):
        for i in page[responseList]:
            yield i


def ecs_client(args):
    session = boto3.Session(profile_name=args.profile, region_name=args.region)
    return session.client("ecs")


def find_by_name(client, cluster, service_re):
    results = depaginate(client, 'list_services', 'serviceArns', cluster=cluster)

    arns = list(results)
    
    result = filter(lambda x: re.findall(service_re, x), arns)

    return  result


def adjust_service_desired_count(ecs_client, cluster, service, noop=False):
    running_service = ecs_client.describe_services(cluster=cluster, services=[service])

    if not running_service["services"]:
        print >> sys.stderr, ("SKIP: Service '{service}' not found in cluster '{cluster}'".format(cluster=cluster, service=service))
        return

    desired_task_count = running_service["services"][0]["desiredCount"]

    clusters = ecs_client.describe_clusters(clusters=[cluster])
    registered_instances = clusters["clusters"][0]["registeredContainerInstancesCount"]

    if desired_task_count != registered_instances:
        print >> sys.stderr, ("Adjusting cluster '{}' to run {} tasks of service '{}'".format(
            cluster, registered_instances, service
        ))
        if noop:
            print "Would adjust {service} in {cluster} to {count}".format(service=service, cluster=cluster, count=registered_instances)
            return
        else:
            response = ecs_client.update_service(
                cluster=cluster,
                service=service,
                desiredCount=registered_instances,
                )

            print >> sys.stderr, (response)
            return response

    # Do nothing otherwise
    print >> sys.stderr, ("SKIP: Cluster {} has {} desired tasks for {} registered instances.".format(
        cluster, desired_task_count, registered_instances
    ))
    return

# function from https://github.com/miketheman/ecs-host-service-scale/blob/master/lambda_function.py
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
        print >> sys.stderr, ("SKIP: Function operates only on ECS Container Instance State Change events.")
        return

    # Valid event, and one we are interested in
    cluster = event["detail"]["clusterArn"]
    adjust_service_desired_count(ecs_client(), cluster, service)
    print >> sys.stderr, ("DONE")


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("--cluster", help="Cluster name or ARN", default=os.environ.get('CLUSTER', ''))
    parser.add_argument("--services", help="Service name or  ARN", default=[], nargs='+')
    parser.add_argument("--profile", help="AWS profile to use")
    parser.add_argument("--region", help="AWS region to use")
    parser.add_argument("--service-re", help="Regular expression to locate services for autoscaling")
    parser.add_argument("--once", help="Run only once", action='store_true', default=False)
    parser.add_argument("--noop", help="Do not actually adjust services", action="store_true", default=False)

    args = parser.parse_args()

    if 'SERVICES' in os.environ:
        args.services.extend(os.environ['SERVICES'].split(' '))

    if not args.cluster:
        print >> sys.stderr,  "Either --cluster must be specified or CLUSTER environment variable must be set"
        sys.exit(1)

    if not (args.services or args.service_re):
        print >> sys.stderr,  "Either --service-re or --services must be specified or SERVICES environment variable must be set"
        sys.exit(1)

    print >> sys.stderr,  "In Cluster '%s', managing:" % args.cluster
    print >> sys.stderr,  "  " + "\n  ".join(args.services)
    if args.service_re:
        print >> sys.stderr,  "  and any cluster matching '{}'\n".format(args.service_re)
    

    while True:
        try:
            client = ecs_client(args)


            services = set(args.services)

            if args.service_re:
                services.update(find_by_name(client, args.cluster, args.service_re))

            print "Services {}".format(services)

            for service in services:
                print "Adjusting %s" % service
                adjust_service_desired_count(client, args.cluster, service, noop=args.noop)
        except Exception as e:
            print >> sys.stderr,  "Exception adjusting service"
            print >> sys.stderr,  traceback.format_exc()
        if args.once:
            break
        time.sleep(60)
    
    
if __name__ == "__main__":
    main()
