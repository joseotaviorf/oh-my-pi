from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.teravoz import (
    TeravozConsumer,
    TeravozCallsConsumer,
    TeravozReportsConsumer,
    TeravozReportAgentStatusConsumer,
)

logger = QuintoAndarLogger("TeravozFactoryConsumer")


class TeravozFactoryConsumer:
    @staticmethod
    def factory(endpoint, api_user, api_pwd, execution_date):
        if endpoint is None:
            raise ValueError("m=factory, class_={}, msg=endpoint can't be None")
        class_ = TeravozFactoryConsumer.__dispatch_dict(endpoint)
        if not class_:
            raise RuntimeError(
                "m=factory, endpoint={}, msg=class type for endpoint not found".format(
                    endpoint
                )
            )
        return class_(api_user=api_user, api_pwd=api_pwd, execution_date=execution_date)

    @staticmethod
    def __dispatch_dict(endpoint):
        return {
            "calls": TeravozCallsConsumer,
            "queues": TeravozConsumer,
            "peers": TeravozConsumer,
            "ddrs": TeravozConsumer,
            "report-agent-performance": TeravozReportsConsumer,
            "report-queue-stats": TeravozReportsConsumer,
            "report-agent-status": TeravozReportAgentStatusConsumer,
        }.get(endpoint)
