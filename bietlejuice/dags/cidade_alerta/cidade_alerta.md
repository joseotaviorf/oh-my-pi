## Cidade Alerta

### Purpose

Extraction of [Cidade Alerta](https://github.com/quintoandar/cidade-alerta) tables into data lake. Cidade Alerta is a 
managing microservice for automated alerts.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables in the raw and clean layers:

Via full load:
    - `highlights`
    - `profile`

Via incremental load:
    - `alert`
    - `audit`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>