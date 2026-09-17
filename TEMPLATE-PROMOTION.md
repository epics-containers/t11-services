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

### Lower resources to fit a 10 CPU namespace quota

- **Commit:** 012d0bc, c51eff4, b1ab682
- **t11-services:** `services/values.yaml`, `services/t11-blueapi/values.yaml`,
  `services/t11-epics-gateways/values.yaml`, `services/t11-rabbitmq/values.yaml`,
  `services/t11-epics-opis/`, `services/t11-epics-pvcs/values.yaml`,
  `services/t11-tiled/values.yaml`, `services/t11-numtracker/values.yaml`,
  `services/t11-opa/`, `services/t11-keycloak/`
- **Template:** `services/values.yaml.jinja`,
  `services/{% if "blueapi" in athena_services %}{{instrument}}-blueapi{% endif %}/values.yaml.jinja`,
  `services/{% if gateway %}{{ domain }}-epics-gateways{% endif %}/values.yaml`,
  `services/{% if "rabbitmq" in athena_services %}{{instrument}}-rabbitmq{% endif %}/values.yaml.jinja`,
  `services/{{ domain }}-epics-opis/values.yaml`,
  `services/{{ domain }}-epics-pvcs/values.yaml`
- **Promote:** candidate
- **Done:** [ ]

A DLS personal namespace has a quota of 10 CPU limits. Its LimitRange gives
every container without resources a default limit of 1 CPU and allows limits
of at most 10 times the requests. Quota counts a Pod as the larger of its
largest init container limit and the sum of its container limits. At the
chart defaults the full beamline needed about 15.7 CPU, so blueapi, rabbitmq,
tiled and tiled-postgres could not start. The limits are now: IOCs 250m in
the `shared` anchor (di-cam keeps 1 CPU), blueapi 1 CPU, epics-gateways 500m
per container, rabbitmq 1 CPU and 1Gi with a 100m init container, epics-opis
100m, epics-pvcs 100m and the blueapi oauth2 Deployment 100m. The t11-only
services are tiled 500m, tiled-postgres 500m, numtracker 200m, opa 200m and
the keycloak bootstrap Job 200m. The total is 8.2 CPU, which leaves room for
rollouts. rabbitmq needs 1 CPU for its startup probe to pass within 5s, and
1Gi because the chart sets the memory high watermark to 60% of the limit.
blueapi sets an ephemeral-storage limit of 2Gi, the LimitRange maximum: the
venv emptyDir exceeded the 1Gi default and the kubelet evicted the Pod.

Review: a beamline namespace has a larger quota, so the template may want
these values only as a commented example. epics-opis is a local chart in t11;
the template uses the upstream chart, which hardcodes a 600m limit. ioc-instance
5.8.0 renders no resources for `initContainers`, so the synoptic init container
still takes the 1 CPU LimitRange default. Both need a change in ec-helm-charts.

### Pin amd64-only images to amd64 nodes

- **Commit:** da0cc76
- **t11-services:** `services/values.yaml`, `services/t11-blueapi/values.yaml`,
  `services/t11-numtracker/values.yaml`, `services/t11-epics-gateways/values.yaml`
- **Template:** `services/values.yaml.jinja`,
  `services/{% if "blueapi" in athena_services %}{{instrument}}-blueapi{% endif %}/values.yaml.jinja`,
  `services/{% if gateway %}{{ domain }}-epics-gateways{% endif %}/values.yaml`
- **Promote:** candidate
- **Done:** [ ]

The IOC, epics-gateways, blueapi and numtracker images are built for amd64
only. Each of these services now sets the `kubernetes.io/arch: amd64`
nodeSelector. For IOCs it is in the `shared` anchor, which both `ioc-instance`
and `dev-c7` merge. The kubelet sets this label on every node. On a cluster
where every node is amd64, as at DLS, the nodeSelector changes nothing. On a
mixed-architecture cluster it keeps these Pods off the other nodes. The
gateway nodeSelector needs epics-gateways 2026.9.2.

Review: the template has no numtracker service, so the numtracker change stays
in t11 only.

### Bump epics-gateways to 2026.9.2

- **Commit:** da0cc76
- **t11-services:** `services/t11-epics-gateways/Chart.yaml`
- **Template:** `services/{% if gateway %}{{ domain }}-epics-gateways{% endif %}/Chart.yaml`
- **Promote:** candidate
- **Done:** [ ]

epics-gateways 2026.9.2 adds a `nodeSelector` value for the gateway Pod. The
chart and its image tag are the only other changes since 2026.9.1.

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
