SELECT
    development_external_id AS id_external_development,
    company_uuid AS uuid_company,
    provider,
    status,
    pipeline_version,
    validated_at AS ts_validated,
    withdrawn_at AS ts_withdrawn,
    year,
    month,
    day
FROM
    datalake_developers_supply_processor_raw.development_validation
