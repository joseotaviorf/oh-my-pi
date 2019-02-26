from datetime import datetime

import mock
import pytest
from mock import Mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksTableEnum, CRMTasksUngroupedManual, CRMTasksRepair, CRMTasksPhotoJob, \
    CRMTasksClosing, CRMTasksCredit, CRMTasksInspection, CRMTasksLead, CRMTasksVisit, CRMTasksOnboardingTenant, \
    CRMTasksPayment, CRMTasksOffboarding, CRMTasksFactory


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

    @mock.patch.object(CRMTasksFactory, '_dispatch_dict')
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
    def test_factory(self, mock__dispatch_dict, factory, class_, expected):
        # arrange
        mock__dispatch_dict.return_value = Mock(class_)

        s3_bucket = mock.ANY
        mongo_client_uri = mock.ANY
        execution_date = datetime.today()

        # act
        result = factory.factory(
            class_=class_,
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

        # assert
        assert mock__dispatch_dict.call_count == 1
        assert mock__dispatch_dict.call_args[0][0] == class_
        assert mock__dispatch_dict.return_value.call_count == 1
        assert result == mock__dispatch_dict.return_value()
        assert mock__dispatch_dict.return_value.call_args_list[0][1] == {
            's3_bucket': s3_bucket,
            'mongo_client_uri': mongo_client_uri,
            'execution_date': execution_date
        }

    @mock.patch.object(CRMTasksFactory, '_dispatch_dict')
    def test_factory_with_class_none(self, mock__dispatch_dict, factory):
        # arrange
        class_ = None
        s3_bucket = mock.ANY
        mongo_client_uri = mock.ANY
        execution_date = datetime.today()

        # act & assert
        with pytest.raises(ValueError):
            factory.factory(
                class_=class_,
                s3_bucket=s3_bucket,
                mongo_client_uri=mongo_client_uri,
                execution_date=execution_date
            )

        # assert
        assert mock__dispatch_dict.call_count == 0

    @mock.patch.object(CRMTasksFactory, '_dispatch_dict', return_value=None)
    def test_factory_with_invalid_class(self, mock__dispatch_dict, factory):
        # arrange
        class_ = mock.ANY
        s3_bucket = mock.ANY
        mongo_client_uri = mock.ANY
        execution_date = datetime.today()

        # act
        with pytest.raises(RuntimeError):
            factory.factory(
                class_=class_,
                s3_bucket=s3_bucket,
                mongo_client_uri=mongo_client_uri,
                execution_date=execution_date
            )

        assert mock__dispatch_dict.call_count == 1
        assert mock__dispatch_dict.call_args[0][0] == class_
