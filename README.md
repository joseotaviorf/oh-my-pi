<table align="center">
  <tr>
    <th>Build Status</th>
  </tr>
  <tr>
    <td>
        <a href="https://woodpecker.shared.quintoandar.com.br/quintoandar/bi-etl-ejuice">
            <img src="https://woodpecker.shared.quintoandar.com.br/api/badges/quintoandar/bi-etl-ejuice/status.svg" />
        </a>
    </td>
  </tr>
</table>

# Bi-etl-ejuice
Repository with implementation of Airflow DAGs and Spark Jobs.

<img src="bietlejuice.jpg" width="200">

---

## Table of contents

- [Bi-etl-ejuice](#bi-etl-ejuice)
  - [Table of contents](#table-of-contents)
  - [Project Overview](#project-overview)
  - [Getting Started](#getting-started)
    - [⚙️ Local Setup Instructions](#️-local-setup-instructions)
  - [Useful Commands](#useful-commands)
    - [Lint \& Check Style](#lint--check-style)
    - [Local Tests](#local-tests)
  - [Monitoring](#monitoring)
  - [Airflow extra features](#airflow-extra-features)
  - [Hotfixes deployment flow :fire:](#hotfixes-deployment-flow-fire)

## Project Overview

  This repository contains the code used to implement the DAGs and Spark Jobs which run in the [Google Cloud Platform (GCP)](http://composer.quintoandar.com.br) and Databricks, respectively.
  For information about the project, architecture and processes please referer to the [Knowledge Base](https://www.notion.so/productquintoandar/Knowledge-Base-8109bb2d9c344e1f8dc7e79c3600635f) page in our [Data Engineering Wiki](https://www.notion.so/productquintoandar/Data-Engineering-Wiki-509776d7775a4abf97c7cd53731749c7).

## Getting Started

 Commands for common steps are defined on a [Makefile](https://en.wikipedia.org/wiki/Makefile),
 please refer to this file at the project root to check the existing commands.

### ⚙️ [Local Setup Instructions](local/README.md)

## Useful Commands

### Lint & Check Style

Having all set with the local environment, you can use any of the following commands for checking the code style standards:

 - Run the check style command for acknowledge possible problems:

```bash
    make check-style
```

 - Then run the lint command for fixing the automatically fixable inconsistencies. P.S.: Not all the problems can be
fixed by this command, so you might need to run `make check-style` and check the reaming manual fixes.

```bash
    make lint
```

### Local Tests

Be sure you have run `make requirements-test` to install the tests' dependencies and then run:

```bash
    make unit-tests
```

To run only a subdirectory of `tests/unit/`, pass `component`:

```bash
    make unit-tests component=qube
    make unit-tests component=base/api
```

## Monitoring
Please refer to the Monitoring page section to check the active monitorings we have: [Monitoring](https://www.notion.so/productquintoandar/Monitoring-33590fa5e29845debe55f11d1d49c5b0).

## Airflow extra features

You can enable some extra features like an _Auto Refresh_ button on the DAG's page with [this chrome extension](https://chrome.google.com/webstore/detail/airflow-lifunf/eloabhccocaamibhganmeogabcenidfa)

## Hotfixes deployment flow :fire:
If you need to urgent deploy a change you can use the _hotfix_ flow. Please check it out in the [Wiki page](https://docs.google.com/document/d/13_0MoPv_R5eYk647v7BRQSp4O6P-mcr3AdouC8gwXVk/edit#heading=h.otmv9f3bbomh).
