from unittest import mock

from bietlejuice.base.sst.core.utils import common as common_module


class TestValidatePartitionReadability:
    def test_executes_read_query_on_target_table(self):
        # arrange
        spark = mock.MagicMock()

        # act
        common_module.validate_partition_readability(
            spark=spark,
            target_table="datalake_sfmc_clean.tb_sonia_ep2ds",
            partition_date="2026-04-15",
        )

        # assert
        spark.read.table.assert_called_once_with("datalake_sfmc_clean.tb_sonia_ep2ds")
