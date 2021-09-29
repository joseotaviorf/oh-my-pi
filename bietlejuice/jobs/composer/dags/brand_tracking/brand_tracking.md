## Brand Tracking

### Purpose

This DAG creates the incremental table for Brand Tracking.
About Brand Tracking, QuintoAndar hires an institute that conducts a survey of brands in the real estate industry and compiles the results by quarter. The survey is a questionnaire they drop out to panelists.

The Data Analysts of Mkt Branding upload the file quarterly at this s3 bucket path: 5a-datalake-prod/raw/files/mkt_branding/brand_tracking/

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered manually quarterly.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw:
- datalake_brand_tracking_raw.brandtracking
- datalake_brand_tracking_raw.brandtracking_unpivoted
    

2. In datalake clean:
- datalake_brand_tracking_clean.brandtracking
- datalake_brand_tracking_clean.brandtracking_unpivoted

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
  
</details>