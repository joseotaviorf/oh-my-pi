"""Unit tests for emr_custom_libraries YAML extractors used by EMR bootstrap."""

import sys
from pathlib import Path

import pytest
import yaml

_SCRIPTS_DIR = Path(__file__).resolve().parents[3] / "scripts"
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

from emr_custom_libraries import (  # noqa: E402
    extract_maven_coords,
    extract_pypi_packages,
    extract_uris,
    gav_to_maven_path,
    main,
    maven_relative_path,
)


@pytest.fixture
def cluster_yaml(tmp_path: Path):
    def _write(payload: dict) -> Path:
        path = tmp_path / "demo_cluster.yml"
        path.write_text(yaml.dump(payload), encoding="utf-8")
        return path

    return _write


class TestExtractJars:
    def test_prod_only_jar(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                        {"whl": "{artifacts_bucket}/pkg/client.whl"},
                    ]
                }
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act
        jars = extract_uris(data, key="jar", is_validation=False)

        # assert
        assert jars == ["{artifacts_bucket}/jars/ojdbc8.jar"]

    def test_validation_union_and_dedupe(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                    ]
                },
                "validation": {
                    "cluster": {
                        "custom_libraries": [
                            {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                            {
                                "jar": (
                                    "{artifacts_bucket}/jars/mssql-jdbc-12.8.1.jre8.jar"
                                )
                            },
                        ]
                    }
                },
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act
        jars = extract_uris(data, key="jar", is_validation=True)

        # assert
        assert jars == [
            "{artifacts_bucket}/jars/ojdbc8.jar",
            "{artifacts_bucket}/jars/mssql-jdbc-12.8.1.jre8.jar",
        ]

    def test_empty_and_missing_custom_libraries(self, cluster_yaml):
        # arrange / act / assert
        assert extract_uris({}, key="jar", is_validation=False) == []
        assert (
            extract_uris(
                {"cluster": {"custom_libraries": []}},
                key="jar",
                is_validation=False,
            )
            == []
        )
        assert (
            extract_uris(
                {"cluster": {}},
                key="jar",
                is_validation=True,
            )
            == []
        )


class TestExtractWhlAndPypi:
    def test_whl_ignores_non_whl_entries(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                        {"whl": "{artifacts_bucket}/airtable/client.whl"},
                        {"pypi": {"package": "paramiko==4.0.0"}},
                    ]
                }
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act / assert
        assert extract_uris(data, key="whl", is_validation=False) == [
            "{artifacts_bucket}/airtable/client.whl"
        ]

    def test_pypi_emr_flags_and_dedupe(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "pypi": {
                                "package": "presidio-analyzer==2.2.357",
                                "no_deps": True,
                            }
                        },
                        {
                            "pypi": {
                                "package": "numpy==1.26.4",
                                "only_binary": "true",
                            }
                        },
                        {"pypi": {"package": "presidio-analyzer==2.2.357"}},
                    ]
                }
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act
        packages = extract_pypi_packages(data, is_validation=False)

        # assert
        assert packages == [
            ("presidio-analyzer==2.2.357", 1, 0),
            ("numpy==1.26.4", 0, 1),
        ]


class TestMainCli:
    def test_jar_mode_prints_uris(self, cluster_yaml, capsys):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                    ]
                }
            }
        )

        # act
        rc = main(["jar", str(path), "0"])

        # assert
        assert rc == 0
        assert capsys.readouterr().out.strip() == ("{artifacts_bucket}/jars/ojdbc8.jar")

    def test_pypi_mode_prints_tsv(self, cluster_yaml, capsys):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "pypi": {
                                "package": "google-auth==2.23.0",
                                "no_deps": False,
                                "only_binary": True,
                            }
                        }
                    ]
                }
            }
        )

        # act
        rc = main(["pypi", str(path)])

        # assert
        assert rc == 0
        assert capsys.readouterr().out.strip() == "google-auth==2.23.0\t0\t1"

    def test_maven_mode_prints_tsv(self, cluster_yaml, capsys):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "maven": {
                                "coordinates": (
                                    "graphframes:graphframes:0.8.1-spark3.0-s_2.12"
                                )
                            }
                        }
                    ]
                }
            }
        )

        # act
        rc = main(["maven", str(path), "0"])

        # assert
        assert rc == 0
        assert capsys.readouterr().out.strip() == (
            "graphframes:graphframes:0.8.1-spark3.0-s_2.12\t-\t"
            "graphframes/graphframes/0.8.1-spark3.0-s_2.12/"
            "graphframes-0.8.1-spark3.0-s_2.12.jar\t"
            "graphframes-0.8.1-spark3.0-s_2.12.jar"
        )

    def test_maven_mode_preserves_custom_repo(self, cluster_yaml, capsys):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "maven": {
                                "coordinates": (
                                    "org.apache.sedona:"
                                    "sedona-python-adapter-3.0_2.12:1.2.1-incubating"
                                ),
                                "repo": "https://repo.example.com/maven2",
                            }
                        }
                    ]
                }
            }
        )

        # act
        rc = main(["maven", str(path), "0"])

        # assert
        assert rc == 0
        line = capsys.readouterr().out.strip()
        cols = line.split("\t")
        assert len(cols) == 4
        assert cols[0].startswith("org.apache.sedona:")
        assert cols[1] == "https://repo.example.com/maven2"
        assert cols[2].startswith("org/apache/sedona/")
        assert cols[3].endswith(".jar")
        # No empty column that would break bash read
        assert all(c != "" for c in cols)

    def test_maven_mode_rejects_malformed_gav(self, cluster_yaml, capsys):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {"maven": {"coordinates": "not-a-gav"}},
                    ]
                }
            }
        )

        # act
        rc = main(["maven", str(path)])

        # assert
        assert rc == 1
        assert "group:artifact:version" in capsys.readouterr().err


class TestGavToMavenPath:
    def test_graphframes_layout(self):
        # act
        group_path, artifact, version, jar_name = gav_to_maven_path(
            "graphframes:graphframes:0.8.1-spark3.0-s_2.12"
        )

        # assert
        assert group_path == "graphframes"
        assert artifact == "graphframes"
        assert version == "0.8.1-spark3.0-s_2.12"
        assert jar_name == "graphframes-0.8.1-spark3.0-s_2.12.jar"
        assert maven_relative_path("graphframes:graphframes:0.8.1-spark3.0-s_2.12") == (
            "graphframes/graphframes/0.8.1-spark3.0-s_2.12/"
            "graphframes-0.8.1-spark3.0-s_2.12.jar"
        )

    def test_dotted_group_and_sedona(self):
        # act
        group_path, artifact, version, jar_name = gav_to_maven_path(
            "org.apache.sedona:sedona-python-adapter-3.0_2.12:1.2.1-incubating"
        )

        # assert
        assert group_path == "org/apache/sedona"
        assert artifact == "sedona-python-adapter-3.0_2.12"
        assert version == "1.2.1-incubating"
        assert jar_name == ("sedona-python-adapter-3.0_2.12-1.2.1-incubating.jar")

    @pytest.mark.parametrize(
        "bad",
        ["", "a:b", "a:b:c:d", ":artifact:1.0", "group::1.0"],
    )
    def test_malformed_raises(self, bad):
        with pytest.raises(ValueError, match="group:artifact:version"):
            gav_to_maven_path(bad)


class TestExtractMaven:
    def test_prod_graphframes_and_sedona(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "maven": {
                                "coordinates": (
                                    "graphframes:graphframes:0.8.1-spark3.0-s_2.12"
                                )
                            }
                        },
                        {
                            "maven": {
                                "coordinates": (
                                    "org.apache.sedona:"
                                    "sedona-python-adapter-3.0_2.12:1.2.1-incubating"
                                )
                            }
                        },
                        {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                    ]
                }
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act
        rows = extract_maven_coords(data, is_validation=False)

        # assert
        assert rows == [
            ("graphframes:graphframes:0.8.1-spark3.0-s_2.12", ""),
            (
                "org.apache.sedona:sedona-python-adapter-3.0_2.12:1.2.1-incubating",
                "",
            ),
        ]

    def test_validation_union_dedupe_and_repo(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "maven": {
                                "coordinates": (
                                    "graphframes:graphframes:0.8.1-spark3.0-s_2.12"
                                )
                            }
                        },
                    ]
                },
                "validation": {
                    "cluster": {
                        "custom_libraries": [
                            {
                                "maven": {
                                    "coordinates": (
                                        "graphframes:graphframes:0.8.1-spark3.0-s_2.12"
                                    )
                                }
                            },
                            {
                                "maven": {
                                    "coordinates": (
                                        "org.datasyslab:geotools-wrapper:1.1.0-25.2"
                                    ),
                                    "repo": "https://repo.example.com/maven2",
                                }
                            },
                        ]
                    }
                },
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act
        rows = extract_maven_coords(data, is_validation=True)

        # assert
        assert rows == [
            ("graphframes:graphframes:0.8.1-spark3.0-s_2.12", ""),
            (
                "org.datasyslab:geotools-wrapper:1.1.0-25.2",
                "https://repo.example.com/maven2",
            ),
        ]

    def test_empty_and_malformed(self):
        # arrange / act / assert
        assert extract_maven_coords({}, is_validation=False) == []
        with pytest.raises(ValueError, match="group:artifact:version"):
            extract_maven_coords(
                {
                    "cluster": {
                        "custom_libraries": [
                            {"maven": {"coordinates": "bad"}},
                        ]
                    }
                },
                is_validation=False,
            )


def test_module_lives_next_to_emr_init_script():
    assert (_SCRIPTS_DIR / "emr_custom_libraries.py").is_file()
    assert (_SCRIPTS_DIR / "emr_init_script.sh").is_file()
