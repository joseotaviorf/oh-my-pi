WITH hrbp_info AS (
    SELECT
        im.id_assignment,
        im.person_number,
        im.name,
        im.work_email
    FROM
        datalake_people.identifier_mapping AS im
)
SELECT
    h.sk_cost_center_version,
    h.cost_center_code,
    h.id_organization,
    h.sk_business_partner_assignment,
    h.sk_business_partner,
    hrbp.person_number AS hrbp_person_number,
    hrbp.name AS hrbp_name,
    hrbp.work_email AS hrbp_work_email,
    h.cost_center_name,
    h.business,
    h.product,
    h.brand,
    h.vertical,
    h.structure,
    h.team,
    h.chapter,
    h.line,
    h.owner_l1_name,
    h.owner_l2_name,
    h.owner_l3_name,
    h.headcount_type,
    h.is_active,
    h.dt_valid_from,
    h.dt_valid_to,
    h.is_current,
    h.ts_created,
    NOW() AS ts_load
FROM
    datalake_people.cost_center_history AS h
LEFT JOIN
    hrbp_info AS hrbp
    ON hrbp.id_assignment = h.sk_business_partner_assignment
