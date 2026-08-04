# EMR Serverless notebook image

Custom EMR Serverless image for SageMaker Unified Studio notebooks. This is the
replacement for Databricks `cluster.custom_libraries`.

- Dockerfile: `.container/Dockerfile.emr-serverless`
- Build context: `.container/emr-serverless/`
- Application Spark config: `.container/emr-serverless/application-runtime-configuration.json`
- CI: `.woodpecker/emr-serverless-image.yml`
- ECR repo: `796143582747.dkr.ecr.us-east-1.amazonaws.com/quintoandar/bi-etl-ejuice`

## Why an image at all

On Databricks, a notebook attached to a cluster inherited whatever that cluster
had installed. One `custom_libraries` block, and every notebook on the cluster
could import it.

EMR Serverless has no cluster to install onto. Workers are created per Spark
session and destroyed after it. There is nothing long-lived to attach libraries
to, so the equivalent of a cluster library is a library baked into the image the
workers boot from.

There is a second, less obvious difference. On Databricks the notebook kernel
*was* the Spark driver, so one install covered both. Here they are separate:

| | Runs where | Gets libraries from |
|---|---|---|
| Notebook kernel | The JupyterLab space | `%pip install` in the notebook, or the space's own image |
| Spark driver + executors | EMR Serverless workers | **This image**, or `spark.submit.pyFiles` |

A `%pip install` in a notebook cell does **not** reach the workers, and this
image does **not** reach the notebook kernel. Most confusing errors during
migration trace back to that split — a UDF failing to import something the
driver could see fine.

## The two variants

| Tag | Contents | Use when |
|---|---|---|
| `prod-emr-serverless-base-latest` | bietlejuice core/runtime/logger/inmetro, the google stack, 5 shared API clients, pandas/numpy/pyarrow, Delta 3.3.2, JDBC + observability JARs | Default. Covers the large majority of notebooks. |
| `prod-emr-serverless-heavy-latest` | base + Sedona, scikit-learn, LightGBM, Presidio, spaCy + `en_core_web_lg`, pytopojson, langfuse, facebook-business, google-ads, acryl-datahub | Geo, ML, or anonymization work. ~1 GB larger, slower cold start. |

Immutable `-<sha7>` tags are published alongside `-latest`. Pin an application
to a `-<sha7>` tag if you need reproducibility across a backfill.

## Spark configuration (no notebook setup required)

Org-wide Spark settings are applied for users — nobody needs to paste a
`%%configure` block to get correct behaviour.

| Setting | Value | Why |
|---|---|---|
| `spark.sql.session.timeZone` | `UTC` | Timestamps are stored and compared in UTC across the lake. Without it a notebook inherits the worker's local timezone and every timestamp comparison silently disagrees with ETL output — nothing errors, the numbers just differ. Matches the fixtures in `packages/bietlejuice-runtime/test/**/conftest.py`. |

These are applied in **two places on purpose**:

1. `.container/emr-serverless/spark-defaults-quintoandar.conf` — appended to the
   image's `spark-defaults.conf`.
2. `.container/emr-serverless/application-runtime-configuration.json` — the
   application's `runtimeConfiguration`.

The second is authoritative. EMR Serverless regenerates `spark-defaults.conf`
when it launches a worker, and AWS does not document a guarantee that image-baked
values survive that, so the image copy is defence in depth rather than the
mechanism. **Keep the two files in sync**; if they disagree, the application
config wins and the image file is the one that is wrong.

Precedence, lowest to highest:

```
image spark-defaults.conf  <  application runtimeConfiguration  <  %%configure in a notebook
```

A user can still override any of it per-notebook — the defaults remove the
obligation, not the option.

Apply the application config with:

```bash
aws emr-serverless update-application \
  --application-id <app-id> \
  --runtime-configuration file://.container/emr-serverless/application-runtime-configuration.json
```

`smoke_test.py` asserts the timezone landed at build time, because a silently
no-op config layer is exactly the failure that would go unnoticed for months.

To add a setting: put it in **both** files, regenerate nothing, open a PR, and
re-apply the runtime configuration after the image is published.

## Overriding what is baked in

**You do not need a rebuild to use a different version.** Everything in the image
is installed into site-packages. PySpark inserts anything passed via
`spark.submit.pyFiles` at `sys.path[1]`, ahead of site-packages, so your copy
wins.

This works because every `quintoandar_*_api_client` wheel is pure-Python
(`py2.py3-none-any`). Wheels with compiled extensions cannot be overridden this
way — for those, use `spark.archives` with a `venv-pack` archive.

The image asserts this precedence at build time (`smoke_test.py`), so if a
future base image breaks it, CI catches it rather than your notebook.

### Override an internal client version

```
%%configure -n <compute_name> -f
{
  "conf": {
    "spark.submit.pyFiles": "s3://artifacts.s3.data.quintoandar.com.br/gsheets-api-client-python/quintoandar_gsheets_api_client-0.3.0-py2.py3-none-any.whl"
  }
}
```

### Add a client that is not baked in

The 10 single-use API clients (airtable, criteo, facebook, hr_system, hubspot,
jira, reclameaqui, sap_4hana, tracksale, twilio_flex_insights) are deliberately
left out to keep the image small:

```
%%configure -n <compute_name> -f
{
  "conf": {
    "spark.submit.pyFiles": "s3://artifacts.s3.data.quintoandar.com.br/jira-api-client-python/quintoandar_jira_api_client-0.3.2-py2.py3-none-any.whl"
  }
}
```

Comma-separate for several wheels.

> **`%%configure` replaces, it does not append.** Setting `spark.submit.pyFiles`
> overwrites any value inherited from the application's `runtimeConfiguration`.
> It does not affect libraries baked into the image — those are always present —
> but if your platform team later sets application-level defaults, list them
> alongside yours.

### Override a PyPI package

Pure-Python packages can go through `pyFiles`. Anything with compiled extensions
(numpy, pyarrow, scikit-learn, lightgbm) needs a full environment swap:

```
%%configure -n <compute_name> -f
{
  "conf": {
    "spark.archives": "s3://<bucket>/venvs/my_env.tar.gz#environment",
    "spark.emr-serverless.driverEnv.PYSPARK_DRIVER_PYTHON": "./environment/bin/python",
    "spark.emr-serverless.driverEnv.PYSPARK_PYTHON": "./environment/bin/python",
    "spark.executorEnv.PYSPARK_PYTHON": "./environment/bin/python"
  }
}
```

Build the archive on Amazon Linux with the same Python version as the image
(3.9), or it will fail at import with cryptic ABI errors.

### What is actually in this image?

```python
import json
print(json.load(open("/opt/quintoandar/image-manifest.json")))   # release, variant, python, build time
print(open("/opt/quintoandar/pip-freeze.txt").read())            # every pinned version
```

## Pinned-on-purpose versions

Most packages float to the newest release compatible with Python 3.9. A few are
frozen in `.container/emr-serverless/constraints.txt` because they change results
rather than just APIs:

| Package | Pin | Why |
|---|---|---|
| `numpy` | `1.26.4` | 2.x changes dtype promotion. DBR 16.4 and 3 DAGs pin this; floating it would make notebook output diverge from ETL output silently. |
| `pyarrow` | `15.0.2` | Arrow format compatibility with the bundled PySpark. |
| `urllib3` | `<1.27` | 2.x breaks the awscli/botocore in the EMR base image. |
| `python-dateutil` | `<=2.9.0` | Same awscli compatibility constraint. |
| `psycopg2-binary` | `2.9.9` | The runtime wheel omits psycopg2 (DBR bundled it); EMR does not. |

`smoke_test.py` asserts numpy and pyarrow at build time, so a transitive
dependency cannot quietly move them.

## Python version

The image targets **Python 3.9**, EMR 7.12's default interpreter, matching
`packages/bietlejuice-compiler/scripts/emr_init_script.sh`. That is what makes a
notebook a trustworthy proxy for the DAG it mirrors.

Two known costs:

- The bietlejuice and inmetro wheels declare `Requires-Python >=3.10` and are
  installed with `--ignore-requires-python`. Validated on EMR 7.12; same
  workaround the ETL bootstrap already uses.
- `acryl-datahub` resolves to the newest 3.9-compatible release rather than the
  `1.4.0` the governance DAGs pin, which requires 3.10+.

When the ETL moves to EMR 7.13+ (where Python 3.11 is the default), flip
`PYTHON_BIN` in the Dockerfile, regenerate the locks with `--python-version 3.11`,
and drop `--ignore-requires-python`.

## Operating it

### Build locally

```bash
# AWS credentials must be in the environment — make runs fetch-artifacts.sh first
make build-emr-serverless-notebook          # base
make build-emr-serverless-notebook-heavy    # heavy
```

CI uses the same script via Woodpecker (`.woodpecker/emr-serverless-image.yml`):
`fetch-artifacts.sh` runs on `prod-ci-base` with a one-shot AWS CLI install (same
pattern as `development.yml`), then `plugins/docker` builds with only `COPY` from
the clone — like [beethoven](https://github.com/quintoandar/beethoven) image
publishes, which never pass AWS secrets to the docker plugin.

### Validate in forno before merging

`prod-` tags only publish from `master`, so nothing below requires merging first.
Three levels, cheapest first — stop as soon as you have your answer.

**1. Library set only, no image (minutes).** If the question is "do these
libraries actually solve my problem on EMR Spark 3.5", answer it with `pyFiles`
against any existing forno application. Same `sys.path` precedence the image
gives you, no build:

```
%%configure -n <compute_name> -f
{
  "conf": {
    "spark.submit.pyFiles": "s3://artifacts.s3.forno.data.quintoandar.com.br/<path>/<wheel>.whl"
  }
}
```

**2. Local build + AWS's offline validator.** Catches image-level breakage
(user, entrypoint, `*_HOME` variables, file structure) without touching ECR:

```bash
make build-emr-serverless-notebook
# https://github.com/awslabs/amazon-emr-serverless-image-cli
amazon-emr-serverless-image validate-image \
  -r emr-7.12.0 -t spark -i bi-etl-ejuice:emr-serverless-base-latest
```

`smoke_test.py` has already run as the final build layer, so a successful build
means every import resolves. Check `docker images` too — EMR Serverless rejects
images over **10 GB**, and the heavy variant is the one to watch.

To validate against forno-published libraries rather than prod ones:

```bash
make build-emr-serverless-notebook \
  ARTIFACTS_BUCKET=s3://artifacts.s3.forno.data.quintoandar.com.br
```

**3. End-to-end in forno.** Push to the `forno` branch or trigger this pipeline
**manually** on your feature branch in Woodpecker. That publishes
`forno-emr-serverless-{base,heavy}-latest` and `-<sha7>`
(see `.woodpecker/emr-serverless-image.yml`), then:

```bash
aws emr-serverless update-application \
  --application-id <forno-app-id> \
  --image-configuration imageUri=796143582747.dkr.ecr.us-east-1.amazonaws.com/quintoandar/bi-etl-ejuice:forno-emr-serverless-base-<sha7>
```

Use the immutable `-<sha7>` tag, not `-latest`, so there is no ambiguity about
which build a notebook actually exercised.

Find the application id with `aws emr-serverless list-applications` in the
forno-data account (`713278628093`). These applications are created by the
SageMaker Unified Studio `EmrServerless` blueprint for projects in the
`Forno_DataAndAI` domain (`dzd-4f640dnkwmj8pz`) — **confirm that a
blueprint-managed application retains a hand-set `imageConfiguration`** before
depending on it; if the blueprint reverts it, the image has to be set through the
project profile instead.

> **Prerequisite for level 3.** The ECR repository policy must include
> `EmrServerlessCustomImageSupport` for `emr-serverless.amazonaws.com` (see
> `infrastructure/cloud/apps/bi-etl-ejuice/shared/ecr/ecr.tf`).

### Change the library set

1. Edit `requirements-base.in` / `requirements-heavy.in` (PyPI) or
   `internal-wheels.txt` / `jars.txt` (S3 artifacts).
2. `make lock-emr-serverless-notebook` and review the lock diff.
3. Open a PR — CI builds the image, and the build fails if any import breaks.
4. On merge to `master`, new tags are published to ECR.
5. **Update the EMR Serverless application to the new tag.** Images resolve at
   application update time, not per job run, so a new tag does nothing until the
   application points at it.

### IAM

Two distinct principals, and mixing them up is the most common setup failure:

- **Woodpecker pipeline IAM role** needs `s3:GetObject` on
  `artifacts.s3.data.quintoandar.com.br` so `fetch-artifacts.sh` can stage wheels
  and JARs before the image build. No Woodpecker repo secrets are involved.
- **EMR Serverless runtime role** needs `s3:GetObject` on the same bucket only if
  notebooks use `spark.submit.pyFiles` overrides. Baked libraries need no runtime
  S3 access.

Neither is the user's SSO role, which is what Databricks used.

### Attach the image to an application

```bash
aws emr-serverless update-application \
  --application-id <app-id> \
  --image-configuration imageUri=796143582747.dkr.ecr.us-east-1.amazonaws.com/quintoandar/bi-etl-ejuice:prod-emr-serverless-base-latest
```

The application must be in `STOPPED` state to update the image, and the EMR
Serverless service principal needs pull access to the ECR repository — see the
prerequisite note under [Validate in forno before merging](#validate-in-forno-before-merging).

## Mapping from the Databricks config

| Databricks | EMR Serverless notebook |
|---|---|
| `cluster.custom_libraries: [{whl: ...}]` | Baked into the image, or `spark.submit.pyFiles` |
| `cluster.custom_libraries: [{pypi: ...}]` | `requirements-base.in` / `requirements-heavy.in` |
| `cluster.custom_libraries: [{jar: ...}]` | `jars.txt` (copied onto the Spark classpath) |
| `default_libraries` in `prod_conf.yml` | `internal-wheels.txt` |
| `cluster.custom_configurations.spark_conf` | `application-runtime-configuration.json` for org-wide defaults; `%%configure` for per-notebook overrides |
| Init script | Dockerfile layers |
