# syntax=docker/dockerfile:1
# Custom Airflow Docker Image mit dbt und OpenMetadata-Ingestion
# ============================================================
# Basiert auf dem offiziellen Apache Airflow 3 Image.
# Erweitert um:
#   - dbt-core + Adapter (Trino, PostgreSQL)
#   - openmetadata-ingestion (für DAGs die Metadaten pushen)
#   - Airflow Providers (Kubernetes, PostgreSQL, AWS/S3)
#
# Build & Push (lokal):
#   docker build -t your-registry/airflow-dbt:3.0.2-python3.12 .
#   docker push your-registry/airflow-dbt:3.0.2-python3.12

ARG AIRFLOW_VERSION=3.0.2
ARG PYTHON_VERSION=3.12

FROM apache/airflow:${AIRFLOW_VERSION}-python${PYTHON_VERSION}

# ============================================================
# System-Abhängigkeiten (git benötigt für dbt + DAG-Sync)
# ============================================================
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Python-Abhängigkeiten
# ============================================================
USER airflow
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

# ============================================================
# Cleanup
# ============================================================
RUN rm -f /requirements.txt

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["airflow", "webserver"]
