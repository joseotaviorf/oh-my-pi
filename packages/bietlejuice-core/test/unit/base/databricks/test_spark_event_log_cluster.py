from bietlejuice.base.databricks.spark_event_log_cluster import (
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
