import json
from unittest import mock

import pytest
import requests

from bietlejuice.services.cid_fanout import (
    CID_CONSUMER_REGISTRY_VARIABLE,
    AirflowDatasetFanout,
    DatasetNotRegisteredOnSatellite,
)


@pytest.fixture
def sample_event():
    return {
        "dag_id": "bietlejuice.dag_inventory",
        "task_id": "load-clean-dag",
        "run_id": "scheduled__2026-01-01T00:00:00+00:00",
        "dataset_name": "datalake_dag_inventory_clean.dag:first-run-of-day",
        "dataset_alias": "bietlejuice.dag_inventory:load-clean-dag:alias",
        "event_type": "first_run_of_day",
        "ts": "2026-01-01T00:00:00Z",
        "data_interval_start": "2026-01-01T00:00:00+00:00",
        "data_interval_end": "2026-01-02T00:00:00+00:00",
        "extra": {},
    }


@pytest.fixture
def registry_json():
    return json.dumps(
        {
            "consumers": [
                {
                    "name": "luigijr",
                    "enabled": True,
                    "airflow_api_base_url": "https://forno-luigijr.example.com/api/v1",
                    "api_token": "test-token",
                }
            ]
        }
    )


class TestAirflowDatasetFanout:
    def test_fanout_is_noop_when_registry_is_empty(self, sample_event):
        with (
            mock.patch(
                "bietlejuice.services.cid_fanout.Variable.get", return_value=None
            ),
            mock.patch("bietlejuice.services.cid_fanout.requests.post") as post,
        ):
            AirflowDatasetFanout.fanout([sample_event])

        post.assert_not_called()

    def test_fanout_skips_task_level_dataset_uris(self, registry_json, sample_event):
        task_event = {
            **sample_event,
            "dataset_name": "bietlejuice.dag_inventory:load-clean-dag:first-run-of-day",
        }
        with (
            mock.patch(
                "bietlejuice.services.cid_fanout.Variable.get",
                side_effect=lambda key, default=None: (
                    registry_json if key == CID_CONSUMER_REGISTRY_VARIABLE else default
                ),
            ),
            mock.patch("bietlejuice.services.cid_fanout.requests.post") as post,
        ):
            AirflowDatasetFanout.fanout([task_event])

        post.assert_not_called()

    def test_fanout_posts_table_qualified_event(self, registry_json, sample_event):
        response = mock.Mock()
        response.status_code = 200
        response.raise_for_status = mock.Mock()

        with (
            mock.patch(
                "bietlejuice.services.cid_fanout.Variable.get",
                side_effect=lambda key, default=None: (
                    registry_json if key == CID_CONSUMER_REGISTRY_VARIABLE else default
                ),
            ),
            mock.patch(
                "bietlejuice.services.cid_fanout.requests.post", return_value=response
            ) as post,
        ):
            AirflowDatasetFanout.fanout([sample_event])

        post.assert_called_once()
        call_kwargs = post.call_args.kwargs
        url = call_kwargs.get("url") or post.call_args.args[0]
        assert url == "https://forno-luigijr.example.com/api/v1/datasets/events"

        payload = call_kwargs["json"]
        headers = call_kwargs["headers"]
        assert payload["dataset_uri"] == sample_event["dataset_name"]
        assert (
            payload["extra"]["data_interval_start"]
            == sample_event["data_interval_start"]
        )
        assert payload["extra"]["source_run_id"] == sample_event["run_id"]
        assert headers["Authorization"] == "Bearer test-token"

    def test_fanout_404_is_silent(self, registry_json, sample_event):
        response = mock.Mock()
        response.status_code = 404

        with (
            mock.patch(
                "bietlejuice.services.cid_fanout.Variable.get",
                side_effect=lambda key, default=None: (
                    registry_json if key == CID_CONSUMER_REGISTRY_VARIABLE else default
                ),
            ),
            mock.patch(
                "bietlejuice.services.cid_fanout.requests.post", return_value=response
            ),
            mock.patch(
                "bietlejuice.services.cid_fanout.AirflowDatasetFanout._alert_fanout_failure"
            ) as alert,
        ):
            AirflowDatasetFanout.fanout([sample_event])

        alert.assert_not_called()

    def test_fanout_other_http_errors_trigger_alert(self, registry_json, sample_event):
        response = mock.Mock()
        response.status_code = 500
        response.text = "internal error"
        response.raise_for_status.side_effect = requests.HTTPError("boom")

        with (
            mock.patch(
                "bietlejuice.services.cid_fanout.Variable.get",
                side_effect=lambda key, default=None: (
                    registry_json if key == CID_CONSUMER_REGISTRY_VARIABLE else default
                ),
            ),
            mock.patch(
                "bietlejuice.services.cid_fanout.requests.post", return_value=response
            ),
            mock.patch(
                "bietlejuice.services.cid_fanout.AirflowDatasetFanout._alert_fanout_failure"
            ) as alert,
        ):
            AirflowDatasetFanout.fanout([sample_event])

        alert.assert_called_once()

    def test_load_enabled_consumers_reads_token_variable(self):
        registry = json.dumps(
            {
                "consumers": [
                    {
                        "name": "luigijr",
                        "enabled": True,
                        "airflow_api_base_url": "https://example.com/api/v1/",
                        "api_token_variable": "CID_LUIGIJR_API_TOKEN",
                    }
                ]
            }
        )

        with mock.patch(
            "bietlejuice.services.cid_fanout.Variable.get",
            side_effect=lambda key, default=None: {
                CID_CONSUMER_REGISTRY_VARIABLE: registry,
                "CID_LUIGIJR_API_TOKEN": "secret-token",
            }.get(key, default),
        ):
            consumers = AirflowDatasetFanout._load_enabled_consumers()

        assert len(consumers) == 1
        assert consumers[0].api_token == "secret-token"
        assert consumers[0].airflow_api_base_url == "https://example.com/api/v1"

    def test_build_api_extra_includes_reprocessing_fields(self):
        event = {
            "dataset_name": "datalake_x.y:reprocessing",
            "extra": {
                "reprocessing_date": "2026-01-01",
                "reprocessing_source": "bietlejuice.foo:bar",
            },
            "data_interval_start": "2026-01-01T00:00:00+00:00",
            "run_id": "manual__2026-01-01",
        }

        extra = AirflowDatasetFanout._build_api_extra(event)

        assert extra["reprocessing_date"] == "2026-01-01"
        assert extra["reprocessing_source"] == "bietlejuice.foo:bar"
        assert extra["source_run_id"] == "manual__2026-01-01"

    def test_post_dataset_event_raises_for_404(self, sample_event):
        consumer = mock.Mock(
            name="luigijr",
            airflow_api_base_url="https://example.com/api/v1",
            api_token="token",
        )
        response = mock.Mock(status_code=404)

        with mock.patch(
            "bietlejuice.services.cid_fanout.requests.post", return_value=response
        ):
            with pytest.raises(DatasetNotRegisteredOnSatellite):
                AirflowDatasetFanout._post_dataset_event(consumer, sample_event)
