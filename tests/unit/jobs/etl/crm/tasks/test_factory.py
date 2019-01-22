import pytest

from bietlejuice.jobs.etl.crm.tasks import CRMTasksTableEnum, CRMTasksUngroupedManual, CRMTasksRepair, CRMTasksPhotoJob, \
    CRMTasksClosing, CRMTasksCredit, CRMTasksInspection, CRMTasksLead, CRMTasksVisit, CRMTasksOnboardingTenant, \
    CRMTasksPayment, CRMTasksOffboarding


class TestCRMTasksFactory(object):
    @pytest.mark.parametrize('class_, expected',
                             [(CRMTasksTableEnum.UNGROUPED_MANUAL, CRMTasksUngroupedManual),
                              (CRMTasksTableEnum.REPAIR, CRMTasksRepair),
                              (CRMTasksTableEnum.PHOTO_JOB, CRMTasksPhotoJob),
                              (CRMTasksTableEnum.CLOSING, CRMTasksClosing),
                              (CRMTasksTableEnum.CREDIT, CRMTasksCredit),
                              (CRMTasksTableEnum.INSPECTION, CRMTasksInspection),
                              (CRMTasksTableEnum.LEAD, CRMTasksLead),
                              (CRMTasksTableEnum.VISIT, CRMTasksVisit),
                              (CRMTasksTableEnum.ONBOARDING_TENANT, CRMTasksOnboardingTenant),
                              (CRMTasksTableEnum.PAYMENT, CRMTasksPayment),
                              (CRMTasksTableEnum.OFFBOARDING, CRMTasksOffboarding)])
    def test__dispatch_dict(self, factory, class_, expected):
        # act
        result = factory._dispatch_dict(class_=class_)

        # assert
        assert result == expected
