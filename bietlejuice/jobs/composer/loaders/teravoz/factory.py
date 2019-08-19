from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.loaders.teravoz import TeravozLoader, TeravozCallsLoader

logger = QuintoAndarLogger("TeravozFactory")


class TeravozFactory:
    @staticmethod
    def factory(table_name, api_user, api_pwd, environment, execution_date=None):
        if table_name is None:
            raise ValueError("m=factory, class_={}, msg=table_name cannot be None")
        class_ = TeravozFactory.__dispatch_dict(table_name)
        if not class_:
            raise RuntimeError(
                "m=factory, table_name={}, msg=class type for table_name not found".format(
                    table_name
                )
            )
        return class_(
            api_user=api_user,
            api_pwd=api_pwd,
            environment=environment,
            execution_date=execution_date,
        )

    @staticmethod
    def __dispatch_dict(table_name):
        return {
          "calls": TeravozCallsLoader,
          "queues": TeravozLoader,
          "peers": TeravozLoader,
          "ddrs": TeravozLoader
        }.get(table_name)
