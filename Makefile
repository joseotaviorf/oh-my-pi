############# Local Airflow Docker environment #############
.PHONY: _setup-local-environment
_setup-local-environment:
	@rm local/.env || true
	@touch local/.env
	@echo "GITHUB_TOKEN=${GITHUB_TOKEN}" >> local/.env
	@echo "PROJECT_PATH=${PROJECT_PATH}" >> local/.env
	@echo "USERNAME=${USERNAME}" >> local/.env
	@echo "DATABRICKS_TOKEN=${DATABRICKS_TOKEN}" >> local/.env

.PHONY: run-local-environment
run-local-environment:
	@make _setup-local-environment
	@docker-compose -f local/docker/docker-compose.yml --env-file local/.env up -d --build --force-recreate

.PHONY: restart-local-environment
restart-local-environment:
	@docker-compose -f local/docker/docker-compose.yml up -d --build

.PHONY: stop-local-environment
stop-local-environment:
	@docker-compose -f local/docker/docker-compose.yml down

############# Local Tests Docker environment #############

.PHONY: _build-tests-environment
_build-tests-environment:
	@docker build -f local/tests-environment.Dockerfile -t bietlejuice-tests-local --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} .

.PHONY: run-tests-environment
run-tests-environment:
	@make _build-tests-environment
	@docker run bietlejuice

############# Local environment S3 upload #############

.PHONY: upload-local-wheel
upload-local-wheel:
	@python3 -m setup sdist bdist_wheel
	@python3 local/upload_local_whl_to_s3.py

.PHONY: upload-local-spark-jobs
upload-local-spark-jobs:
	@python3 local/upload_local_spark_jobs_to_s3.py databricks.s3.forno.data.quintoandar.com.br

.PHONY: upload-local-package
upload-local-package:
	@python3 local/upload_local_spark_jobs_to_s3.py
	@python3 -m setup sdist bdist_wheel
	@python3 local/upload_local_whl_to_s3.py

############# Local Python environment #############

.PHONY: environment
environment:
	@echo ""
	@echo "Creating Python environment for bi-etl-ejuice package"
	@echo "=========="
	@echo ""
	@pyenv install -s 3.8.12
	@pyenv virtualenv 3.8.12 bi-etl-ejuice
	@pyenv local bi-etl-ejuice
	@echo "-> Python virtual environment 'bi-etl-ejuice' has been set as the current virtualenv."

############# Requirements setup #############

.PHONY: requirements
requirements:
	@echo ""
	@echo "Installing packages"
	@echo "=========="
	@echo ""
	@python -m pip install -U -r requirements.txt --extra-index-url https://quintoandar.github.io/python-package-server/
	@make requirements-lint

.PHONY: requirements-test
requirements-test:
	@echo ""
	@echo "Installing tests packages"
	@echo "=========="
	@echo ""
	@python -m pip install -r requirements_test.txt  --extra-index-url https://quintoandar.github.io/python-package-server/

.PHONY: requirements-lint
requirements-lint:
	@echo ""
	@echo "Installing lint packages"
	@echo "=========="
	@echo ""
	@python -m pip install -r requirements_lint.txt

.PHONY: requirements-scripts
requirements-scripts:
	@echo ""
	@echo "Installing scripts packages"
	@echo "=========="
	@echo ""
	@python -m pip install -U -r requirements_scripts.txt --extra-index-url https://quintoandar.github.io/python-package-server/

############# Package setup #############

.PHONY: package
package:
	@make requirements
	@echo ""
	@echo "Creating 'requirements-freeze.txt' to prepare building dependencies"
	@echo "=========="
	@echo ""
	@python -m pip freeze > requirements-freeze.txt
	@echo ""
	@echo "Creating wheel for bi-etl-ejuice"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python -m setup sdist bdist_wheel

############# Style handling #############

.PHONY: lint
## run black to fix code style
lint:
	@echo ""
	@echo "Running lint in all files from <bietlejuice/>"
	@echo "=========="
	@echo ""
	@python -m black bietlejuice/ tests/unit/

.PHONY: check-style
## check style with flake8 and black
check-style:
	@echo ""
	@echo "Running Check Style"
	@echo "=========="
	@echo ""
	@python -m black --check bietlejuice/ tests/unit/ && echo "\n\nSuccess\n" || (echo "\n\nFailure\n\nRun \"make lint\" to apply style formatting to your code\n" && exit 1)
	@python -m flake8 --config=setup.cfg bietlejuice/ tests/unit/

############# Tests commands #############
.PHONY: tests
## run all unit and integration tests with coverage report
tests:
	@python -m pytest -W ignore::DeprecationWarning --cov-config=.coveragerc --cov=bietlejuice/ --cov-report term --cov-report html:htmlcov --cov-report xml:coverage.xml tests
	@python -m coverage xml -i

.PHONY: unit-tests
unit-tests:
	@echo ""
	@echo "Unit Tests"
	@echo "=========="
	@echo ""
	@python -m pytest -W ignore::DeprecationWarning --cov-config=.coveragerc --cov-report term --cov-report html:htmlcov --cov=bietlejuice/ --cov-fail-under=40 tests/unit/

.PHONY: integration-tests
## run integration tests with coverage report
integration-tests:
	@echo ""
	@echo "Integration Tests"
	@echo "================="
	@echo ""
	@python -m pytest -W ignore::DeprecationWarning --cov-config=.coveragerc --cov-report term --cov-report xml:integration-tests-cov.xml --cov=bietlejuice/ --cov-fail-under=0 tests/integration

.PHONY: files-validation
files-validation:
	@echo ""
	@echo "Validation Files Tests"
	@echo "=========="
	@echo ""
	@python -m pytest tests/files_validation/

############# Validations commands #############

.PHONY: validate-dags-dependencies
validate-dags-dependencies:
	@echo ""
	@echo "Validating DAGs dependencies"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python3 scripts/ci_cd/validate_dags_dependencies.py

.PHONY: validate-atlas-metadata-files
validate-atlas-metadata-files:
	@echo ""
	@echo "Validating Atlas metadata files"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@PYTHONPATH=. python3 scripts/atlas_metadata_validation/validate_atlas_metadata.py  "$(DRONE_BRANCH)"

.PHONY: validate-metadata-files-exist
validate-metadata-files-exist:
	@echo ""
	@echo "Validating if new/modified query files have corresponding tags/lineage metadata defined"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@PYTHONPATH=. python3 scripts/atlas_metadata_validation/validate_metadata_files_exist.py  "$(DRONE_BRANCH)"

.PHONY: validate-datamarts-metadata-files-exist
validate-datamarts-metadata-files-exist:
	@echo ""
	@echo "Validating if new/modified datamarts have corresponding lineage metadata defined"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@PYTHONPATH=. python3 scripts/atlas_metadata_validation/validate_datamarts_metadata_files_exist.py  "$(DRONE_BRANCH)"

############# common commands #############

.PHONY: cov-badge
## build coverage badge
cov-badge:
	@echo ""
	@echo "Building Coverage Badge"
	@echo "=========="
	@echo ""
	@coverage-badge -o badge-lines.svg

.PHONY: clean
## delete all compiled python files
clean:
	@find ./ -type d -name '.pytest_cache' -exec rm -rf {} +;
	@find ./ -type d -name 'build' -exec rm -rf {} +;
	@find ./ -type d -name 'dist' -exec rm -rf {} +;
	@find ./ -type d -name 'python_logger.egg-info' -exec rm -rf {} +;
	@find ./ -type d -name 'metastore_db' -exec rm -rf {} +;
	@find ./ -type d -name 'htmlcov' -exec rm -rf {} +;
	@find ./ -type f -name 'coverage.xml' -exec rm -f {} \;
	@find ./ -type f -name 'coverage-badge.svg' -exec rm -f {} \;
	@find ./ -type f -name '.coverage' -exec rm -f {} \;
	@find ./ -type f -name '*-cov.*' -exec rm -f {} \;
	@find ./ -type f -name '*derby.log' -exec rm -f {} \;
	@find ./ -type f -name '.version' -exec rm -f {} \;
	@find ./ -type f -name '.package_name' -exec rm -f {} \;
	@find ./ -type f -name '*.pyc' -exec rm -f {} \;
	@find ./ -type f -name '*~' -exec rm -f {} \;

.PHONY: help
# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=19 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')

.DEFAULT_GOAL := help
