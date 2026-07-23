SELECT
  trc.id_session AS id_langfuse_session,
  MAX(
    CASE
      WHEN obs.name = 'RetrieveProspect.clarification'
        AND GET_JSON_OBJECT(obs.input, '$.lead_id') IS NOT NULL
        THEN GET_JSON_OBJECT(obs.input, '$.lead_id')
    END
  ) AS id_lead_retrieved,
  BOOL_OR(obs.name = 'UserNameQualification.post_clarification' AND GET_JSON_OBJECT(obs.output, '$.user_name.first_name') IS NOT NULL) AS has_user_name,
  BOOL_OR(obs.name = 'AddressCollectorAgent.clarification' AND GET_JSON_OBJECT(obs.output, '$.is_address_confirmed') = 'true') AS has_property_address,
  BOOL_OR(obs.name = 'ListingType.post_clarification' AND (GET_JSON_OBJECT(obs.output, '$.property_intent.for_rent') = 'true' OR GET_JSON_OBJECT(obs.output, '$.property_intent.for_sale') = 'true')) AS has_business_context,
  BOOL_OR(obs.name = 'PropertyVacancy.post_clarification' AND GET_JSON_OBJECT(obs.output, '$.is_available') = 'true') AS has_property_vacancy,
  BOOL_OR(obs.name = 'PropertyDetailsNode.post_clarification') AS has_property_details,
  BOOL_OR(obs.name = 'PropertyNumbersNode.post_clarification') AS has_property_features,
  BOOL_OR(obs.name = 'CostsCondo.post_clarification') AS has_property_condo,
  BOOL_OR(obs.name = 'CostsIPTU.post_clarification') AS has_property_iptu,
  BOOL_OR(obs.name = 'DraftConfirmation.post_clarification') AS has_property_features_confirmation,
  BOOL_OR(
    obs.name IN ('RentPricingSuggestion.post_clarification', 'SalePricingSuggestion.post_clarification')
    AND (
      GET_JSON_OBJECT(obs.output, '$.pricing.chosen_rent_price') IS NOT NULL
      OR GET_JSON_OBJECT(obs.output, '$.pricing.chosen_sale_price') IS NOT NULL
    )
  ) AS has_pricing_information,
  BOOL_OR(obs.name = 'ListAvailablePhotoTimeNode.post_clarification' AND GET_JSON_OBJECT(obs.output, '$.photo_schedule_date') IS NOT NULL) AS has_photo_selected,
  BOOL_OR(obs.name = 'Submission.post_clarification' AND GET_JSON_OBJECT(obs.output, '$.photo_session_successfully_scheduled') = 'true') AS has_submission,
  BOOL_OR(obs.name = 'escalate_when_qualified') AS has_escalated_qualified,
  BOOL_OR(obs.name = 'FAQAgentInputState') AS has_faq_agent_interaction,
  BOOL_OR(obs.name = 'escalation_node') AS has_escalated_non_qualified,
  BOOL_OR(obs.name = 'EntryAccessModelNode.post_clarification') AS has_entry_model,
  BOOL_OR(
    obs.name = 'EntryAccessModelNode.post_clarification'
    AND GET_JSON_OBJECT(obs.output, '$.entry_access_model_details.access_model_type') IN ('FRONT_DOOR', 'PASSWORD', 'KEYS_WITH_AGENT')
  ) AS has_easy_entry_model,
  BOOL_OR(obs.name = 'PhotoSessionSchedulingAuth.clarification') AS has_auth_request,
  BOOL_OR(obs.name = 'RetrieveProspect.clarification' AND GET_JSON_OBJECT(obs.input, '$.lead_id') IS NOT NULL) AS has_retrieved_lead,
  BOOL_OR(GET_JSON_OBJECT(obs.output, '$.is_draft_enabled') = 'true') AS is_full_process,
  MIN(trc.ts_created) AS ts_session
FROM
  datalake_langfuse_clean.observations AS obs
INNER JOIN
  datalake_langfuse_clean.traces AS trc
    ON obs.id_trace = trc.id_trace
WHERE
  obs.ts_started >= TIMESTAMP('{load_start_date}')
  AND trc.environment = 'prod'
  AND obs.name IN (
    'orchestrator_init',
    'UserNameQualification.post_clarification',
    'AddressCollectorAgent.clarification',
    'ListingType.post_clarification',
    'PropertyVacancy.post_clarification',
    'PropertyDetailsNode.post_clarification',
    'PropertyNumbersNode.post_clarification',
    'CostsCondo.post_clarification',
    'CostsIPTU.post_clarification',
    'DraftConfirmation.post_clarification',
    'RentPricingSuggestion.post_clarification',
    'SalePricingSuggestion.post_clarification',
    'ListAvailablePhotoTimeNode.post_clarification',
    'Submission.post_clarification',
    'escalate_when_qualified',
    'FAQAgentInputState',
    'escalation_node',
    'EntryAccessModelNode.post_clarification',
    'PhotoSessionSchedulingAuth.clarification',
    'RetrieveProspect.clarification'
  )
GROUP BY 1
