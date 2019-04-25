import time

import boto3
from botocore.exceptions import ClientError
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('Redshift')


class Redshift(object):
    AVAILABLE_STATUS = 'available'
    CLUSTER_SUBNET_GROUP_NAME = 'quintoandar-aux'

    def __init__(self):
        self.redshift_client = boto3.client('redshift')

    def create_cluster_from_snapshot(self, source_cluster_id, target_cluster_id):
        """Create an Amazon Redshift cluster from previous snapshot

        The function returns without waiting for the cluster to be fully created.

        :param source_cluster_id: string; Name of the cluster which contains the source snapshots
        :param target_cluster_id: string; Name to assign the cluster to be created
        :return dictionary containing cluster information
        """
        if self.check_if_cluster_exists(cluster_id=target_cluster_id):
            raise ValueError('cluster_id={},msg=Cluster already exists'.format(target_cluster_id))
        else:
            snapshot_id = self.get_latest_snapshot(cluster_id=source_cluster_id)

            if not snapshot_id:
                raise ValueError('cluster_id={},msg=No snapshot found'.format(source_cluster_id))

            try:
                response = \
                    self.redshift_client.restore_from_cluster_snapshot(
                        ClusterIdentifier=target_cluster_id,
                        SnapshotIdentifier=snapshot_id,
                        SnapshotClusterIdentifier=source_cluster_id,
                        ClusterSubnetGroupName=self.CLUSTER_SUBNET_GROUP_NAME)
            except Exception as e:
                raise RuntimeError(
                    'cluster_id={0}, snapshot={1}, error={2}, msg=Not able to start cluster'.format(target_cluster_id,
                                                                                                    snapshot_id,
                                                                                                    e.message))

            logger.info('cluster_id={0}, msg=Cluster starting.'.format(target_cluster_id))

    def check_if_cluster_exists(self, cluster_id):
        """Check whether an Amazon Redshift cluster exists

        :param cluster_id: string; Cluster name to be checked
        :return boolean; Whether cluster exists
        """
        try:
            response = self.redshift_client.describe_clusters(ClusterIdentifier=cluster_id)
            return True
        except ClientError:
            return False

    def get_latest_snapshot(self, cluster_id):
        """Get the latest snapshot from Amazon Redshift cluster

        :param cluster_id: string; Cluster identifier
        :return string; Latest Snapshot Identifier
        """
        # TODO
        # Get only last day snapshot

        snapshot_list = []

        try:
            response = self.redshift_client.describe_cluster_snapshots(ClusterIdentifier=cluster_id,
                                                                       SnapshotType='automated')
        except ClientError as e:
            raise RuntimeError(
                'cluster_id={0}, error={1}, msg=Unable to gather info from cluster'.format(cluster_id, e.message))

        for item in response['Snapshots']:
            snapshot_list.append(item['SnapshotIdentifier'])

        snapshot_list.sort(reverse=True)
        return snapshot_list[0]

    def shutdown_cluster(self, cluster_id):
        """Shutdown an Amazon Redshift cluster

        :param cluster_id: string; Cluster name to be shutdown
        :return boolean; Whether cluster was shutdown
        """
        if self.check_if_cluster_exists(cluster_id=cluster_id):
            try:
                response = \
                    self.redshift_client.delete_cluster(ClusterIdentifier=cluster_id,
                                                        FinalClusterSnapshotIdentifier='{}-before-shuting-down'.format(
                                                            cluster_id))
                return True
            except ClientError as e:
                raise RuntimeError('cluster_id={0}, error={1}, msg=Unable to shutdown cluster'.format(cluster_id,
                                                                                                      e.message))
        else:
            logger.error('cluster_id={0}, msg=Cluster does not exist'.format(cluster_id))
            return False

    def get_cluster_status(self, cluster_id):
        """Get status from an Amazon Redshift cluster

        :param cluster_id: string; Cluster name to be shutdown
        :return string; Cluster status
        """
        try:
            response = self.redshift_client.describe_clusters(ClusterIdentifier=cluster_id)
            return response['Clusters'][0]['ClusterStatus']
        except ClientError as e:
            raise RuntimeError('cluster_id={0}, error={1}, msg=Unable to gather info from cluster'.format(cluster_id,
                                                                                                          e.message))

    def wait_for_cluster_availability(self, cluster_id, timeout_seconds=3600):
        """Get status from an Amazon Redshift cluster

        :param cluster_id: string; Cluster name to be shutdown
        :param timeout_seconds: integer; Max seconds to wait for cluster become available
        """
        waiter_coefficient = 60 * 5
        for i in range(0, (timeout_seconds / waiter_coefficient) - 1):
            status = self.get_cluster_status(cluster_id=cluster_id)
            if status == self.AVAILABLE_STATUS:
                logger.info('cluster_id={0}, approximate_waiting_time={1} seconds,'
                            'msg=Cluster available'.format(cluster_id, str(i * waiter_coefficient)))
                return

            # Waits before trying again
            logger.info('cluster_id={0}, retrial={1}, sum_waiting_time={2}, '
                        'msg=Starting waiting mode'.format(cluster_id, str(i + 1), str(i * waiter_coefficient)))
            time.sleep(waiter_coefficient)

        raise RuntimeError('cluster_id={0}, msg=Timeout waiting for cluster to become available'.format(cluster_id))

    def wait_for_cluster_shutdown(self, cluster_id, timeout_seconds=3600):
        """Get status from an Amazon Redshift cluster

        :param cluster_id: string; Cluster name to be shutdown
        :param timeout_seconds: integer; Max seconds to wait for cluster become available
        """
        waiter_coefficient = 60 * 5
        for i in range(0, (timeout_seconds / waiter_coefficient) - 1):
            try:
                status = self.get_cluster_status(cluster_id=cluster_id)
            except RuntimeError:
                logger.info('cluster_id={0}, approximate_waiting_time={1} seconds,'
                            'msg=Cluster not found'.format(cluster_id, str(i * waiter_coefficient)))
                return

            # Waits before trying again
            logger.info('cluster_id={0}, retrial={1}, sum_waiting_time={2}, status={3} '
                        'msg=Starting waiting mode'.format(cluster_id, str(i + 1), str(i * waiter_coefficient), status))
            time.sleep(waiter_coefficient)

        raise RuntimeError('cluster_id={0}, msg=Timeout waiting for cluster to shutdown'.format(cluster_id))
