-- Static reference catalog of DataHub Data Products.
-- Updated quarterly or after DataHub catalog changes.
-- Source: dags/governance/enrich_tars/schemas/datahub_products.yml (Jun 2026, 36 products).
SELECT
    product_slug,
    product_name,
    datahub_domain,
    is_test
FROM (
    VALUES
        ('visits', 'Visits', 'for_rent', FALSE),
        ('nps', 'NPS', 'for_rent', FALSE),
        ('offboarding', 'Offboarding', 'for_rent', FALSE),
        ('inspection', 'Inspection', 'for_rent', FALSE),
        ('repairs', 'Repairs', 'for_rent', FALSE),
        ('owner-statement', 'Owner Statement', 'for_rent', FALSE),
        ('rent-contracts', 'Rent Contracts', 'for_rent', FALSE),
        ('supply', 'Supply', 'growth', FALSE),
        ('leads', 'Leads', 'growth', FALSE),
        ('marketing-attribution', 'Marketing Attribution', 'growth', FALSE),
        ('pricing', 'Pricing', 'growth', FALSE),
        ('listing', 'Listing', 'growth', FALSE),
        ('fs-transact', 'FS Transact', 'growth', FALSE),
        ('offers', 'Offers', 'growth', FALSE),
        ('closing', 'Closing', 'fintech', FALSE),
        ('collections-recovery', 'Collections Recovery', 'fintech', FALSE),
        ('ticket', 'Ticket', 'fintech', FALSE),
        ('payments', 'Payments', 'fintech', FALSE),
        ('invoice', 'Invoice', 'fintech', FALSE),
        ('insurance', 'Insurance', 'fintech', FALSE),
        ('chatbot-sessions', 'Chatbot Sessions', 'support_and_services', FALSE),
        ('customer-service', 'Customer Service', 'support_and_services', FALSE),
        ('smart-home', 'Smart Home', 'support_and_services', FALSE),
        ('maintenance', 'Maintenance', 'support_and_services', FALSE),
        ('data-platform-quality', 'Data Platform Quality', 'untagged', FALSE),
        ('datahub-assets', 'DataHub Assets', 'untagged', FALSE),
        ('trino-usage', 'Trino Usage', 'untagged', FALSE),
        ('pipeline-health', 'Pipeline Health', 'untagged', FALSE),
        ('superset-governance', 'Superset Governance', 'untagged', FALSE),
        ('airflow-governance', 'Airflow Governance', 'untagged', FALSE),
        ('documentation', 'Documentation', 'untagged', FALSE),
        ('fair-metadata', 'FAIR Metadata', 'untagged', FALSE),
        ('anonymization', 'Anonymization', 'untagged', FALSE),
        ('jira-governance', 'Jira Governance', 'untagged', FALSE),
        ('test-product-1', 'Test Product 1', 'untagged', TRUE),
        ('test-product-2', 'Test Product 2', 'untagged', TRUE)
) AS products(product_slug, product_name, datahub_domain, is_test)
