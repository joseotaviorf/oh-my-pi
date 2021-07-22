## DW Trovit
​
### Purpose
​
Creates incremental DW fact and dimension tables for Trovit campaigns to analyse classified ads costs. [Trovit](https://www.trovit.com.br/) is a search engine specializing in classified ads. Its ads are optimized and managed at [Thribee](https://thribee.com/), a traffic acquisition service part of Lifull Connect enterprise.
​
<details>
    <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator, after `bietlejuice.trovit` DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output tables in DW layer: 
​
- `trovit.dim_trovit_campaign`
- `trovit.fact_trovit_daily_cost_attributions` 
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>