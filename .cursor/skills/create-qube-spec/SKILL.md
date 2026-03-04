---
name: create-qube-spec
description: Scaffold a Qube semantic layer spec (dimension, measure, or metric) in bi-etl-ejuice. Creates the declaration YAML in the correct dags/qube/ folder. Use when the user asks to create a Qube dimension, measure, metric, or qube_spec.
---

# Create a Qube Spec

## Step 1 — Gather inputs

Ask the user (or infer from context):
1. **Spec type**: dimension, measure, or metric?
2. **Entity**: core entity name (e.g. `contract`, `visit`, `listing`, `offer`)
3. **Name**: specific dimension/measure/metric name (e.g. `contract_status`, `visit_total`)
4. **Windows** (optional, default `[1, 7, 28]`): rolling time windows in days

For **dimensions**, also ask:
- Source table and date expression (SQL expression returning Unix timestamp in seconds)
- Which columns to select
- Logic: cardinality (`single`/`multi`), value type (`string`/`number`/`boolean`), aggregation (`last`, `count`, etc.)

For **measures**, also ask:
- Source date expression
- Filter SQL (a boolean SQL expression; use `"TRUE"` for no filter)

For **metrics**, also ask:
- Which existing dimensions to reference (by name)
- Which existing measures to reference (by name)
- Counter type: `long` (exact) or `approx` (HyperLogLog, faster at scale)
- k-anonymity value (default `1`)

## Step 2 — Determine folder and DAG name

| Spec type | Folder | DAG name |
|-----------|--------|----------|
| dimension | `dags/qube/dimensions_{entity}_{name}/` | `qube_dimension_{entity}_{name}` |
| measure | `dags/qube/measures_{entity}_{name}/` | `qube_measure_{entity}_{name}` |
| metric | `dags/qube/metrics_{entity}_{name}/` | `qube_metric_{entity}_{name}` |

## Step 3 — Write the declaration file

File: `dags/qube/{folder}/{dag_name}_declaration.yml`

**Dimension:**
```yaml
dag:
  name: qube_dimension_{entity}_{name}
  schedule_start_date: "2025, 1, 1"
  schedule_interval: "0 5 * * *"
  owner: Data Engineering
  documentation:
    dag_purpose: "Builds QUBE dimension table for {entity}.{name}"
  folder_name: dimensions_{entity}_{name}
workflow:
  type: qube_dimension
  layer: qube
  has_hive_sync: true
  custom_schema: "dimensions"
  qube_specs:
    entity: {entity}
    name: {name}
    source:
      date_expr: "unix_timestamp(ts_updated, \"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'\")"
      select:
        - id_{entity}
        - {value_col}
        - ts_updated
    logic:
      card: single
      type: string
      agg: last
      value_col: {value_col}
    order_by:
      ts_col: ts_updated
      nulls_last: true
    defaults:
      unknown_string: UNKNOWN
cluster:
  type: databricks_16_4_rfleet_instance_cluster
  databricks_conn_id: databricks_new
```

**Measure:**
```yaml
dag:
  name: qube_measure_{entity}_{name}
  schedule_start_date: "2025, 1, 1"
  schedule_interval: "0 6 * * *"
  owner: Data Engineering
  documentation:
    dag_purpose: "Builds QUBE measure table for {entity}.{name}"
  folder_name: measures_{entity}_{name}
workflow:
  type: qube_measure
  layer: qube
  has_hive_sync: true
  custom_schema: "measures"
  qube_specs:
    entity: {entity}
    name: {name}
    source:
      date_expr: "unix_timestamp(dt_{entity}, 'yyyy-MM-dd')"
    logic:
      filter_sql: "TRUE"
    windows:
      - 1
      - 7
      - 28
cluster:
  type: databricks_16_4_rfleet_instance_cluster
  databricks_conn_id: databricks_new
```

**Metric:**
```yaml
dag:
  name: qube_metric_{entity}_{name}
  schedule_start_date: "2025, 1, 1"
  schedule_interval: "0 7 * * *"
  owner: Data Engineering
  documentation:
    dag_purpose: "Builds QUBE metric table for {entity}.{name}"
  folder_name: metrics_{entity}_{name}
workflow:
  type: qube_metric
  layer: qube
  has_hive_sync: true
  custom_schema: "metrics"
  qube_specs:
    entity: {entity}
    name: {name}
    dimensions:
      - name: {dimension_name}
        card: single
        type: string
    measures:
      - name: {measure_name}
    counters:
      type: long
    privacy:
      k_anonymity: 1
    windows:
      - 1
      - 7
      - 28
cluster:
  type: databricks_16_4_rfleet_instance_cluster
  databricks_conn_id: databricks_new
```

## Step 4 — Schedule timing

Stagger schedules so dependencies build in order:
- Dimensions: `0 5 * * *`
- Measures: `0 6 * * *`
- Metrics: `0 7 * * *` (or later if depending on specific dimensions/measures)

## Step 5 — Validate

```bash
make validate-dag-declaration-files dag_name=qube_{type}_{entity}_{name}
```

## Key constraints

- A metric cannot be created before its referenced dimensions and measures exist.
- `source.date_expr` must return Unix timestamp in **seconds** (use `unix_timestamp()`).
- `logic.filter_sql` is required for measures and must be a valid SQL boolean expression.
- `logic.card: multi` is only for dimensions where an entity can have multiple simultaneous values.
