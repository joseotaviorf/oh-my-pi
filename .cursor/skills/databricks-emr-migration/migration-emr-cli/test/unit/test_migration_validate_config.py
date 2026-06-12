from emr.config import load_settings_file
from emr.paths import package_root


def test_migration_validate_settings_loads() -> None:
    path = package_root() / "config" / "migration-validate.yml"
    cfg = load_settings_file(path)
    assert cfg["action_on_failure"] == "CONTINUE"
    assert cfg["idle_timeout_sec"] == 7200
    assert cfg["core_instance_count"] == 3
    assert cfg["core_instance_type"] == "m7g.2xlarge"
    assert cfg["master_instance_type"] == "m7g.2xlarge"
    spark_defaults = next(
        block
        for block in cfg["configurations"]
        if block.get("Classification") == "spark-defaults"
    )["Properties"]
    assert spark_defaults["spark.dynamicAllocation.maxExecutors"] == "12"
    hive = [
        block
        for block in cfg["configurations"]
        if block.get("Classification") == "hive-site"
    ]
    assert hive
