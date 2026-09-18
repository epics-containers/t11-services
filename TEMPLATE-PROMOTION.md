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

### Make blueapi scans write through tiled, OPA and numtracker

- **Commit:** 37d00c7, 84589a4, 4060051, 627b540, 0b83436
- **t11-services:** `services/t11-tiled/values.yaml`,
  `services/t11-tiled/templates/configmap-access-policy.yaml`,
  `services/t11-opa/values.yaml`, `services/t11-opa/templates/deployment.yaml`,
  `services/t11-numtracker/values.yaml`,
  `services/t11-numtracker/templates/job-configure.yaml`
- **Template:** none
- **Promote:** candidate
- **Done:** [ ]

Four faults stopped every scan: the tiled `volumeMounts` override dropped the
chart's config mount, so tiled ran with no authentication; the DLS access
policy used `PrincipalType.external`, which tiled 0.2.18 renamed to `user`; OPA
had no `ISSUER`, so no token verified; and numtracker had no instrument
configured. Review: p46-p49-services carry the same access policy and
`volumeMounts` pattern.

### Use DLS names for the camera PVs

- **Commit:** 6f1cb55
- **t11-services:** `services/bl11t-di-cam-01/config/ioc.yaml`,
  `synoptic/techui.yaml`, `synoptic/DCAM1.bob`,
  `services/t11-blueapi/values.yaml`, `dodal/t11.py`
- **Template:** none
- **Promote:** candidate
- **Done:** [ ]

techui-support shows an ADSimDetector with the ADAravis summary screen, which
hardcodes `$(P):DRV:*`, `$(P):STAT:*` and `pva://$(P):PVA:ARRAY` and ignores
`R`. The camera used `:DET:` and `PVA:OUTPUT`, so its synoptic screen showed
disconnected PVs. The driver is now `:DRV:`, the PVA output `PVA:ARRAY` and
the asyn ports `CAM.*`. blueapi moves to `dodal.beamlines.t11`, which uses the
`DRV:` suffix. Review: if the template's example camera IOC uses `:DET:`, it
has the same mismatch with its techui screens.

### Publish the blueapi web UI

- **Commit:** 9e75046, eda4375, 305de35, 57c5153, 4f95f7b
- **t11-services:** `services/t11-blueapi/values.yaml`,
  `services/t11-blueapi/templates/keycloak-proxy.yaml`,
  `services/t11-keycloak/templates/_realm.tpl`, `README.md`
- **Template:** none
- **Promote:** no. A real beamline logs in at identity.diamond.ac.uk, which
  has a stable hostname, and publishes blueapi through an Ingress.
- **Done:** n/a

The t11-blueapi-oauth2 Service is a LoadBalancer. A browser can resolve none
of the in-cluster names, and the IPs change, so it logs in through that one
IP: oauth2-proxy forwards `/realms/` and `/resources/` to an nginx sidecar,
which calls keycloak as `t11-keycloak:8080`, so that every token's issuer is
the one blueapi checks, and rewrites keycloak's absolute URLs into relative
ones. The login URL is relative, discovery is off, and the t11-blueapi client
accepts any redirect URI. The sidecar needs an explicit securityContext for
the DLS Kyverno policy, and a single nginx worker to fit its memory limit.

### Bootstrap keycloak on every start

- **Commit:** 50f19c1, 40ad27e, 8abb06e
- **t11-services:** `services/t11-keycloak/templates/deployment.yaml`,
  `services/t11-keycloak/templates/configmap-bootstrap.yaml`,
  `services/t11-keycloak/templates/_realm.tpl`,
  `services/t11-keycloak/values.yaml`, `README.md`; removes
  `services/t11-keycloak/templates/job-bootstrap.yaml`
- **Template:** none
- **Promote:** no. The template has no keycloak.
- **Done:** n/a

Keycloak's H2 database lives on the container filesystem, so every restart
starts with an empty realm. The bootstrap Job only ran when its ConfigMap
changed, so a restart left keycloak without its clients and users. A postStart
hook in the keycloak container now runs `startup.sh` on every start, as
compose's `post_start` did, and the container is not Ready until it finishes.
The Job and `bootstrapResources` are gone, which also frees the Job's 1 CPU of
quota. The users and clients are now one keycloak partial import, rendered
from values by `_realm.tpl`, in place of a JVM-starting kcadm.sh or kcreg.sh
call per user and client, and the realm it creates is identical.

### Publish the keycloak admin console

- **Commit:** 77b494d
- **t11-services:** `services/t11-keycloak/values.yaml`,
  `services/t11-keycloak/templates/deployment.yaml`, `README.md`
- **Template:** none
- **Promote:** no. The template has no keycloak; t11 runs its own only to
  simulate the DLS central one.
- **Done:** n/a

The t11-keycloak Service is now a LoadBalancer, and `hostname` defaults to
empty, which leaves `KC_HOSTNAME` unset. start-dev then takes the hostname
from each request, so the admin console works at
`http://<external IP>:8080/admin`. The in-cluster clients all call
`http://t11-keycloak:8080`, so their token issuer is unchanged.

### Bump ioc-instance and ioc-group to 5.9.0

- **Commit:** 3b9c526
- **t11-services:** `.helm-shared/Chart.yaml`, `.helm-shared/GroupChart.yaml`,
  `.helm-shared/values.schema.json`
- **Template:** `.helm-shared/Chart.yaml`, `.helm-shared/GroupChart.yaml`,
  `.helm-shared/values.schema.json`
- **Promote:** candidate
- **Done:** [ ]

ioc-instance 5.9.0 gives init containers and extra containers the IOC
`resources` unless an entry sets its own. Entries can now also set
`volumeMounts`, `env`, `securityContext`, `workingDir` and `imagePullPolicy`.
Without resources, a DLS LimitRange gives an init container a 1 CPU limit,
and the quota counts that limit for the whole Pod. The bl11t-synoptic Pod now
counts 250m. ioc-group moves from 5.7.0-beta.2 to the same release.

### Lower resources to fit a 10 CPU namespace quota

- **Commit:** 012d0bc, c51eff4, b1ab682, 3496ae1
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
the keycloak bootstrap Job 1 CPU while it runs. The total is 8.2 CPU, which
leaves room for rollouts. The bootstrap Job failed at 200m: each kcadm.sh and
kcreg.sh call starts a JVM, and the admin token expired before the call used
it. rabbitmq needs 1 CPU for its startup probe to pass within 5s, and
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
