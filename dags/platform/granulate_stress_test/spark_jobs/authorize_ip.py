"""
This Spark job is temporary. It is only here to provide a task for the Granulate stress test cluster to run.
If we're going to run something every 15 minutes, it might as well be useful and update the Trino IPs in the NAT Gateway.

This will be removed as soon as we're done with the stress test.
"""

import boto3
import socket
import json

ROUTE_TABLE = "rtb-0f2676b988a2522ce"
NAT_GATEWAY = "nat-0a7d93effdf5e5810"


class TrinoConnectionHelper:
    @staticmethod
    def start_client(service=None):
        client = boto3.client(service, region_name="us-east-1")
        return client

    @staticmethod
    def get_ips(client, rtb, nat):
        route_ips = []
        response = client.describe_route_tables(RouteTableIds=[rtb])

        obj = response["RouteTables"][0]["Routes"]
        for o in obj:
            try:
                if o["NatGatewayId"] == nat:
                    route_ips.append(o["DestinationCidrBlock"][:-3])
            except:
                pass

        return route_ips

    @staticmethod
    def validate_and_remove_existing_routes(
        client, rtb, nat_gateway, route_ips, trino_ips
    ):
        for route_ip in route_ips:
            if route_ip not in trino_ips:
                client.delete_route(
                    DestinationCidrBlock=route_ip + "/32", RouteTableId=rtb
                )

    @staticmethod
    def validate_and_add_unexisting_routes(
        client, rtb, nat_gateway, route_ips, trino_ips
    ):
        for trino_ip in trino_ips:
            if trino_ip not in route_ips:
                client.create_route(
                    DestinationCidrBlock=trino_ip + "/32",
                    RouteTableId=rtb,
                    NatGatewayId=nat_gateway,
                )

    @staticmethod
    def get_trino_ips(host):
        trino_infos = socket.gethostbyname_ex(
            host
        )  # gethostbyname_ex returns a Tuple (primary-ip, all-aliases, all-ips)
        trino_ips = trino_infos[2]  # the 3rd parameter are all the ips from the cluster

        return list(set(trino_ips))

    @staticmethod
    def authorize_ips(route_table, nat_gateway, trino_host):
        client = TrinoConnectionHelper.start_client(service="ec2")
        trino_ips = TrinoConnectionHelper.get_trino_ips(trino_host)
        route_ips = TrinoConnectionHelper.get_ips(client, route_table, nat_gateway)
        TrinoConnectionHelper.validate_and_remove_existing_routes(
            client, route_table, nat_gateway, route_ips, trino_ips
        )
        TrinoConnectionHelper.validate_and_add_unexisting_routes(
            client, route_table, nat_gateway, route_ips, trino_ips
        )


trino_confs = dbutils.secrets.get("quintoandar", "TRINO")  # noqa: F821
trino_confs_json = json.loads(trino_confs)
TRINO_HOST = trino_confs_json["host"]

TrinoConnectionHelper.authorize_ips(ROUTE_TABLE, NAT_GATEWAY, TRINO_HOST)
