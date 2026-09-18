{{/*
The users and clients that the bootstrap creates, as a keycloak partial import.
Lifted from the create_client calls and mapper templates of
dev-environment/daq-services/services/keycloak_config/startup.sh. One
partialImport call replaces a kcadm.sh or kcreg.sh call per user and client,
each of which started a JVM.
*/}}

{{/* mappers for a client used by people: fedid from the username, and an
audience. Argument: the audience */}}
{{- define "t11-keycloak.generalMappers" -}}
[
    {
        "name": "username",
        "protocol": "openid-connect",
        "protocolMapper": "oidc-usermodel-attribute-mapper",
        "consentRequired": false,
        "config": {
            "aggregate.attrs": "false",
            "introspection.token.claim": "true",
            "multivalued": "false",
            "userinfo.token.claim": "true",
            "user.attribute": "username",
            "id.token.claim": "true",
            "lightweight.claim": "false",
            "access.token.claim": "true",
            "claim.name": "fedid",
            "jsonType.label": "String"
        }
    },
    {
        "name": "audience-mapper",
        "protocol": "openid-connect",
        "protocolMapper": "oidc-audience-mapper",
        "config": {
            "introspection.token.claim": "true",
            "access.token.claim": "true",
            "id.token.claim": "true",
            "included.custom.audience": {{ . | quote }}
        }
    }
]
{{- end }}

{{/* mappers for the beamline service account: a hardcoded beamline claim,
and the tiled-writer audience. Argument: the beamline claim */}}
{{- define "t11-keycloak.beamlineServiceMappers" -}}
[
    {
        "name": "beamline",
        "protocol": "openid-connect",
        "protocolMapper": "oidc-hardcoded-claim-mapper",
        "consentRequired": false,
        "config": {
            "introspection.token.claim": "true",
            "claim.value": {{ . | quote }},
            "userinfo.token.claim": "true",
            "id.token.claim": "true",
            "lightweight.claim": "false",
            "access.token.claim": "true",
            "claim.name": "beamline",
            "jsonType.label": "String",
            "access.tokenResponse.claim": "false"
        }
    },
    {
        "name": "tiled",
        "protocol": "openid-connect",
        "protocolMapper": "oidc-audience-mapper",
        "consentRequired": false,
        "config": {
            "id.token.claim": "false",
            "lightweight.claim": "false",
            "access.token.claim": "true",
            "introspection.token.claim": "true",
            "included.custom.audience": "tiled-writer"
        }
    }
]
{{- end }}

{{/* mappers for a service account that acts as a user: a hardcoded fedid
claim, and an audience. Argument: list of the audience and the fedid */}}
{{- define "t11-keycloak.userServiceMappers" -}}
[
    {
        "name": "fedid",
        "protocol": "openid-connect",
        "protocolMapper": "oidc-hardcoded-claim-mapper",
        "config": {
            "introspection.token.claim": "true",
            "claim.value": {{ index . 1 | quote }},
            "userinfo.token.claim": "true",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "fedid",
            "jsonType.label": "String"
        }
    },
    {
        "name": "audience-mapper",
        "protocol": "openid-connect",
        "protocolMapper": "oidc-audience-mapper",
        "config": {
            "introspection.token.claim": "true",
            "access.token.claim": "true",
            "included.custom.audience": {{ index . 0 | quote }}
        }
    }
]
{{- end }}

{{/* the partial import document */}}
{{- define "t11-keycloak.realm" -}}
{{- $P := .Values.clientPrefix -}}
{{- $cliAttributes := dict
    "frontchannel.logout.session.required" "true"
    "oauth2.device.authorization.grant.enabled" "true"
    "use.refresh.tokens" "true"
    "backchannel.logout.session.required" "true" -}}
{{- /* enabling a service account through the admin API adds the
service_account scope (the client_id claim), and a partial import does not.
Name it, with the defaults that keycloak 26 gives every client. Naming the
default scopes drops the default optional scopes, so name those too */ -}}
{{- $serviceScopes := list "web-origins" "service_account" "acr" "profile" "roles" "basic" "email" -}}
{{- $optionalScopes := list "address" "phone" "offline_access" "organization" "microprofile-jwt" -}}
{{- $webAttributes := dict
    "frontchannel.logout.session.required" "true"
    "use.refresh.tokens" "true" -}}

{{- $users := list -}}
{{- range .Values.users -}}
{{- $users = append $users (dict
    "username" (regexReplaceAll ":.*$" . "")
    "enabled" true
    "credentials" (list (dict "type" "password" "value" (regexReplaceAll "^.*:" . "") "temporary" false))) -}}
{{- end -}}

{{- /* t11-blueapi has no rootUrl, so that keycloak resolves the relative
redirect URI against the host of each request: a browser that reaches keycloak
through the oauth2-proxy LoadBalancer may return to that IP. See the oauth2
values in t11-blueapi */ -}}
{{- $clients := list
  (dict "clientId" (print $P "-cli-blueapi")
    "standardFlowEnabled" false "publicClient" true
    "redirectUris" (list "/*") "attributes" $cliAttributes
    "protocolMappers" (include "t11-keycloak.generalMappers" (print $P "-blueapi") | fromJsonArray))
  (dict "clientId" (print $P "-blueapi")
    "standardFlowEnabled" true "secret" "blueapi-secret"
    "redirectUris" (list (print .Values.redirect.blueapi "/*") "/oauth2/callback") "attributes" $webAttributes
    "protocolMappers" (include "t11-keycloak.generalMappers" (print $P "-blueapi") | fromJsonArray))
  (dict "clientId" "tiled"
    "standardFlowEnabled" true "secret" "tiled-secret"
    "rootUrl" .Values.redirect.tiled
    "redirectUris" (list (print .Values.redirect.tiled "/*"))
    "protocolMappers" (include "t11-keycloak.generalMappers" "account" | fromJsonArray))
  (dict "clientId" "tiled-cli"
    "standardFlowEnabled" false "publicClient" true
    "redirectUris" (list "/*") "attributes" $cliAttributes
    "protocolMappers" (include "t11-keycloak.generalMappers" "tiled" | fromJsonArray))
  (dict "clientId" "tiled-writer"
    "secret" "secret" "standardFlowEnabled" false "serviceAccountsEnabled" true
    "defaultClientScopes" $serviceScopes "optionalClientScopes" $optionalScopes
    "redirectUris" (list "/*")
    "protocolMappers" (include "t11-keycloak.beamlineServiceMappers" .Values.beamlineClaim | fromJsonArray))
-}}
{{- range list "admin" "alice" "bob" -}}
{{- $clients = append $clients (dict "clientId" (print "system-test-blueapi-" .)
    "secret" "secret" "standardFlowEnabled" false "serviceAccountsEnabled" true
    "defaultClientScopes" $serviceScopes "optionalClientScopes" $optionalScopes
    "redirectUris" (list "/*")
    "protocolMappers" (include "t11-keycloak.userServiceMappers" (list (print $P "-blueapi") .) | fromJsonArray)) -}}
{{- end -}}

{{- dict "ifResourceExists" "SKIP" "users" $users "clients" $clients | toPrettyJson -}}
{{- end }}
