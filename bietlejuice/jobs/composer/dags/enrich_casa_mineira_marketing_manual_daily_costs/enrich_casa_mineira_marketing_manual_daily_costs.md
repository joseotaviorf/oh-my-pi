## Enrich Casa Mineira Marketing Manual Daily Costs

### Purpose

Casa Mineira's Marketing Manual Daily Costs DAG transforms Casa Mineira's marketing cost data retrieved from Google Sheets manual inputs, and applies, when existant, manually-defined ratio factors to split cost into each platform.

#### Structure

The resulting `daily_cost` enrich table has its content split between **automatic** and **manual** partitions by the column `flow_type`, each partition being updated by its respective DAG flow.

More information about marketing data flow architecture can be found at [this diagram](https://viewer.diagrams.net/?page-id=XMpkxgjBueLUIo4w7sMd&highlight=0000ff&nav=1&hide-pages=1#G1aM-IGy6JcG1rxB0IyDxOJpyCU6GMoFzm), also shown in details below.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  <iframe
    src="https://viewer.diagrams.net/?page-id=XMpkxgjBueLUIo4w7sMd&highlight=0000ff&nav=1&hide-pages=1#G1aM-IGy6JcG1rxB0IyDxOJpyCU6GMoFzm"
    style="width:100%; height:300px;">
  </iframe>

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily after dependencies. More information about run time [here]({chart_url}{dag_id}).

### Outputs

- `datalake_casa_mineira_marketing_costs.daily_costs`

</details>
