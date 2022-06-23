from unittest.mock import Mock

import mock


class TestSyncMetastoreExternalTablePartitionsPipeline:
    @mock.patch(
        "bietlejuice.jobs.composer.metastore_pipeline.sync_metastore_external_table_partitions_pipeline.HiveMetastoreLoader"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.metastore_pipeline.sync_metastore_external_table_partitions_pipeline.HiveMetastoreService"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.metastore_pipeline.sync_metastore_external_table_partitions_pipeline.HiveMetastoreClient"
    )
    def test_run_for_partitioned_table(
        self,
        mocked_hive_metastore_client,
        mocked_hive_metastore_service,
        mocked_hive_metastore_loader,
        sync_metastore_external_table_partitions_pipeline,
    ):
        # arrange
        host = Mock()
        database_name = Mock()
        table_name = Mock()
        partition_keys = [("a", "int"), ("b", "string")]
        partition_values = Mock()
        sync_metastore_external_table_partitions_pipeline.metastore_host = host
        sync_metastore_external_table_partitions_pipeline.database_name = database_name
        sync_metastore_external_table_partitions_pipeline.table_name = table_name
        sync_metastore_external_table_partitions_pipeline.partition_keys = (
            partition_keys
        )
        sync_metastore_external_table_partitions_pipeline.partition_values = (
            partition_values
        )

        hm_client = Mock()
        mocked_hive_metastore_client.return_value = hm_client

        hm_service = Mock()
        mocked_hive_metastore_service.return_value = hm_service

        hm_loader = Mock()
        mocked_hive_metastore_loader.return_value = hm_loader

        # act
        sync_metastore_external_table_partitions_pipeline.run()

        # assert
        mocked_hive_metastore_client.assert_called_once_with(host)
        mocked_hive_metastore_service.assert_called_once_with(hm_client)
        mocked_hive_metastore_loader.assert_called_once_with(hm_service)
        hm_loader.update_table_partitions.assert_called_once_with(
            database_name=database_name,
            table_name=table_name,
            partition_values=partition_values,
        )

    @mock.patch(
        "bietlejuice.jobs.composer.metastore_pipeline.sync_metastore_external_table_partitions_pipeline.HiveMetastoreLoader"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.metastore_pipeline.sync_metastore_external_table_partitions_pipeline.HiveMetastoreService"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.metastore_pipeline.sync_metastore_external_table_partitions_pipeline.HiveMetastoreClient"
    )
    def test_run_for_non_partitioned_table(
        self,
        mocked_hive_metastore_client,
        mocked_hive_metastore_service,
        mocked_hive_metastore_loader,
        sync_metastore_external_table_partitions_pipeline,
    ):
        # arrange
        host = Mock()
        database_name = Mock()
        table_name = Mock()
        partition_keys = []
        partition_values = Mock()
        sync_metastore_external_table_partitions_pipeline.metastore_host = host
        sync_metastore_external_table_partitions_pipeline.database_name = database_name
        sync_metastore_external_table_partitions_pipeline.table_name = table_name
        sync_metastore_external_table_partitions_pipeline.partition_keys = (
            partition_keys
        )
        sync_metastore_external_table_partitions_pipeline.partition_values = (
            partition_values
        )

        hm_client = Mock()
        mocked_hive_metastore_client.return_value = hm_client

        hm_service = Mock()
        mocked_hive_metastore_service.return_value = hm_service

        hm_loader = Mock()
        mocked_hive_metastore_loader.return_value = hm_loader

        # act
        sync_metastore_external_table_partitions_pipeline.run()

        # assert
        mocked_hive_metastore_client.assert_called_once_with(host)
        mocked_hive_metastore_service.assert_called_once_with(hm_client)
        mocked_hive_metastore_loader.assert_called_once_with(hm_service)
        hm_loader.update_table_partitions.assert_not_called()
