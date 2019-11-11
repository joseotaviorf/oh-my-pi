from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.api_consumers.teravoz.teravoz_calls_consumer import (
    TeravozCallsConsumer,
)
from bietlejuice.jobs.composer.consumers.api_consumers.teravoz.teravoz_consumer import (
    TeravozConsumer,
)
from bietlejuice.jobs.composer.consumers.api_consumers.teravoz.teravoz_report_agent_status_consumer import (
    TeravozReportAgentStatusConsumer,
)
from bietlejuice.jobs.composer.consumers.api_consumers.teravoz.teravoz_reports_consumer import (
    TeravozReportsConsumer,
)

logger = QuintoAndarLogger("TeravozFactoryConsumer")


class TeravozFactoryConsumer:
    @staticmethod
    def factory(teravoz_client, spark_client, endpoint, execution_date):
        if endpoint is None:
            raise ValueError("m=factory, class_={}, msg=endpoint can't be None")
        class_ = TeravozFactoryConsumer.__dispatch_dict(endpoint)
        if not class_:
            raise RuntimeError(
                "m=factory, endpoint={}, msg=class type for endpoint not found".format(
                    endpoint
                )
            )
        return class_(teravoz_client, spark_client, execution_date)

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
