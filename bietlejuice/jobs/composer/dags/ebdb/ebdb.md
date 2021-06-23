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
    - All tables available in source's database, except for Operationals (REV_CHANGES) and some trash (_UsuarioRevisionEntity_new).
    - Views: MapRegiao and vw_lead_reason

2. In datalake clean:
    `access_authorization_type`, `access_type`, `account`, `account_transaction`, `affiliate_data`, `affiliate_data_aud`, `agent`, `agent_data`, `agent_data_aud`, `agent_data_business_contexts_served`, `agent_data_types`, `agent_region_data`, `agent_rent_flow`, `agent_specific_hour`, `agent_specific_hour_aud`, `agent_support`, `agent_support_aud`, `agent_weekly_hours`, `agent_weekly_hours_aud`, `amenities`, `appointment_change_reason_category`, `bank`, `booking`, `booking_aud`, `booking_status_change`, `cep`, `city`, `condo`, `condo_amenities`, `condo_contact`, `contract`, `contract_aud`, `contract_negotiation`, `contract_partnership_data`, `contract_person`, `contract_person_aud`, `contract_version`, `conversion_lead`, `device`, `doorman_affiliate_data`, `doorman_affiliate_occupation`, `dynamic_pricing_house`, `dynamic_pricing_house_aud`, `dynamic_pricing_parameters`, `dynamic_pricing_parameters_aud`, `entrance`, `feedback_tag`, `financial_data`, `follow_up_details`, `follow_up_details_feedback_tag`, `full_contract`, `house`, `house_aud`, `house_guarantees_aud`, `house_maintenance_condition`, `house_maintenance_condition_aud`, `house_media`, `house_rating`, `house_rating_rating_label`, `house_registration_status`, `house_registration_status_aud`, `house_special_condition`, `house_user`, `house_visit_information`, `house_visit_information_aud`, `house_visit_status_aud`, `house_weekly_schedule`, `house_weekly_schedule_aud`, `image`, `info_amenities`, `info_amenities_aud`, `info_condo_amenities`, `info_condo_amenities_aud`, `inspection`, `inspection_aud`, `inspection_item`, `instant_offer`, `key_type`, `lead`, `lead_aud`, `lead_reason`, `leads_grouped_by_phone`, `listing_business_context`, `listing_business_context_aud`, `listing_info`, `local`, `map_region`, `occupant_type`, `offer`, `offer_aud`, `onboarding`, `ownerlead`, `partner`, `partner_agent`, `photographer_data`, `photographer_job`, `photographer_job_aud`, `polygon_region`, `portability`, `portability_aud`, `pre_proposal`, `pre_proposal_aud`, `pre_proposal_condition`, `proponent_proposal`, `proponent_proposal_aud`, `proposal`, `proposal_aud`, `proposal_condition`, `proposal_condition_aud`, `proposal_document`, `proposal_resident`, `rating_label`, `real_estate_agency_lead`, `real_estate_agent_rating`, `real_estate_agent_rating_rating_label`, `region`, `rent_flow`, `rent_flow_aud`, `restriction_type`, `restriction_type_aud`, `sales_rep`, `sales_rep_aud`, `signature`, `special_condition`, `special_condition_aud`, `state`, `state_aud`, `user`, `user_aud`, `user_document`, `user_info`, `user_merge_aud`, `user_preferences`, `user_revision_entity`, `visit`, `visit_aud`, `visit_origin`, `visitor`

3. In DW:
    - `dim_contract_person`
    - `dim_proposal_person`
    - `fact_contract_people`
    - `fact_proposal_people`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>