class BaseSubDag(object):

    def build(self):
        raise NotImplementedError("Should have implemented this")

    def __build_local_dag(self):
        raise NotImplementedError("Should have implemented this")

    def __build_data_tasks(self, dag):
        raise NotImplementedError("Should have implemented this")

    def __build_tests_tasks(self, dag):
        raise NotImplementedError("Should have implemented this")