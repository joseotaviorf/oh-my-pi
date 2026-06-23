SELECT
    uuid AS uuid_crm_integration,
    company_uuid AS uuid_company,
    crm_broker_account_id AS id_crm_broker_account,
    platform,
    xml_inventory_url,
    post_lead_url,
    post_direct_lead_url,
    crm_api_token,
    active AS is_active,
    CAST(deactivated_at AS TIMESTAMP) AS ts_deactivated,
    CAST(ready_gate_sent_at AS TIMESTAMP) AS ts_ready_gate_sent,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    YEAR(CAST(updated_at AS TIMESTAMP)) AS year,
    MONTH(CAST(updated_at AS TIMESTAMP)) AS month,
    DAY(CAST(updated_at AS TIMESTAMP)) AS day
FROM
    datalake_alias_raw.crm_integrations