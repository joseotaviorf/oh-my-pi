import mock
from mock import MagicMock, Mock

from bietlejuice.jobs.base import BaseDAG

from bietlejuice.jobs.etl.marketing import TwitterCampaigns


class TestMarketingTwitterCampaignsSubdag(object):

    @mock.patch('bietlejuice.jobs.dags.marketing.marketing_twitter_campaigns_subdag.'
                'TwitterCampaigns')
    @mock.patch.object(BaseDAG, 'build_python_operator')
    def test_build_clean_tasks_with_no_account(self, mock__build_python_operator,
                                               mock__twitter_campaigns,
                                               twitter_campaigns_subdag):
        # arrange
        mock__twitter_campaigns.get_accounts = MagicMock(return_value=[])

        mocked_dag = Mock()
        mock__build_python_operator.return_value = MagicMock()
        twitter_campaigns_subdag.transfer_files_to_clean = MagicMock()

        # act
        twitter_campaigns_subdag.build_clean_tasks(mocked_dag)

        # assert
        mock__build_python_operator.assert_not_called()

    @mock.patch('bietlejuice.jobs.dags.marketing.marketing_twitter_campaigns_subdag.'
                'TwitterCampaigns')
    @mock.patch.object(BaseDAG, 'build_python_operator')
    def test_build_clean_tasks_with_no_tables(self, mock__build_python_operator,
                                              mock__twitter_campaigns,
                                              twitter_campaigns_subdag):
        # arrange
        mock_accounts = MagicMock()
        mock_accounts.__iter__.return_value = [1, 2, 3, 4]

        mock_instance = MagicMock()
        mock_instance.get_accounts.return_value = mock_accounts

        mock__twitter_campaigns.return_value = mock_instance

        mocked_dag = Mock()
        mock__build_python_operator.return_value = MagicMock()
        twitter_campaigns_subdag.transfer_files_to_clean = MagicMock()

        twitter_campaigns_subdag.tables = []

        # act
        twitter_campaigns_subdag.build_clean_tasks(mocked_dag)

        # assert
        mock__build_python_operator.assert_not_called()

    @mock.patch('bietlejuice.jobs.dags.marketing.marketing_twitter_campaigns_subdag.'
                'TwitterCampaigns')
    @mock.patch.object(BaseDAG, 'build_python_operator')
    def test_build_clean_tasks(self, mock__build_python_operator,
                               mock__twitter_campaigns,
                               twitter_campaigns_subdag):
        # arrange
        acc_id = 11
        acc = MagicMock()
        acc.id = acc_id
        mock_accounts = MagicMock()
        mock_accounts.__iter__.return_value = [acc]

        mock_instance = MagicMock()
        mock_instance.get_accounts.return_value = mock_accounts

        mock__twitter_campaigns.return_value = mock_instance

        mocked_dag = Mock()
        mock__build_python_operator.return_value = MagicMock()
        twitter_campaigns_subdag.transfer_files_to_clean = MagicMock()

        # act
        twitter_campaigns_subdag.build_clean_tasks(mocked_dag)

        # assert
        mock__build_python_operator.assert_has_calls([mock.call(
            dag=mocked_dag,
            task_id=TwitterCampaigns.CAMPAIGNS_TABLE_NAME + '_task',
            python_callable=twitter_campaigns_subdag.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': 'bucket',
                'datalake_table': TwitterCampaigns.CAMPAIGNS_TABLE_NAME,
                'account': acc_id
            }), mock.call(
            dag=mocked_dag,
            task_id=TwitterCampaigns.AD_GROUPS_TABLE_NAME + '_task',
            python_callable=twitter_campaigns_subdag.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': 'bucket',
                'datalake_table': TwitterCampaigns.AD_GROUPS_TABLE_NAME,
                'account': acc_id
            }), mock.call(
            dag=mocked_dag,
            task_id=TwitterCampaigns.ADS_TABLE_NAME + '_task',
            python_callable=twitter_campaigns_subdag.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': 'bucket',
                'datalake_table': TwitterCampaigns.ADS_TABLE_NAME,
                'account': acc_id
            }), mock.call(
            dag=mocked_dag,
            task_id=TwitterCampaigns.ADS_STATS_TABLE_NAME + '_task',
            python_callable=twitter_campaigns_subdag.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': 'bucket',
                'datalake_table': TwitterCampaigns.ADS_STATS_TABLE_NAME,
                'account': acc_id
            })
        ])
