## Brokers Supply Processor

### Purpose
This DAG imports the tables from Supply Processor, a platform responsible for bringing and processing properties from other real estate agencies in Rede QuintoAndar.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake_brokers_supply_processor_raw:

Via **incremental load**:
    - `file`
    - `file_aud`
    - `lead3p`
    - `lead3p_aud`
    - `revinfo`

This pipeline produces, in datalake_brokers_supply_processor_clean:

Via **incremental load**:
    - `file`
    - `file_aud`
    - `lead_3p`
    - `lead_3p_aud`
    - `rev_info`

</details>
