## IPTU

### Purpose
This pipeline aims to extract IPTU data from the city of São Paulo. The data has been made available by the city hall and can be found [here](https://geosampa.prefeitura.sp.gov.br).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered in the first 4 months of the year, if the load has already been made, we will skip the ingestion. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake_iptu_raw and datalake_iptu_clean:

Via **full load**:
    - `iptu_sp`

</details>
