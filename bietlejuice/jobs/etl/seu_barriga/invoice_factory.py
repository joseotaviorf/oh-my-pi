from bietlejuice.jobs.etl.seu_barriga.fine import SeuBarrigaFine
from bietlejuice.jobs.etl.seu_barriga.report import SeuBarrigaReport
from bietlejuice.jobs.etl.seu_barriga.seu_barriga_table_enum import SeuBarrigaTableEnum


class SeuBarrigaInvoiceFactory(object):

    @staticmethod
    def factory(_class, s3_bucket, api_dict, execution_date):
        __class = SeuBarrigaInvoiceFactory.__dispatch_dict(_class)
        return __class(
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
