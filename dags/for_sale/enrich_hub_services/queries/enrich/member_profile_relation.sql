WITH member_profile AS (
      SELECT
          mp.id,
          mp.id_business_unit,
          mp.id_user,
          mp.id_parent_member_profile,
          mp.profile,
          mp.is_active,
          ts_created AS ts_relationship_start,
          LEAD(mp.ts_created) OVER(PARTITION BY mp.id ORDER BY mp.ts_created) AS ts_relationship_finish
      FROM
          datalake_hub_services_clean.member_profile_aud AS mp
      WHERE
          (mp.mod_id_parent_member_profile IS TRUE OR mp.mod_active IS TRUE)
),
users_relations AS (
      SELECT
            mp.id,
            mp.id_business_unit,
            mp.id_user,
            mp.id_parent_member_profile,
            mp.profile,
            mp.ts_relationship_start,
            mp.ts_relationship_finish
      FROM
            member_profile AS mp
      WHERE
            is_active IS NOT FALSE
),
hub_users AS (
      SELECT
            u.id,
            u.id_external,
            u.name,
            u.email
      FROM
            datalake_hub_services_clean.users AS u
      QUALIFY
            ROW_NUMBER() OVER (PARTITION BY id ORDER BY u.ts_updated DESC) = 1
),
business_unit AS (
      SELECT
            bu.id,
            bu.hub_name,
            bu.business_context
      FROM
            datalake_hub_services_clean.business_unit AS bu
      QUALIFY
            ROW_NUMBER() OVER (PARTITION BY bu.id ORDER BY bu.ts_updated DESC) = 1
),
teams_relations AS (
      SELECT
            ur_ag.id,
            ag_info.id_external AS id_external_agent,
            ur_ag.id_business_unit,
            bu.id AS id_business_unit,
            bu.hub_name,
            bu.business_context,
            ag_info.name AS nome_corretor,
            ag_info.email AS email_corretor,
            en_info.id_external AS id_user_external_en,
            ur_en.id_user AS id_user_en,
            ur_en.id AS id_mp_en,
            en_info.name AS nome_EN,
            en_info.email AS email_EN,
            ur_ag.ts_relationship_start,
            ur_ag.ts_relationship_finish
      FROM
            users_relations AS ur_ag
      LEFT JOIN
            business_unit AS bu
                  ON ur_ag.id_business_unit = bu.id
      LEFT JOIN
            hub_users AS ag_info
                  ON ur_ag.id_user = ag_info.id
      LEFT JOIN
            users_relations AS ur_en
                  ON ur_en.id = ur_ag.id_parent_member_profile
      LEFT JOIN
            hub_users AS en_info
                  ON ur_en.id_user = en_info.id
      WHERE
            ur_ag.profile = 'AGENT'
      QUALIFY
            ROW_NUMBER() OVER (PARTITION BY ur_ag.id, ur_en.id ORDER BY ur_en.ts_relationship_finish DESC NULLS FIRST) = 1
),
last_mp AS (
      SELECT
            id,
            id_user,
            id_parent_member_profile,
            profile
      FROM
            datalake_hub_services_clean.member_profile
      QUALIFY
            ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1
),
teams_relations_en AS (
      SELECT
            mp_en.id AS id_mp_en,
            mp_ea.id AS id_mp_ea,
            mp_en.id_user AS id_user_en,
            mp_ea.id_user AS id_user_ea,
            en_info.id_external AS id_external_en,
            ea_info.id_external AS id_external_ea,
            ea_info.name AS nome_ea,
            ea_info.email AS email_ea
      FROM
            last_mp AS mp_en
      LEFT JOIN
            hub_users AS en_info
                  ON mp_en.id_user = en_info.id
      LEFT JOIN
            last_mp AS mp_ea
                  ON mp_ea.id = mp_en.id_parent_member_profile
      LEFT JOIN
            hub_users AS ea_info
                  ON mp_ea.id_user = ea_info.id
)
SELECT
     du.id_agent,
     tr.id AS id_member_profile_agent,
     tr.id_external_agent,
     tr.id_user_en AS id_user_negotiation_executive,
     tr_en.id_mp_en AS id_member_profile_negotiation_executive,
     tr_en.id_external_en AS id_external_negotiation_executive,
     tr_en.id_user_ea AS id_user_associated_executive,
     tr_en.id_mp_ea AS id_member_profile_associated_executive,
     tr_en.id_external_ea AS id_external_associated_executive,
     tr.hub_name,
     tr.business_context AS hub_business_context,
     tr.nome_corretor AS agent_name,
     tr.email_corretor AS agent_email,
     tr.nome_en AS negotiation_executive_name,
     tr.email_en AS negotiation_executive_email,
     tr_en.nome_ea AS associated_executive_name,
     tr_en.email_ea AS associated_executive_email,
     tr.ts_relationship_start AS ts_agent_en_relationship_start,
     tr.ts_relationship_finish AS ts_agent_en_relationship_finish
FROM
     teams_relations AS tr
LEFT JOIN
     datalake_ebdb_user.user AS du
           ON du.id = tr.id_external_agent
LEFT JOIN
     teams_relations_en AS tr_en
           ON tr.id_mp_en = tr_en.id_mp_en
