from bietlejuice.jobs.etl.seu_barriga.fine import SeuBarrigaFine
from bietlejuice.jobs.etl.seu_barriga.report import SeuBarrigaReport
from bietlejuice.jobs.etl.seu_barriga.seu_barriga_table_enum import SeuBarrigaTableEnum


class SeuBarrigaInvoiceFactory(object):

    @staticmethod
    def factory(class_, s3_bucket, api_dict, execution_date):
        if class_ is None or not class_:
            raise TypeError('m=factory, class_={}, msg=invalid class'.format(class_))

        _class = SeuBarrigaInvoiceFactory.__dispatch_dict(class_)
        if _class is None:
            raise RuntimeError('m=factory, class_={}, msg=class type not found'.format(class_))

        return _class(
            s3_bucket=s3_bucket,
            api_dict=api_dict,
            execution_date=execution_date
        )

    @staticmethod
    def __dispatch_dict(_class):
        return {
            SeuBarrigaTableEnum.REPORT: SeuBarrigaReport,
            SeuBarrigaTableEnum.FINE: SeuBarrigaFine
        }.get(_class)
