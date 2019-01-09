from bietlejuice.jobs.etl.crm.tasks import CRMTasksTableEnum, CRMTasksUngroupedManual


class TestCRMTasksFactory(object):
    def test_move_fact_to_staging(self, factory):
        # arrange
        class_ = CRMTasksTableEnum.UNGROUPED_MANUAL

        # act
        result = factory._dispatch_dict(class_=class_)

        # assert
        assert result == CRMTasksUngroupedManual
