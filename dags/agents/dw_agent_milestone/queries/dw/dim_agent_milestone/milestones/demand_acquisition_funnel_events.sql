-- TQC/TQA demand-acquisition funnel events (referral, VB, VC, CCV) for dim_agent_milestone.
-- Source: datalake_agent_performance.fact_agent_demand_acquisition (AAREDE-504 swap off agent_lead_referral).
-- Params: {business_context} — SALE (TQC) or RENT (TQA).
--         {ts_expr} / {entity_expr} — dotted path after "fada." to the stage's timestamp/entity
--           field, e.g. "valid_from" / "id_referral" (referral), or
--           "sale_first_events.ts_visit_booked" / "sale_first_events.id_booking" (VB).
--         {entity_type} — entity_type string stored alongside sk_entity.
--         {same_agent_expr} — "TRUE" for the any-agent variant, or the matching
--           is_*_same_agent column (e.g. "fada.is_visit_same_agent = TRUE") for the
--           _SAME_AGENT variant.
--         {scan_predicate} — framework watermark.
-- Identity: sk_user = id_user_referring_agent; id_agent from datalake_agent_accreditation.agent.
SELECT
    CAST(fada.id_user_referring_agent AS BIGINT) AS sk_user,
    CAST(acc.id_agent AS BIGINT) AS id_agent,
    fada.{ts_expr} AS ts_event,
    CAST(fada.{entity_expr} AS BIGINT) AS sk_entity,
    '{entity_type}' AS entity_type
FROM
    datalake_agent_performance.fact_agent_demand_acquisition AS fada
INNER JOIN
    datalake_agent_accreditation.agent AS acc
        ON CAST(fada.id_user_referring_agent AS STRING) = CAST(acc.id_user AS STRING)
WHERE
    fada.id_user_referring_agent IS NOT NULL
    AND fada.business_context = '{business_context}'
    AND fada.{ts_expr} IS NOT NULL
    AND acc.id_agent IS NOT NULL
    AND ({same_agent_expr})
    AND ({scan_predicate})
