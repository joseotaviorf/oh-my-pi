CREATE TABLE pre_proposal_condition (
  "PreProposta_id" bigint NOT NULL,
  "condicoes_id" bigint NOT NULL,
  PRIMARY KEY ("PreProposta_id","condicoes_id")
)