"""EMR/Databricks runtime-specific tests for DAGPackagesPathService.

These tests live in bietlejuice-runtime because they patch
``bietlejuice.base.spark.runtime_detector.RuntimeDetector`` which is shipped
by bietlejuice-runtime. The remaining DAGPackagesPathService tests live in
bietlejuice-core/test.
"""

from unittest import mock

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class TestDAGPackagesPathServiceQueryFileContent:
    @mock.patch.object(DAGPackagesPathService, "_read_dag_package_file_from_s3")
    @mock.patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    def test_get_query_file_content_uses_boto3_on_emr_with_default_engine(
        self, mock_runtime_detector, mock_read_s3
    ):
        mock_runtime_detector.is_emr.return_value = True
        mock_read_s3.return_value = "SELECT 1"

        DAGPackagesPathService.get_query_file_content_in_spark_jobs(
            dag_name="my_dag", table_name="t1", layer="clean"
        )

        mock_read_s3.assert_called_once()
        _, kwargs = mock_read_s3.call_args
        assert kwargs["engine"] == "boto3"

    @mock.patch.object(DAGPackagesPathService, "_read_dag_package_file_from_s3")
    @mock.patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    def test_get_query_file_content_forces_boto3_on_emr_even_if_spark_requested(
        self, mock_runtime_detector, mock_read_s3
    ):
        mock_runtime_detector.is_emr.return_value = True
        mock_read_s3.return_value = "SELECT 1"

        DAGPackagesPathService.get_query_file_content_in_spark_jobs(
            dag_name="my_dag",
            table_name="t1",
            layer="clean",
            engine="spark",
        )

        _, kwargs = mock_read_s3.call_args
        assert kwargs["engine"] == "boto3"

    @mock.patch.object(DAGPackagesPathService, "_read_dag_package_file_from_s3")
    @mock.patch("bietlejuice.base.spark.runtime_detector.RuntimeDetector")
    def test_get_query_file_content_keeps_databricks_volume_when_not_emr(
        self, mock_runtime_detector, mock_read_s3
    ):
        mock_runtime_detector.is_emr.return_value = False
        mock_read_s3.return_value = "SELECT 1"

        DAGPackagesPathService.get_query_file_content_in_spark_jobs(
            dag_name="my_dag", table_name="t1", layer="clean"
        )

        _, kwargs = mock_read_s3.call_args
        assert kwargs["engine"] == "databricks_volume"
