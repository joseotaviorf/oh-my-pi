select
	id as id,
	cast(case
    	-- Retrieving original lead id in newer leads
     	when infosExtras like '%id_origin_lead%'
     	then substring(
				replace(
						concat(substr(infosExtras,
									instr(infosExtras, 'id_origin_lead')+
										if(infosExtras like '%id_origin_lead=%', 15, 17)), ';')
						, ' ', ';'),
				1,
				instr(
					replace(
							concat(substr(infosExtras,
									instr(infosExtras, 'id_origin_lead')+
										if(infosExtras like '%id_origin_lead=%', 15, 17)), ';')
							, ' ', ';'),
					';') - 1
		 		)
		-- Retrieving original lead id in older leads
	    when substring_index(infosExtras,';',1) REGEXP '^-?[0-9]+$'
	    then substring_index(infosExtras,';',1)
    else
    	-- No pattern inside infoExtras matched reprocessed leads
	    null
  end as unsigned) as id_origin_lead
from Lead l
where origem = 'Reprocessado'
	  and
	coalesce(infosExtras,'') <> ''