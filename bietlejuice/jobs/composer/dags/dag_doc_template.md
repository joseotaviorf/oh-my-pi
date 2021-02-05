_<This is the DAGs' documentation template to be followed when creating a new DAG.>_

## <DAG_NAME>

### Purpose

E.g. extraction of Bla tables into data lake.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Dumps the entire source database in raw and produces the following output tables in clean:

- `campaigns` - Campaigns information for all accounts, partitioned by `account_id`, `year`, `month`, `day`
- `campaign_stats` -  The daily campaigns stats, partitioned by `account_id`, `campaing_id`, `year`, `month`, `day`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

### Additional Information

_<If there is any external link or documentation that helps to understand this DAG, you can add it here. Else, 
you must remove this section.>_