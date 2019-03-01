from datetime import datetime

import mock
import pytest

from bietlejuice.jobs.etl.asterisk import AsteriskCDR, AsteriskCXPanelQueues, AsteriskCXPanelUsers, AsteriskDevices, \
    AsteriskFactory, AsteriskIVRDetails, AsteriskIVREntries, AsteriskQueuesConfig, AsteriskQueuesDetails, \
    AsteriskTableEnum, AsteriskUsers


class TestAsteriskFactory(object):

    @pytest.mark.parametrize('class_, expected', [
        (AsteriskTableEnum.IVR_DETAILS, AsteriskIVRDetails),
        (AsteriskTableEnum.IVR_ENTRIES, AsteriskIVREntries),
        (AsteriskTableEnum.USERS, AsteriskUsers),
        (AsteriskTableEnum.DEVICES, AsteriskDevices),
        (AsteriskTableEnum.QUEUES_CONFIG, AsteriskQueuesConfig),
        (AsteriskTableEnum.QUEUES_DETAILS, AsteriskQueuesDetails),
        (AsteriskTableEnum.CXPANEL_QUEUES, AsteriskCXPanelQueues),
        (AsteriskTableEnum.CXPANEL_USERS, AsteriskCXPanelUsers),
        (AsteriskTableEnum.CDR, AsteriskCDR)
    ])
    def test_factory(self, class_, expected):
        # arrange
        s3_bucket = mock.ANY
        execution_date = datetime.today()

        # act
        result = AsteriskFactory.factory(class_, s3_bucket, execution_date)

        # assert
        assert isinstance(result, expected)

    def test_factory_with_invalid_class(self):
        # arrange
        s3_bucket = mock.ANY
        execution_date = datetime.today()
        class_ = mock.ANY

        # act & assert
        with pytest.raises(RuntimeError):
            AsteriskFactory.factory(class_, s3_bucket, execution_date)
