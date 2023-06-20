## DW Country

### Purpose

Static DAG that creates the country dimension used commonly across all lines. This table is created with statically generated data and is not meant to be executed in a periodic frequency.

Therefore, **this DAG is destined to be executed only on scenarios that require table recreation or static data update/upgrade.**

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

None (static DAG)

### Outputs

This pipeline produces the following output tables:

- `dim_country`:
    A table that contains information about each country QuintoAndar is present.
    Is fully based on `datalake_ebdb_clean.country`, but is available in the `DW` layer.
