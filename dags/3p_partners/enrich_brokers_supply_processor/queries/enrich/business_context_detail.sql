SELECT
    id,
    id_listing,
    id_file,
    id_partner,
    business_context,
    status,
    FROM_JSON(NULLIF(status_reason, '{{}}'), 'map<string, string>') AS status_reason,
    has_3p_access_control,
    ts_created,
    ts_updated
FROM
    datalake_brokers_supply_processor_clean.business_context_detail
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1