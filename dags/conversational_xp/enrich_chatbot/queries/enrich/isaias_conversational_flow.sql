SELECT
  t.id_session AS id_langfuse_session,
  MAX(o.name = 'UserNameQualification.post_clarification' AND GET_JSON_OBJECT(o.output, '$.user_name.first_name') IS NOT NULL) AS has_user_name_success,
  MAX(o.name = 'PropertyAddress.post_clarification' AND CAST(GET_JSON_OBJECT(o.output, '$.property_address_verified') AS BOOLEAN) = TRUE) AS has_property_address_success,
  MAX(o.name = 'PropertyAddressConfirmation.post_clarification' AND (CAST(GET_JSON_OBJECT(o.output, '$.location_covered') AS BOOLEAN) = TRUE OR CAST(GET_JSON_OBJECT(o.output, '$.location_covered_for_rent') AS BOOLEAN) = TRUE OR CAST(GET_JSON_OBJECT(o.output, '$.location_covered_for_sale') AS BOOLEAN) = TRUE)) AS has_property_address_confirmation_success,
  MAX(o.name = 'PropertyCity.disqualification' OR o.name = 'PropertyAddressConfirmation.disqualification') AS has_property_address_confirmation_disqualification,
  MAX(o.name = 'PropertyType.disqualification') AS has_property_type_disqualification,
  MAX(o.name = 'PropertyType.post_clarification') AS has_property_type_success,
  MAX(o.name = 'PropertyAvailability.disqualification') AS has_property_availability_disqualification,
  MAX(o.name = 'PropertyAvailability.post_clarification' AND CAST(GET_JSON_OBJECT(o.output, '$.is_available') AS BOOLEAN) = TRUE) AS has_property_availability_success,
  MAX(GET_JSON_OBJECT(o.input, '$.lead_id') IS NOT NULL AND o.name = 'RetrieveProspect.clarification') AS has_retrieved_lead,
  MAX(CASE WHEN GET_JSON_OBJECT(o.input, '$.lead_id') IS NOT NULL AND o.name = 'RetrieveProspect.clarification' THEN GET_JSON_OBJECT(o.input, '$.lead_id') END) AS id_lead_retrieved
FROM
  datalake_langfuse_clean.observations o
INNER JOIN
  datalake_langfuse_clean.traces t 
    ON o.id_trace = t.id_trace
WHERE 
  o.ts_started >= '{load_start_date}'
  AND t.environment = 'prod' 
  AND o.name IN (
    'UserNameQualification.post_clarification',
    'PropertyAddress.post_clarification',
    'PropertyAddressConfirmation.post_clarification',
    'PropertyCity.disqualification',
    'PropertyAddressConfirmation.disqualification',
    'PropertyType.disqualification',
    'PropertyType.post_clarification',
    'PropertyAvailability.disqualification',
    'PropertyAvailability.post_clarification',
    'escalation_node',
    'escalate_when_qualified',
    'RetrieveProspect.clarification'
  )
GROUP BY 1