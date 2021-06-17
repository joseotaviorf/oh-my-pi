## Enrich Amplitude Talk To Agent
​
### Purpose
​
This DAG brings data from Talk To Agent events, which is used on Sale modelling for `fact_sale_flows`. This table contains events data from feature "Fale com Corretor", active during the start of the Covid-19 pandemic, as an alternative for blocking presential visits. 

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is no longer running since we don't have any updated data about TTA events. Anyway, it is still part of the funnel, so we must keep it.

More information about run time [here]({chart_url}{dag_id})

### Outputs
​
This pipeline produces the following output table, via full load: 
​
- `talk_to_agent_events` – Contains information about TTA events.
​
### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>