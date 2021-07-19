## DW Mitula
​
### Purpose
​
Creates incremental DW fact and dimension tables for Mitula campaigns to analyse classified ads costs. [Mitula](https://www.mitula.com.br/) is a real estate, employment and cars classified ad aggregator that shows its content to users for free. Its ads are optimized and managed at [Thribee](https://thribee.com/), a traffic acquisition service part of Lifull Connect enterprise.
​
<details>
    <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator, after `bietlejuice.mitula` DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output tables in DW layer: 
​
- `mitula.dim_mitula_campaign`
- `mitula.fact_mitula_daily_cost_attributions` 
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>