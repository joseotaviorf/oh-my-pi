select
	a.id as id_booking,
	r.rating,
	r.complementaryInfo as tag_other,
	coalesce(max(rl.label = 'Pontualidade'), 0) as tag_punctuality,
	coalesce(max(rl.label = 'Corretor bem informado'), 0) as tag_agent_well_informed,
	coalesce(max(rl.label = 'Gentileza'), 0) as tag_kindness,
	coalesce(max(rl.label = 'Corretor não foi gentil'), 0) as tag_no_kindness,
	coalesce(max(rl.label = 'Imóvel igual ao anúncio'), 0) as tag_house_as_listing,
	coalesce(max(rl.label = 'Imóvel não corresponde ao anúncio'), 0) as tag_house_not_as_listing,
	coalesce(max(rl.label = 'Outro motivo (por favor, conte abaixo)'
		and rl.ratingReference >= 4), 0) as tag_other_reason_positive,
	coalesce(max(rl.label = 'Outro motivo (por favor, conte abaixo)'
		and rl.ratingReference <= 3), 0) as tag_other_reason_negative,
	coalesce(max(rl.label = 'Corretor se atrasou'), 0) as tag_agent_late,
	coalesce(max(rl.label = 'Corretor sem informações'), 0) as tag_agent_with_no_info
from Visita v
join Usuario u
    on u.id = v.visitante_id
join RealEstateAgentRating r
	on r.id = v.realEstateAgentRating_id
join Device d
	on d.usuario_id = v.visitante_id
join Agendamento a
	on a.visita_id = v.id
left join RealEstateAgentRating_RatingLabel rrl
	on rrl.RealEstateAgentRating_id = v.realEstateAgentRating_id
left join RatingLabel rl
	on rl.id = rrl.ratingLabels_id
where v.realEstateAgentRating_id is not null
	and d.mobileApp = 'Inquilinos'
	and a.fupVisita is not null
	and DATE(coalesce(a.criadoEm, '1900-01-01 00:00:00')) <= DATE('{}')
group by 1, 2, 3