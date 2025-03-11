SELECT
    id,
    name,
    person_type,
    cost_center,
    business_place,
    sequence_code,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM 
    datalake_sap_gateway_raw.rule_modifier