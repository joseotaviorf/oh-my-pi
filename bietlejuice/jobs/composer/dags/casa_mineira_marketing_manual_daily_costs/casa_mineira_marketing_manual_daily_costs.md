## Casa Mineira Marketing Manual Daily Costs

### Purpose

Casa Mineira's Marketing Manual Daily Costs DAG retrieves cost inputs from Google Sheets added manually by data analysts.

<details>
    <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily, 11:00 BRT. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via full load:

- In datalake's `raw` layer:
    - `casa_mineira_marketing_manual_shared_costs`

- In datalake's `clean` layer:
    - `casa_mineira_marketing_manual_shared_costs`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>