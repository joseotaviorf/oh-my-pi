import mock
import pytest

from bietlejuice.jobs.etl.demand import ActiveUserSessionsETL, ActiveUsersETL, DemandEnum, DemandFactory


class TestDemandFactory(object):

    @pytest.mark.parametrize('table, expected', [
        (DemandEnum.ACTIVE_USER_SESSIONS, ActiveUserSessionsETL),
        (DemandEnum.ACTIVE_USERS, ActiveUsersETL)
    ])
    def test_factory(self, table, expected):
        # arrange
        s3_bucket = mock.ANY

        # act
        result = DemandFactory.factory(table, s3_bucket)

        # assert
        assert isinstance(result, expected)

    def test_factory_with_invalid_table(self):
        # arrange
        table = mock.ANY
        s3_bucket = mock.ANY

        # act
        with pytest.raises(RuntimeError):
            DemandFactory.factory(table, s3_bucket)

    def test_factory_with_none_table(self):
        # arrange
        table = None
        s3_bucket = mock.ANY

        # act
        with pytest.raises(ValueError):
            DemandFactory.factory(table, s3_bucket)
