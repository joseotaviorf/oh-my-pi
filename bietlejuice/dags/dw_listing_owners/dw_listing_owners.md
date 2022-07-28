## DW Listing Owners

### Purpose

This DAG loads to DW our model `dim_listing_owner`, referent to information about rent and sale listing owners users. 

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load: 

- `quintoandar.dim_listing_owner` – Contains information about users with login that are responsible (manager) for a listing at QuintoAndar. Note that they do not have to be the property owners (but could also be). These could be individuals, property managers, employees of real estate companies (B2B). Each line is a user.

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>