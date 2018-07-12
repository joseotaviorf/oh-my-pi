from bietlejuice.jobs.new_etl.invoice.fines import Fine
from bietlejuice.jobs.new_etl.invoice.reports import Report


class InvoiceFactory(object):

    @staticmethod
    def factory(_class, **kwargs):
        __class = InvoiceFactory.__dispatch_dict(_class)
        return __class(
            bucket=kwargs['bucket'],
            api_dict=kwargs['api_dict'],
            execution_date=kwargs['execution_date']
        )

    @staticmethod
    def __dispatch_dict(_class):
        return {
            'report': Report,
            'fine': Fine
        }.get(_class, None)
