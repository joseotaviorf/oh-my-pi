--drop view if exists vw_potential_listings_house_b2b;
--create or replace view vw_potential_listings_house_b2b as
with leads_b2b AS (
  SELECT DISTINCT
    l.id AS id_lead,
    pa_b2b_online.partner_id AS online_partner_id
  FROM lead AS l
  JOIN partner_agent AS pa_b2b_online
    ON pa_b2b_online.user_id = l.usuario_que_indicou_id
  WHERE pa_b2b_online.partner_id IS NOT NULL
),
autonomous_agent_info AS (
    SELECT
    	pa.user_id AS sk_autonomous_agent,
    	pa.ts_created
    FROM partner_agent AS pa
    JOIN partner AS dp
	    ON pa.partner_id = dp.id
	    AND dp.type = 'AUTONOMOUS_AGENT'
	    AND dp.id <> '257' -- Test User
)
SELECT
    f.id,
    COALESCE(h.condo_id, '-1'::INTEGER::BIGINT) AS sk_condo,
    COALESCE(f.imovel_id || '00' || COALESCE(hl_version_zero.version, 1)::VARCHAR, '-1')::BIGINT AS sk_house_listing,
    COALESCE(pa_b2b_prime.partner_id, l_b2b.online_partner_id, f.partner_id, '-1'::INTEGER::BIGINT) AS sk_partner,
    COALESCE(aa_info.sk_autonomous_agent, -1) AS sk_autonomous_agent,
    h.exclusivity AS is_exclusive,
    COALESCE(aa_info.sk_autonomous_agent IS NOT NULL, FALSE) AS is_autonomous_agent,
    h.usuario_que_cadastrou_id AS house_usuario_que_cadastrou_id
  FROM listing_flows_with_reprocessed_leads AS f
  LEFT JOIN house AS h
    ON f.imovel_id = h.id
  LEFT JOIN leads_b2b AS l_b2b
    ON l_b2b.id_lead = f.lead_id
  LEFT JOIN partner_agent AS pa_b2b_prime
    ON h.usuario_id = pa_b2b_prime.user_id
  LEFT JOIN house_listing AS hl_version_zero
    ON hl_version_zero.id_house = f.imovel_id
    AND hl_version_zero.version = 0
  LEFT JOIN autonomous_agent_info AS aa_info
    ON aa_info.sk_autonomous_agent = h.usuario_que_cadastrou_id
    AND h.data_criacao >= aa_info.ts_created --This rule might change when we start to considering migration
    AND h.external_id IS NOT NULL --This rule might change when we start to considering migration
