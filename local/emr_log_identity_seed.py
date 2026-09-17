# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "boto3",
#     "pyarrow",
# ]
# ///

import argparse
import concurrent.futures
import datetime
import os
import re
import sys
import time

import boto3
import pyarrow as pa
import pyarrow.parquet as pq
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

NODE_REGEX = re.compile(r"(?:^|/)node/(i-[a-zA-Z0-9]+)/")
STEP_REGEX = re.compile(r"(?:^|/)steps/(s-[a-zA-Z0-9]+)/")
APPLICATION_REGEX = re.compile(r"(?:^|/)containers/(application_[a-zA-Z0-9_]+)/")

SCHEMA = pa.schema(
    [
        ("dag_id", pa.string()),
        ("id_emr_cluster", pa.string()),
        ("id_ec2_instance", pa.string()),
        ("node_role", pa.string()),
        ("ts_first_log", pa.timestamp("us", tz="UTC")),
        ("ts_last_log", pa.timestamp("us", tz="UTC")),
        ("object_count", pa.int64()),
        ("ts_cluster_first_log", pa.timestamp("us", tz="UTC")),
        ("ts_cluster_last_log", pa.timestamp("us", tz="UTC")),
        ("step_count", pa.int64()),
        ("application_count", pa.int64()),
    ]
)


def derive_cluster_rows(
    dag_id: str,
    id_emr_cluster: str,
    objects: list[tuple[str, datetime.datetime]],
) -> list[dict]:
    if not objects:
        return []

    cluster_first_log = min(timestamp for _, timestamp in objects)
    cluster_last_log = max(timestamp for _, timestamp in objects)

    step_ids: set[str] = set()
    application_ids: set[str] = set()
    node_objects: dict[str, list[tuple[str, datetime.datetime]]] = {}

    for key, timestamp in objects:
        step_match = STEP_REGEX.search(key)
        if step_match:
            step_ids.add(step_match.group(1))

        application_match = APPLICATION_REGEX.search(key)
        if application_match:
            application_ids.add(application_match.group(1))

        node_match = NODE_REGEX.search(key)
        if node_match:
            instance_id = node_match.group(1)
            if instance_id not in node_objects:
                node_objects[instance_id] = []
            node_objects[instance_id].append((key, timestamp))

    rows: list[dict] = []
    for instance_id, items in node_objects.items():
        node_keys = [key for key, _ in items]
        has_resource_manager = any(
            "hadoop-yarn-resourcemanager" in key for key in node_keys
        )
        has_name_node = any("hadoop-hdfs-namenode" in key for key in node_keys)
        has_data_node = any("hadoop-hdfs-datanode" in key for key in node_keys)
        has_node_manager = any("hadoop-yarn-nodemanager" in key for key in node_keys)

        if has_resource_manager or has_name_node:
            node_role = "MASTER"
        elif has_data_node:
            node_role = "CORE"
        elif has_node_manager:
            node_role = "TASK"
        else:
            node_role = "UNKNOWN"

        node_first_log = min(timestamp for _, timestamp in items)
        node_last_log = max(timestamp for _, timestamp in items)

        rows.append(
            {
                "dag_id": dag_id,
                "id_emr_cluster": id_emr_cluster,
                "id_ec2_instance": instance_id,
                "node_role": node_role,
                "ts_first_log": node_first_log,
                "ts_last_log": node_last_log,
                "object_count": len(items),
                "ts_cluster_first_log": cluster_first_log,
                "ts_cluster_last_log": cluster_last_log,
                "step_count": len(step_ids),
                "application_count": len(application_ids),
            }
        )

    return rows


def process_cluster(
    s3_client,
    bucket: str,
    dag_id: str,
    cluster_id: str,
    cluster_prefix: str,
) -> list[dict]:
    paginator = s3_client.get_paginator("list_objects_v2")
    objects: list[tuple[str, datetime.datetime]] = []
    for page in paginator.paginate(Bucket=bucket, Prefix=cluster_prefix):
        for item in page.get("Contents", []):
            objects.append((item["Key"], item["LastModified"]))
    return derive_cluster_rows(dag_id, cluster_id, objects)


def list_dag_prefixes(
    s3_client, bucket: str, prefix: str, dag_filter: str | None
) -> list[tuple[str, str]]:
    if prefix and not prefix.endswith("/"):
        prefix += "/"
    dag_prefixes: list[tuple[str, str]] = []
    for page in s3_client.get_paginator("list_objects_v2").paginate(
        Bucket=bucket, Prefix=prefix, Delimiter="/"
    ):
        for common_prefix in page.get("CommonPrefixes", []):
            dag_prefix = common_prefix["Prefix"]
            dag_id = dag_prefix.rstrip("/").split("/")[-1]
            if dag_filter and dag_filter not in dag_id:
                continue
            dag_prefixes.append((dag_id, dag_prefix))
    return dag_prefixes


def list_cluster_prefixes(
    s3_client, bucket: str, dag_prefix: str
) -> list[tuple[str, str]]:
    cluster_prefixes: list[tuple[str, str]] = []
    for page in s3_client.get_paginator("list_objects_v2").paginate(
        Bucket=bucket, Prefix=dag_prefix, Delimiter="/"
    ):
        for common_prefix in page.get("CommonPrefixes", []):
            cluster_prefix = common_prefix["Prefix"]
            cluster_id = cluster_prefix.rstrip("/").split("/")[-1]
            if cluster_id.startswith("j-"):
                cluster_prefixes.append((cluster_id, cluster_prefix))
    return cluster_prefixes


def write_parquet(rows: list[dict], output_path: str, chunk_size: int = 50_000) -> None:
    with pq.ParquetWriter(output_path, SCHEMA) as writer:
        if not rows:
            writer.write_table(pa.Table.from_batches([], schema=SCHEMA))
            return
        for index in range(0, len(rows), chunk_size):
            writer.write_table(
                pa.Table.from_pylist(rows[index : index + chunk_size], schema=SCHEMA)
            )


def process_dag(
    executor,
    s3_client,
    bucket: str,
    dag_id: str,
    dag_prefix: str,
    limit_clusters: int | None,
) -> tuple[int, list[dict]]:
    cluster_prefixes = list_cluster_prefixes(s3_client, bucket, dag_prefix)[
        :limit_clusters
    ]
    futures = {
        executor.submit(
            process_cluster, s3_client, bucket, dag_id, cluster_id, cluster_prefix
        ): cluster_id
        for cluster_id, cluster_prefix in cluster_prefixes
    }
    return len(cluster_prefixes), [
        row
        for future in concurrent.futures.as_completed(futures)
        for row in future.result()
    ]


def process_dag_with_retries(
    attempts: int = 4, **dag_arguments
) -> tuple[int, list[dict]]:
    for attempt in range(1, attempts + 1):
        try:
            return process_dag(**dag_arguments)
        except (BotoCoreError, ClientError) as error:
            if (
                isinstance(error, ClientError)
                and error.response["Error"]["Code"] == "ExpiredToken"
            ):
                raise
            if attempt == attempts:
                raise
            backoff_seconds = 10 * attempt
            sys.stderr.write(
                f"Attempt {attempt}/{attempts} failed for {dag_arguments['dag_id']}: {error}; "
                f"retrying in {backoff_seconds}s\n"
            )
            time.sleep(backoff_seconds)
    raise AssertionError("unreachable")


def run_self_test() -> None:
    base_time = datetime.datetime(2026, 5, 18, 10, 0, 0, tzinfo=datetime.timezone.utc)
    fake_items = [
        (
            "emr/logs/dags/bietlejuice.fake_dag/j-TESTCLUSTER/node/i-master01/applications/hadoop-yarn/hadoop-yarn-resourcemanager.log.gz",
            base_time + datetime.timedelta(minutes=5),
        ),
        (
            "emr/logs/dags/bietlejuice.fake_dag/j-TESTCLUSTER/node/i-master01/applications/hadoop-hdfs/hadoop-hdfs-namenode.log.gz",
            base_time + datetime.timedelta(minutes=10),
        ),
        (
            "emr/logs/dags/bietlejuice.fake_dag/j-TESTCLUSTER/node/i-core01/applications/hadoop-hdfs/hadoop-hdfs-datanode.log.gz",
            base_time + datetime.timedelta(minutes=2),
        ),
        (
            "emr/logs/dags/bietlejuice.fake_dag/j-TESTCLUSTER/node/i-core01/applications/hadoop-yarn/hadoop-yarn-nodemanager.log.gz",
            base_time + datetime.timedelta(minutes=15),
        ),
        (
            "emr/logs/dags/bietlejuice.fake_dag/j-TESTCLUSTER/node/i-task01/applications/hadoop-yarn/hadoop-yarn-nodemanager.log.gz",
            base_time + datetime.timedelta(minutes=8),
        ),
        (
            "emr/logs/dags/bietlejuice.fake_dag/j-TESTCLUSTER/steps/s-step01/syslog.gz",
            base_time + datetime.timedelta(minutes=1),
        ),
        (
            "emr/logs/dags/bietlejuice.fake_dag/j-TESTCLUSTER/steps/s-step02/syslog.gz",
            base_time + datetime.timedelta(minutes=20),
        ),
        (
            "emr/logs/dags/bietlejuice.fake_dag/j-TESTCLUSTER/containers/application_12345_0001/container_1/stdout.gz",
            base_time + datetime.timedelta(minutes=12),
        ),
    ]

    rows = derive_cluster_rows("bietlejuice.fake_dag", "j-TESTCLUSTER", fake_items)
    assert len(rows) == 3, f"Expected 3 rows, got {len(rows)}"

    rows_by_instance = {row["id_ec2_instance"]: row for row in rows}
    assert "i-master01" in rows_by_instance
    assert "i-core01" in rows_by_instance
    assert "i-task01" in rows_by_instance

    master = rows_by_instance["i-master01"]
    assert master["node_role"] == "MASTER", (
        f"Expected MASTER, got {master['node_role']}"
    )
    assert master["object_count"] == 2
    assert master["ts_first_log"] == base_time + datetime.timedelta(minutes=5)
    assert master["ts_last_log"] == base_time + datetime.timedelta(minutes=10)

    core = rows_by_instance["i-core01"]
    assert core["node_role"] == "CORE", f"Expected CORE, got {core['node_role']}"
    assert core["object_count"] == 2
    assert core["ts_first_log"] == base_time + datetime.timedelta(minutes=2)
    assert core["ts_last_log"] == base_time + datetime.timedelta(minutes=15)

    task = rows_by_instance["i-task01"]
    assert task["node_role"] == "TASK", f"Expected TASK, got {task['node_role']}"
    assert task["object_count"] == 1
    assert task["ts_first_log"] == base_time + datetime.timedelta(minutes=8)
    assert task["ts_last_log"] == base_time + datetime.timedelta(minutes=8)

    for row in rows:
        assert row["dag_id"] == "bietlejuice.fake_dag"
        assert row["id_emr_cluster"] == "j-TESTCLUSTER"
        assert row["step_count"] == 2, f"Expected 2 steps, got {row['step_count']}"
        assert row["application_count"] == 1, (
            f"Expected 1 application, got {row['application_count']}"
        )
        assert row["ts_cluster_first_log"] == base_time + datetime.timedelta(minutes=1)
        assert row["ts_cluster_last_log"] == base_time + datetime.timedelta(minutes=20)

    print("OK")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Enumerate EMR S3 log tree to seed cluster and instance identity."
    )
    parser.add_argument(
        "--bucket",
        default="artifacts.s3.data.quintoandar.com.br",
        help="S3 bucket containing EMR logs.",
    )
    parser.add_argument(
        "--prefix",
        default="emr/logs/dags/",
        help="S3 prefix for EMR DAG logs.",
    )
    parser.add_argument(
        "--output",
        default="/tmp/emr_log_identity_seed",
        help="Output directory; one <dag_id>.parquet per DAG, existing files are skipped so a run can resume.",
    )
    parser.add_argument(
        "--dag-filter",
        default=None,
        help="Optional DAG ID substring filter.",
    )
    parser.add_argument(
        "--limit-clusters",
        type=int,
        default=None,
        help="Optional limit on clusters per DAG (smoke runs).",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=16,
        help="Number of worker threads.",
    )
    parser.add_argument(
        "--region",
        default="us-east-1",
        help="AWS region.",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run offline self-test and exit.",
    )

    arguments = parser.parse_args()

    if arguments.self_test:
        run_self_test()
        sys.exit(0)

    client_config = Config(
        retries={"max_attempts": 10, "mode": "adaptive"},
        max_pool_connections=max(arguments.workers * 2, 20),
    )
    s3_client = boto3.client("s3", region_name=arguments.region, config=client_config)

    os.makedirs(arguments.output, exist_ok=True)
    dag_prefixes = list_dag_prefixes(
        s3_client, arguments.bucket, arguments.prefix, arguments.dag_filter
    )
    start_time = time.monotonic()
    clusters_done = 0
    rows_written = 0

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=arguments.workers
    ) as executor:
        for dag_index, (dag_id, dag_prefix) in enumerate(dag_prefixes, start=1):
            output_path = os.path.join(arguments.output, f"{dag_id}.parquet")
            if os.path.exists(output_path):
                continue
            cluster_count, rows = process_dag_with_retries(
                executor=executor,
                s3_client=s3_client,
                bucket=arguments.bucket,
                dag_id=dag_id,
                dag_prefix=dag_prefix,
                limit_clusters=arguments.limit_clusters,
            )
            write_parquet(rows, output_path)
            clusters_done += cluster_count
            rows_written += len(rows)
            elapsed = time.monotonic() - start_time
            sys.stderr.write(
                f"[{elapsed:.0f}s] {dag_index}/{len(dag_prefixes)} {dag_id}: "
                f"{cluster_count:,} clusters; total {clusters_done:,} clusters, {rows_written:,} rows\n"
            )

    sys.stderr.write(
        f"Finished {clusters_done:,} clusters ({rows_written:,} rows) in {time.monotonic() - start_time:.0f}s\n"
    )


if __name__ == "__main__":
    main()
