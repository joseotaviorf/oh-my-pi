from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.loaders.teravoz import TeravozCallsLoader

logger = QuintoAndarLogger('TeravozFactory')

class TeravozFactory():

    @staticmethod
    def factory(entity, api_user, api_pwd, execution_date):
        if entity is None:
            raise ValueError('m=factory, class_={}, msg=entity cannot be None')
        class_ = TeravozFactory.__dispatch_dict(entity)
        if not class_:
            raise RuntimeError('m=factory, entity={}, msg=class type for entity not found'.format(entity))
        return class_(
            api_user=api_user,
            api_pwd=api_pwd,
            execution_date=execution_date
        )

    @staticmethod
    def __dispatch_dict(entity):
        return {
            "calls": TeravozCallsLoader,
        }.get(entity)
