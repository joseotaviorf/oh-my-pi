from datetime import datetime

import mock
import pytest

from bietlejuice.jobs.etl.planner import PlannerAgent, PlannerFactory, PlannerRegion, PlannerTableEnum


class TestPlannerFactory(object):

    @pytest.mark.parametrize('table, expected', [
        (PlannerTableEnum.AGENT, PlannerAgent),
        (PlannerTableEnum.REGION, PlannerRegion)
    ])
    def test_factory(self, table, expected):
        # arrange
        s3_bucket = mock.ANY
        execution_date = datetime.today()

        # act
        result = PlannerFactory.factory(table, s3_bucket, execution_date)

        # assert
        assert isinstance(result, expected)

    def test_factory_with_table_none(self):
        # arrange
        table = None
        s3_bucket = mock.ANY
        execution_date = mock.ANY

        # act
        with pytest.raises(ValueError):
            PlannerFactory.factory(table, s3_bucket, execution_date)

    def test_factory_with_invalid_table(self):
        # arrange
        table = mock.ANY
        s3_bucket = mock.ANY
        execution_date = mock.ANY

        # act
        with pytest.raises(RuntimeError):
            PlannerFactory.factory(table, s3_bucket, execution_date)
