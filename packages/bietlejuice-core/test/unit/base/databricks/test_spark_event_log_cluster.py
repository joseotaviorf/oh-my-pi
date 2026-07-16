from bietlejuice.base.databricks.spark_event_log_cluster import (
    apply_shard_event_log_dir_suffix,
    apply_validation_event_log_overrides,
)


class TestApplyValidationEventLogOverrides:
    def test_disables_event_log_when_spark_conf_present(self):
        cluster_configuration = {
            "spark_conf": {
                "spark.eventLog.enabled": "true",
                "spark.eventLog.dir": "s3a://bucket/spark-event-logs/dag",
            }
        }

        result = apply_validation_event_log_overrides(cluster_configuration)

        assert result["spark_conf"]["spark.eventLog.enabled"] == "false"
        assert (
            result["spark_conf"]["spark.eventLog.dir"]
            == "s3a://bucket/spark-event-logs/dag"
        )

    def test_disables_event_log_when_spark_conf_missing(self):
        cluster_configuration = {"spark_version": "16.4.x-scala2.12"}

        result = apply_validation_event_log_overrides(cluster_configuration)

        assert result["spark_conf"]["spark.eventLog.enabled"] == "false"

    def test_does_not_mutate_input_spark_conf(self):
        spark_conf = {"spark.eventLog.enabled": "true"}
        cluster_configuration = {"spark_conf": spark_conf}

        apply_validation_event_log_overrides(cluster_configuration)

        assert spark_conf["spark.eventLog.enabled"] == "true"


class TestApplyShardEventLogDirSuffix:
    _BASE_DIR = (
        "s3a://{{ var.value.databricks_s3_bucket }}/spark-event-logs/{{ dag.dag_id }}"
    )

    def test_appends_cluster_1_when_local_id_is_none(self):
        cluster_configuration = {
            "spark_conf": {
                "spark.eventLog.enabled": "true",
                "spark.eventLog.dir": self._BASE_DIR,
            }
        }

        result = apply_shard_event_log_dir_suffix(
            cluster_configuration,
            execute_job_cluster_local_id=None,
        )

        assert (
            result["spark_conf"]["spark.eventLog.dir"] == f"{self._BASE_DIR}/cluster-1"
        )

    def test_appends_cluster_n_for_sharded_task(self):
        cluster_configuration = {
            "spark_conf": {
                "spark.eventLog.enabled": "true",
                "spark.eventLog.dir": self._BASE_DIR,
            }
        }

        result = apply_shard_event_log_dir_suffix(
            cluster_configuration,
            execute_job_cluster_local_id=3,
        )

        assert (
            result["spark_conf"]["spark.eventLog.dir"] == f"{self._BASE_DIR}/cluster-3"
        )

    def test_no_op_when_event_log_disabled(self):
        cluster_configuration = {
            "spark_conf": {
                "spark.eventLog.enabled": "false",
                "spark.eventLog.dir": self._BASE_DIR,
            }
        }

        result = apply_shard_event_log_dir_suffix(
            cluster_configuration,
            execute_job_cluster_local_id=2,
        )

        assert result["spark_conf"]["spark.eventLog.dir"] == self._BASE_DIR

    def test_no_op_when_event_log_dir_missing(self):
        cluster_configuration = {
            "spark_conf": {
                "spark.eventLog.enabled": "true",
            }
        }

        result = apply_shard_event_log_dir_suffix(
            cluster_configuration,
            execute_job_cluster_local_id=2,
        )

        assert "spark.eventLog.dir" not in result["spark_conf"]

    def test_idempotent_when_suffix_already_present(self):
        already_suffixed = f"{self._BASE_DIR}/cluster-3"
        cluster_configuration = {
            "spark_conf": {
                "spark.eventLog.enabled": "true",
                "spark.eventLog.dir": already_suffixed,
            }
        }

        result = apply_shard_event_log_dir_suffix(
            cluster_configuration,
            execute_job_cluster_local_id=3,
        )

        assert result["spark_conf"]["spark.eventLog.dir"] == already_suffixed

    def test_does_not_mutate_input_configuration(self):
        spark_conf = {
            "spark.eventLog.enabled": "true",
            "spark.eventLog.dir": self._BASE_DIR,
        }
        cluster_configuration = {"spark_conf": spark_conf}

        apply_shard_event_log_dir_suffix(
            cluster_configuration,
            execute_job_cluster_local_id=2,
        )

        assert spark_conf["spark.eventLog.dir"] == self._BASE_DIR

    def test_shards_get_distinct_event_log_dirs(self):
        cluster_configuration = {
            "spark_conf": {
                "spark.eventLog.enabled": "true",
                "spark.eventLog.dir": self._BASE_DIR,
            }
        }
        shard_ids = [None, 2, 3, 15]
        dirs = {
            apply_shard_event_log_dir_suffix(
                cluster_configuration,
                execute_job_cluster_local_id=shard_id,
            )["spark_conf"]["spark.eventLog.dir"]
            for shard_id in shard_ids
        }

        assert len(dirs) == len(shard_ids)
        assert dirs == {
            f"{self._BASE_DIR}/cluster-1",
            f"{self._BASE_DIR}/cluster-2",
            f"{self._BASE_DIR}/cluster-3",
            f"{self._BASE_DIR}/cluster-15",
        }
