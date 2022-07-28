## DW Rent Fact Listing Owners

### Purpose

This DAG loads to DW our model fact_listing_owners, referent to information about rent listing owners users. 

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW: 

- `fact_listing_owners` – Contains information about users with login that have registered a listing For Rent with QuintoAndar and are responsible for the listing. Note that they do not have to be the property owners (but could also be). These could be individuals, property managers, employees of real estate companies (B2B). Each line is a user.

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>