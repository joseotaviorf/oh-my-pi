import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

_COMPILER_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_COMPILER_ROOT))

with patch(
    "scripts.services.metadata_file_service.MetadataFileService",
    return_value=MagicMock(),
):
    from scripts.governance_metadata_validation.validate_pii_privacy import (  # noqa: E402
        _controls_changed_in_diff,
        get_metadata_file_paths,
        remove_prefix,
    )
from scripts.governance_metadata_validation import (  # noqa: E402
    validate_pii_privacy as validate_pii_privacy_module,
)
from scripts.services.git_service import GitService  # noqa: E402


class TestRemovePrefix:
    def test_strips_dags_prefix(self):
        # Arrange
        file_path = "dags/for_rent/example/metadata/clean/person.yml"

        # Act
        result = remove_prefix(file_path)

        # Assert
        assert result == "for_rent/example/metadata/clean/person.yml"


class TestControlsChangedInDiff:
    @patch("scripts.governance_metadata_validation.validate_pii_privacy.GitService")
    def test_true_when_controls_file_modified(self, mock_git_service_cls):
        # Arrange
        mock_git_service_cls.UPSERT_STATUS_CODES = GitService.UPSERT_STATUS_CODES
        mock_git_service_cls.return_value.get_modified_files_from_diff.return_value = {
            "governance/pii_anonymization_controls/rae.yml": "M",
            "dags/foo/metadata/clean/bar.yml": "M",
        }

        # Act
        result = _controls_changed_in_diff("origin/master", "HEAD")

        # Assert
        assert result is True

    @patch("scripts.governance_metadata_validation.validate_pii_privacy.GitService")
    def test_false_when_only_metadata_changed(self, mock_git_service_cls):
        # Arrange
        mock_git_service_cls.UPSERT_STATUS_CODES = GitService.UPSERT_STATUS_CODES
        mock_git_service_cls.return_value.get_modified_files_from_diff.return_value = {
            "dags/foo/metadata/clean/bar.yml": "M",
        }

        # Act
        result = _controls_changed_in_diff("origin/master", "HEAD")

        # Assert
        assert result is False


class TestGetMetadataFilePaths:
    def test_file_mode_returns_single_metadata_path(self):
        # Arrange
        relative = "dags/for_rent/example/metadata/clean/person.yml"
        validate_pii_privacy_module.metadata_file_service.filter_metadata_files.return_value = [
            (relative, "A")
        ]

        # Act
        paths = get_metadata_file_paths("file", relative)

        # Assert
        assert paths == [(relative, "A")]
