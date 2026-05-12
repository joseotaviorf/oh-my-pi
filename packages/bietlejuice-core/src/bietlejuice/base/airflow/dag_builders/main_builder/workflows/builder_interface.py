from abc import ABC


class BuilderInterface(ABC):
    def build_dag(self):
        """
        Implements the tasks that will be necessary for a certain workflow.
        """
        raise NotImplementedError()

    def dag_instance(self):
        """
        The method will need to be used by all workflows for the declaration of the DAG.
        """
        raise NotImplementedError()
