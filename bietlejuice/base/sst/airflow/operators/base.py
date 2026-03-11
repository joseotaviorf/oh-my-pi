from airflow.operators.empty import EmptyOperator


class SStPlaceholderOperator(EmptyOperator):
    """
    An empty operator that can be used to represent a SST job.
    """

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def execute(self, context):
        pass
