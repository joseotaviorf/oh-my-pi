SELECT
    id,
    development_external_id AS id_external_development,
    typology_external_id AS id_external_typology,
    company_uuid AS uuid_company,
    provider,
    rule_code,
    severity,
    year,
    month,
    day
FROM
    datalake_developers_supply_processor_raw.development_validation_failure
