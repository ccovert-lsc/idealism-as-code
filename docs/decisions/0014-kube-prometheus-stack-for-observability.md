# 0014. kube-prometheus-stack for Cluster Observability

**Date:** 2026-09-19
**Status:** Accepted

## Context

Operating a multi-app k3s cluster without visibility into resource usage, pod health, and alerting is fragile. We needed:
- Metrics collection across all nodes and pods
- A dashboard for visualising cluster and app health
- Alerting to the Matrix room when things break

## Decision

Deploy [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) via the `prometheus-community/kube-prometheus-stack` Helm chart. This bundles:

- **Prometheus** — metrics collection and alerting rules
- **Grafana** — dashboards (cluster overview, node metrics, pod resource usage)
- **Alertmanager** — alert routing

Grafana is exposed publicly via Cloudflare Tunnel at `https://grafana.example.com` and gated behind Authentik SSO. The Grafana admin password is stored in the Helm-managed secret; the initial value is set in the values file.

**Alertmanager → Matrix routing:** Alertmanager routes alerts to a custom webhook (`matrix-alertmanager`) running in the cluster. The webhook is a small Python service (`http.server`) that posts formatted messages to the `#alerts` Matrix room via the Matrix client API.

## Consequences

- Out-of-the-box dashboards for Kubernetes cluster health (nodes, pods, PVCs) without custom configuration.
- Alertmanager sends alerts to the Matrix room — alerts are visible on any device running Element.
- kube-prometheus-stack installs CRDs (ServiceMonitor, PrometheusRule, etc.). Uninstalling the chart does not clean up CRDs; manual cleanup is needed on a full rebuild.
- The Prometheus TSDB and Grafana state are stored on local-path PVCs. Data is lost if the node hosting the PVC is rebuilt. Acceptable for a homelab — historical metrics are nice-to-have, not critical.

## Alternatives considered

**Grafana Cloud (free tier):** Would avoid running Prometheus and Grafana ourselves. Rejected to keep all data self-hosted and avoid a cloud dependency for observability.

**Separate Prometheus + Grafana Helm charts:** More control but more coordination. kube-prometheus-stack bundles pre-configured integrations (node-exporter, kube-state-metrics, default dashboards) that would otherwise require manual setup.

**Victoria Metrics:** More resource-efficient than Prometheus for long-term storage. Not adopted here — kube-prometheus-stack's opinionated defaults are a better fit for a single-operator homelab.
