import datetime

import boto3
from botocore.exceptions import ClientError
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('Redshift')


class RedshiftClient(object):
    def __init__(self):
        self.redshift_client = boto3.client('redshift')

    @logger
    def create_cluster_from_snapshot(self, source_cluster_id, target_cluster_id, config_json):
        """Create an Amazon Redshift cluster from previous snapshot

        The function returns without waiting for the cluster to be fully created.

        :param source_cluster_id: string; Name of the cluster which contains the source snapshots
        :param target_cluster_id: string; Name to assign the cluster to be created
        :param config_json: string; Json with parameters to be used in the creation of cluster
        """
        if self.check_if_cluster_exists(cluster_id=target_cluster_id):
            raise ValueError(
                'm=create_cluster_from_snapshot, cluster_id={},msg=Cluster already exists'.format(target_cluster_id))

        snapshot_id = self.get_latest_snapshot(cluster_id=source_cluster_id)

        if not snapshot_id:
            raise ValueError(
                'm=create_cluster_from_snapshot, cluster_id={},msg=No snapshot found'.format(source_cluster_id))

        try:
            response = \
                self.redshift_client.restore_from_cluster_snapshot(
                    ClusterIdentifier=target_cluster_id,
                    SnapshotIdentifier=snapshot_id,
                    SnapshotClusterIdentifier=source_cluster_id,
                    ClusterSubnetGroupName=config_json.get('CLUSTER_SUBNET_GROUP_NAME'),
                    ClusterParameterGroupName=config_json.get('CLUSTER_PARAMETER_GROUP_NAME'),
                    VpcSecurityGroupIds=config_json.get('VPC_SECURITY_GROUP_ID'),
                    IamRoles=config_json.get('IAM_ROLES'),
                    AvailabilityZone=config_json.get('AVAILABILITY_ZONE'),
                    PubliclyAccessible=True)
        except Exception as e:
            raise RuntimeError(
                'm=create_cluster_from_snapshot, cluster_id={0}, snapshot={1}, error={2}, '
                'msg=Not able to start cluster'.format(
                    target_cluster_id,
                    snapshot_id,
                    e.message))

        logger.info('m=create_cluster_from_snapshot, cluster_id={0}, msg=Cluster starting.'.format(target_cluster_id))

    @logger
    def check_if_cluster_exists(self, cluster_id):
        """Check whether an Amazon Redshift cluster exists

        :param cluster_id: string; Cluster name to be checked
        :return boolean; Whether cluster exists
        """
        try:
            response = self.redshift_client.describe_clusters(ClusterIdentifier=cluster_id)
            logger.info('m=check_if_cluster_exists, cluster_id={0}, msg=Cluster exists'.format(cluster_id))
            return True
        except ClientError as e:
            logger.error(
                'm=check_if_cluster_exists, cluster_id={0}, error={1}, msg=Cluster does not exists'.format(cluster_id,
                                                                                                           e.message))
            return False

    @logger
    def get_latest_snapshot(self, cluster_id):
        """Get the latest snapshot from Amazon Redshift cluster

        :param cluster_id: string; Cluster identifier
        :return string; Latest Snapshot Identifier
        """
        snapshot_list = []

        try:
            response = self.redshift_client.describe_cluster_snapshots(ClusterIdentifier=cluster_id,
                                                                       SnapshotType='automated')
        except ClientError as e:
            raise RuntimeError(
                'm=get_latest_snapshot, cluster_id={0}, error={1}, msg=Unable to gather info from cluster'.format(
                    cluster_id, e.message))

        if not response['Snapshots']:
            raise ValueError(
                'm=get_latest_snapshot, cluster_id={0}, msg=No snapshot from cluster found'.format(cluster_id))

        for item in response['Snapshots']:
            snapshot_list.append(item['SnapshotIdentifier'])

        snapshot_list.sort(reverse=True)
        return snapshot_list[0]

    @logger
    def shutdown_cluster(self, cluster_id):
        """Send command to shutdown an Amazon Redshift cluster

        :param cluster_id: string; Cluster name to be shutdown
        """
        if not self.check_if_cluster_exists(cluster_id=cluster_id):
            raise ValueError('m=shutdown_cluster, cluster_id={0}, msg=Cluster does not exist'.format(cluster_id))

        try:
            response = \
                self.redshift_client.delete_cluster(ClusterIdentifier=cluster_id,
                                                    FinalClusterSnapshotIdentifier='{}-{}'.format(
                                                        cluster_id,
                                                        str(datetime.datetime.today().strftime('%Y%m%d-%H-%M'))))

            logger.info('m=shutdown_cluster, cluster_id={0}, msg=Command to shutdown sent'.format(cluster_id))
        except ClientError as e:
            raise RuntimeError(
                'm=shutdown_cluster, cluster_id={0}, error={1}, msg=Unable to shutdown cluster'.format(cluster_id,
                                                                                                       e.message))

    @logger
    def get_cluster_status(self, cluster_id):
        """Get status from an Amazon Redshift cluster

        :param cluster_id: string; Cluster name to be shutdown
        :return string; Cluster status
        """
        try:
            response = self.redshift_client.describe_clusters(ClusterIdentifier=cluster_id)
            return response['Clusters'][0]['ClusterStatus']
        except ClientError as e:
            raise RuntimeError(
                'm=get_cluster_status, cluster_id={0}, error={1}, msg=Unable to gather info from cluster'.format(
                    cluster_id,
                    e.message))

    @logger
    def wait_for_cluster_availability(self, cluster_id):
        """Wait for Amazon Redshift cluster to become available

        :param cluster_id: string; Cluster name to monitor
        """
        waiter = self.redshift_client.get_waiter('cluster_available')
        try:
            waiter.wait(ClusterIdentifier=cluster_id)
        except Exception as e:
            raise RuntimeError(
                'm=wait_for_cluster_availability, cluster_id={0}, error={1}, '
                'msg=Timeout waiting for cluster to became available'.format(cluster_id, e.message))

    @logger
    def wait_for_cluster_shutdown(self, cluster_id):
        """Wait for Amazon Redshift cluster to shutdown

        :param cluster_id: string; Cluster name to monitor
        """
        waiter = self.redshift_client.get_waiter('cluster_deleted')
        try:
            waiter.wait(ClusterIdentifier=cluster_id)
        except Exception as e:
            raise RuntimeError(
                'm=wait_for_cluster_shutdown, cluster_id={0}, error={1}, '
                'msg=Timeout waiting for cluster to shutdown'.format(cluster_id, e.message))

    @logger
    def scale_down_cluster(self, cluster_id):
        """Send command to scale down an Amazon Redshift cluster

        :param cluster_id: string; Cluster name to be resized
        """
        if self.check_if_cluster_exists(cluster_id=cluster_id):
            try:
                response = \
                    self.redshift_client.modify_cluster(ClusterIdentifier=cluster_id,
                                                        ClusterType='single-node',
                                                        NodeType='dc2.large')

                logger.info('m=scale_down_cluster, cluster_id={0}, msg=Command to scale down sent'.format(cluster_id))
            except ClientError as e:
                raise RuntimeError(
                    'm=scale_down_cluster, cluster_id={0}, error={1}, msg=Unable to scale down cluster'.format(
                        cluster_id,
                        e.message))
        else:
            raise ValueError('m=scale_down_cluster, cluster_id={0}, msg=Cluster does not exist'.format(cluster_id))
