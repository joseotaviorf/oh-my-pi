from bietlejuice.services.reverse_bpo_export_summary import (
    build_summary_marker_path,
    build_summary_marker_prefix,
    format_dag_summary_message,
    order_saved_files_by_declaration,
)


class TestBuildSummaryMarkerPath:
    def test_builds_marker_path(self):
        path = build_summary_marker_path(
            "5a-dataops-prod",
            "reverse_atento",
            "manual__2026-08-26",
            "cases_perspective_2026_08_26.parquet",
        )

        assert path == (
            "s3a://5a-dataops-prod/_bpo_reverse_notifications/"
            "reverse_atento/manual__2026-08-26/"
            "cases_perspective_2026_08_26.parquet.marker"
        )


class TestBuildSummaryMarkerPrefix:
    def test_builds_s3_prefix(self):
        assert build_summary_marker_prefix("reverse_aec", "scheduled__2026-08-26") == (
            "_bpo_reverse_notifications/reverse_aec/scheduled__2026-08-26/"
        )


class TestOrderSavedFilesByDeclaration:
    def test_orders_files_by_declaration_table_order(self):
        saved_files = [
            "taxonomy_2026_08_26.parquet",
            "backlog_metric_2026_08_26.parquet",
            "cases_perspective_2026_08_26.parquet",
        ]
        declaration_tables = ["backlog_metric", "cases_perspective", "taxonomy"]

        ordered = order_saved_files_by_declaration(saved_files, declaration_tables)

        assert ordered == [
            "backlog_metric_2026_08_26.parquet",
            "cases_perspective_2026_08_26.parquet",
            "taxonomy_2026_08_26.parquet",
        ]


class TestFormatDagSummaryMessage:
    def test_formats_saved_files_with_checks(self):
        message = format_dag_summary_message(
            "reverse_atento",
            [
                "backlog_metric_2026_08_26.parquet",
                "cases_perspective_2026_08_26.parquet",
            ],
        )

        assert "reverse_atento" in message
        assert "✅ backlog_metric_2026_08_26.parquet" in message
        assert "✅ cases_perspective_2026_08_26.parquet" in message

    def test_formats_empty_summary(self):
        message = format_dag_summary_message("reverse_atento", [])

        assert "Nenhum arquivo foi salvo nesta execução." in message
