## Wall Street
​
### Purpose
​
This DAG creates the full tables for Wall Street, a hub that integrates with financial servide providers.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

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
    - `subscription`
​
</details>
