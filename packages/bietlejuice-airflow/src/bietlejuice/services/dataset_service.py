import json
import re
from datetime import datetime
from typing import Any, Dict, List, Optional, Union

import boto3
import requests
from airflow.datasets import Dataset
from airflow.exceptions import AirflowException
from airflow.models import Variable
from airflow.models.dataset import DatasetEvent
from airflow.utils.context import Context
from airflow.utils.db import create_session
from airflow.utils.session import provide_session
from airflow.utils.types import DagRunType
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from bietlejuice.base.airflow.datasets.dataset_parser import DatasetParser
from bietlejuice.base.airflow.enums.dag_run_type_enum import DagRunTypeEnum
from bietlejuice.base.db.datalake_metastore_mapping import TRANSFORMATION_GRADES
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from bietlejuice.base.dependencies.bietlejuice_redundant_dependency_finder import (
    BietlejuiceRedundantDependencyFinder,
)
from bietlejuice.services.cid_fanout import AirflowDatasetFanout


class DatasetService:
    _LAYER_TO_DATABASE_NAME = {
        "transactional": "datalake_{schema}_transactional",
        "raw": "datalake_{schema}_raw",
        "clean": "datalake_{schema}_clean",
        "clean_staging": "datalake_{schema}_clean_staging",
        "core": "{schema}",
        "enrich": "datalake_{schema}",
        "dw": "dw_{schema}",
        "dw_staging": "dw_{schema}_staging",
        "metric": "metric_{schema}",
        "reverse": "reverse_{schema}",
        "qube": "qube_{schema}",
        # Prefix-free, matching DatalakeMetastoreMapping.
        "consumption": "{schema}",
        "wonka": "wonka",
        "transformation": "transformation_{schema}_{transformation_grade}",
    }

    @classmethod
    def _build_table_dataset_name(cls, context: Context) -> Optional[str]:
        """
        Build a qualified table dataset name from task params.
        Returns ``<database_name>.<table_name>`` in lowercase when schema,
        layer and table_name are all present in context params, or ``None``
        otherwise. Lowercasing aligns with lake naming and task_id slugify.
        """
        params = context.get("params", {})
        schema = params.get("schema")
        layer = params.get("layer")
        table_name = params.get("table_name")
        if not schema or not layer or not table_name:
            return None
        template = cls._LAYER_TO_DATABASE_NAME.get(layer)
        if template is None:
            return None
        if layer == "transformation":
            grade = params.get("transformation_grade")
            if grade not in TRANSFORMATION_GRADES:
                return None
            database_name = template.format(schema=schema, transformation_grade=grade)
        else:
            database_name = template.format(schema=schema)
        return f"{database_name}.{table_name}".lower()

    @staticmethod
    def format_alert_message(context):
        return {
            "cardsV2": [
                {
                    "cardId": "dataset_service_alert",
                    "card": {
                        "header": {
                            "title": "🚨 Dataset Alerts 🚨",
                            "subtitle": f"{context['task_instance'].dag_id}:{context['task_instance'].task_id}",
                            "imageUrl": "https://media.licdn.com/dms/image/v2/D560BAQGNzZcOWa-Afw/company-logo_200_200/B56ZXuOuLWGoAM-/0/1743458591974/astronomer_logo?e=2147483647&v=beta&t=ubbCJrPu9UU_FD1IR4IND8n7C98VulEVuInTFpEgR_s",
                            "imageType": "CIRCLE",
                        },
                        "sections": [
                            {
                                "widgets": [
                                    {
                                        "textParagraph": {
                                            "text": f"The task <b>'{context['task_instance'].task_id}'</b> from the DAG <b>'{context['task_instance'].dag_id}'</b> and run_id <b>'{context['task_instance'].run_id}'</b> couldn't generate the Dataset event."
                                        }
                                    }
                                ]
                            }
                        ],
                    },
                }
            ]
        }

    @staticmethod
    def format_dataset_alias(dag_id: str, task_id: str) -> str:
        """Based on Dataset name, format into dataset alias pattern."""
        return f"{dag_id}:{task_id}:alias"

    @staticmethod
    def transform_alias_into_dataset_name(dataset_alias: str) -> str:
        """Transform Dataset alias into Dataset name."""

        return dataset_alias.replace(":alias", "")

    @classmethod
    def get_dag_datasets(cls, dag_id: str) -> Dataset:
        """
        Reads dependencies file, get all DAG dependencies Datasets and apply logic for reprocessing datasets.
        It identifies redundant dependencies automatically.
        """
        dependencies = BietlejuiceDependencyHelper.read_dependencies()
        if dag_id not in dependencies:
            return None
        redundant_dependency_finder = BietlejuiceRedundantDependencyFinder(dependencies)
        redundant_dependencies = (
            redundant_dependency_finder.find_redundant_dependencies(dag_id)
        )
        return DatasetService.get_dag_datasets_from_dependencies(
            dependencies[dag_id], redundant_dependencies
        )

    @staticmethod
    def get_dag_datasets_from_dependencies(
        dependencies: Union[dict, list], redundant_dependencies: list = None
    ) -> Dataset:
        """
        Given the dependency list, or an object with "any" or "all" keys, assemble the DAG Datasets and apply logic for reprocessing datasets.
        Optionally, you can provide a list of dependencies that were identified as redundant. These will be removed from the "reprocessing"
        section of the dataset logic, to avoid triggering the dependent DAG multiple times.
        """

        if not dependencies:
            return None

        # We're creating all the logic as a dictionary and then parsing the dictionary into a Dataset object
        # That's because we later want to allow custom logic to be defined in the dependencies file
        # So it will be easier to treat everything as a dictionary and then parse it into a Dataset object
        dict_dataset_expression = (
            DatasetService.get_dataset_as_dict_expression_from_dependencies(
                dependencies, redundant_dependencies
            )
        )
        return DatasetParser.parse_dict_expression_as_dataset(dict_dataset_expression)

    @classmethod
    def get_dataset_as_dict_expression_from_dependencies(
        cls, dependencies: Union[dict, list], redundant_dependencies: list = None
    ) -> dict:
        """
        Reads the dependencies (i.e., list of strings in the format <dag_id>:<task_id>,
        or a dict in the formats {"any": []} or {"all": []} with the same format inside the list),
        and returns a dict expression that represents the dataset dependencies.

        For example, the list
        - ["dag1:task1", "dag1:task2", "dag2:task1"]

        Will be transformed into the following dict expression:
        {"any": [
            {"all": ["dag1:task1", "dag1:task2", "dag2:task1"]},
            {"any": [
                "dag1:task1:reprocessing",
                "dag1:task2:reprocessing",
                "dag2:task1:reprocessing"
            ]}
        ]

        And the dict
        {"any": ["dag1:task1", "dag1:task2", "dag2:task1"]}
        Will be transformed into the following dict expression:
        {"any": [
            {"all": ["dag1:task1", "dag1:task2", "dag2:task1"]},
            {"any": [
                "dag1:task1:reprocessing",
                "dag1:task2:reprocessing",
                "dag2:task1:reprocessing"
            ]}
        ]

        Notice that we will trigger the dependent when either:
        1. All dependencies have run since the last execution
        or
        2. Any of the dependencies was reprocessed.

        Optionally, you can provide a list of dependencies that were identified as redundant. These will be removed from the "reprocessing"
        section of the dataset logic, to avoid triggering the dependent DAG multiple times.

        For example, if we have the following dependencies:
        - ["dag1:task1", "dag1:task2", "dag2:task1"]
        And we have the following redundant dependencies:
        - ["dag1:task1"]
        The resulting dict expression will be:
        {"any": [
            {"all": ["dag1:task1", "dag1:task2", "dag2:task1"]},
            {"any": [
                "dag1:task2:reprocessing",
                "dag2:task1:reprocessing"
            ]}
        ]
        }
        """

        if not dependencies:
            return None

        # DAGs are triggered in two circumstances:
        # When all dependencies have run since the last execution
        if isinstance(dependencies, list):
            dag_datasets = {"all": dependencies}
        elif isinstance(dependencies, dict):
            dag_datasets = dependencies
        else:
            raise ValueError(f"Invalid dependencies type: {type(dependencies)}")

        # Or when any of the dependencies was reprocessed (i.e., a dataset with the ":reprocessing" suffix was updated)
        dag_datasets_reprocessing = {"any": []}

        unique_dependencies_without_redundancies = (
            cls._find_unique_dependencies_without_redundancies(
                dependencies, redundant_dependencies
            )
        )
        dag_datasets_reprocessing["any"].extend(
            [
                f"{task}:reprocessing"
                for task in unique_dependencies_without_redundancies
            ]
        )

        return {"any": [dag_datasets, dag_datasets_reprocessing]}

    @classmethod
    def _find_unique_dependencies_without_redundancies(
        cls, dependencies: Union[dict, list], redundant_dependencies: list = None
    ) -> set:
        """
        Given either a list of dependencies or a dict with "any" or "all" keys,
        return a set of unique dependencies.

        Optionally, you can provide a list of dependencies that were identified as redundant. These will be removed.
        """
        unique_dependencies = (
            BietlejuiceDependencyHelper.find_unique_dependencies_in_dependency_object(
                dependencies
            )
        )
        redundant_dependencies = redundant_dependencies or []
        return set(unique_dependencies) - set(redundant_dependencies)

    @classmethod
    def is_reprocessing_run(cls, context: Context) -> bool:
        """Check if the DAG run is a reprocessing or if the event that triggered the DAG was a reprocessing."""
        # Manually marked as reprocessing when the DAG was triggered

        run_type = cls._get_run_type(context)
        if run_type == DagRunTypeEnum.REPROCESSING_RUN:
            return True

        for triggering_event_name in context.get("triggering_dataset_events", {}):
            # If a reprocessing event caused this DAG to trigger, this DAG should also be marked as reprocessing
            if triggering_event_name.endswith(":reprocessing"):
                return True
        return False

    @staticmethod
    def find_reprocessing_source(context: Context) -> str:
        for triggering_event_name, triggering_events in context.get(
            "triggering_dataset_events", {}
        ).items():
            if triggering_event_name.endswith(":reprocessing"):
                # We find the source of the reprocessing event using the extra field
                # If the extra field is not set, we assume the source is the DAG ID
                reprocessing_source = triggering_events[0].extra.get(
                    "reprocessing_source", triggering_events[0].source_dag_id
                )
                if reprocessing_source is None:
                    # May happen if the event was triggered manually
                    # Fallback to the DAG ID from the event name
                    return triggering_event_name.split(":")[0]
                else:
                    return reprocessing_source

        # If it hasn't returned yet, it means the reprocessing was triggered manually
        # The source is the current DAG ID
        return context["dag"].dag_id

    @staticmethod
    def find_reprocessing_date(context: Context) -> str:
        """
        Returns the date of the original reprocessing event that lead to this DAG run.
        We need this because we have a convention that the reprocessing event won't apply
        to future dates.
        """

        for triggering_event_name, triggering_events in context.get(
            "triggering_dataset_events", {}
        ).items():
            if triggering_event_name.endswith(":reprocessing"):
                # We find the date of the reprocessing event using the extra field
                # If the extra field is not set, we assume the date is the current date
                return triggering_events[0].extra.get(
                    "reprocessing_date", datetime.now().date().isoformat()
                )

        # If it hasn't returned yet, it means the reprocessing was triggered manually
        # The date is the current date
        return datetime.now().date().isoformat()

    @classmethod
    def _is_impacting_downstream_dependents(cls, context: Context) -> bool:
        """Check if the DAG run will impact downstream dependendents."""
        # If the param run_type is not defined, we consider that will not impact downstream dependents.
        run_type = cls._get_run_type(context)

        return run_type == DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS

    @staticmethod
    def _get_run_type(context: Context) -> DagRunTypeEnum:
        """
        Get the run type of the DAG run based on the context.
        If it is an automatic run (scheduled, dataset or mediator triggered), the default run type is set to
        `IMPACT_DOWNSTREAM_DEPENDENTS`. If it is a manual run, the run type is set to `TEST_RUN` unless it was
        triggered with a specific run type parameter.
        """
        run_type = DagRunTypeEnum(
            context.get("params", {}).get("run_type", DagRunTypeEnum.DEFAULT.value)
        )
        if run_type != DagRunTypeEnum.DEFAULT:
            # If the run type was explicitly set, we use it
            return run_type
        elif context["dag_run"].run_type in (
            DagRunType.SCHEDULED,
            DagRunType.DATASET_TRIGGERED,
        ) or context["dag_run"].run_id.startswith("mediator_trig__"):
            # If it's an automatic run, we set the run type to `IMPACT_DOWNSTREAM_DEPENDENTS`
            return DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
        else:
            return DagRunTypeEnum.TEST_RUN

    @staticmethod
    def _build_dataset_event_payload(
        context: Context,
        dataset_name: str,
        dataset_alias: str,
        event_type: str,
        extra: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Build a JSON-serializable dict for one dataset event (for S3 list-of-dicts)."""
        ti = context.get("task_instance") or context.get("ti")
        if ti is None:
            return {}
        dag_run = context.get("dag_run") or getattr(ti, "dag_run", None)
        data_interval_start = None
        data_interval_end = None
        if (
            dag_run
            and hasattr(dag_run, "data_interval_start")
            and dag_run.data_interval_start
        ):
            data_interval_start = dag_run.data_interval_start.isoformat()
        if (
            dag_run
            and hasattr(dag_run, "data_interval_end")
            and dag_run.data_interval_end
        ):
            data_interval_end = dag_run.data_interval_end.isoformat()
        return {
            "dag_id": ti.dag_id,
            "task_id": ti.task_id,
            "run_id": ti.run_id,
            "dataset_name": dataset_name,
            "dataset_alias": dataset_alias,
            "event_type": event_type,
            "ts": datetime.utcnow().isoformat() + "Z",
            "data_interval_start": data_interval_start,
            "data_interval_end": data_interval_end,
            "extra": extra or {},
        }

    @staticmethod
    def _get_boto3_session_for_dataset_events():
        """
        Return a boto3 session for S3/STS used by dataset events.
        If Variable DATASET_EVENTS_ASSUME_ROLE_ARN is set, assumes that role and returns
        a session with the assumed credentials; otherwise uses default credentials.
        """
        role_arn = Variable.get("DATASET_EVENTS_ASSUME_ROLE_ARN", None)
        if not role_arn:
            return boto3.Session()
        sts = boto3.client("sts")
        response = sts.assume_role(
            RoleArn=role_arn,
            RoleSessionName="airflow-dataset-events",
            DurationSeconds=3600,
        )
        creds = response["Credentials"]
        return boto3.Session(
            aws_access_key_id=creds["AccessKeyId"],
            aws_secret_access_key=creds["SecretAccessKey"],
            aws_session_token=creds["SessionToken"],
        )

    @staticmethod
    def _write_dataset_events_to_s3(events: List[Dict[str, Any]]) -> None:
        """
        Write a list of dataset event dicts to S3 as one JSON array (Spark-friendly).
        Bucket from Airflow Variable DATASET_EVENTS_S3_BUCKET (bucket name only, no s3:// prefix); if unset or events empty, no-op.
        If Variable DATASET_EVENTS_ASSUME_ROLE_ARN is set, assumes that IAM role before calling S3/STS.
        Path: airflow_datasets/dataset_events/year=YYYY/month=MM/day=DD/<run_id>_<dag_id>_<task_id>_<ts>.json
        """
        bucket = Variable.get("DATASET_EVENTS_S3_BUCKET", None)
        if not bucket or not events:
            print(
                f"m=write_dataset_events_to_s3, msg=Skipping S3 write. bucket={bucket!r}, events_count={len(events)}"
            )
            return
        object_key = None
        try:
            session = DatasetService._get_boto3_session_for_dataset_events()
            sts = session.client("sts")
            identity = sts.get_caller_identity()
            print(
                f"m=write_dataset_events_to_s3, msg=AWS caller identity (dataset post action): {identity}"
            )
            first = events[0]
            ts = str(first.get("ts", datetime.utcnow().isoformat() + "Z"))
            run_id = str(first.get("run_id", ""))
            dag_id = str(first.get("dag_id", ""))
            task_id = str(first.get("task_id", ""))
            ts_safe = re.sub(r"[^\w\-.:]", "_", ts)[:26]
            run_id_safe = re.sub(r"[^\w\-]", "_", run_id)[:64]
            dag_id_safe = re.sub(r"[^\w\-]", "_", dag_id)[:64]
            task_id_safe = re.sub(r"[^\w\-]", "_", task_id)[:64]
            year, month, day = ts[:4], ts[5:7], ts[8:10]
            object_key = (
                f"airflow_datasets/dataset_events/year={year}/month={month}/day={day}"
                f"/{run_id_safe}_{dag_id_safe}_{task_id_safe}_{ts_safe}.json"
            )
            print(
                f"m=write_dataset_events_to_s3, msg=Writing dataset events to S3. bucket={bucket!r}, key={object_key!r}, events_count={len(events)}"
            )
            body = json.dumps(events, default=str)
            client = session.client("s3")
            client.put_object(
                Bucket=bucket,
                Key=object_key,
                Body=body,
                ContentType="application/json",
            )
            print(
                f"m=write_dataset_events_to_s3, msg=Wrote dataset events to S3. bucket={bucket!r}, key={object_key!r}"
            )
        except Exception as e:
            print(
                f"m=write_dataset_events_to_s3, msg=Failed to write dataset events to S3. bucket={bucket!r}, key={object_key!r}, error={e}"
            )

    @staticmethod
    def archive_dataset_events_to_s3(events: List[Dict[str, Any]]) -> str:
        """Durably archive DatasetEvent rows to S3 as one JSON array before deletion.
        Raises if the bucket is unset or the write fails, so callers can skip deletion.
        Returns the written object key. Path:
        airflow_datasets/dataset_events_reset_archive/year=YYYY/month=MM/day=DD/reset_<ts>.json
        """
        bucket = Variable.get("DATASET_EVENTS_S3_BUCKET", None)
        if not bucket:
            raise AirflowException(
                "Variable DATASET_EVENTS_S3_BUCKET is not set; cannot archive dataset events"
            )
        session = DatasetService._get_boto3_session_for_dataset_events()
        ts = datetime.utcnow().isoformat() + "Z"
        year, month, day = ts[:4], ts[5:7], ts[8:10]
        ts_safe = re.sub(r"[^\w\-.:]", "_", ts)[:26]
        object_key = f"airflow_datasets/dataset_events_reset_archive/year={year}/month={month}/day={day}/reset_{ts_safe}.json"
        body = json.dumps(events, default=str)
        session.client("s3").put_object(
            Bucket=bucket,
            Key=object_key,
            Body=body,
            ContentType="application/json",
        )
        return object_key

    @classmethod
    def update_datasets(cls, context: Context) -> None:
        """
        This method is used as a callback to update the datasets after the task has run.

        Here are the rules for updating the datasets:
        - If this is a clear rerun and the dataset was updated before, we do not update it again.
        - If this is a reprocessing run, we update the dataset with a ":reprocessing" suffix.
        - If this is a run that will impact downstream dependents, we update the dataset without a suffix. We
        also update the dataset with a ":first-run-of-day" suffix if this is the first run of the day for this DAG.
        """
        try:
            if cls._has_updated_dataset_before(context):
                # If the dataset was updated before, we should not update it again.
                print("Dataset was updated before, skipping update.")
                return

            is_first_run_of_date = cls._is_first_run_of_date(context)

            dataset_alias = context["outlets"][0].name
            dataset_name = DatasetService.transform_alias_into_dataset_name(
                dataset_alias=dataset_alias
            )

            event_payloads: List[Dict[str, Any]] = []
            table_dataset_name = cls._build_table_dataset_name(context)

            if DatasetService.is_reprocessing_run(context):
                reprocessing_date = DatasetService.find_reprocessing_date(context)
                if reprocessing_date < datetime.now().date().isoformat():
                    print(
                        f"Reprocessing date is in the past ({reprocessing_date}), skipping dataset update."
                    )
                else:
                    print(
                        "This is a reprocessing run, updating the dataset with ':reprocessing' suffix."
                    )
                    extra_reprocessing = {
                        # The downstream DAGs can use this to know which DAG initially triggered the reprocessing
                        # This is useful to avoid triggering the same DAG multiple times, and for debugging purposes
                        "reprocessing_source": DatasetService.find_reprocessing_source(
                            context
                        ),
                        "reprocessing_date": reprocessing_date,
                    }
                    context["outlet_events"][dataset_alias].add(
                        Dataset(f"{dataset_name}:reprocessing"),
                        extra=extra_reprocessing,
                    )
                    event_payloads.append(
                        cls._build_dataset_event_payload(
                            context,
                            f"{dataset_name}:reprocessing",
                            dataset_alias,
                            "reprocessing",
                            extra_reprocessing,
                        )
                    )
                    if table_dataset_name:
                        context["outlet_events"][dataset_alias].add(
                            Dataset(f"{table_dataset_name}:reprocessing"),
                            extra=extra_reprocessing,
                        )
                        event_payloads.append(
                            cls._build_dataset_event_payload(
                                context,
                                f"{table_dataset_name}:reprocessing",
                                dataset_alias,
                                "reprocessing",
                                extra_reprocessing,
                            )
                        )
            elif DatasetService._is_impacting_downstream_dependents(context):
                print(
                    "This run will impact downstream dependents, updating the dataset without a suffix."
                )
                context["outlet_events"][dataset_alias].add(Dataset(dataset_name))
                event_payloads.append(
                    cls._build_dataset_event_payload(
                        context, dataset_name, dataset_alias, "normal", {}
                    )
                )
                if table_dataset_name:
                    context["outlet_events"][dataset_alias].add(
                        Dataset(table_dataset_name)
                    )
                    event_payloads.append(
                        cls._build_dataset_event_payload(
                            context,
                            table_dataset_name,
                            dataset_alias,
                            "normal",
                            {},
                        )
                    )
                if is_first_run_of_date:
                    # Let's imagine we have a DAG A that is intraday,
                    # DAG B depends on DAG A, but DAG B only needs to run once (it is not intraday).
                    # It can use the dataset with a suffix of ":first-run-of-day" to trigger the DAG only once.
                    print(
                        "This is the first run of the day, updating the dataset with ':first-run-of-day' suffix."
                    )
                    context["outlet_events"][dataset_alias].add(
                        Dataset(f"{dataset_name}:first-run-of-day")
                    )
                    event_payloads.append(
                        cls._build_dataset_event_payload(
                            context,
                            f"{dataset_name}:first-run-of-day",
                            dataset_alias,
                            "first_run_of_day",
                            {},
                        )
                    )
                    if table_dataset_name:
                        context["outlet_events"][dataset_alias].add(
                            Dataset(f"{table_dataset_name}:first-run-of-day")
                        )
                        event_payloads.append(
                            cls._build_dataset_event_payload(
                                context,
                                f"{table_dataset_name}:first-run-of-day",
                                dataset_alias,
                                "first_run_of_day",
                                {},
                            )
                        )

            try:
                cls._write_dataset_events_to_s3(event_payloads)
            except Exception:
                pass

            try:
                AirflowDatasetFanout.fanout(event_payloads)
            except Exception as fanout_error:
                print(
                    "m=update_datasets, msg=CID fan-out failed unexpectedly. "
                    f"error={fanout_error}"
                )
        except Exception as e:
            webhook_url = Variable.get("DLC_GCHAT_DATASET_EVENTS", None)
            payload = DatasetService.format_alert_message(context)
            print(f"m=update_dataset, msg=Dataset has failed to update. error={e}")

            if webhook_url:
                print("Sending msg to GChat...")
                response = requests.post(webhook_url, json=payload)
                try:
                    response.raise_for_status()
                except Exception as e:
                    print(
                        f"m=send_message, msg=Gchat message was not sent, check"
                        f" the webhook url: {webhook_url}, payload: yes,"
                        f" error: {e}"
                    )
            else:
                print(
                    "Webhook token DLC_GCHAT_DATASET_EVENTS is not configured in Airflow Variables."
                )

    @staticmethod
    def _has_updated_dataset_before(context: Context) -> bool:
        """
        Check if the current task instance has updated the dataset before.
        If it has, we should not update the dataset again.
        """
        try:
            with create_session() as session:
                dataset_event = (
                    session.query(DatasetEvent)
                    .filter(DatasetEvent.source_task_instance == context["ti"])
                    .first()
                )
        except SQLAlchemyError as e:
            # If, for any reason, we cannot query the database,
            # it's safer to assume that the dataset was not updated before.
            # Otherwise, we might skip updating the dataset incorrectly.
            print(f"Error checking if dataset was updated before: {e}")
            return False

        return dataset_event is not None

    @provide_session
    def _is_first_run_of_date(context: dict, session=None) -> bool:
        """
        Check if the current DAG run is the first run of the day.
        This is used to determine if we should update the dataset with a suffix of ":first-run-of-day".
        """
        if not session:
            raise AirflowException("SQLAlchemy session not provided.")

        dataset_alias = context["outlets"][0].name
        dataset_name = DatasetService.transform_alias_into_dataset_name(
            dataset_alias=dataset_alias
        )
        start_date = context[
            "task_instance"
        ].start_date.isoformat()  # Convert datetime to ISO string for SQL comparison

        sql_query = text(
            """
            SELECT COUNT(de.id)
            FROM dataset_event de
            JOIN dataset d ON de.dataset_id = d.id
            WHERE
                d.uri LIKE :dataset_uri_prefix || :dataset_uri_suffix
                AND de.timestamp::date = :start_date_param;
        """
        )

        try:
            result = session.execute(
                sql_query,
                {
                    "dataset_uri_prefix": dataset_name,
                    "start_date_param": start_date,
                    "dataset_uri_suffix": ":first-run-of-day",
                },
            )
            first_run_event_count = result.scalar()
            return first_run_event_count == 0
        except Exception as e:
            # Log the error and re-raise as an AirflowException for better error handling in DAGs
            print(f"Error checking first run of the task '{context['ti'].task_id}: {e}")
            raise AirflowException(f"Failed to check first run of date: {e}")
