# Gateway setup

Deploys an EPICS gateway to route traffic from services to IOCs. Includes containerised IOCs in the namespace, and others in the beamline network. Exposed as a LoadBalancer to allow services outside of the cluster to communicate with containerised IOCs.

## Configuring services in the cluster

Add the following environment variables to any container(s) that communicate with the appropriate EPICS protocol(s):

```yaml
- name: EPICS_PVA_NAME_SERVERS
  value: t11-epics-gateways
- name: EPICS_PVA_AUTO_ADDR_LIST
  value: "NO"
- name: EPICS_CA_NAME_SERVERS
  value: t11-epics-gateways
- name: EPICS_CA_AUTO_ADDR_LIST
  value: "NO"
```

## Configuring external services with the LoadBalancer

Get the external IP of the created LoadBalancer, noting that the external IP can change, especially when nodes are drained for upgrades. If the service is required longer than a single interactive session and the service cannot be deployed into the cluster, consider requesting a static IP and DNS entry.
Ingresses do not support non-HTTP traffic, so UDP/TCP support will require either a static LoadBalancer or Gateway API support.

```sh
$ module load k8s-t11
$ kubectl get svc -n t11-beamline t11-epics-gateways
NAME             ...    EXTERNAL-IP ...
t11-epics-gateways   ... 172.23.XX.XX   ...
$ export GATEWAY_IP=172.23.XX.XX
```

Launch your service with the LoadBalancer as the name server for the appropriate EPICS protocol(s):

```sh
$ EPICS_PVA_AUTO_ADDR_LIST=NO EPICS_PVA_NAME_SERVERS=${GATEWAY_IP} EPICS_CA_AUTO_ADDR_LIST=NO EPICS_CA_NAME_SERVERS=${GATEWAY_IP} my_service
```
