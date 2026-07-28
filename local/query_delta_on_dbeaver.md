# Querying Delta Tables in DBeaver

Guide for querying data lake Delta tables directly in [DBeaver](https://dbeaver.io/) without spinning up a Spark cluster. Useful for ad hoc inspection of data not available in Superset/Trino.

## Use cases

- Ad hoc queries on **raw** or **adhoc** tables before they are exposed in Superset.
- Quick data validation after a DAG run on Forno.
- Exploring tables in legacy databases or layers not yet published in the catalog.

> **Limitation:** DuckDB reads the current state of a Delta table but does not replicate Spark cluster optimizations (partitioning, advanced pushdown, UDFs). For heavy queries or pipeline logic, use Spark/EMR or Trino.

## Prerequisites

| Item | Details |
|------|---------|
| [DBeaver](https://dbeaver.io/download/) | Community or Enterprise |
| DuckDB extension | Installed automatically when creating a DuckDB connection in DBeaver |
| AWS credentials | Read access to the data lake bucket (`5a-datalake-forno` or `5a-datalake-prod`) |
| [Weep](https://github.com/Netflix/weep) or [QLI](https://github.com/quintoandar/qli) | To obtain temporary credentials via ConsoleMe |

### Recommended AWS role

```
sso_DataAndAnalyticsManagement_Staff
```

Use the role your team is allowed to assume in ConsoleMe. Adjust if needed.

## 1. Authenticate with AWS

Credentials must be available in your local environment **before** connecting in DBeaver. DuckDB uses the *credential chain* (`config → sso → env`).

### Option A — Weep (legacy)

```bash
weep file
```

This writes the `default` profile to `~/.aws/credentials`. Renew when it expires (`ExpiredToken`).

### Option B — QLI (recommended)

```bash
qli aws file
```

Exports `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN` into the terminal session. If DBeaver was launched from that terminal, the environment variables are also available to DuckDB.

## 2. Create a DuckDB connection in DBeaver

1. **Database → New Database Connection → DuckDB**.
2. Under **Path**, select an existing `.duckdb` file or specify a new path (e.g. `~/duckdb-lake.duckdb`). The file stores local schemas and views — the data itself remains on S3.
3. Test the connection and save.

## 3. Bootstrap queries (S3 authentication)

Open **Edit Connection → Connection Settings → Initialization → Bootstrap queries → Configure** and paste the SQL below.

This script runs every time the connection is (re)opened, reloading extensions and AWS credentials:

```sql
INSTALL aws; LOAD aws;
INSTALL delta; LOAD delta;
INSTALL httpfs; LOAD httpfs;

CREATE OR REPLACE SECRET secret (
   TYPE s3,
   PROVIDER credential_chain,
   CHAIN 'config;sso;env',  -- skips EC2 metadata check (IP error)
   REGION 'us-east-1',
   REFRESH auto
);

CALL load_aws_credentials('default');
```

| Parameter | Description |
|-----------|-------------|
| `CHAIN 'config;sso;env'` | Lookup order: `~/.aws/credentials` → SSO cache → environment variables |
| `REGION` | Bucket region (`us-east-1` for standard data lake buckets) |

> If you use an AWS profile other than `default`, change the argument in `load_aws_credentials('...')`.

## 4. S3 path convention

Delta tables in bi-etl-ejuice follow this pattern:

```
s3://5a-datalake-{environment}/{layer}/{schema}/{table}/
```

| Environment | Bucket |
|-------------|--------|
| Forno (dev/staging) | `5a-datalake-forno` |
| Production | `5a-datalake-prod` |

| Layer | Path example |
|-------|--------------|
| raw | `s3://5a-datalake-forno/raw/sales_flow/sales_flow/` |
| clean | `s3://5a-datalake-forno/clean/sales_flow/sales_flow/` |
| enrich | `s3://5a-datalake-forno/enrich/sale_offer/core_sale_offer/` |
| dw | `s3://5a-datalake-forno/dw/...` |

The path ends at the **Delta table folder** (where `_delta_log/`, `part-*.parquet`, etc. live). Confirm with `DESCRIBE TABLE EXTENDED <schema>.<table>` in Databricks if unsure.

## 5. Querying data

### Direct query with `delta_scan`

```sql
SELECT *
FROM delta_scan('s3://5a-datalake-forno/raw/sales_flow/sales_flow');
```

### Create schema + view (recommended for reuse)

Organize views by lake database, mirroring the Hive/Databricks schema name:

```sql
CREATE SCHEMA IF NOT EXISTS datalake_sales_flow_raw_forno;

CREATE OR REPLACE VIEW datalake_sales_flow_raw_forno.sales_flow AS
SELECT *
FROM delta_scan('s3://5a-datalake-forno/raw/sales_flow/sales_flow');
```

Then query as usual:

```sql
SELECT id, ts_created
FROM datalake_sales_flow_raw_forno.sales_flow
LIMIT 100;
```

Views are saved in the local `.duckdb` file and persist across sessions.

## 6. Summary flow

```
ConsoleMe (Weep/QLI)  →  ~/.aws/credentials or env vars
        ↓
DBeaver + DuckDB (bootstrap queries load extensions + credentials)
        ↓
delta_scan('s3://...')  or  local VIEW pointing to the path
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `ExpiredToken` / `403 Forbidden` | Expired credentials | Renew via Weep/QLI and reconnect in DBeaver |
| EC2 metadata / IP error | Chain tried instance role | Keep `CHAIN 'config;sso;env'` (no `ec2`) |
| `IO Error: No files found` | Incorrect S3 path | Verify layer/schema/table; check with `DESCRIBE TABLE EXTENDED` |
| Extension not found | Bootstrap did not run | Reopen connection; check Initialization → Bootstrap queries |
| Very slow query | Large table without filters | Add `WHERE` on partition columns (`year`, `month`, `day`) when available |
| Unreadable struct/array columns | Client limitation | Select specific fields instead of `SELECT *` |

## References

- [DuckDB — Delta extension](https://duckdb.org/docs/extensions/delta)
- [DuckDB — AWS extension](https://duckdb.org/docs/extensions/aws)
- Lake buckets and layers: conventions in `dags/**/forno_conf.yml` and `ConfigurationService` in the bi-etl-ejuice repository.
