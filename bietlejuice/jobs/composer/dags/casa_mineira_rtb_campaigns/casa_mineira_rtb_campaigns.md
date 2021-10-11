## Casa Mineira RTB Campaigns

### Purpose

Casa Mineira RTB Campaigns DAG retrieves Casa Mineira's marketing campaign statistics data from RTB platform. It uses data extracted from [RTB Stats API endpoint](https://api.panel.rtbhouse.com/api/docs) using [RTB House SDK for Python](https://github.com/rtbhouse-apps/rtbhouse-python-sdk).
RTB House is a provider of retargeting technology, leveraging deep learning algorithms to enable its retail clients to deliver digital advertising campaigns to potential customers who have displayed purchase intent.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via incremental load:

- In datalake raw:
    - `casa_mineira_rtb_campaigns_raw.rtb_campaigns`
- In datalake clean:
    - `casa_mineira_rtb_campaigns_clean.rtb_campaigns`
  
### Responsible Data Teams
For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
