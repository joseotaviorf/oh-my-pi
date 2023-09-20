WITH visitor AS (
    SELECT
        id,
        id_external,
        visitor_name,
        email AS visitor_email
    FROM
        datalake_hub_services_clean.visitor
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY version DESC) = 1
),
leads AS (
    SELECT
        le.id AS id_lead,
        le.id_visitor,
        vi.id_external,
        le.id_house,
        le.id_business_unit,
        le.lead_type,
        visitor_name,
        visitor_email
    FROM
        datalake_hub_services_clean.lead AS le
    LEFT JOIN
        visitor AS vi
            ON vi.id = le.id_visitor
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY le.id ORDER BY le.version DESC) = 1
),
users AS (
    SELECT
      id,
      id_external,
      email
    FROM
        datalake_hub_services_clean.users
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY version DESC) = 1
),
events_aud AS (
    SELECT
        re.id_lead,
        re.is_active,
        le.id_visitor,
        le.id_external AS id_external_lead,
        resp_u.id_external AS id_external_responsible,
        dist_u.id_external AS id_external_distributor,
        le.id_house,
        le.id_business_unit,
        re.id_responsible,
        re.id_distributor,
        le.lead_type,
        le.visitor_name,
        le.visitor_email,
        resp_u.email AS responsible_email,
        dist_u.email AS distributor_email,
        re.ts_assigned,
        re.ts_unassigned
    FROM
        datalake_hub_services_clean.responsible AS re
    LEFT JOIN
        leads AS le
            ON le.id_lead = re.id_lead
    LEFT JOIN
        users AS resp_u
            ON re.id_responsible = resp_u.id
    LEFT JOIN
        users AS dist_u
            ON re.id_distributor = dist_u.id
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY re.id_lead, re.id ORDER BY re.ts_created DESC) = 1
)
SELECT
    ev.id_lead,
    ev.id_external_lead,
    id_external_responsible,
    id_external_distributor,
    ev.id_house,
    ev.id_business_unit,
    ev.lead_type,
    ev.visitor_name,
    ev.visitor_email,
    ev.responsible_email,
    ev.distributor_email,
    ev.is_active,
    ev.ts_assigned,
    ev.ts_unassigned
FROM
    events_aud AS ev
