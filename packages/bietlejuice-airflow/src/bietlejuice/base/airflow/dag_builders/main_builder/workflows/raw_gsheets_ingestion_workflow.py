from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.enums.task_enum import TaskEnum
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.airflow.task_creators.task_creator_factory import (
    TaskCreatorFactory,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class RawGsheetsIngestionWorkflow(BaseWorkflow):
    """Ingestão simples de Google Sheets em UMA etapa.

    Para cada planilha declarada em ``tables_customization``, lê a fonte e SOBRESCREVE
    (overwrite total) a tabela diretamente no schema final (clean), via o Spark job
    ``load_gsheets_full_overwrite``, e em seguida sincroniza a tabela no Hive metastore
    (catálogo que o Trino lê). Grafo:

        execute-job-cluster >> load-gsheets-<t> >> sync-metadata-clean-<t> >> dummy-job-cluster-finished

    O ``sync-metadata`` roda com ``--bypass-propagate`` (só hive sync, sem lineage/Atlas — que
    exigiria metadata files); Glue/Unity já é coberto pelo load. Resultado: tabela consultável no
    Databricks/Glue (load) e no Trino (hive sync).

    Diferente do ``RawGsheetsWorkflow`` (modelo antigo raw->clean->done com
    create-cluster/terminate-cluster), aqui:
      - NÃO há camada raw nem clean-SQL — escreve direto no schema final;
      - NÃO há ``validate_clean_query_against_raw`` (sem o falso-positivo do load-raw);
      - usa o **job cluster efêmero** do builder novo (sem terminate-cluster paralelo),
        então não existe a corrida que matava o sync-metadata-clean;
      - cada planilha muda no overwrite, então o schema da tabela acompanha a fonte.

    Declaração esperada:
        workflow:
          type: gsheets_ingestion
          layer: raw
          custom_schema: gsheets            # -> datalake_gsheets_clean
          tables_customization:
            minha_tabela:
              sheet_id: "<id da planilha>"
              sheet_name: "<aba>"
    """

    def build_dag(self):
        dag = super().dag_instance()

        bucket_config = self.workflow_args.get("bucket_config_name", "datalake_bucket")
        bucket = self.config_service.get_config(bucket_config)

        dag_execution_context = self._get_dag_execution_context(dag, bucket)
        self._initialize_task_creators(dag_execution_context)

        execute_job_cluster_task = self.execute_job_cluster_task_creator.create_task()
        dummy_job_cluster_finished_task = (
            self.dummy_job_cluster_finished_task_creator.create_task()
        )

        for table_name in self.workflow_args["tables_customization"]:
            # A tabela vive no schema final (clean): datalake_<custom_schema>_clean.<table>.
            # Layer CLEAN é o que o sync_metadata usa pra localizar a tabela no Hive metastore.
            table_attributes = TableAttributes(
                self.dag_args, self.workflow_args, LayerEnum.CLEAN, table_name
            )
            load_task = self.load_gsheets_task_creator.create_task(table_attributes)

            execute_job_cluster_task >> load_task
            last_table_task = load_task

            # Sync pro Hive metastore (catálogo que o Trino lê) só quando habilitado:
            # `_check_include_sync_hive_tasks` respeita os overrides `has_hive_sync`
            # (workflow/tabela) e desabilita o sync em DAGs de validação (is_validation).
            # `--bypass-propagate` pula o lineage/Atlas (que exigiria metadata files,
            # inexistentes neste fluxo single-step); o Glue/Unity já é coberto pelo load
            # (update_metastore -> sync_table_to_unity_catalog).
            if self._check_include_sync_hive_tasks(table_attributes):
                sync_trino_task = self.sync_metadata_task_creator.create_task(
                    table_attributes, bypass_task="--bypass-propagate"
                )
                load_task >> sync_trino_task
                last_table_task = sync_trino_task

            last_table_task >> dummy_job_cluster_finished_task

        return dag

    def _initialize_task_creators(self, dag_execution_context: DagExecutionContext):
        task_creator_factory = TaskCreatorFactory(dag_execution_context)

        self.execute_job_cluster_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.EXECUTE_JOB_CLUSTER, self.config_service
        )
        self.load_gsheets_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.LOAD_GSHEETS
        )
        self.sync_metadata_task_creator = task_creator_factory.get_task_creator(
            TaskEnum.SYNC_METADATA
        )
        self.dummy_job_cluster_finished_task_creator = (
            task_creator_factory.get_task_creator(TaskEnum.DUMMY_JOB_CLUSTER_FINISHED)
        )
