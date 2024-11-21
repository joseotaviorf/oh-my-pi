## Hub Services

### Purpose
This DAG imports the tables from [HubServices](https://github.com/quintoandar/hubs), a service that centralizes hub data.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake_hub_services_raw:

Via **incremental load**:
    - `business_unit`
    - `business_unit_aud`
    - `business_unit_region`
    - `business_unit_region_aud`
    - `lead`
    - `lead_aud`
    - `member_profile`
    - `member_profile_aud`
    - `observation`
    - `observation_aud`
    - `region`
    - `region_aud`
    - `reminder`
    - `reminder_aud`
    - `reminder_type`
    - `reminder_type_aud`
    - `responsible`
    - `responsible_aud`
    - `revinfo`
    - `users`
    - `users_aud`
    - `visitor`
    - `visitor_aud`
    - `visitor_event`
    - `visitor_event_aud`
    - `visitor_prospection`
    - `visitor_prospection_aud`

This pipeline produces, in datalake_hub_services_clean:

Via **incremental load**:
    - `business_unit`
    - `business_unit_aud`
    - `business_unit_region`
    - `business_unit_region_aud`
    - `lead`
    - `lead_aud`
    - `member_profile`
    - `member_profile_aud`
    - `observation`
    - `observation_aud`
    - `region`
    - `region_aud`
    - `reminder`
    - `reminder_aud`
    - `reminder_type`
    - `reminder_type_aud`
    - `responsible`
    - `responsible_aud`
    - `rev_info`
    - `users`
    - `users_aud`
    - `visitor`
    - `visitor_aud`
    - `visitor_event`
    - `visitor_event_aud`
    - `visitor_prospection`
    - `visitor_prospection_aud`

</details>
