select false
from dim_offer
where status not in (
  'Aprovada',
  'EmNegociacao',
  'Rejeitada'
)
;