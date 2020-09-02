drop table if exists fact_listing_rent_flows;
create table if not exists fact_listing_rent_flows
(
 ods_id bigint   encode az64
 ,sk_house_listing bigint   encode az64
 ,sk_house_first_listing_date bigint   encode az64
 ,sk_house_listing_date bigint   encode az64
 ,sk_house_listing_de_publication_date bigint   encode az64
 ,sk_house_listing_first_offer_submitted_date bigint   encode az64
 ,sk_region bigint   encode az64
 ,sk_condo bigint   encode az64
 ,sk_rent_flow bigint   encode az64
 ,sk_booking bigint   encode az64
 ,sk_tenant_booking_review bigint   encode az64
 ,sk_booking_created_date bigint   encode az64
 ,sk_visit_date bigint   encode az64
 ,sk_owner bigint   encode az64
 ,sk_user_agent bigint   encode az64
 ,sk_agent_sign_up_date bigint   encode az64
 ,sk_client bigint   encode az64
 ,sk_client_sign_up_date bigint   encode az64
 ,sk_visit bigint   encode az64
 ,sk_offer bigint   encode az64
 ,sk_offer_submitted_date bigint   encode az64
 ,sk_min_offer_submitted_date bigint   encode az64
 ,sk_offer_approved_date bigint   encode az64
 ,sk_reservation bigint   encode az64
 ,sk_reservation_created_date bigint   encode az64
 ,reservation_attempts smallint   encode az64
 ,sk_proposal bigint   encode az64
 ,sk_proposal_approved_date bigint   encode az64
 ,sk_proposal_processed_date bigint   encode az64
 ,sk_tenant_first_doc_sent_date bigint   encode az64
 ,sk_tenant_manual_first_doc_sent_date bigint   encode az64
 ,sk_tenant_auto_first_doc_sent_date bigint   encode az64
 ,sk_tenant_first_doc_complete_date bigint   encode az64
 ,sk_tenant_last_doc_complete_date bigint   encode az64
 ,sk_tenant_doc_complete_date bigint   encode az64
 ,sk_contract bigint   encode az64
 ,sk_contract_created_date bigint   encode az64
 ,sk_contract_signed_date bigint   encode az64
 ,sk_contract_annulment_date bigint   encode az64
 ,sk_contract_canceled_date bigint   encode az64
 ,sk_credit_analysis_first_init_date bigint   encode az64
 ,sk_credit_analysis_last_init_date bigint   encode az64
 ,sk_credit_analysis_init_date bigint   encode az64
 ,sk_credit_analysis_first_end_date bigint   encode az64
 ,sk_credit_analysis_last_end_date bigint   encode az64
 ,sk_credit_analysis_end_date bigint   encode az64
 ,sk_credit_analysis_approved_date bigint   encode az64
 ,sk_first_credit_evaluation_init bigint   encode az64
 ,sk_last_credit_evaluation_init bigint   encode az64
 ,sk_first_credit_evaluation_positive bigint encode az64
 ,sk_last_credit_evaluation_positive bigint encode az64
 ,sk_first_credit_evaluation_negative bigint   encode az64
 ,sk_last_credit_evaluation_negative bigint   encode az64
 ,sk_guarantee_date bigint encode az64
 ,sk_first_doc_analysis_approved bigint   encode az64
 ,sk_last_doc_analysis_approved bigint   encode az64
 ,sk_first_doc_analysis_rejected bigint   encode az64
 ,sk_last_doc_analysis_rejected bigint   encode az64
 ,sk_guarantee_paid_date bigint encode az64
 ,flg_visit_completed boolean
 ,flg_visit_performed boolean
 ,flg_visit_created_from_app boolean
 ,visit_created_type varchar(256)   encode lzo
 ,flg_visit_last_updated_from_app boolean
 ,sk_rent_flow_taxonomy bigint   encode az64
 ,booking_utm_campaign varchar(2000)   encode lzo
 ,booking_utm_content varchar(256)   encode lzo
 ,booking_utm_term varchar(256)   encode lzo
 ,days_booking_created_to_visit numeric(14,2)   encode az64
 ,days_user_created_to_visit numeric(14,2)   encode az64
 ,days_offer_submitted_to_internal_analysis numeric(14,2)   encode az64
 ,days_offer_approved_to_doc_first_sent numeric(14,2)   encode az64
 ,days_offer_approved_to_owner_doc_sent numeric(14,2)   encode az64
 ,days_first_doc_sent_to_credit_processed numeric(14,2)   encode az64
 ,days_first_doc_sent_to_doc_completed numeric(14,2)   encode az64
 ,days_doc_completed_to_credit_processed numeric(14,2)   encode az64
 ,days_credit_approved_to_contract_created numeric(14,2)   encode az64
 ,days_credit_approved_to_contract_signed numeric(14,2)   encode az64
 ,days_contract_created_to_contract_signed numeric(14,2)   encode az64
 ,days_booking_created_to_contract_signed numeric(14,2)   encode az64
 ,days_visit_to_contract_signed numeric(14,2)   encode az64
 ,days_visit_to_offer_submitted numeric(14,2)   encode az64
 ,days_booking_created_to_offer_submitted numeric(14,2)   encode az64
 ,days_tenant_first_doc_sent_to_insurance_approved numeric(14,2)   encode az64
 ,days_insurance_approved_to_contract_signed numeric(14,2)   encode az64
 ,days_offer_approved_to_tenant_first_doc_sent numeric(14,2)   encode az64
 ,days_offer_submitted_to_offer_approved numeric(14,2)   encode az64
 ,days_offer_approved_to_credit_init numeric(14,2)   encode az64
 ,days_offer_submitted_to_contract_signed numeric(14,2)   encode az64
 ,days_offer_approved_to_contract_signed numeric(14,2)   encode az64
 ,days_tenant_doc_completed_to_credit_approved numeric(14,2)   encode az64
 ,days_tenant_first_doc_sent_to_doc_completed numeric(14,2)   encode az64
 ,days_house_listing_to_contract_signed numeric(14,2)   encode az64
 ,days_house_listing_to_visit numeric(14,2)   encode az64
 ,days_credit_approved_to_closing_processed numeric(14,2)   encode az64
 ,days_offer_approved_to_doc_contact numeric(14,2)   encode az64
 ,sk_agent_review_rating_date bigint   encode az64
 ,funnel_step varchar(255)   encode lzo
 ,funnel_step_drop_reason varchar(255)   encode lzo
 ,ts_load timestamp without time zone   encode az64
)
diststyle key
distkey (sk_booking)
;
