from __future__ import annotations

import sys

import click

from emr import __version__, emr_ops
from emr.config import (
    load_settings_file,
    merge_base_config,
    merge_runtime_config,
    merge_step_submit_config,
    resolve_settings_path,
    validate_persistent_cluster,
    validate_step_submit,
    validate_transient,
)


def _tags_from_kv_pairs(pairs: tuple[str, ...]) -> dict[str, str]:
    out: dict[str, str] = {}
    for item in pairs:
        if "=" not in item:
            raise click.BadParameter(f"tag must be Key=Value, got {item!r}")
        k, v = item.split("=", 1)
        out[k.strip()] = v.strip()
    return out


@click.group(context_settings={"help_option_names": ["-h", "--help"]})
@click.version_option(__version__, prog_name="emr")
@click.pass_context
def main(ctx: click.Context) -> None:
    """AWS EMR helpers: transient cluster+step, persistent cluster, terminate, add Spark step."""
    ctx.ensure_object(dict)
    try:
        ctx.obj["settings_path"] = resolve_settings_path()
    except ValueError as e:
        raise click.ClickException(str(e)) from e


@main.command("transient")
@click.pass_context
@click.option("--wait/--no-wait", default=False, show_default=True)
@click.option("--s3-uri", required=True, help="S3 URI of the PySpark script (.py)")
@click.option(
    "--name", "job_flow_name", required=True, help="Job flow Name for this RunJobFlow."
)
@click.option(
    "--step-name",
    default="Spark application",
    show_default=True,
    help="EMR step name for this job.",
)
@click.option(
    "--tag",
    "tag_pairs",
    multiple=True,
    help="EMR tag as Key=Value (repeatable).",
)
@click.option(
    "--master-instance-type",
    default=None,
    help="Override master InstanceType from settings file.",
)
@click.option(
    "--core-instance-type",
    default=None,
    help="Override core InstanceType from settings file.",
)
@click.option(
    "--core-instance-count",
    type=int,
    default=None,
    help="Override number of core instances from settings file (>= 1).",
)
@click.option(
    "--bootstrap-script-uri",
    default=None,
    help=(
        "Optional S3/HTTP(S) URI of a bootstrap shell script; runs on every instance "
        "(master + cores) at cluster start before the Spark step."
    ),
)
def cmd_transient(
    ctx: click.Context,
    wait: bool,
    s3_uri: str,
    job_flow_name: str,
    step_name: str,
    tag_pairs: tuple[str, ...],
    master_instance_type: str | None,
    core_instance_type: str | None,
    core_instance_count: int | None,
    bootstrap_script_uri: str | None,
) -> None:
    settings_path = str(ctx.obj["settings_path"])
    tags: dict[str, str] | None = _tags_from_kv_pairs(tag_pairs) if tag_pairs else None
    try:
        cfg = merge_runtime_config(
            config_path=settings_path,
            s3_uri=s3_uri,
            step_name=step_name,
            name=job_flow_name,
            tags=tags,
            master_instance_type=master_instance_type,
            core_instance_type=core_instance_type,
            core_instance_count=core_instance_count,
            bootstrap_script_uri=bootstrap_script_uri,
        )
        validate_transient(cfg)
    except ValueError as e:
        raise click.ClickException(str(e)) from e

    try:
        emr_ops.submit_transient(cfg, wait=wait)
    except Exception as e:
        print(str(e), file=sys.stderr)
        raise SystemExit(1) from e


@main.command("create-cluster")
@click.pass_context
@click.option(
    "--name", "job_flow_name", required=True, help="Job flow Name for RunJobFlow."
)
@click.option(
    "--tag",
    "tag_pairs",
    multiple=True,
    help="EMR tag as Key=Value (repeatable).",
)
@click.option(
    "--master-instance-type",
    default=None,
    help="Override master InstanceType from settings file.",
)
@click.option(
    "--core-instance-type",
    default=None,
    help="Override core InstanceType from settings file.",
)
@click.option(
    "--core-instance-count",
    type=int,
    default=None,
    help="Override number of core instances from settings file (>= 1).",
)
@click.option(
    "--bootstrap-script-uri",
    default=None,
    help="Optional bootstrap script URI (s3/http/https); runs on every instance at cluster start.",
)
def cmd_create_cluster(
    ctx: click.Context,
    job_flow_name: str,
    tag_pairs: tuple[str, ...],
    master_instance_type: str | None,
    core_instance_type: str | None,
    core_instance_count: int | None,
    bootstrap_script_uri: str | None,
) -> None:
    """Persistent cluster; idle auto-termination uses ``idle_timeout_sec`` in the env YAML only."""
    settings_path = str(ctx.obj["settings_path"])
    tags: dict[str, str] | None = _tags_from_kv_pairs(tag_pairs) if tag_pairs else None
    try:
        cfg = merge_base_config(
            config_path=settings_path,
            name=job_flow_name,
            tags=tags,
            master_instance_type=master_instance_type,
            core_instance_type=core_instance_type,
            core_instance_count=core_instance_count,
            bootstrap_script_uri=bootstrap_script_uri,
        )
        validate_persistent_cluster(cfg)
    except ValueError as e:
        raise click.ClickException(str(e)) from e

    try:
        emr_ops.create_persistent_cluster(cfg)
    except Exception as e:
        print(str(e), file=sys.stderr)
        raise SystemExit(1) from e


@main.command("terminate")
@click.pass_context
@click.option(
    "--cluster-id", required=True, help="EMR cluster / job flow id (e.g. j-XXXXXXXX)."
)
def cmd_terminate(ctx: click.Context, cluster_id: str) -> None:
    settings_path = str(ctx.obj["settings_path"])
    try:
        r = str(load_settings_file(settings_path)["region"])
        emr_ops.terminate_cluster(cluster_id=cluster_id.strip(), region=r)
    except Exception as e:
        print(str(e), file=sys.stderr)
        raise SystemExit(1) from e


@main.command("submit-step")
@click.pass_context
@click.option(
    "--cluster-id", required=True, help="Running cluster id to add the step to."
)
@click.option("--s3-uri", required=True, help="S3 URI of the PySpark script (.py)")
@click.option(
    "--step-name", default="Spark application", show_default=True, help="EMR step name."
)
@click.option("--wait/--no-wait", default=False, show_default=True)
def cmd_submit_step(
    ctx: click.Context,
    cluster_id: str,
    s3_uri: str,
    step_name: str,
    wait: bool,
) -> None:
    settings_path = str(ctx.obj["settings_path"])
    try:
        cfg = merge_step_submit_config(
            config_path=settings_path,
            s3_uri=s3_uri,
            step_name=step_name,
            region=str(load_settings_file(settings_path)["region"]),
        )
        validate_step_submit(cfg)
    except ValueError as e:
        raise click.ClickException(str(e)) from e

    try:
        emr_ops.submit_step_to_cluster(cfg, cluster_id=cluster_id.strip(), wait=wait)
    except Exception as e:
        print(str(e), file=sys.stderr)
        raise SystemExit(1) from e


def run() -> None:
    main()
