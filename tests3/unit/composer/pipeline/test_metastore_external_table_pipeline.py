from unittest.mock import Mock

import mock


class TestMetastoreExternalTablePipeline:
    @mock.patch(
        "bietlejuice.jobs.composer.pipeline.metastore_external_table_pipeline.HiveMetastoreLoader"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.pipeline.metastore_external_table_pipeline.HiveMetastoreService"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.pipeline.metastore_external_table_pipeline.HiveMetastoreClient"
    )
    def test_run_for_partitioned_tables(
        self,
        mocked_hive_metastore_client,
        mocked_hive_metastore_service,
        mocked_hive_metastore_loader,
        metastore_external_table_pipeline,
    ):
        # arrange
        host = Mock()
        database_name = Mock()
        table_name = Mock()
        database_location = Mock()
        table_schema = Mock()
        partition_keys = [("a", "int"), ("b", "string")]
        partition_values = Mock()
        format_info = Mock()
        metastore_external_table_pipeline.metastore_host = host
        metastore_external_table_pipeline.database_name = database_name
        metastore_external_table_pipeline.table_name = table_name
        metastore_external_table_pipeline.database_location = database_location
        metastore_external_table_pipeline.table_schema = table_schema
        metastore_external_table_pipeline.partition_keys = partition_keys
        metastore_external_table_pipeline.partition_values = partition_values
        metastore_external_table_pipeline.format_info = format_info

        hm_client = Mock()
        mocked_hive_metastore_client.return_value = hm_client

        hm_service = Mock()
        mocked_hive_metastore_service.return_value = hm_service

        hm_loader = Mock()
        mocked_hive_metastore_loader.return_value = hm_loader

        # act
        metastore_external_table_pipeline.run()

        # assert
        mocked_hive_metastore_client.assert_called_once_with(host)
        mocked_hive_metastore_service.assert_called_once_with(hm_client)
        hm_service.create_database.assert_called_once_with(database_name)
        mocked_hive_metastore_loader.assert_called_once_with(hm_service)
        hm_loader.sync_metastore.assert_called_once_with(
            database_name=database_name,
            table_name=table_name,
            database_location=database_location,
            table_schema=table_schema,
            partition_keys=partition_keys,
            format_info=format_info,
            source_schema=table_schema,
        )
        hm_loader.update_table_partitions.assert_called_once_with(
            database_name=database_name,
            table_name=table_name,
            partition_values=partition_values,
        )

    @mock.patch(
        "bietlejuice.jobs.composer.pipeline.metastore_external_table_pipeline.HiveMetastoreLoader"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.pipeline.metastore_external_table_pipeline.HiveMetastoreService"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.pipeline.metastore_external_table_pipeline.HiveMetastoreClient"
    )
    def test_run_for_non_partitioned_tables(
        self,
        mocked_hive_metastore_client,
        mocked_hive_metastore_service,
        mocked_hive_metastore_loader,
        metastore_external_table_pipeline,
    ):
        # arrange
        host = Mock()
        database_name = Mock()
        table_name = Mock()
        database_location = Mock()
        table_schema = Mock()
        partition_keys = []
        partition_values = Mock()
        format_info = Mock()
        metastore_external_table_pipeline.metastore_host = host
        metastore_external_table_pipeline.database_name = database_name
        metastore_external_table_pipeline.table_name = table_name
        metastore_external_table_pipeline.database_location = database_location
        metastore_external_table_pipeline.table_schema = table_schema
        metastore_external_table_pipeline.partition_keys = partition_keys
        metastore_external_table_pipeline.partition_values = partition_values
        metastore_external_table_pipeline.format_info = format_info

        hm_client = Mock()
        mocked_hive_metastore_client.return_value = hm_client

        hm_service = Mock()
        mocked_hive_metastore_service.return_value = hm_service

        hm_loader = Mock()
        mocked_hive_metastore_loader.return_value = hm_loader

        # act
        metastore_external_table_pipeline.run()

        # assert
        mocked_hive_metastore_client.assert_called_once_with(host)
        mocked_hive_metastore_service.assert_called_once_with(hm_client)
        hm_service.create_database.assert_called_once_with(database_name)
        mocked_hive_metastore_loader.assert_called_once_with(hm_service)
        hm_loader.sync_metastore.assert_called_once_with(
            database_name=database_name,
            table_name=table_name,
            database_location=database_location,
            table_schema=table_schema,
            partition_keys=partition_keys,
            format_info=format_info,
            source_schema=table_schema,
        )
        hm_loader.update_table_partitions.assert_not_called()
