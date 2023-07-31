## Enrich Open External Data

### Purpose

This DAG is intended to generate the unique ITBI addresses to use QuintoAndar's Geocoding solution.

​<details>

Creates enrich tables for ITBI data extracted from public databases.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables in `datalake_itbi_addresses`:

**Fully:**
- `itbi_sp`
- `itbi_bh`

</details>
