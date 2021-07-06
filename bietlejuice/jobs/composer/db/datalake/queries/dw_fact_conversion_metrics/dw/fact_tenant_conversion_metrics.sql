-- filter only users that are tenants, thus have tenant mobile app
with
    filter_tenant_users
    as
    (
        select
            u.id,
            d.id_user is not null as has_tenant_app
        from datalake_ebdb_clean.user u
            inner join datalake_ebdb_clean.device d
            on u.id = d.id_user
        where d.mobile_app = 'Inquilinos'
        group by 1,2
    ),
    user_to_contract
    as
    (
        select
            u.id,
            b.ts_created as ts_created_booking,
            b.status as status_booking,
            v.dt_visit,
            pp.ts_created as ts_created_pre_proposal,
            p.ts_created as ts_created_proposal,
            c.id as id_contract,
            c.ts_created as ts_created_contract,
            c.ts_signed as ts_signed_contract,
            c.status as status_contract
        from datalake_ebdb_clean.user u
            left join datalake_ebdb_clean.booking b
            on b.id_visitor = u.id
            left join datalake_ebdb_clean.visit v
            on v.id = b.id_visit
            left join datalake_ebdb_clean.rent_flow fl
            on fl.id = b.id_rent_flow
            left join datalake_ebdb_clean.pre_proposal pp
            on fl.id_client = pp.id_user
            left join datalake_ebdb_clean.proposal p
            on p.id_pre_proposal = pp.id
            left join datalake_ebdb_clean.contract c
            on c.id_proposal = p.id
    ),

    -- get the timeline start from tenant funnel
    user_dates
    as
    (
        select
            id,
            cast(min(ts_created_booking) as date) as first_booking_date,
            min(dt_visit) as first_visit_date,
            min(ts_created_pre_proposal) as first_pre_proposal_date,
            min(ts_created_proposal) as first_proposal_accepted_date,
            min(ts_created_contract) as first_contract_date,
            min(ts_signed_contract) as first_signed_contract
        from user_to_contract utc6
        group by id
    ),
    booking_metrics
    as
    (
        select
            id_visitor,
            count(1) as visits_booked,
            sum(case when visit_fup in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho') then 1 else 0 end) as visits_realized,
            sum(case when visit_fup is not null then 1 else 0 end) as visits_expected_to_happen
        from datalake_ebdb_clean.booking
        group by id_visitor
    ),
    contract_metrics
    as
    (
        select
            id as id_user,
            count(case when status_contract in ('Ativo','Finalizado') then id_contract end) as contracts_signed,
            count(case when status_contract in ('Cancelado') then id_contract end) as contracts_cancelled,
            count(case when status_contract in ('Finalizado') then id_contract end) as contracts_annuled,
            count(case when status_contract in ('Minuta','PreAssinaturas') then id_contract end) as contracts_to_be_signed
        from user_to_contract
        group by 1
    ),
    -- build offer ETL from both sources (old and Firestore) to create offer metrics
    old_pre_proposal
    as
    (
        select
            id as id_offer,
            (id * 100) + 1 as sk_offer,
            status,
            id_user as user_id,
            id_house as house_id,
            cast(ts_created as date) as dt_created,
            cast(ts_updated as date) as dt_updated,
            cast(ts_last_edition_updated as date) as offer_submitted,
            rejection_reason
        from datalake_ebdb_clean.pre_proposal
    ),
    offer_firestore
    as
    (
        select
            eo.id as id_offer,
            max(coalesce(eo.id_godfather, go_firestore.id)) over (partition by eo.id_firestore) as id_godfather
        from datalake_ebdb_clean.offer eo
            left join datalake_godfather_clean.offer go_firestore
            on eo.id_firestore = go_firestore.id_firestore
                and eo.id_godfather is null
    ),
    firestore_offers
    as
    (
        select
            of.id_offer,
            go_firestore.id_firestore,
            go_firestore.id,
            go_firestore.ts_first_sent,
            go_firestore.ts_last_sent,
            go_firestore.type as distinct_type
        from offer_firestore
     of
	join datalake_godfather_clean.offer go_firestore
    	on go_firestore.id = of.id_godfather
	group by 1,2,3,4,5,6
),
new_offer as
(
	select
    distinct o.id as id_offer,
    (o.id * 100) + 2 as sk_offer,
    o.status,
    o.id_client as user_id,
    o.id_house,
    cast(o.ts_created as date) as dt_created,
    cast(o.ts_updated as date) as dt_updated,
    coalesce(go_godfather.ts_last_sent, go_firestore.ts_last_sent) as offer_submitted,
    o.rejection_reason
from datalake_ebdb_clean.offer o
    left join datalake_godfather_clean.offer go_godfather
    on o.id_godfather = go_godfather.id
        and o.id_godfather is not null
    left join firestore_offers go_firestore
    on o.id = go_firestore.id_offer
)
,
all_offers as
    (
        select *
    from new_offer
union
    select *
    from old_pre_proposal
)
,
offer_metrics as
(
	select
    user_id,
    min(offer_submitted) as first_offer_sent_date,
    count(id_offer) as offers_sent,
    count(case when status = 'Aprovada' then id_offer end) as offers_approved,
    count(case when status = 'Rejeitada' then id_offer end) as offers_rejected,
    count(case when status = 'EmNegociacao' then id_offer end) as offers_negotiating
from all_offers
group by 1
)
,
-- build rule for ongoing contracts such as described in Strategy datamart
ongoing_contracts as
( 
	select
    id,
    case when status in ('Ativo','Finalizado')
        and type <> 'DealOnly'
        and current_date >= date(coalesce(coalesce(ts_signed,dt_started),dt_entered))
        and (current_date < dt_termination or dt_termination is null)
			then true
		else false end as is_ongoing_contract
from datalake_ebdb_clean.contract
)
,
-- identify tenants that have ongoing contracts
tenant_ongoing as
(
	select
    c.id_user as sk_client,
    count(oc.id)
> 0 as has_ongoing_contract
	from datalake_ebdb_clean.contract c 
	inner join ongoing_contracts oc 
		on c.id = oc.id
		and is_ongoing_contract = true
	group by 1
)
select
    u.id as sk_user,
    coalesce(cast(date_format(ud.first_booking_date, 'yyyyMMdd') as integer), -1) as sk_first_booking_date,
    coalesce(cast(date_format(ud.first_visit_date, 'yyyyMMdd') as integer), -1) as sk_first_visit_date,
    coalesce(cast(date_format(om.first_offer_sent_date, 'yyyyMMdd') as integer), -1) as sk_first_offer_sent_date,
    coalesce(cast(date_format(ud.first_proposal_accepted_date, 'yyyyMMdd') as integer), -1) as sk_first_proposal_accepted_date,
    coalesce(cast(date_format(ud.first_signed_contract, 'yyyyMMdd') as integer), -1) as sk_first_contract_signed_date,
    coalesce(bm.visits_booked,0) as visits_booked,
    coalesce(bm.visits_realized,0) as visits_realized,
    coalesce(bm.visits_expected_to_happen,0) as visits_expected_to_happen,
    coalesce(om.offers_sent,0) as offers_sent,
    coalesce(om.offers_approved,0) as offers_approved,
    coalesce(om.offers_rejected,0) as offers_rejected,
    coalesce(om.offers_negotiating,0) as offers_negotiating,
    coalesce(cm.contracts_signed,0) as contracts_signed,
    coalesce(cm.contracts_cancelled,0) as contracts_cancelled,
    coalesce(cm.contracts_annuled,0) as contracts_annuled,
    coalesce(cm.contracts_to_be_signed,0) as contracts_to_be_signed,
    coalesce(bm.visits_expected_to_happen > 0,false) as has_visits_to_happen,
    coalesce(om.offers_negotiating > 0,false) as is_negotiating_offers,
    coalesce(cm.contracts_to_be_signed > 0,false) as has_contracts_to_sign,
    coalesce(to.has_ongoing_contract, false) as has_ongoing_contracts,
    now() as ts_load
from filter_tenant_users u
    inner join user_dates ud
    on ud.id = u.id
    left join booking_metrics bm
    on bm.id_visitor = u.id
    left join offer_metrics om
    on om.user_id = u.id
    left join contract_metrics cm
    on cm.id_user = u.id
    left join tenant_ongoing to 
	on to.sk_client = u.id
