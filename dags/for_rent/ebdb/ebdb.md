## EBDB

### Purpose

Extraction of EBDB tables into data lake. EBDB is the main database for QuintoAndar.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

1. In datalake raw:
    - All tables available in source's database that have clean or use in metabase, except for Operationals (REV_CHANGES) and some trash (_UsuarioRevisionEntity_new).
    - Views: MapRegiao and vw_lead_reason

2. In datalake clean:
    <div style="overflow-x: scroll; height: 200px">

    `conservation_item_functional`
    `conservation_item_status`
    `conservation_room`
    `country`
    `house_agent`
    `house_agent_aud`
    `house_listing_relation`
    `house_listing_relation_aud`
    `house_visit_information`
    `house_visit_information_aud`
    `map_region`
    `ownerlead`
    `photographer_job`
    `photographer_job_aud`
    `polygon_region`
    `preferred_fixed_agent`
    `preferred_fixed_agent_aud`
    `processed_message`
    `region_config`
    `suspected_unavailability_listings`
    `suspected_unavailability_listings_aud`

    </div>
