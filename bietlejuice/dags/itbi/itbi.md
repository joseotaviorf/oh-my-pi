## ITBI SP 

### Purpose
This DAG imports "Imposto de Transmissão de Bens Imóveis (ITBI)" information from the public site of city of São Paulo.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered weekly.

More information about run time [here]({chart_url}{dag_id}).
### Inputs

Can we use the execution_date variable to send a specific date to run the DAG

### Outputs

This pipeline produces, in datalake_itbi_raw and datalake_itbi_clean:

Via **incremental load**:
    - `itbi_sp`

</details>
