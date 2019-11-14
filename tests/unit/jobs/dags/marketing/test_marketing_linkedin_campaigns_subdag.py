import mock
from mock import MagicMock, Mock

from bietlejuice.jobs.base import BaseDAG
from bietlejuice.jobs.etl.marketing.linkedin_campaigns import LinkedInCampaigns


class TestMarketingLinkedInCampaignsSubdag(object):

    @mock.patch.object(LinkedInCampaigns, 'get_accounts')
    @mock.patch.object(BaseDAG, 'build_python_operator')
    def test_build_clean_tasks_with_no_account(self, mock_build_python_operator,
                                               mock_get_accounts,
                                               linkedin_campaigns_subdag):
        # arrange
        mock_get_accounts.return_value = []
        mock_build_python_operator.return_value = MagicMock()
        linkedin_campaigns_subdag.transfer_files_to_clean = MagicMock()

        # act
        linkedin_campaigns_subdag.build_clean_tasks(Mock())

        # assert
        mock_build_python_operator.assert_not_called()

    @mock.patch.object(LinkedInCampaigns, 'get_accounts')
    @mock.patch.object(BaseDAG, 'build_python_operator')
    def test_build_clean_tasks_with_no_tables(self, mock_build_python_operator,
                                              mock_get_accounts,
                                              linkedin_campaigns_subdag):
        # arrange
        mock_get_accounts.return_value = [1, 2, 3, 4]
        linkedin_campaigns_subdag.tables = []

        # act
        linkedin_campaigns_subdag.build_clean_tasks(Mock())

        # assert
        mock_build_python_operator.assert_not_called()

    @mock.patch.object(LinkedInCampaigns, 'get_accounts')
    @mock.patch.object(BaseDAG, 'build_python_operator')
    def test_build_clean_tasks(self, mock_build_python_operator, mock_get_accounts,
                               linkedin_campaigns_subdag):
        # arrange
        acc_id = 13
        acc = Mock()
        acc.id = acc_id
        mock_get_accounts.return_value = [acc]
        mock_build_python_operator.return_value = Mock()
        linkedin_campaigns_subdag.transfer_files_to_clean = Mock()
        mocked_dag = Mock()

        # act
        linkedin_campaigns_subdag.build_clean_tasks(mocked_dag)

        # assert
        mock_build_python_operator.assert_has_calls([mock.call(
            dag=mocked_dag,
            task_id='acc-{}-{}-task'.format(acc.id,
                                            LinkedInCampaigns.CAMPAIGN_GROUPS_TABLE_NAME),
            python_callable=linkedin_campaigns_subdag.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': 'bucket',
                'datalake_table': LinkedInCampaigns.CAMPAIGN_GROUPS_TABLE_NAME,
                'account': acc_id
            }), mock.call(
            dag=mocked_dag,
            task_id='acc-{}-{}-task'.format(acc.id,
                                            LinkedInCampaigns.CAMPAIGNS_TABLE_NAME),
            python_callable=linkedin_campaigns_subdag.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': 'bucket',
                'datalake_table': LinkedInCampaigns.CAMPAIGNS_TABLE_NAME,
                'account': acc_id
            }), mock.call(
            dag=mocked_dag,
            task_id='acc-{}-{}-task'.format(acc.id,
                                            LinkedInCampaigns.CREATIVES_TABLE_NAME),
            python_callable=linkedin_campaigns_subdag.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': 'bucket',
                'datalake_table': LinkedInCampaigns.CREATIVES_TABLE_NAME,
                'account': acc_id
            }), mock.call(
            dag=mocked_dag,
            task_id='acc-{}-{}-task'.format(acc.id,
                                            LinkedInCampaigns.CREATIVES_STATS_TABLE_NAME),
            python_callable=linkedin_campaigns_subdag.transfer_files_to_clean,
            provide_context=True,
            op_kwargs={
                'bucket': 'bucket',
                'datalake_table': LinkedInCampaigns.CREATIVES_STATS_TABLE_NAME,
                'account': acc_id
            })
        ])
