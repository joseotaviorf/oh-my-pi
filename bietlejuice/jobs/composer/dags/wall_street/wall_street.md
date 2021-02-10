## Wall Street
​
### Purpose
​
This DAG creates the full tables for Wall Street, a hub that integrates with financial servide providers.

### Execution​ Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables: 

1. In data lake raw: 
- All tables available in source's database.

2. In data lake clean:​
​
- `charge`
- `charge_aud`
- `charge_mundipagg`
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
