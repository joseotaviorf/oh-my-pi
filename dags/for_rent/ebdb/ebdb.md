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

    `access_authorization_type`
    `access_type`
    `account`
    `account_transaction`
    `affiliate_data`
    `affiliate_data_aud`
    `agent`
    `agent_data`
    `agent_data_aud`
    `agent_data_business_contexts_served`
    `agent_data_business_contexts_served_aud`
    `agent_data_types`
    `agent_region_data`
    `agent_specific_hour`
    `agent_specific_hour_aud`
    `agent_support`
    `agent_support_aud`
    `agent_weekly_hours`
    `agent_weekly_hours_aud`
    `agents_prospect`
    `agents_prospect_aud`
    `amenities`
    `appointment_change_reason_category`
    `bank`
    `booking`
    `booking_aud`
    `booking_status_change`
    `category_house`
    `category`
    `cep`
    `city`
    `condo`
    `condo_amenities`
    `condo_contact`
    `condo_manager`
    `condo_manager_emails`
    `condo_manager_phones`
    `condo_names_history`
    `conservation_assessment`
    `conservation_item_functional`
    `conservation_item_status`
    `conservation_item`
    `conservation_room`
    `consumption_bill`
    `country`
    `device`
    `doorman_affiliate_data`
    `doorman_affiliate_occupation`
    `dynamic_pricing_house`
    `dynamic_pricing_house_aud`
    `dynamic_pricing_parameters`
    `dynamic_pricing_parameters_aud`
    `entrance`
    `feedback_tag`
    `financial_data`
    `follow_up_details`
    `follow_up_details_feedback_tag`
    `house`
    `house_agent`
    `house_agent_aud`
    `house_aud`
    `house_enrichment`
    `house_enrichment_aud`
    `house_guarantees_aud`
    `house_maintenance_condition`
    `house_maintenance_condition_aud`
    `house_media`
    `house_listing_relation`
    `house_listing_relation_aud`
    `house_predicted_price`
    `house_predicted_price_aud`
    `house_rating`
    `house_rating_rating_label`
    `house_registration_status`
    `house_registration_status_aud`
    `house_rent_costs_aud`
    `house_special_condition`
    `house_user`
    `house_visit_information`
    `house_visit_information_aud`
    `house_visit_status_aud`
    `house_weekly_schedule`
    `house_weekly_schedule_aud`
    `image`
    `image_aud`
    `info_amenities`
    `info_amenities_aud`
    `info_condo_amenities`
    `info_condo_amenities_aud`
    `inspection`
    `inspection_aud`
    `inspection_item`
    `instant_offer`
    `instant_offer_aud`
    `key_type`
    `lead_reason`
    `listing_business_context`
    `listing_business_context_aud`
    `listing_info`
    `listing_rent_model`
    `listing_rent_model_aud`
    `listing_sale_model`
    `listing_sale_model_aud`
    `local`
    `map_region`
    `occupant_type`
    `offer`
    `offer_aud`
    `ownerlead`
    `partner`
    `partner_agent`
    `partner_agent_aud`
    `photographer_data`
    `photographer_job`
    `photographer_job_aud`
    `polygon_region`
    `pre_proposal`
    `pre_proposal_aud`
    `pre_proposal_condition`
    `pro_owner_fee`
    `pro_owner_fee_aud`
    `property_fee`
    `property_fee_assigned`
    `property_fee_assigned_aud`
    `property_fee_aud`
    `proponent_info_resend_request`
    `proponent_info_resend_request_aud`
    `proponent_proposal`
    `proponent_proposal_aud`
    `proposal`
    `proposal_aud`
    `proposal_condition`
    `proposal_condition_aud`
    `proposal_document`
    `proposal_resident`
    `rating_label`
    `real_estate_agency_lead`
    `real_estate_agent_rating`
    `real_estate_agent_rating_rating_label`
    `region`
    `region_business_contexts_served`
    `region_business_contexts_served_aud`
    `region_config`
    `rental_administrator_change_request`
    `rental_administrator_change_request_aud`
    `restriction_type_aud`
    `sale_operation_management`
    `sales_rep`
    `sales_rep_aud`
    `shop_window`
    `shop_window_aud`
    `shop_window_listing_business_context`
    `shop_window_listing_business_context_aud`
    `special_condition`
    `special_condition_aud`
    `state`
    `state_aud`
    `suspected_unavailability_listings`
    `suspected_unavailability_listings_aud`
    `user`
    `user_aud`
    `user_document`
    `user_info`
    `user_merge`
    `user_merge_aud`
    `user_preferences`
    `user_pro_owner`
    `user_pro_owner_aud`
    `user_revision_entity`
    `visit`
    `visit_aud`
    `visit_cancellation_details`
    `visit_cancellation_details_aud`
    `visit_origin`
    `visitor`
    `agent_region_data_aud`
    `mask_weekly_hour`

    </div>

