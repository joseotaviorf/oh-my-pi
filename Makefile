############# DOCKER commands ########################
.PHONY: _create-docker-environment
_create-docker-environment:
	@rm docker/.env || true
	@touch docker/.env
	@echo "GITHUB_TOKEN=${GITHUB_TOKEN}" >> docker/.env
	@echo "PROJECT_PATH=${PROJECT_PATH}" >> docker/.env
	@echo "USERNAME=${USERNAME}" >> docker/.env
	@echo "DATABRICKS_TOKEN=${DATABRICKS_TOKEN}" >> docker/.env

.PHONY: create-docker-environment
create-docker-environment:
	@make _create-docker-environment
	@chmod +x start.sh
	@sudo docker-compose -f docker/docker-compose.yml --env-file docker/.env up -d --build --force-recreate
	@sudo docker image prune -f

.PHONY: restart-docker-environment
restart-docker-environment:
	@sudo docker-compose -f docker/docker-compose.yml up -d --build

.PHONY: kill-docker-environment
kill-docker-environment:
	@sudo docker-compose -f docker/docker-compose.yml down

.PHONY: build-local-whl
build-local-whl:
	@python3 scripts/upload_local_spark_jobs_to_s3.py
	@python3 -m setup sdist bdist_wheel
	@python3 scripts/upload_local_whl_to_s3.py

.PHONY: upload-local-spark-jobs-to-s3
upload-local-spark-jobs-to-s3:
	@python3 scripts/upload_local_spark_jobs_to_s3.py databricks.s3.forno.data.quintoandar.com.br

############# Local environment commands #######################

.PHONY: environment
environment:
	@echo ""
	@echo "Creating environment for Bi-etl-ejuice project"
	@echo "=========="
	@echo ""
	@pyenv install -s 3.7.3
	@pyenv virtualenv 3.7.3 bi-etl-ejuice
	@pyenv local bi-etl-ejuice

.PHONY: build-test-environment
build-test-environment:
	@docker build --file docker/test-environment.Dockerfile -t bietlejuice --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} .

.PHONY: test-environment
test-environment:
	@make build-test-environment
	@docker run bietlejuice

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

.PHONY: lint
## run black to fix code style
lint:
	@echo ""
	@echo "Running lint in all files from <bietlejuice/jobs/composer/> and <tests/unit/composer/>"
	@echo "=========="
	@echo ""
	@python -m black bietlejuice/jobs/composer/ tests/unit/composer/

.PHONY: check-style
## check style with flake8 and black
check-style:
	@echo ""
	@echo "Running Check Style"
	@echo "=========="
	@echo ""
	@python -m black --check bietlejuice/jobs/composer/ tests/unit/composer/ && echo "\n\nSuccess\n" || (echo "\n\nFailure\n\nRun \"make lint\" to apply style formatting to your code\n" && exit 1)
	@python -m flake8 --config=setup.cfg bietlejuice/jobs/composer/ tests/unit/composer/

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

.PHONY: unit-tests
unit-tests:
	@echo ""
	@echo "Unit Tests"
	@echo "=========="
	@echo ""
	@python -m pytest -W ignore::DeprecationWarning --cov-config=.coveragerc --cov-report term --cov-report html:htmlcov --cov=bietlejuice/jobs/composer --cov-fail-under=40 tests/unit/

.PHONY: files-validation
files-validation:
	@echo ""
	@echo "Validation Files Tests"
	@echo "=========="
	@echo ""
	@python -m pytest tests/files_validation/

.PHONY: validate-dags-dependencies
validate-dags-dependencies:
	@echo ""
	@echo "Validating DAGs dependencies"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python3 scripts/validate_dags_dependencies.py

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

############# common commands #######################

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
	@find ./ -type d -name 'htmlcov' -exec rm -rf {} +;
	@find ./ -type f -name 'coverage.xml' -exec rm -f {} \;
	@find ./ -type f -name 'coverage-badge.svg' -exec rm -f {} \;
	@find ./ -type f -name '.coverage' -exec rm -f {} \;
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

