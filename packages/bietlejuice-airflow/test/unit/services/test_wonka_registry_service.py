"""Unit tests for the option-A Wonka registry service (parse-time DAG build)."""

from __future__ import annotations

import hashlib
import json
import sys
from unittest import mock

import pytest

from bietlejuice.services import wonka_registry_service as svc


@pytest.fixture()
def sample_config() -> dict:
    return {
        "job_name": "user-visits",
        "job_module": "user_visits",
        "job_config": {
            "dag": {
                "name": "user_visits",
                "owner": "MLOps",
                "dataset_dependencies": [
                    "bietlejuice.enrich_rent_flows:load-enrich-rent-flows:first-run-of-day"
                ],
            },
            "workflow": {
                "type": "wonka",
                "layer": "wonka",
                "wonka_config": {"name": "user_visits"},
            },
            "cluster": {"type": "wonka_cluster_emr"},
        },
        "build_info": {
            "commit": "abc123",
            "branch": "main",
            "artifact_path": "s3://bucket/quintoml/commit/abc123/jobs.wonka.user-visits/",
            "ci_pipeline_url": None,
            "ci_pipeline_created": None,
            "context": None,
        },
    }


@pytest.fixture()
def fake_dispatcher(monkeypatch):
    """Stub the lazily-imported FactoryDispatcher module (auto-restored)."""
    mod_name = (
        "bietlejuice.base.airflow.dag_builders.main_builder.factories."
        "factory_dispatcher"
    )
    mock_dispatcher_cls = mock.MagicMock(name="FactoryDispatcher")
    fake_mod = mock.MagicMock()
    fake_mod.FactoryDispatcher = mock_dispatcher_cls
    monkeypatch.setitem(sys.modules, mod_name, fake_mod)
    return mock_dispatcher_cls


def _factory_returning(dag_id: str):
    mock_dag = mock.Mock()
    mock_dag.dag_id = dag_id
    mock_workflow = mock.Mock()
    mock_workflow.build_dag.return_value = mock_dag
    mock_factory = mock.Mock()
    mock_factory.get_workflow.return_value = mock_workflow
    return mock_factory


def _write_registry(tmp_path, configs: dict) -> str:
    """Write config files + manifest into tmp_path; return manifest path."""
    jobs = []
    for job_key, entry in configs.items():
        raw = json.dumps(entry).encode()
        config_path = tmp_path / f"{job_key}.json"
        config_path.write_bytes(raw)
        jobs.append(
            {
                "job_key": job_key,
                "config_path": str(config_path),
                "sha256": hashlib.sha256(raw).hexdigest(),
            }
        )
    manifest = {"schema_version": 1, "jobs": jobs}
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest))
    return str(manifest_path)


# --------------------------------------------------------------------------
# Schema validation
# --------------------------------------------------------------------------


def test_validate_config_accepts_valid(sample_config):
    assert svc.validate_config(sample_config) == []


def test_validate_config_rejects_wrong_workflow_type(sample_config):
    sample_config["job_config"]["workflow"]["type"] = "cdc"
    assert svc.validate_config(sample_config)


def test_validate_config_rejects_bad_dataset_uri(sample_config):
    # non-string and empty entries are invalid; arbitrary non-empty strings
    # (including plain table names) are valid Airflow dataset URIs
    sample_config["job_config"]["dag"]["dataset_dependencies"] = [123]
    assert svc.validate_config(sample_config)
    sample_config["job_config"]["dag"]["dataset_dependencies"] = ["  "]
    assert svc.validate_config(sample_config)
    sample_config["job_config"]["dag"]["dataset_dependencies"] = [
        "datalake_ebdb_listing.house_listing"
    ]
    assert svc.validate_config(sample_config) == []


def test_prepare_dag_args_merges_build_info(sample_config):
    dag_args = svc.prepare_dag_args(
        sample_config["job_name"],
        sample_config["job_config"],
        sample_config["build_info"],
    )
    assert dag_args["name"] == "user-visits"
    assert dag_args["artifact_path"].endswith("jobs.wonka.user-visits/")
    assert dag_args["commit"] == "abc123"
    assert "bietlejuice.enrich_rent_flows" in dag_args["dataset_dependencies"][0]


def test_prepare_dataset_dependencies():
    deps = svc.prepare_dataset_dependencies(["bietlejuice.x:y:first-run-of-day"])
    assert deps is not None
    assert deps[0].uri == "bietlejuice.x:y:first-run-of-day"
    assert svc.prepare_dataset_dependencies([]) is None


# --------------------------------------------------------------------------
# URI resolution
# --------------------------------------------------------------------------


def test_registry_uri_env_override(monkeypatch):
    monkeypatch.setenv("WONKA_REGISTRY_URI", "s3://custom/manifest.json")
    assert svc.registry_manifest_uri() == "s3://custom/manifest.json"


def test_registry_uri_defaults_to_configuration_service(monkeypatch):
    monkeypatch.delenv("WONKA_REGISTRY_URI", raising=False)
    with mock.patch.object(svc, "ConfigurationService") as mock_conf:
        mock_conf.return_value.get_config.return_value = "s3://artifacts-bucket"
        uri = svc.registry_manifest_uri()
    assert uri == "s3://artifacts-bucket/quintoml/registry/manifest.json"
    mock_conf.return_value.get_config.assert_called_once_with("artifacts_bucket")


# --------------------------------------------------------------------------
# DAG build
# --------------------------------------------------------------------------


def test_build_dags_from_config_calls_dispatcher(sample_config, fake_dispatcher):
    mock_dispatcher = fake_dispatcher
    mock_dispatcher.return_value.get_factory.return_value = _factory_returning(
        "quintoml.wonka.user_visits"
    )

    dags = svc.build_dags_from_config(sample_config)

    assert [d.dag_id for d in dags] == ["quintoml.wonka.user_visits"]
    _, kwargs = mock_dispatcher.return_value.get_factory.call_args
    assert kwargs["dag_args"]["artifact_path"].startswith("s3://")
    assert kwargs["dataset_dependencies"][0].uri.startswith("bietlejuice.")
    assert "is_validation" not in kwargs


def test_build_dags_builds_validation_shadow_dag(sample_config, fake_dispatcher):
    sample_config["job_config"]["validation"] = {
        "cluster": {"type": "wonka_cluster_emr", "num_workers": 1}
    }
    mock_dispatcher = fake_dispatcher
    mock_dispatcher.return_value.get_factory.side_effect = [
        _factory_returning("quintoml.wonka.user_visits"),
        _factory_returning("quintoml.wonka.user_visits_validation"),
    ]

    dags = svc.build_dags_from_config(sample_config)

    assert [d.dag_id for d in dags] == [
        "quintoml.wonka.user_visits",
        "quintoml.wonka.user_visits_validation",
    ]
    _, validation_kwargs = mock_dispatcher.return_value.get_factory.call_args_list[1]
    assert validation_kwargs["is_validation"] is True
    assert validation_kwargs["dataset_dependencies"] is None
    assert (
        validation_kwargs["validation_config"]
        == (sample_config["job_config"]["validation"])
    )
    # validation cluster overlaid on prod cluster
    assert validation_kwargs["cluster_args"]["num_workers"] == 1


def test_validation_dag_failure_keeps_production_dag(sample_config, fake_dispatcher):
    sample_config["job_config"]["validation"] = {"cluster": {"type": "boom"}}
    mock_dispatcher = fake_dispatcher
    broken_factory = mock.Mock()
    broken_factory.get_workflow.side_effect = RuntimeError("validation build broke")
    mock_dispatcher.return_value.get_factory.side_effect = [
        _factory_returning("quintoml.wonka.user_visits"),
        broken_factory,
    ]

    dags = svc.build_dags_from_config(sample_config)

    assert [d.dag_id for d in dags] == ["quintoml.wonka.user_visits"]


# --------------------------------------------------------------------------
# Registration semantics
# --------------------------------------------------------------------------


def test_kill_switch_registers_nothing(monkeypatch):
    monkeypatch.setenv("WONKA_REGISTRY_ENABLED", "0")
    with mock.patch.object(svc, "load_manifest") as mock_load:
        assert svc.register_wonka_dags_from_registry({}) == 0
    mock_load.assert_not_called()


def test_missing_manifest_is_noop(monkeypatch, tmp_path):
    monkeypatch.delenv("WONKA_REGISTRY_ENABLED", raising=False)
    monkeypatch.setenv("WONKA_REGISTRY_URI", str(tmp_path / "absent.json"))
    assert svc.register_wonka_dags_from_registry({}) == 0


def test_unsupported_schema_version_raises(monkeypatch, tmp_path):
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps({"schema_version": 2, "jobs": []}))
    monkeypatch.setenv("WONKA_REGISTRY_URI", str(manifest_path))
    with pytest.raises(ValueError, match="schema_version"):
        svc.register_wonka_dags_from_registry({})


def test_register_from_local_manifest_skips_invalid_entry(
    monkeypatch, tmp_path, sample_config, fake_dispatcher
):
    bad = json.loads(json.dumps(sample_config))
    bad["job_config"]["workflow"]["type"] = "cdc"
    manifest_path = _write_registry(
        tmp_path,
        {"jobs.wonka.user-visits": sample_config, "jobs.wonka.bad": bad},
    )
    monkeypatch.setenv("WONKA_REGISTRY_URI", manifest_path)
    monkeypatch.delenv("WONKA_REGISTRY_ENABLED", raising=False)

    mock_dispatcher = fake_dispatcher
    mock_dispatcher.return_value.get_factory.return_value = _factory_returning(
        "quintoml.wonka.user_visits"
    )

    globals_dict: dict = {}
    count = svc.register_wonka_dags_from_registry(globals_dict)

    assert count == 1
    assert "quintoml.wonka.user_visits" in globals_dict


def _two_job_registry(tmp_path, sample_config):
    """Registry with two distinct valid jobs; returns the manifest path."""
    second = json.loads(json.dumps(sample_config))
    second["job_name"] = "user-clicks"
    return _write_registry(
        tmp_path,
        {"jobs.wonka.user-visits": sample_config, "jobs.wonka.user-clicks": second},
    )


def test_register_skips_job_on_checksum_mismatch(
    monkeypatch, tmp_path, sample_config, fake_dispatcher
):
    manifest_path = _two_job_registry(tmp_path, sample_config)
    manifest = json.loads(open(manifest_path).read())
    manifest["jobs"][0]["sha256"] = "0" * 64
    open(manifest_path, "w").write(json.dumps(manifest))
    monkeypatch.setenv("WONKA_REGISTRY_URI", manifest_path)
    fake_dispatcher.return_value.get_factory.return_value = _factory_returning(
        "quintoml.wonka.user_clicks"
    )

    globals_dict: dict = {}
    assert svc.register_wonka_dags_from_registry(globals_dict) == 1
    assert "quintoml.wonka.user_clicks" in globals_dict


def test_register_skips_job_missing_sha256(
    monkeypatch, tmp_path, sample_config, fake_dispatcher
):
    manifest_path = _two_job_registry(tmp_path, sample_config)
    manifest = json.loads(open(manifest_path).read())
    del manifest["jobs"][0]["sha256"]
    open(manifest_path, "w").write(json.dumps(manifest))
    monkeypatch.setenv("WONKA_REGISTRY_URI", manifest_path)
    fake_dispatcher.return_value.get_factory.return_value = _factory_returning(
        "quintoml.wonka.user_clicks"
    )

    assert svc.register_wonka_dags_from_registry({}) == 1


def test_zero_registered_of_nonempty_manifest_raises(
    monkeypatch, tmp_path, sample_config, fake_dispatcher
):
    """All-jobs-failed must raise, never import cleanly with an empty bag."""
    manifest_path = _write_registry(tmp_path, {"jobs.wonka.user-visits": sample_config})
    manifest = json.loads(open(manifest_path).read())
    manifest["jobs"][0]["sha256"] = "0" * 64
    open(manifest_path, "w").write(json.dumps(manifest))
    monkeypatch.setenv("WONKA_REGISTRY_URI", manifest_path)

    with pytest.raises(svc.RegistryUnavailableError, match="none could be"):
        svc.register_wonka_dags_from_registry({})


def test_config_fetch_infra_failure_raises(monkeypatch, tmp_path, sample_config):
    """A RegistryUnavailableError on a config fetch fails the import loudly."""
    manifest_path = _write_registry(tmp_path, {"jobs.wonka.user-visits": sample_config})
    monkeypatch.setenv("WONKA_REGISTRY_URI", manifest_path)
    with mock.patch.object(
        svc,
        "_fetch_config_bytes",
        side_effect=svc.RegistryUnavailableError("s3 down"),
    ):
        with pytest.raises(svc.RegistryUnavailableError, match="s3 down"):
            svc.register_wonka_dags_from_registry({})


def test_non_dict_job_entry_is_skipped(
    monkeypatch, tmp_path, sample_config, fake_dispatcher
):
    manifest_path = _write_registry(tmp_path, {"jobs.wonka.user-visits": sample_config})
    manifest = json.loads(open(manifest_path).read())
    manifest["jobs"].insert(0, None)
    manifest["jobs"].insert(0, "bogus")
    open(manifest_path, "w").write(json.dumps(manifest))
    monkeypatch.setenv("WONKA_REGISTRY_URI", manifest_path)
    fake_dispatcher.return_value.get_factory.return_value = _factory_returning(
        "quintoml.wonka.user_visits"
    )

    assert svc.register_wonka_dags_from_registry({}) == 1


def test_duplicate_dag_id_keeps_first(
    monkeypatch, tmp_path, sample_config, fake_dispatcher
):
    manifest_path = _two_job_registry(tmp_path, sample_config)
    monkeypatch.setenv("WONKA_REGISTRY_URI", manifest_path)
    # both jobs resolve to the same dag_id
    fake_dispatcher.return_value.get_factory.return_value = _factory_returning(
        "quintoml.wonka.user_visits"
    )

    globals_dict: dict = {}
    assert svc.register_wonka_dags_from_registry(globals_dict) == 1
    assert list(globals_dict) == ["quintoml.wonka.user_visits"]


def test_manifest_must_be_object(monkeypatch, tmp_path):
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps([1, 2, 3]))
    monkeypatch.setenv("WONKA_REGISTRY_URI", str(manifest_path))
    with pytest.raises(ValueError, match="JSON object"):
        svc.register_wonka_dags_from_registry({})


def test_manifest_jobs_must_be_list(monkeypatch, tmp_path):
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps({"schema_version": 1, "jobs": "oops"}))
    monkeypatch.setenv("WONKA_REGISTRY_URI", str(manifest_path))
    with pytest.raises(ValueError, match="non-list"):
        svc.register_wonka_dags_from_registry({})


def test_manifest_null_jobs_is_noop(monkeypatch, tmp_path):
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps({"schema_version": 1, "jobs": None}))
    monkeypatch.setenv("WONKA_REGISTRY_URI", str(manifest_path))
    assert svc.register_wonka_dags_from_registry({}) == 0


def test_build_info_cannot_override_job_name(sample_config):
    sample_config["build_info"]["name"] = "evil-name"
    dag_args = svc.prepare_dag_args(
        sample_config["job_name"],
        sample_config["job_config"],
        sample_config["build_info"],
    )
    assert dag_args["name"] == "user-visits"


def test_ttl_invalid_env_falls_back(monkeypatch):
    monkeypatch.setenv("WONKA_REGISTRY_TTL", "300s")
    assert svc._ttl_seconds() == 300


def test_cache_paths_do_not_collide():
    a, _ = svc._cache_paths("s3://b/quintoml/registry/foo/bar/config.json")
    b, _ = svc._cache_paths("s3://b/quintoml/registry/foo__bar/config.json")
    assert a != b


# --------------------------------------------------------------------------
# S3 cache / failure semantics
# --------------------------------------------------------------------------


def _client_error(code: str):
    from botocore.exceptions import ClientError

    return ClientError({"Error": {"Code": code}}, "GetObject")


def test_s3_manifest_nosuchkey_is_noop(monkeypatch, tmp_path):
    monkeypatch.setenv(
        "WONKA_REGISTRY_URI", "s3://bucket/quintoml/registry/manifest.json"
    )
    monkeypatch.setenv("WONKA_REGISTRY_CACHE", str(tmp_path / "cache"))
    with mock.patch.object(svc, "boto3") as mock_boto:
        mock_boto.client.return_value.get_object.side_effect = _client_error(
            "NoSuchKey"
        )
        assert svc.register_wonka_dags_from_registry({}) == 0


def test_s3_failure_without_cache_raises(monkeypatch, tmp_path):
    monkeypatch.setenv(
        "WONKA_REGISTRY_URI", "s3://bucket/quintoml/registry/manifest.json"
    )
    monkeypatch.setenv("WONKA_REGISTRY_CACHE", str(tmp_path / "cache"))
    with mock.patch.object(svc, "boto3") as mock_boto:
        mock_boto.client.return_value.get_object.side_effect = _client_error(
            "AccessDenied"
        )
        with pytest.raises(svc.RegistryUnavailableError):
            svc.register_wonka_dags_from_registry({})


def test_s3_failure_with_stale_cache_uses_cache(monkeypatch, tmp_path):
    cache_dir = tmp_path / "cache"
    cache_dir.mkdir()
    uri = "s3://bucket/quintoml/registry/manifest.json"
    monkeypatch.setenv("WONKA_REGISTRY_URI", uri)
    monkeypatch.setenv("WONKA_REGISTRY_CACHE", str(cache_dir))
    monkeypatch.setenv("WONKA_REGISTRY_TTL", "0")
    manifest_bytes = json.dumps({"schema_version": 1, "jobs": []}).encode()
    cache_file, meta_file = svc._cache_paths(uri)
    cache_file.write_bytes(manifest_bytes)
    meta_file.write_text("0")
    with mock.patch.object(svc, "boto3") as mock_boto:
        mock_boto.client.return_value.get_object.side_effect = _client_error(
            "AccessDenied"
        )
        # empty jobs list -> registers nothing, but no raise (stale cache used)
        assert svc.register_wonka_dags_from_registry({}) == 0


def test_s3_fetch_writes_cache_once(monkeypatch, tmp_path):
    cache_dir = tmp_path / "cache"
    monkeypatch.setenv("WONKA_REGISTRY_CACHE", str(cache_dir))
    uri = "s3://bucket/quintoml/registry/manifest.json"
    body = json.dumps({"schema_version": 1, "jobs": []}).encode()
    with mock.patch.object(svc, "boto3") as mock_boto:
        mock_boto.client.return_value.get_object.return_value = {
            "Body": mock.Mock(read=mock.Mock(return_value=body))
        }
        raw = svc._fetch_bytes(uri)
    assert raw == body
    cache_file, _ = svc._cache_paths(uri)
    assert cache_file.read_bytes() == body


# --------------------------------------------------------------------------
# Assume-role S3 client (WONKA_REGISTRY_ROLE_ARN)
# --------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _clear_s3_client_cache(monkeypatch):
    monkeypatch.delenv("WONKA_REGISTRY_ROLE_ARN", raising=False)
    svc._reset_s3_client_cache()
    yield
    svc._reset_s3_client_cache()


def test_s3_client_default_chain_when_role_unset(monkeypatch):
    monkeypatch.delenv("WONKA_REGISTRY_ROLE_ARN", raising=False)
    with mock.patch.object(svc, "boto3") as mock_boto:
        client = svc._s3_client()
    mock_boto.client.assert_called_once_with("s3")
    assert client is mock_boto.client.return_value


def test_s3_client_assumes_role_when_arn_set(monkeypatch):
    from datetime import datetime, timedelta, timezone

    role_arn = "arn:aws:iam::206390561754:role/airflow-prod-role"
    monkeypatch.setenv("WONKA_REGISTRY_ROLE_ARN", role_arn)
    expiry = datetime.now(timezone.utc) + timedelta(hours=1)

    mock_sts = mock.Mock()
    mock_sts.assume_role.return_value = {
        "Credentials": {
            "AccessKeyId": "AKIATEST",
            "SecretAccessKey": "secret",
            "SessionToken": "token",
            "Expiration": expiry,
        }
    }
    mock_s3 = mock.Mock(name="assumed-s3")

    def client_factory(service, **kwargs):
        if service == "sts":
            return mock_sts
        if service == "s3":
            return mock_s3
        raise AssertionError(f"unexpected client: {service}")

    with mock.patch.object(svc, "boto3") as mock_boto:
        mock_boto.client.side_effect = client_factory
        client = svc._s3_client()

    assert client is mock_s3
    mock_sts.assume_role.assert_called_once_with(
        RoleArn=role_arn,
        RoleSessionName="wonka-registry-dag-parse",
    )
    s3_kwargs = mock_boto.client.call_args_list[1].kwargs
    assert s3_kwargs["aws_access_key_id"] == "AKIATEST"
    assert s3_kwargs["aws_secret_access_key"] == "secret"
    assert s3_kwargs["aws_session_token"] == "token"


def test_s3_client_reuses_cached_assumed_client(monkeypatch):
    from datetime import datetime, timedelta, timezone

    monkeypatch.setenv(
        "WONKA_REGISTRY_ROLE_ARN",
        "arn:aws:iam::206390561754:role/airflow-prod-role",
    )
    expiry = datetime.now(timezone.utc) + timedelta(hours=1)
    mock_sts = mock.Mock()
    mock_sts.assume_role.return_value = {
        "Credentials": {
            "AccessKeyId": "AKIATEST",
            "SecretAccessKey": "secret",
            "SessionToken": "token",
            "Expiration": expiry,
        }
    }
    mock_s3 = mock.Mock(name="assumed-s3")

    def client_factory(service, **kwargs):
        return mock_sts if service == "sts" else mock_s3

    with mock.patch.object(svc, "boto3") as mock_boto:
        mock_boto.client.side_effect = client_factory
        first = svc._s3_client()
        second = svc._s3_client()

    assert first is second is mock_s3
    assert mock_sts.assume_role.call_count == 1


def test_assume_role_failure_without_cache_raises(monkeypatch, tmp_path):
    monkeypatch.setenv(
        "WONKA_REGISTRY_URI", "s3://bucket/quintoml/registry/manifest.json"
    )
    monkeypatch.setenv("WONKA_REGISTRY_CACHE", str(tmp_path / "cache"))
    monkeypatch.setenv(
        "WONKA_REGISTRY_ROLE_ARN",
        "arn:aws:iam::206390561754:role/airflow-prod-role",
    )
    with mock.patch.object(svc, "boto3") as mock_boto:
        mock_boto.client.return_value.assume_role.side_effect = RuntimeError(
            "InvalidIdentityToken"
        )
        with pytest.raises(svc.RegistryUnavailableError, match="cannot fetch"):
            svc.register_wonka_dags_from_registry({})


def test_assume_role_failure_with_stale_cache_uses_cache(monkeypatch, tmp_path):
    cache_dir = tmp_path / "cache"
    cache_dir.mkdir()
    uri = "s3://bucket/quintoml/registry/manifest.json"
    monkeypatch.setenv("WONKA_REGISTRY_URI", uri)
    monkeypatch.setenv("WONKA_REGISTRY_CACHE", str(cache_dir))
    monkeypatch.setenv("WONKA_REGISTRY_TTL", "0")
    monkeypatch.setenv(
        "WONKA_REGISTRY_ROLE_ARN",
        "arn:aws:iam::206390561754:role/airflow-prod-role",
    )
    manifest_bytes = json.dumps({"schema_version": 1, "jobs": []}).encode()
    cache_file, meta_file = svc._cache_paths(uri)
    cache_file.write_bytes(manifest_bytes)
    meta_file.write_text("0")
    with mock.patch.object(svc, "boto3") as mock_boto:
        mock_boto.client.return_value.assume_role.side_effect = RuntimeError(
            "InvalidIdentityToken"
        )
        assert svc.register_wonka_dags_from_registry({}) == 0


# --------------------------------------------------------------------------
# sha256-validated cache + parallel fetch
# --------------------------------------------------------------------------


def test_sha_validated_cache_skips_s3_even_after_ttl(
    monkeypatch, tmp_path, sample_config
):
    """Cached config bytes matching the manifest sha must not trigger an S3 GET."""
    cache_dir = tmp_path / "cache"
    cache_dir.mkdir()
    monkeypatch.setenv("WONKA_REGISTRY_CACHE", str(cache_dir))
    monkeypatch.setenv("WONKA_REGISTRY_TTL", "0")

    raw = json.dumps(sample_config).encode()
    expected = hashlib.sha256(raw).hexdigest()
    uri = "s3://bucket/quintoml/registry/jobs/jobs.wonka.user-visits/config.json"
    cache_file, meta_file = svc._cache_paths(uri)
    cache_file.write_bytes(raw)
    meta_file.write_text("0")

    job_entry = {
        "job_key": "jobs.wonka.user-visits",
        "config_key": "quintoml/registry/jobs/jobs.wonka.user-visits/config.json",
        "sha256": expected,
    }
    monkeypatch.setenv(
        "WONKA_REGISTRY_URI", "s3://bucket/quintoml/registry/manifest.json"
    )

    with mock.patch.object(svc, "_s3_client") as mock_client:
        result = svc._fetch_config_bytes(job_entry)

    assert result == raw
    mock_client.assert_not_called()


def test_sha_validated_cache_miss_on_checksum_mismatch_refetches(
    monkeypatch, tmp_path, sample_config
):
    cache_dir = tmp_path / "cache"
    cache_dir.mkdir()
    monkeypatch.setenv("WONKA_REGISTRY_CACHE", str(cache_dir))
    monkeypatch.setenv("WONKA_REGISTRY_TTL", "0")
    monkeypatch.setenv(
        "WONKA_REGISTRY_URI", "s3://bucket/quintoml/registry/manifest.json"
    )

    raw = json.dumps(sample_config).encode()
    expected = hashlib.sha256(raw).hexdigest()
    uri = "s3://bucket/quintoml/registry/jobs/jobs.wonka.user-visits/config.json"
    cache_file, meta_file = svc._cache_paths(uri)
    cache_file.write_bytes(b'{"stale": true}')
    meta_file.write_text("0")

    job_entry = {
        "job_key": "jobs.wonka.user-visits",
        "config_key": "quintoml/registry/jobs/jobs.wonka.user-visits/config.json",
        "sha256": expected,
    }

    body = mock.Mock()
    body.read.return_value = raw
    mock_s3 = mock.Mock()
    mock_s3.get_object.return_value = {"Body": body}

    with mock.patch.object(svc, "_s3_client", return_value=mock_s3):
        result = svc._fetch_config_bytes(job_entry)

    assert result == raw
    assert mock_s3.get_object.call_count >= 1


def test_fetch_all_config_bytes_preserves_order_and_parallelizes(
    monkeypatch, tmp_path, sample_config
):
    second = json.loads(json.dumps(sample_config))
    second["job_name"] = "user-clicks"
    configs = {
        "jobs.wonka.user-visits": sample_config,
        "jobs.wonka.user-clicks": second,
    }
    jobs = []
    for job_key, entry in configs.items():
        raw = json.dumps(entry).encode()
        path = tmp_path / f"{job_key}.json"
        path.write_bytes(raw)
        jobs.append(
            {
                "job_key": job_key,
                "config_path": str(path),
                "sha256": hashlib.sha256(raw).hexdigest(),
            }
        )

    call_order = []
    original = svc._fetch_config_bytes

    def tracking_fetch(job_entry):
        call_order.append(job_entry["job_key"])
        return original(job_entry)

    with mock.patch.object(svc, "_fetch_config_bytes", side_effect=tracking_fetch):
        results = svc._fetch_all_config_bytes(jobs)

    assert [je["job_key"] for je, _ in results] == [
        "jobs.wonka.user-visits",
        "jobs.wonka.user-clicks",
    ]
    assert all(isinstance(raw, bytes) for _, raw in results)
    assert set(call_order) == {
        "jobs.wonka.user-visits",
        "jobs.wonka.user-clicks",
    }


def test_fetch_all_propagates_registry_unavailable(
    monkeypatch, tmp_path, sample_config
):
    manifest_path = _write_registry(tmp_path, {"jobs.wonka.user-visits": sample_config})
    monkeypatch.setenv("WONKA_REGISTRY_URI", manifest_path)

    with mock.patch.object(
        svc,
        "_fetch_config_bytes",
        side_effect=svc.RegistryUnavailableError("s3 down"),
    ):
        with pytest.raises(svc.RegistryUnavailableError, match="s3 down"):
            svc.register_wonka_dags_from_registry({})
