## Enrich Amplitude Sale Visit Intent

### Purpose

Enrich sale visit intent context events in Amplitude and load into Data Lake.
This DAG enriches data coming from Amplitude events that have a Sale context and a visit intent type.
Also, we are filtering just events after the first January of 2020.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `amplitude_sale_visit_intent`

### Responsible Data Teams
​
For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​</details>
