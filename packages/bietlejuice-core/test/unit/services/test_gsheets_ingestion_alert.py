from bietlejuice.services.gsheets_ingestion_alert import (
    classify_gsheet_ingestion_error,
    display_error_type,
    format_error_for_alert,
    format_gsheet_ingestion_alert,
    get_metadata_owner,
    sanitize_error_trace,
)

FORNO_CIQ_COSTS_SPARK_ERROR = (
    "[UNRESOLVED_COLUMN.WITH_SUGGESTION] A column, variable, or "
    "function parameter with name `city` cannot be resolved. "
    "Did you mean one of the following? [cityy, comission_cs_ciq_full]."
)


class TestClassifyGsheetIngestionError:
    def test_empty_sheet(self):
        info = classify_gsheet_ingestion_error(
            ValueError("m=__generate_schema, msg=Table advance_base Empty!")
        )
        assert info.error_type == "EMPTY_SHEET"
        assert "IMPORTRANGE" in info.likely_cause

    def test_spreadsheet_not_found(self):
        info = classify_gsheet_ingestion_error(
            Exception(
                "{'code': 404, 'message': 'Requested entity was not found.', "
                "'status': 'NOT_FOUND'}"
            )
        )
        assert info.error_type == "SPREADSHEET_NOT_FOUND"

    def test_worksheet_not_found_bare_name(self):
        info = classify_gsheet_ingestion_error(Exception("Plataforma"))
        assert info.error_type == "WORKSHEET_NOT_FOUND"
        assert "Plataforma" in info.likely_cause

    def test_schema_drift_extracts_column(self):
        info = classify_gsheet_ingestion_error(
            Exception(
                "[UNRESOLVED_COLUMN.WITH_SUGGESTION] A column, variable, or "
                "function parameter with name recomenda_wo cannot be resolved. "
                "Did you mean one of the following? [email]."
            )
        )
        assert info.error_type == "SCHEMA_DRIFT"
        assert "recomenda_wo" in info.likely_cause
        assert "unknown" not in info.likely_cause

    def test_schema_drift_extracts_backtick_column_and_suggestions(self):
        info = classify_gsheet_ingestion_error(Exception(FORNO_CIQ_COSTS_SPARK_ERROR))
        assert info.error_type == "SCHEMA_DRIFT"
        assert "'city'" in info.likely_cause
        assert "unknown" not in info.likely_cause
        assert "Did you mean: cityy, comission_cs_ciq_full?" in info.likely_cause

    def test_other_fallback(self):
        info = classify_gsheet_ingestion_error(Exception("boom something unexpected"))
        assert info.error_type == "OTHER"


class TestDisplayErrorType:
    def test_schema_drift_friendly_label(self):
        assert display_error_type("SCHEMA_DRIFT") == "Missing or renamed column"

    def test_unknown_type_passthrough(self):
        assert display_error_type("CUSTOM") == "CUSTOM"


class TestSanitizeErrorTrace:
    def test_truncates_and_strips_quotes(self):
        long_msg = 'error with "quotes" and `ticks` ' + ("x" * 200)
        sanitized = sanitize_error_trace(Exception(long_msg), max_length=40)
        assert len(sanitized) <= 40
        assert sanitized.endswith("...")
        assert '"' not in sanitized
        assert "`" not in sanitized

    def test_long_unresolved_column_error_ends_with_ellipsis(self):
        sanitized = sanitize_error_trace(Exception(FORNO_CIQ_COSTS_SPARK_ERROR))
        assert "city" in sanitized
        assert "`" not in sanitized


class TestFormatErrorForAlert:
    def test_schema_drift_structured_summary(self):
        error_info = classify_gsheet_ingestion_error(
            Exception(FORNO_CIQ_COSTS_SPARK_ERROR)
        )
        summary = format_error_for_alert(
            Exception(FORNO_CIQ_COSTS_SPARK_ERROR), error_info
        )
        assert summary == (
            "UNRESOLVED_COLUMN: column 'city' cannot be resolved. "
            "Did you mean [cityy, comission_cs_ciq_full]?"
        )


class TestFormatGsheetIngestionAlert:
    def test_includes_type_likely_cause_and_owner(self):
        sheet_details = {
            "clean_table_name": "associate_executive_bonus",
            "sheet_id": "abc123",
            "sheet_context": "fintech",
            "owner": "someone@quintoandar.com.br",
        }
        message = format_gsheet_ingestion_alert(
            sheet_details,
            ValueError(
                "m=__generate_schema, msg=Table associate_executive_bonus Empty!"
            ),
        )
        assert "⚠️ *Gsheet ingestion failures*" in message
        assert "was not ingested in this run due to some error" in message
        assert "*Owner Team*: fintech." in message
        assert "*Data Owner*: someone@quintoandar.com.br" in message
        assert "*Type*: Empty sheet tab" in message
        assert "*Likely cause*:" in message
        assert "IMPORTRANGE" in message
        assert "*❌ Error*: ```" in message
        assert "associate_executive_bonus Empty!" in message

    def test_omits_owner_when_missing(self):
        sheet_details = {
            "clean_table_name": "ipo_roadmap",
            "sheet_id": "xyz",
            "sheet_context": "for_sale",
        }
        message = format_gsheet_ingestion_alert(
            sheet_details,
            ValueError("m=__generate_schema, msg=Table ipo_roadmap Empty!"),
        )
        assert "Data Owner:" not in message
        assert "*Type*: Empty sheet tab" in message
        assert "*Owner Team*: for_sale." in message

    def test_ciq_costs_schema_drift_forno_message(self):
        sheet_details = {
            "clean_table_name": "ciq_costs",
            "sheet_id": "1ZkPABh53UrzKn4aQudZzr5QpJsBXhCZDnJkDZob2Rqc",
            "sheet_context": "growth",
            "owner": "henrique.paulo@quintoandar.com.br",
        }
        message = format_gsheet_ingestion_alert(
            sheet_details,
            Exception(FORNO_CIQ_COSTS_SPARK_ERROR),
            dag_name="gsheets_growth",
        )
        assert "*Type*: Missing or renamed column" in message
        assert "'city'" in message
        assert "unknown" not in message
        assert "Did you mean: cityy, comission_cs_ciq_full?" in message
        assert (
            "UNRESOLVED_COLUMN: column 'city' cannot be resolved. "
            "Did you mean [cityy, comission_cs_ciq_full]?"
        ) in message


class TestGetMetadataOwner:
    def test_reads_owner_from_metadata_yml(self, tmp_path, monkeypatch):
        dag_dir = tmp_path / "gsheets_growth"
        metadata_dir = dag_dir / "metadata" / "clean"
        metadata_dir.mkdir(parents=True)
        (metadata_dir / "ciq_costs.yml").write_text(
            "database_name: datalake_gsheets_clean\n"
            "table_name: ciq_costs\n"
            "owner: henrique.paulo@quintoandar.com.br\n",
            encoding="utf-8",
        )

        monkeypatch.setattr(
            "bietlejuice.services.gsheets_ingestion_alert.DAGPackagesPathService.get_dag_path",
            lambda _dag_name: str(dag_dir),
        )

        assert (
            get_metadata_owner("gsheets_growth", "ciq_costs")
            == "henrique.paulo@quintoandar.com.br"
        )

    def test_returns_none_when_metadata_missing(self, monkeypatch):
        monkeypatch.setattr(
            "bietlejuice.services.gsheets_ingestion_alert.DAGPackagesPathService.get_dag_path",
            lambda _dag_name: None,
        )
        assert get_metadata_owner("gsheets_growth", "missing_table") is None
