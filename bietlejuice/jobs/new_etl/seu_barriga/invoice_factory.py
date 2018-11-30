from bietlejuice.jobs.new_etl.seu_barriga.fines import SeuBarrigaFine
from bietlejuice.jobs.new_etl.seu_barriga.reports import SeuBarrigaReport
from bietlejuice.jobs.new_etl.seu_barriga.seu_barriga_table_enum import SeuBarrigaTableEnum


class SeuBarrigaInvoiceFactory(object):

    @staticmethod
    def factory(_class, **kwargs):
        __class = SeuBarrigaInvoiceFactory.__dispatch_dict(_class)
        return __class(
            bucket=kwargs['bucket'],
            api_dict=kwargs['api_dict'],
            execution_date=kwargs['execution_date']
        )

    @staticmethod
    def __dispatch_dict(_class):
        return {
            SeuBarrigaTableEnum.REPORT: SeuBarrigaReport,
            SeuBarrigaTableEnum.FINE: SeuBarrigaFine
        }.get(_class, None)
