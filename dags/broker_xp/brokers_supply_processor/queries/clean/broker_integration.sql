SELECT
    id AS id_broker_integration,
    name,
    company_uuid AS uuid_company,
    integrator_partner_uuid AS uuid_integrator_partner,
    preset_id AS uuid_integration_preset,
    integration_params,
    active AS is_active,
    deleted AS is_deleted,
    last_source_modified_at AS ts_last_source_modified,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.broker_integration
