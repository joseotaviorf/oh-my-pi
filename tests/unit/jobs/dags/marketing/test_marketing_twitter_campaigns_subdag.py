import mock
from mock import MagicMock, Mock

from bietlejuice.jobs.base import BaseDAG


class TestMarketingTwitterCampaignsSubdag(object):

    @mock.patch.object(BaseDAG, 'build_python_operator')
    def test_build_clean_tasks(self, mock__build_python_operator,
                               twitter_campaigns_subdag):
        # arrange
        mocked_dag = Mock()
        dalake_table = 'xpto_table'
        mock__build_python_operator.return_value = MagicMock()
        twitter_campaigns_subdag.transfer_files_to_clean = MagicMock()
        twitter_campaigns_subdag.datalake_tables = [dalake_table]

        # act
        twitter_campaigns_subdag.build_clean_tasks(mocked_dag)

        # assert
        mock__build_python_operator.assert_called_with(
            dag=mocked_dag,
            task_id='twitter_campaigns_task',
            python_callable=twitter_campaigns_subdag.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': 'bucket',
                'datalake_table': dalake_table,
                'account': 'default'
            })
