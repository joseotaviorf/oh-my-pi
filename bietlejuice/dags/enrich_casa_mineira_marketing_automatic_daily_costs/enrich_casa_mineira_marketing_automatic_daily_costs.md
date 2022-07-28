## Enrich Casa Mineira Marketing Automatic Daily Costs
### Purpose

Casa Mineira's Marketing Automatic Daily Costs DAG removes test campaigns and applies taxonomy on costs retrieved automatically by programmatic flows like API integrations or crawlers.

#### Structure

The resulting `daily_cost` enrich table has its content split between **automatic** and **manual** partitions by the column `flow_type`, each partition being updated by its respective DAG flow.

More information about marketing data flow architecture can be found at [this diagram](https://viewer.diagrams.net/?page-id=XMpkxgjBueLUIo4w7sMd&highlight=0000ff&nav=1&hide-pages=1#G1aM-IGy6JcG1rxB0IyDxOJpyCU6GMoFzm), also shown in details below.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  <iframe
    src="https://viewer.diagrams.net/?page-id=XMpkxgjBueLUIo4w7sMd&highlight=0000ff&nav=1&hide-pages=1#G1aM-IGy6JcG1rxB0IyDxOJpyCU6GMoFzm"
    style="width:100%; height:300px;">
  </iframe>

### Execution Interval

Daily after dependencies. More information about run time [here]({chart_url}{dag_id}).

### Outputs

- `datalake_casa_mineira_marketing_costs.daily_costs`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>