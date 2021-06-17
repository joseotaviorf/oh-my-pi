## Enrich Amplitude Visit

### Purpose

Enrich visit context events in Amplitude and load into data lake.

This DAG enriches data coming from Amplitude events that have a visit confirmed.
Thus, we can have the information about the Urchin Tracking and understand better 
the behavior behind a visit confirmed.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `amplitude_visit`

### Responsible Data Teams
​
For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​</details>
