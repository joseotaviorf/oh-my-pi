## Rental Guarantee

### Purpose

This DAG handles the ingestion of our raw and clean data for our Rental Guarantee Microservice, which is a Microservice that was created to offer new possibilities for Tenants to be a part of 5A, when they weren’t approved in our credit policies. For more information about the Database please refer to [the repository](https://github.com/quintoandar/rental-guarantee).

OBS: The aud tables, for now, are using full load, but we are already tracking the reasons for created_at/updated_at columns are almost empties with the Product Team.

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw:
    - All tables mapped in the clean layer which are available in the source's database.

2. In datalake clean:
    - `charge_aud`
    - `charge`
    - `guarantee_aud`
    - `guarantee`
    - `renewal`
    - `rev_info`
    - `risk_category_aud`
    - `risk_category`
    
### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
