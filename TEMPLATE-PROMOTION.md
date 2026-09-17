# Changes to promote to services-template-helm

t11 is the test bed for
[services-template-helm](https://github.com/epics-containers/services-template-helm).
This log records each t11-services change that other beamlines may need, so
that the template can pick it up.

Add an entry when you make such a change. Set **Promote** to one of:

- **yes**: the change belongs in the template.
- **candidate**: review the change before it goes into the template.
- **no**: the change is specific to t11. Say why.

Tick **Done** when the template has the change, and link the template PR.

Template paths are relative to `template/` in services-template-helm.

## Log

### Clone the synoptic repo into /tmp, not /data

- **Commit:** 0697155
- **t11-services:** `services/bl11t-synoptic/values.yaml`
- **Template:** `services/{{ location }}-synoptic/values.yaml`
- **Promote:** yes
- **Done:** [ ]

The synoptic init container used `/data/synoptic-git` only as a git cache.
ioc-instance 5.8.0 no longer adds the data volume by default, so the init
container now clones into `/tmp`, which is an emptyDir mounted in the Pod. The
IOC then needs no 1000Mi RWX data PVC. Each Pod start clones the repo again.

### Bump ioc-instance to 5.8.0

- **Commit:** 4118d3c
- **t11-services:** `.helm-shared/Chart.yaml`, `.helm-shared/values.schema.json`,
  `services/.ioc_template/values.yaml`, `services/.group_ioc_template/values.yaml`
- **Template:** `.helm-shared/Chart.yaml`, `.helm-shared/values.schema.json`,
  `services/.*_template/values.yaml`
- **Promote:** candidate
- **Done:** [ ]

ioc-instance 5.8.0 makes the data volume optional and off by default. An IOC
that writes to the data volume must set `dataVolume.enabled: true`, or Argo CD
prunes its `<ioc>-data` PVC. The commented `dataVolume` examples now include
`enabled: true`.

Review: the template schema link still points at ioc-instance 5.4.6. The group
template example needs ioc-group 5.8.0, but t11 still pins ioc-group
5.7.0-beta.2 in `.helm-shared/GroupChart.yaml`.

### Bump epics-gateways to 2026.9.1

- **Commit:** 5b62c4d
- **t11-services:** `services/t11-epics-gateways/Chart.yaml`
- **Template:** `services/{% if gateway %}{{ domain }}-epics-gateways{% endif %}/Chart.yaml`
- **Promote:** candidate
- **Done:** [ ]

epics-gateways 2026.9.1 no longer sets a fixed `clusterIP` from `baseIp`, so
Kubernetes allocates the Service IP. The Service is then valid on clusters
whose service CIDR is not the DLS `10.96.0.0/12`.

### Make the OPI Service port configurable

- **Commit:** ae33855
- **t11-services:** `services/t11-epics-opis/values.yaml`,
  `services/t11-epics-opis/templates/deploy.yaml`
- **Template:** `services/{{ domain }}-epics-opis/`
- **Promote:** candidate
- **Done:** [ ]

A new `service.port` value, default 80, sets the Service port. The unused
443 port is gone, because nginx listens only on 80. t11 carries a local copy of
the epics-opis chart. Review: check whether the template uses the published
epics-opis chart, which would need the change in ec-helm-charts instead.
