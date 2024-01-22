## Enrich Open External Data

### Purpose

This DAG is intended to handle tables retrieved from public data (eg. taxes, interest rate, inflation rate etc).

​<details>
### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables in `datalake_open_external_data`:

**Fully:**
- `iptu_sp_residential_properties`
- `itbi_sp_residential_transactions`
- `itbi_bh_residential_transactions`
- `itbi_all_residential_transactions`

</details>
