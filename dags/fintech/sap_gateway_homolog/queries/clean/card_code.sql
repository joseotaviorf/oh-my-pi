SELECT
    tax_id                      AS id_tax,
    tax_id_type                 AS id_tax_type,
    supplier_landlord_code,
    supplier_tenant_code,
    supplier_estate_agent_code,
    customer_landlord_code,
    customer_tenant_code,
    customer_reservation_code,
    customer_seller_code
FROM
    datalake_sap_gateway_homolog_raw.card_code
