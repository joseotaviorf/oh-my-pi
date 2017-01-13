let
    Source = Odbc.DataSource("dsn=DW", [HierarchicalNavigation=true]),
    dw_Database = Source{[Name="dw",Kind="Database"]}[Data],
    public_Schema = dw_Database{[Name="public",Kind="Schema"]}[Data],
    dim_user_Table = public_Schema{[Name="dim_user",Kind="Table"]}[Data],
    #"Removed Columns" = Table.RemoveColumns(dim_user_Table,{"data_nascimento", "formacao_data_inicio", "formacao_data_fim", "load_timestamp"}),
    #"Changed Type" = Table.TransformColumnTypes(#"Removed Columns",{{"cpf_validado_receita", type logical}, {"bloqueado", type logical}, {"recebeu_busca_guiada", type logical}, {"dadosagente_ativo", type logical}, {"aceita_sms", type logical}, {"dadosbancarios_outro_titular", type logical}, {"nao_enviar_aviso_mensal_procura", type logical}, {"dadosfotografo_ativo", type logical}, {"dadosafiliado_verificado", type logical}, {"dadosafiliado_ativo", type logical}, {"active", type logical}}),
    #"Merged Queries" = Table.NestedJoin(#"Changed Type",{"id"},#"Marketing Attribution",{"usuario_id"},"NewColumn",JoinKind.LeftOuter),
    #"Expanded NewColumn" = Table.ExpandTableColumn(#"Merged Queries", "NewColumn", {"uuid", "campaign", "channel", "event_type", "mobile_app", "platform", "subchannel", "adquirido_em"}, {"Marketing Acquisition.uuid", "Marketing Acquisition.campaign", "Marketing Acquisition.channel", "Marketing Acquisition.event_type", "Marketing Acquisition.mobile_app", "Marketing Acquisition.platform", "Marketing Acquisition.subchannel", "Marketing Acquisition.adquirido_em"})
in
    #"Expanded NewColumn"