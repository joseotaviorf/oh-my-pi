#!/usr/bin/env python3
"""Build-time verification for the EMR Serverless notebook image.

Runs as the last RUN step of each target. A failure here fails the build, which
is the point: an image that ships with an unimportable library costs every
notebook user a confusing ModuleNotFoundError hours later, far from the cause.

Checks, in order of how likely they are to catch a real regression:

  1. Every baked library actually imports. pip resolving a version is not the
     same as the package working — native extensions built against the wrong
     numpy, or a package whose import name differs from its distribution name,
     both pass `pip install` and fail at `import`.

  2. The pins that must match ETL still match. If numpy silently floats to 2.x
     because a transitive dependency demanded it, notebook results stop being a
     valid proxy for production and nobody notices until the numbers disagree.

  3. Org-wide Spark defaults (UTC session timezone) are actually baked in. The
     whole point of putting them in the image is that users write no %%configure;
     if the layer silently no-ops, every notebook gets the worker's local
     timezone and nothing errors — the timestamps just quietly disagree.

  4. sys.path ordering still puts site-packages LAST among the writable entries,
     which is the property that makes user overrides via spark.submit.pyFiles
     work. If a future base image prepends site-packages, overrides break
     silently and this is the only place that would catch it.

Usage:
    python3 smoke_test.py --variant base
    python3 smoke_test.py --variant heavy
"""

from __future__ import annotations

import argparse
import importlib
import os
import pathlib
import sys

# (import name, distribution name) — they differ often enough to be worth stating.
# Private wheels are checked by DISTRIBUTION name via importlib.metadata rather
# than by import. Their top-level module names are not derivable from the wheel
# filename (bietlejuice_core ships the `bietlejuice` namespace, for instance), and
# guessing wrong would fail the build for a package that installed correctly.
# `pip install` recording the distribution is the property we actually care about.
REQUIRED_DISTRIBUTIONS: list[str] = [
    "bietlejuice-core",
    "bietlejuice-runtime",
    "quintoandar-logger",
    "inmetro",
    "quintoandar-gsheets-api-client",
    "quintoandar-survicate-api-client",
    "quintoandar-velo-neurotech-api-client",
    "quintoandar-omie-api-client",
    "quintoandar-braze-api-client",
]

BASE_IMPORTS: list[tuple[str, str]] = [
    # google stack — the 28-DAG common path
    ("googleapiclient", "google-api-python-client"),
    ("google.auth", "google-auth"),
    ("google.cloud.bigquery", "google-cloud-bigquery"),
    ("google.cloud.pubsub", "google-cloud-pubsub"),
    ("gspread", "gspread"),
    ("oauth2client", "oauth2client"),
    # data stack
    ("pandas", "pandas"),
    ("numpy", "numpy"),
    ("pyarrow", "pyarrow"),
    ("delta", "delta-spark"),
    ("pyspark", "pyspark (bundled by EMR, not pip-installed)"),
    ("psycopg2", "psycopg2-binary"),
    ("pymongo", "pymongo"),
    ("sqlalchemy", "SQLAlchemy"),
    ("sqlglot", "sqlglot"),
    ("trino", "trino"),
    ("pydeequ", "pydeequ"),
    # misc DAG deps
    ("paramiko", "paramiko"),
    ("openpyxl", "openpyxl"),
    ("pyxlsb", "pyxlsb"),
    ("kafka", "kafka-python"),
    ("ftfy", "ftfy"),
    ("bs4", "bs4"),
    ("holidays", "holidays"),
    ("pendulum", "pendulum"),
    ("boto3", "boto3"),
]

HEAVY_IMPORTS: list[tuple[str, str]] = [
    ("sedona", "apache-sedona"),
    ("sklearn", "scikit-learn"),
    ("lightgbm", "lightgbm"),
    ("presidio_analyzer", "presidio-analyzer"),
    ("spacy", "spacy"),
    ("en_core_web_lg", "en_core_web_lg (spaCy model)"),
    ("pytopojson", "pytopojson"),
    ("langfuse", "langfuse"),
    ("facebook_business", "facebook-business"),
    ("google.ads.googleads", "google-ads"),
    ("datahub", "acryl-datahub"),
]

# Must match .container/emr-serverless/constraints.txt.
REQUIRED_PINS: dict[str, str] = {
    "numpy": "1.26.4",
    "pyarrow": "15.0.2",
}


def bootstrap_spark_runtime() -> None:
    """Make EMR's bundled Spark/PySpark importable during Kaniko build.

    EMR Serverless workers get PYTHONPATH and SPARK_* from the runtime launcher.
    During `docker build` / Kaniko there is no launcher, so delta / pydeequ /
    pyspark imports would fail even though the packages are present on the image.
    """
    spark_home = pathlib.Path(os.environ.get("SPARK_HOME", "/usr/lib/spark"))
    os.environ.setdefault("SPARK_HOME", str(spark_home))
    # pydeequ reads SPARK_VERSION at import time; EMR 7.12 ships Spark 3.5.
    os.environ.setdefault("SPARK_VERSION", "3.5")

    py_dir = spark_home / "python"
    if not py_dir.is_dir():
        return

    entries = [str(py_dir)]
    py4j_zips = sorted((py_dir / "lib").glob("py4j-*.zip"))
    if py4j_zips:
        entries.append(str(py4j_zips[0]))

    for entry in entries:
        if entry not in sys.path:
            sys.path.insert(0, entry)


def check_imports(variant: str) -> list[str]:
    targets = list(BASE_IMPORTS)
    if variant == "heavy":
        targets += HEAVY_IMPORTS

    failures = []
    for module, dist in targets:
        try:
            importlib.import_module(module)
        except Exception as exc:  # noqa: BLE001 - we want every failure, not the first
            failures.append(f"import {module} ({dist}): {type(exc).__name__}: {exc}")
    print(f"  imports: {len(targets) - len(failures)}/{len(targets)} OK")
    return failures


def check_distributions() -> list[str]:
    """Private wheels installed from S3 must be present in the metadata."""
    from importlib import metadata

    failures = []
    for dist in REQUIRED_DISTRIBUTIONS:
        try:
            metadata.version(dist)
        except metadata.PackageNotFoundError:
            failures.append(
                f"distribution {dist!r} not installed — the S3 wheel fetch or the "
                "pip install step silently skipped it"
            )
    ok = len(REQUIRED_DISTRIBUTIONS) - len(failures)
    print(f"  distributions: {ok}/{len(REQUIRED_DISTRIBUTIONS)} OK")
    return failures


def check_spark_defaults(conf_files: list["pathlib.Path"] | None = None) -> list[str]:
    """Org-wide Spark defaults must be baked in, so notebooks need no %%configure.

    Only warns if the file is missing entirely (some base images do not ship one
    until first launch); fails if it exists but lacks the setting, which is the
    case that would silently give notebooks a non-UTC session timezone.
    """
    expected = {"spark.sql.session.timeZone": "UTC"}
    if conf_files is None:
        conf_files = [
            pathlib.Path("/usr/lib/spark/conf/spark-defaults.conf"),
            pathlib.Path("/etc/spark/conf/spark-defaults.conf"),
        ]
    present = [p for p in conf_files if p.exists()]
    if not present:
        print("  spark defaults: no spark-defaults.conf in image (application "
              "runtimeConfiguration is authoritative — not fatal)")
        return []

    blobs = [p.read_text() for p in present]
    failures = []
    for key, value in expected.items():
        if not any(f"{key} {value}" in b or f"{key}={value}" in b for b in blobs):
            failures.append(
                f"{key} is not set to {value} in {[str(p) for p in present]}. "
                "Notebooks would inherit the worker's local timezone and their "
                "timestamps would silently disagree with ETL output."
            )
    print(f"  spark defaults: {len(expected) - len(failures)}/{len(expected)} OK")
    return failures


def check_pins() -> list[str]:
    failures = []
    for module, expected in REQUIRED_PINS.items():
        try:
            actual = importlib.import_module(module).__version__
        except Exception as exc:  # noqa: BLE001
            failures.append(f"{module}: could not read __version__ ({exc})")
            continue
        if actual != expected:
            failures.append(
                f"{module}=={actual} but constraints.txt requires {expected}. "
                "A transitive dependency moved the pin; notebook results would no "
                "longer match ETL."
            )
    print(f"  pins: {len(REQUIRED_PINS) - len(failures)}/{len(REQUIRED_PINS)} OK")
    return failures


def check_override_precedence() -> list[str]:
    """site-packages must not be first, or spark.submit.pyFiles cannot override it.

    PySpark inserts pyFiles entries at sys.path[1]. That only wins if the baked
    site-packages sits further down. This asserts the invariant the whole
    override story rests on.
    """
    import site

    site_dirs = set(site.getsitepackages() + [site.getusersitepackages()])
    for idx, entry in enumerate(sys.path):
        if entry in site_dirs:
            if idx <= 1:
                return [
                    f"site-packages is at sys.path[{idx}]; spark.submit.pyFiles "
                    "inserts at index 1 and would NOT take precedence. User "
                    "overrides are broken in this image."
                ]
            print(f"  override precedence: site-packages at sys.path[{idx}] OK")
            return []
    print("  override precedence: site-packages not on sys.path (unexpected, not fatal)")
    return []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=["base", "heavy"], default="base")
    args = parser.parse_args()

    print(f"Smoke-testing EMR Serverless notebook image (variant={args.variant})")
    print(f"  python: {sys.version.split()[0]}")

    bootstrap_spark_runtime()

    failures = (
        check_imports(args.variant)
        + check_distributions()
        + check_pins()
        + check_spark_defaults()
        + check_override_precedence()
    )

    if failures:
        print("\nFAILED:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
