import yaml

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class ProfilingFromYaml:
    @staticmethod
    def get_profiling_data_quality(dag_name: str, layer: str, table_name: str) -> bool:
        """
        This function goes into data_quality files to check if there is a negative for dataset profiling there.

        :param dag_name: folder name in which is the queries and specifics spark jobs
        :type dag_name: str
        :param table_name: table name without schema
        :type table_name: str
        :param layer: QuintoAndar layer enums, sucha as clean, enrich, dw, etc
        :type layer: str
        """

        data_quality_yml = DAGPackagesPathService.get_data_quality_file_content_in_spark_jobs(
            dag_name=dag_name, layer=layer, table_name=table_name, intermediate_path=""
        )
        data_quality_yml_content = yaml.safe_load(data_quality_yml)
        return data_quality_yml_content.get("dataset_profiling", True)
