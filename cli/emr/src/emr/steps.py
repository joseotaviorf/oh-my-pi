from __future__ import annotations

COMMAND_RUNNER_JAR = "command-runner.jar"


def build_spark_step(
    *,
    name: str,
    action_on_failure: str,
    s3_py_uri: str,
    deploy_mode: str,
) -> dict:
    """Build EMR Step dict: command-runner.jar with ``spark-submit`` (name only, not a path)."""
    args: list[str] = [
        "spark-submit",
        "--master",
        "yarn",
        "--deploy-mode",
        deploy_mode,
        s3_py_uri,
    ]

    return {
        "Name": name,
        "ActionOnFailure": action_on_failure,
        "HadoopJarStep": {"Jar": COMMAND_RUNNER_JAR, "Args": args},
    }
