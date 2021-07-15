with first_sent as (
  with first_change as (
    select
      ppa.id_pre_proposal,
      min(rev) as min_rev
    from datalake_ebdb_clean.pre_proposal_aud ppa
    where ppa.mod_edition
      and ppa.rev_type = 1
    group by 1
  )
  select
    pp.id as id_pre_proposal,
    min(FROM_UNIXTIME(ure.ts_revision/1000)) as ts_first_sent
  from datalake_ebdb_clean.pre_proposal pp
  join first_change fc
    on fc.id_pre_proposal = pp.id
  join datalake_ebdb_clean.user_revision_entity ure
    on ure.id = fc.min_rev
  group by 1
),
last_analysis as (
  select
    ppa.id_pre_proposal,
    max(FROM_UNIXTIME(ure.ts_revision/1000)) as ts_last_analysis
  from datalake_ebdb_clean.pre_proposal_aud ppa
  join datalake_ebdb_clean.user_revision_entity ure
    on ure.id = ppa.rev
  	and ppa.status in ('Aprovada', 'Rejeitada')
  group by 1
),
special_conditions as (
  select
    pp.id as id_pre_proposal,
    count(pc.id) as special_conditions_count,
    sum(cast(pc.title = 'Remove' as integer)) as remove_conditions_count,
    sum(cast(pc.title = 'Include' as integer)) as include_conditions_count,
    sum(cast(pc.title = 'MaintenanceOrRepair' as integer)) as maintenance_or_repair_conditions_count,
    sum(cast(pc.title = 'ReplaceOrModify' as integer)) as replace_or_modify_conditions_count,
    sum(cast(pc.title not in ('Remove',
                              'Include',
                              'MaintenanceOrRepair',
                              'ReplaceOrModify') as integer)
                              ) as other_conditions_count
  from datalake_ebdb_clean.pre_proposal pp
  join datalake_ebdb_clean.pre_proposal_condition ppc
    on pp.id = ppc.id_pre_proposal
  join datalake_ebdb_clean.proposal_condition pc
    on pc.id = ppc.id_conditions
  group by 1
)
select
  pp.id,
  (pp.id * 100) + 1 as id_offer_context,
  pp.id_user,
  pp.id_house,
  pp.code,
  pp.rejection_reason,
  pp.rent,
  pp.original_rent,
  pp.original_condo,
  pp.edition,
  pp.status,
  pp.last_edition_updated,
  pp.ts_created,
  pp.ts_updated,
  fs.ts_first_sent,
  la.ts_last_analysis,
  pp.has_rental_accepted,
  pp.has_income_proof_accepted,
  pp.has_charge_accepted,
  pp.is_owner_accept_condition,
  coalesce(ani.description is null, false) as has_animals_condition,
  coalesce(we_live.description is null, false) as has_when_will_live_condition,
  coalesce(wo_live.description is null, false) as has_who_will_live_condition,
  (pp.last_edition_updated > 0) as has_edition_update,
  coalesce(sc.special_conditions_count, 0) as special_conditions_count,
  coalesce(sc.remove_conditions_count, 0) as remove_conditions_count,
  coalesce(sc.include_conditions_count, 0) as include_conditions_count,
  coalesce(sc.maintenance_or_repair_conditions_count, 0) as maintenance_or_repair_conditions_count,
  coalesce(sc.replace_or_modify_conditions_count, 0) as replace_or_modify_conditions_count,
  coalesce(sc.other_conditions_count, 0) as other_conditions_count
from
  datalake_ebdb_clean.pre_proposal pp
left join
  datalake_ebdb_clean.proposal_condition ani
    on ani.id = pp.id_animals
left join
  datalake_ebdb_clean.proposal_condition we_live
    on we_live.id = pp.id_when_will_live
left join
  datalake_ebdb_clean.proposal_condition wo_live
    on wo_live.id = pp.id_who_will_live
left join
  first_sent fs
    on fs.id_pre_proposal = pp.id
left join
  last_analysis la
    on la.id_pre_proposal = pp.id
left join
  special_conditions sc
    on pp.id = sc.id_pre_proposal
