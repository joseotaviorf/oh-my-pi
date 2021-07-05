## Linkedin
### Important Note
This DAG was deactivated since we don't need it for now.
In the future we may need to reactivate it. In this case,  add the dependencies removed in this PR
(https://github.com/quintoandar/bi-etl-ejuice/pull/5195) to the dependencies.yaml file.
### Purpose

Linkedin brings our marketing campaigns data from linkedin platform. We implemented an [API client](https://github.com/quintoandar/linkedin-client-python) for usage in raw.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table for both our raw and clean layers:

- `linkedin_campaign_groups`
- `linkedin_campaigns`
- `linkedin_creatives_stats`
- `linkedin_creatives`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
