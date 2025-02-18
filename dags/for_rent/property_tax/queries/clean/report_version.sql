SELECT
    id AS id_report_version,
    tax_report_id AS id_tax_report,
    author_id AS id_author,
    tenant_email_status,
    landlord_email_status,
    tenant_email_sent_at AS ts_tenant_email_sent,
    landlord_email_sent_at AS ts_landlord_email_sent,
    created_at AS ts_created,
    sent_at AS ts_sent
FROM
    datalake_property_tax_raw.report_version
