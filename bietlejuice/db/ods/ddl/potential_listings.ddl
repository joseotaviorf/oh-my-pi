drop table public.potential_listings;
create table public.potential_listings (
   sk_house_listing_flow bigint not null  
 ,sk_condo bigint   
 ,sk_lead integer   
 ,sk_lead_conversion integer   
 ,sk_first_photo_job integer   
 ,sk_house_listing bigint   
 ,sk_user_house_registrant integer   
 ,sk_user_sales_rep integer   
 ,sk_user_lead_affiliate integer   
 ,sk_user_first_task_assignee integer   
 ,sk_user_last_task_assignee integer   
 ,sk_region integer
 ,sk_first_region integer
 ,id_city integer
 ,sk_partner integer,
    sk_lead_date integer,
   sk_prospect_date integer,
   sk_first_task_created_date integer,
    sk_first_task_closed_date integer,
    sk_last_task_created_date integer,
    sk_last_task_closed_date integer,
    sk_first_contact_date integer,
    sk_conversion_date integer,
   sk_qualified_date integer,
   sk_opportunity_date integer,
   sk_first_listing_date integer,
   sk_discard_date integer,
   sk_sales_company_lead_sent_date integer,
    sk_user_lead_first_discarder integer,
   sk_user_lead_last_discarder integer,
 flow varchar(255),
 acquisition_method varchar(255),
 acquisition_channel varchar(255),
 acquisition_source varchar(255),
 funnel_step varchar(255)
 ,funnel_drop_reason varchar(255)
 ,hours_lead_to_prospect numeric(10,1)
 ,hours_prospect_to_qualified numeric(10,1)
 ,hours_lead_to_first_contact numeric(10,1)
 ,hours_prospect_to_first_contact numeric(10,1)
 ,hours_qualified_to_opportunity numeric(10,1)
 ,hours_opportunity_to_listing numeric(10,1)
 ,hours_lead_to_listing numeric(10,1)
 ,days_lead_to_prospect numeric(10,1)
 ,days_prospect_to_qualified numeric(10,1)
 ,days_lead_to_first_contact numeric(10,1)
 ,days_prospect_to_first_contact numeric(10,1)
 ,days_qualified_to_opportunity numeric(10,1)
 ,days_opportunity_to_listing numeric(10,1)
 ,days_lead_to_listing numeric(10,1)
 ,days_lead_to_processing numeric(10,1)
 ,is_exclusive smallint
 ,first_isales_intervention varchar(50)
 ,lead_type varchar(255)
 ,lead_origin varchar(255)
 ,utm_source varchar(255)
 ,utm_medium varchar(255)
 ,tracking_platform varchar(255)
 ,is_branded boolean
 ,is_b2b boolean
 , reprocessed_flg boolean
 ,is_doorman boolean
 ,is_isales_direct_register boolean
 ,is_cx_direct_register boolean
 ,is_ops_direct_register boolean
 ,has_isales_intervention boolean
 ,has_fup_photo_task boolean
  ,lead_referring_domain varchar(512)
   ,lead_referring_category varchar(512),
   lead_id integer,
      listing_flows_affiliate_type varchar(255),
      affiliate_id integer,
      is_agent_referral boolean,
      region_id integer,
      house_usuario_que_cadastrou_id integer
);

CREATE INDEX pot_list_lead_id_idx ON public.potential_listings USING btree (lead_id);
CREATE INDEX pot_list_region_id_idx ON public.potential_listings USING btree (region_id);
CREATE INDEX pot_list_usuario_que_cadast_id_idx ON public.potential_listings USING btree (house_usuario_que_cadastrou_id);
