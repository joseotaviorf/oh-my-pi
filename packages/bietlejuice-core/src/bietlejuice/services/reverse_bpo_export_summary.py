from __future__ import annotations

SUMMARY_MARKER_PREFIX = "_bpo_reverse_notifications"


def build_summary_marker_path(
    bucket: str, dag_name: str, dag_run_id: str, file_name: str
) -> str:
    return (
        f"s3a://{bucket}/{SUMMARY_MARKER_PREFIX}/{dag_name}/{dag_run_id}/"
        f"{file_name}.marker"
    )


def build_summary_marker_prefix(dag_name: str, dag_run_id: str) -> str:
    return f"{SUMMARY_MARKER_PREFIX}/{dag_name}/{dag_run_id}/"


def order_saved_files_by_declaration(
    saved_files: list[str], declaration_tables: list[str]
) -> list[str]:
    ordered: list[str] = []
    saved_set = set(saved_files)
    for table_name in declaration_tables:
        matching = sorted(
            file_name
            for file_name in saved_set
            if file_name.startswith(f"{table_name}_")
        )
        ordered.extend(matching)
        saved_set -= set(matching)
    ordered.extend(sorted(saved_set))
    return ordered


def format_dag_summary_message(dag_name: str, saved_files: list[str]) -> str:
    if not saved_files:
        return (
            f"ℹ️ *{dag_name}* — resumo da execução\n\n"
            "Nenhum arquivo foi salvo nesta execução."
        )

    file_lines = "\n".join(f"✅ {file_name}" for file_name in saved_files)
    return f"✅ *{dag_name}* — resumo da execução\n\n{file_lines}"
