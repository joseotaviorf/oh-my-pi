"""Cross-instance dataset fan-out to satellite Airflow instances (CID).

After the principal ``DatasetService`` emits dataset events locally, this module
can forward table-qualified events to satellite Airflow REST APIs via
``POST /api/v1/datasets/events``.

The consumer registry is opt-in: when ``CID_CONSUMER_REGISTRY`` is unset or has
no enabled consumers, ``fanout`` is a no-op and upstream behavior is unchanged.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import requests
from airflow.models import Variable
from airflow.utils.context import Context

CID_CONSUMER_REGISTRY_VARIABLE = "CID_CONSUMER_REGISTRY"
CID_FANOUT_ALERT_VARIABLE = "DLC_GCHAT_CID_FANOUT"
DATASET_EVENTS_ALERT_VARIABLE = "DLC_GCHAT_DATASET_EVENTS"

_TABLE_DATASET_URI_PATTERN = re.compile(
    r"^(?:datalake_|dw_|metric_|core_|reverse_|wonka\.)"
)


class DatasetNotRegisteredOnSatellite(Exception):
    """Raised when the satellite Airflow API returns HTTP 404 for a dataset URI."""


@dataclass(frozen=True)
class CidConsumer:
    name: str
    airflow_api_base_url: str
    api_token: str
    enabled: bool = True


class AirflowDatasetFanout:
    @classmethod
    def fanout(cls, event_payloads: List[Dict[str, Any]]) -> None:
        """Forward dataset events to enabled satellite consumers.

        Never raises to callers: 404 responses are logged as warnings; other
        errors trigger alerts only.
        """
        consumers = cls._load_enabled_consumers()
        if not consumers or not event_payloads:
            return

        for consumer in consumers:
            for event in event_payloads:
                dataset_uri = event.get("dataset_name")
                if not dataset_uri or not cls._is_table_qualified_dataset_uri(
                    dataset_uri
                ):
                    continue

                try:
                    cls._post_dataset_event(consumer, event)
                except DatasetNotRegisteredOnSatellite as exc:
                    print(
                        "m=cid_fanout, msg=Dataset not registered on satellite, skipping. "
                        f"consumer={consumer.name}, dataset_uri={dataset_uri}, detail={exc}"
                    )
                except Exception as exc:
                    cls._alert_fanout_failure(consumer, event, exc)

    @staticmethod
    def _load_enabled_consumers() -> List[CidConsumer]:
        raw_registry = Variable.get(CID_CONSUMER_REGISTRY_VARIABLE, None)
        if not raw_registry:
            return []

        try:
            registry = json.loads(raw_registry)
        except (TypeError, json.JSONDecodeError) as exc:
            print(
                "m=cid_fanout, msg=Invalid CID consumer registry JSON, skipping fan-out. "
                f"variable={CID_CONSUMER_REGISTRY_VARIABLE}, error={exc}"
            )
            return []

        entries = registry.get("consumers", registry)
        if isinstance(entries, dict):
            entries = [
                {"name": name, **config}
                for name, config in entries.items()
                if isinstance(config, dict)
            ]
        if not isinstance(entries, list):
            print(
                "m=cid_fanout, msg=Invalid CID consumer registry shape, skipping fan-out."
            )
            return []

        consumers: List[CidConsumer] = []
        for entry in entries:
            if not isinstance(entry, dict) or not entry.get("enabled", False):
                continue

            name = entry.get("name")
            base_url = entry.get("airflow_api_base_url")
            if not name or not base_url:
                print(
                    "m=cid_fanout, msg=Skipping consumer with missing name or base URL. "
                    f"entry={entry!r}"
                )
                continue

            api_token = entry.get("api_token")
            if not api_token:
                token_variable = entry.get("api_token_variable")
                if token_variable:
                    api_token = Variable.get(token_variable, None)

            if not api_token:
                print(
                    "m=cid_fanout, msg=Skipping consumer without API token. "
                    f"consumer={name}"
                )
                continue

            consumers.append(
                CidConsumer(
                    name=name,
                    airflow_api_base_url=base_url.rstrip("/"),
                    api_token=api_token,
                    enabled=True,
                )
            )

        return consumers

    @staticmethod
    def _is_table_qualified_dataset_uri(dataset_uri: str) -> bool:
        base_uri = dataset_uri.split(":", 1)[0]
        return bool(_TABLE_DATASET_URI_PATTERN.match(base_uri))

    @classmethod
    def _post_dataset_event(cls, consumer: CidConsumer, event: Dict[str, Any]) -> None:
        dataset_uri = event["dataset_name"]
        payload = {
            "dataset_uri": dataset_uri,
            "extra": cls._build_api_extra(event),
        }
        url = f"{consumer.airflow_api_base_url}/datasets/events"
        response = requests.post(
            url,
            json=payload,
            headers={
                "Authorization": f"Bearer {consumer.api_token}",
                "Content-Type": "application/json",
            },
            timeout=30,
        )

        if response.status_code == 404:
            raise DatasetNotRegisteredOnSatellite(
                f"HTTP 404 from {consumer.name} for dataset_uri={dataset_uri}"
            )

        try:
            response.raise_for_status()
        except requests.HTTPError as exc:
            raise RuntimeError(
                f"HTTP {response.status_code} from {consumer.name} for "
                f"dataset_uri={dataset_uri}: {response.text}"
            ) from exc

        print(
            "m=cid_fanout, msg=Forwarded dataset event to satellite. "
            f"consumer={consumer.name}, dataset_uri={dataset_uri}"
        )

    @staticmethod
    def _build_api_extra(event: Dict[str, Any]) -> Dict[str, Any]:
        extra = dict(event.get("extra") or {})
        for key in (
            "data_interval_start",
            "data_interval_end",
            "dag_id",
            "task_id",
            "run_id",
            "event_type",
            "ts",
        ):
            value = event.get(key)
            if value is not None:
                extra[key] = value

        if event.get("dag_id") is not None:
            extra.setdefault("source_dag_id", event["dag_id"])
        if event.get("task_id") is not None:
            extra.setdefault("source_task_id", event["task_id"])
        if event.get("run_id") is not None:
            extra.setdefault("source_run_id", event["run_id"])

        return extra

    @classmethod
    def _alert_fanout_failure(
        cls,
        consumer: CidConsumer,
        event: Dict[str, Any],
        error: Exception,
        context: Optional[Context] = None,
    ) -> None:
        dataset_uri = event.get("dataset_name")
        print(
            "m=cid_fanout, msg=Failed to forward dataset event to satellite. "
            f"consumer={consumer.name}, dataset_uri={dataset_uri}, error={error}"
        )

        webhook_url = Variable.get(CID_FANOUT_ALERT_VARIABLE, None) or Variable.get(
            DATASET_EVENTS_ALERT_VARIABLE, None
        )
        if not webhook_url:
            print(
                "m=cid_fanout, msg=Fan-out alert webhook is not configured. "
                f"variables={CID_FANOUT_ALERT_VARIABLE!r}, "
                f"{DATASET_EVENTS_ALERT_VARIABLE!r}"
            )
            return

        payload = cls._format_alert_message(consumer, event, error, context)
        response = requests.post(webhook_url, json=payload, timeout=30)
        try:
            response.raise_for_status()
        except Exception as alert_error:
            print(
                "m=cid_fanout, msg=Failed to send fan-out alert. "
                f"webhook={webhook_url}, error={alert_error}"
            )

    @staticmethod
    def _format_alert_message(
        consumer: CidConsumer,
        event: Dict[str, Any],
        error: Exception,
        context: Optional[Context] = None,
    ) -> Dict[str, Any]:
        ti = None
        if context is not None:
            ti = context.get("task_instance") or context.get("ti")

        source = (
            f"{ti.dag_id}:{ti.task_id}"
            if ti is not None
            else f"{event.get('dag_id')}:{event.get('task_id')}"
        )
        return {
            "cardsV2": [
                {
                    "cardId": "cid_fanout_alert",
                    "card": {
                        "header": {
                            "title": "CID fan-out alert",
                            "subtitle": source,
                        },
                        "sections": [
                            {
                                "widgets": [
                                    {
                                        "textParagraph": {
                                            "text": (
                                                f"Failed to forward dataset event to "
                                                f"<b>{consumer.name}</b> for "
                                                f"<b>{event.get('dataset_name')}</b>. "
                                                f"Error: {error}"
                                            )
                                        }
                                    }
                                ]
                            }
                        ],
                    },
                }
            ]
        }
