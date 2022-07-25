from unittest.mock import Mock

import mock


class TestSyncMetastoreExternalTableStructurePipeline:
    @mock.patch(
        "bietlejuice.jobs.composer.metastore_pipeline.sync_metastore_external_table_structure_pipeline.HiveMetastoreLoader"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.metastore_pipeline.sync_metastore_external_table_structure_pipeline.HiveMetastoreService"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.metastore_pipeline.sync_metastore_external_table_structure_pipeline.HiveMetastoreClient"
    )
    def test_run(
        self,
        mocked_hive_metastore_client,
        mocked_hive_metastore_service,
        mocked_hive_metastore_loader,
        sync_metastore_external_table_structure_pipeline,
    ):
        # arrange
        host = Mock()
        database_name = Mock()
        table_name = Mock()
        database_location = Mock()
        table_schema = Mock()
        partition_keys = [("a", "int"), ("b", "string")]
        format_info = Mock()
        sync_metastore_external_table_structure_pipeline.metastore_host = host
        sync_metastore_external_table_structure_pipeline.database_name = database_name
        sync_metastore_external_table_structure_pipeline.table_name = table_name
        sync_metastore_external_table_structure_pipeline.database_location = (
            database_location
        )
        sync_metastore_external_table_structure_pipeline.table_schema = table_schema
        sync_metastore_external_table_structure_pipeline.partition_keys = partition_keys
        sync_metastore_external_table_structure_pipeline.format_info = format_info

        hm_client = Mock()
        mocked_hive_metastore_client.return_value = hm_client

        hm_service = Mock()
        mocked_hive_metastore_service.return_value = hm_service

        hm_loader = Mock()
        mocked_hive_metastore_loader.return_value = hm_loader

        # act
        sync_metastore_external_table_structure_pipeline.run()

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
