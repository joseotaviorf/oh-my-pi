from datetime import datetime

import mock
import pytest

from bietlejuice.jobs.etl.seu_barriga import SeuBarrigaTableEnum, SeuBarrigaReport, SeuBarrigaFine


class TestInvoiceFactory(object):
    @pytest.mark.parametrize('enum, expected', [
        (SeuBarrigaTableEnum.REPORT, SeuBarrigaReport),
        (SeuBarrigaTableEnum.FINE, SeuBarrigaFine)
    ])
    def test_factory(self, enum, expected, seu_barriga_invoice_factory):
        # arrange
        s3_bucket = mock.ANY
        execution_date = datetime.today()
        api_dict = mock.ANY

        # act
        result = seu_barriga_invoice_factory.factory(
            class_=enum,
            s3_bucket=s3_bucket,
            api_dict=api_dict,
            execution_date=execution_date
        )

        # assert
        assert isinstance(result, expected)

    @pytest.mark.parametrize('enum', ['', None])
    def test_factory_with_class_enum_invalid(self, enum, seu_barriga_invoice_factory):
        # arrange
        s3_bucket = mock.ANY
        execution_date = datetime.today()
        api_dict = mock.ANY

        # act
        with pytest.raises(TypeError):
            seu_barriga_invoice_factory.factory(
                class_=enum,
                s3_bucket=s3_bucket,
                api_dict=api_dict,
                execution_date=execution_date
            )

    @pytest.mark.parametrize('enum', [mock.ANY])
    def test_factory_with_table_none(self, enum, seu_barriga_invoice_factory):
        # arrange
        s3_bucket = mock.ANY
        execution_date = datetime(2019, 1, 1)
        api_dict = mock.ANY

        # act
        with pytest.raises(RuntimeError):
            seu_barriga_invoice_factory.factory(
                class_=enum,
                s3_bucket=s3_bucket,
                api_dict=api_dict,
                execution_date=execution_date
            )
