from bietlejuice.jobs.composer.services import ConfigurationService


class MetadataService:
    """
    Service to provide operations about governance metadata definitions in dags or tables
    """

    def dag_has_lineage_from_product_config(
        self, source: str, context: str, dag_name: str, env: str
    ) -> bool:
        """
        Checks if a dag has a valid lineage from product configuration
        :param source: The DAG source
        :param context: The DAG context
        :param dag_name:  The DAG name
        :param env: The environment to check for the variable
        :return: True if it has a confif, else False
        :rtype: bool
        """
        if source == context and context == dag_name:
            intermediate_path = None
        else:
            intermediate_path = f"{source}/{context}"

        configs = ConfigurationService(
            dag_name, intermediate_path=intermediate_path, env=env
        )
        try:
            configs.get_config("lineage_product_database_name")
            return True
        except IndexError:
            return False
