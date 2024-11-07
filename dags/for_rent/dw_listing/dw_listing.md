## DW Listing

### Purpose

This DAG loads to DW our models related to the listings (properties listed in the site).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load:

- `dw_public.dim_condo`
- `dw_rent.dim_house_listing`
- `dw_rent.fact_house_listing_daily_available_hours`
- `dw_rent.fact_house_listing_daily_infos`
- `dw_rent.fact_house_listing_status`
- `dw_rent.fact_house_listings`
-
</details>
