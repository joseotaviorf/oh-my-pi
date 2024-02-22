WITH persona_type_pivot AS (
  SELECT
    pt.id_snapshot,
    pt.id_user,
    pt.id_country,
    COALESCE(MAX(pt.cpf), -1) AS id_personal_number,
    pt.main_phone,
    pt.name,
    pt.email,
    pt.is_active,
    pt.is_blocked,
    year,
    month,
    day,
    COALESCE(MAX(pt.dt_birth), CAST('1900-01-01' AS TIMESTAMP)) AS dt_user_birth,
    COALESCE(MAX(pt.ts_user_updated), CAST('1900-01-01' AS TIMESTAMP)) AS ts_user_updated,
    COALESCE(MAX(pt.ts_user_created), CAST('1900-01-01' AS TIMESTAMP)) AS ts_user_created,
    MAX(CASE WHEN pt.client_type = 'tenant' THEN pt.journey_step ELSE NULL END) AS tenant_journey_step,
    MAX(CASE WHEN pt.client_type = 'tenant' THEN pt.persona_step ELSE NULL END) AS tenant_persona_step,
    MAX(CASE WHEN pt.client_type = 'tenant' THEN pt.is_offboarding ELSE FALSE END) AS is_tenant_offboarding,
    MAX(CASE WHEN pt.client_type = 'tenant' THEN pt.is_ongoing ELSE FALSE END) AS is_tenant_ongoing,
    MAX(CASE WHEN pt.client_type = 'tenant' THEN pt.is_onboarding ELSE FALSE END) AS is_tenant_onboarding,
    MAX(CASE WHEN pt.client_type = 'tenant' THEN pt.is_contract_to_entrance ELSE FALSE END) AS is_tenant_contract_to_entrance,
    MAX(CASE WHEN pt.client_type = 'tenant' THEN pt.is_visits_to_offer ELSE FALSE END) AS is_tenant_visits_to_offer,
    MAX(CASE WHEN pt.client_type = 'tenant' THEN pt.is_listing_and_search ELSE FALSE END) AS is_tenant_listing_and_search,
    MAX(CASE WHEN pt.client_type = 'tenant' THEN pt.is_pre_contract ELSE FALSE END) AS is_tenant_pre_contract,
    MAX(CASE WHEN pt.client_type = 'tenant' THEN pt.is_post_contract ELSE FALSE END) AS is_tenant_post_contract,
    MAX(CASE WHEN pt.client_type = 'landlord' THEN pt.journey_step ELSE NULL END) AS landlord_journey_step,
    MAX(CASE WHEN pt.client_type = 'landlord' THEN pt.persona_step ELSE NULL END) AS landlord_persona_step,
    MAX(CASE WHEN pt.client_type = 'landlord' THEN pt.is_offboarding ELSE FALSE END) AS is_landlord_offboarding,
    MAX(CASE WHEN pt.client_type = 'landlord' THEN pt.is_ongoing ELSE FALSE END) AS is_landlord_ongoing,
    MAX(CASE WHEN pt.client_type = 'landlord' THEN pt.is_onboarding ELSE FALSE END) AS is_landlord_onboarding,
    MAX(CASE WHEN pt.client_type = 'landlord' THEN pt.is_contract_to_entrance ELSE FALSE END) AS is_landlord_contract_to_entrance,
    MAX(CASE WHEN pt.client_type = 'landlord' THEN pt.is_visits_to_offer ELSE FALSE END) AS is_landlord_visits_to_offer,
    MAX(CASE WHEN pt.client_type = 'landlord' THEN pt.is_listing_and_search ELSE FALSE END) AS is_landlord_listing_and_search,
    MAX(CASE WHEN pt.client_type = 'landlord' THEN pt.is_pre_contract ELSE FALSE END) AS is_landlord_pre_contract,
    MAX(CASE WHEN pt.client_type = 'landlord' THEN pt.is_post_contract ELSE FALSE END) AS is_landlord_post_contract,
    COALESCE(MAX(pt.is_pp_multi), FALSE) AS is_pp_multi,
    MAX(CASE WHEN pt.client_type = 'tenant' THEN TRUE ELSE FALSE END) AS is_tenant,
    MAX(CASE WHEN pt.client_type = 'broker' THEN TRUE ELSE FALSE END) AS is_broker,
    MAX(CASE WHEN pt.client_type = 'landlord' THEN TRUE ELSE FALSE END) AS is_landlord,
    MAX(CASE WHEN pt.client_type = 'photographer' THEN TRUE ELSE FALSE END) AS is_photographer
  FROM
    datalake_user.persona_type AS pt
  WHERE
    pt.year = {year}
    AND pt.month = {month}
    AND pt.day = {day}
  GROUP BY 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13
)
SELECT
  ptp.id_snapshot,
  ptp.id_user,
  ptp.id_country,
  ptp.id_personal_number,
  COALESCE(cm.id_last_csi_ticket, -1) AS id_last_csi_ticket,
  ptp.main_phone,
  ptp.name,
  ptp.email,
  ptp.tenant_journey_step,
  ptp.tenant_persona_step,
  ptp.landlord_journey_step,
  ptp.landlord_persona_step,
  cbm.last_bot_csat_answered_score,
  chm.last_human_csat_answered_score,
  cbm.bot_csat_detractor_percentage_within_three_months,
  chm.human_csat_detractor_percentage_within_three_months,
  rm.total_created_tickets_within_four_days AS total_created_front_tickets_within_four_days,
  rm.total_recontact_tickets_within_four_days,
  cm.total_csi_tickets_created,
  cbm.total_bot_csat_answered,
  cbm.total_bot_csat_promoter,
  cbm.total_bot_csat_neutral,
  cbm.total_bot_csat_detractor,
  cbm.avg_bot_csat_score_within_three_months,
  cbm.total_bot_csat_detractor_within_three_months,
  cbm.total_bot_csat_neutral_within_three_months,
  cbm.total_bot_csat_promoter_within_three_months,
  cbm.total_bot_csat_answered_within_three_months,
  chm.total_human_csat_answered,
  chm.total_human_csat_promoter,
  chm.total_human_csat_neutral,
  chm.total_human_csat_detractor,
  chm.avg_human_csat_score_within_three_months,
  chm.total_human_csat_detractor_within_three_months,
  chm.total_human_csat_neutral_within_three_months,
  chm.total_human_csat_promoter_within_three_months,
  chm.total_human_csat_answered_within_three_months,
  aim.app_version,
  ptp.is_pp_multi,
  ptp.is_tenant,
  ptp.is_broker,
  ptp.is_landlord,
  ptp.is_photographer,
  ptp.is_tenant_offboarding,
  ptp.is_tenant_ongoing,
  ptp.is_tenant_onboarding,
  ptp.is_tenant_contract_to_entrance,
  ptp.is_tenant_visits_to_offer,
  ptp.is_tenant_listing_and_search,
  ptp.is_tenant_pre_contract,
  ptp.is_tenant_post_contract,
  ptp.is_landlord_offboarding,
  ptp.is_landlord_ongoing,
  ptp.is_landlord_onboarding,
  ptp.is_landlord_contract_to_entrance,
  ptp.is_landlord_visits_to_offer,
  ptp.is_landlord_listing_and_search,
  ptp.is_landlord_pre_contract,
  ptp.is_landlord_post_contract,
  ptp.is_active,
  ptp.is_blocked,
  IF(cm.id_user IS NOT NULL, TRUE, FALSE) AS has_created_csi_ticket,
  COALESCE(cbm.has_answered_bot_csat_within_three_months, FALSE) AS has_answered_bot_csat_within_three_months,
  COALESCE(chm.has_answered_human_csat_within_three_months, FALSE) AS has_answered_human_csat_within_three_months,
  COALESCE(aim.has_app_installed, FALSE) AS has_app_installed,
  ptp.dt_user_birth,
  ptp.ts_user_updated,
  ptp.ts_user_created,
  COALESCE(cm.ts_most_recent_csi_ticket_creation_date, CAST('1900-01-01' AS TIMESTAMP)) AS ts_most_recent_csi_ticket_creation_date,
  COALESCE(cm.ts_most_recent_csi_ticket_solved_date, CAST('1900-01-01' AS TIMESTAMP)) AS ts_most_recent_csi_ticket_solved_date,
  COALESCE(cbm.ts_last_bot_csat_created, CAST('1900-01-01' AS TIMESTAMP)) AS ts_last_bot_csat_created,
  COALESCE(chm.ts_last_human_csat_created, CAST('1900-01-01' AS TIMESTAMP)) AS ts_last_human_csat_created,
  COALESCE(aim.ts_last_app_installed, CAST('1900-01-01' AS TIMESTAMP)) AS ts_last_app_installed,
  ptp.year,
  ptp.month,
  ptp.day
FROM
  persona_type_pivot AS ptp
LEFT JOIN
  datalake_ss_logic_model.user_recontact_metric AS rm
    ON rm.id_user = ptp.id_user
    AND rm.id_snapshot = ptp.id_snapshot
LEFT JOIN
  datalake_ss_logic_model.user_csi_metric AS cm
    ON cm.id_user = ptp.id_user
    AND cm.id_snapshot = ptp.id_snapshot
LEFT JOIN
  datalake_ss_logic_model.user_csat_bot_metric AS cbm
    ON cbm.id_user = ptp.id_user
    AND cbm.id_snapshot = ptp.id_snapshot
LEFT JOIN
  datalake_ss_logic_model.user_csat_human_metric AS chm
    ON chm.id_user = ptp.id_user
    AND chm.id_snapshot = ptp.id_snapshot
LEFT JOIN
  datalake_ss_logic_model.user_app_installed_metric AS aim
    ON aim.id_user = ptp.id_user
    AND aim.id_snapshot = ptp.id_snapshot
