"""Offline checks for every manifest under stages/. Standard library only; yq turns YAML into JSON.

Run: python3 -I code/lib/manifests_check.py [stages-dir]
     python3 -I code/lib/manifests_check.py --stage <one stage dir>   (that stage's manifests only, no tree scan)
Rebuild the schema snapshot from a checkout of the Kong Operator v2.3.3 tag (read only):
     python3 -I code/lib/manifests_check.py --schemas <v2.3.3-checkout> > code/lib/crd-schemas.json
Exit 0 when every check passes. Each failure prints one line.

Checks
- Every document has apiVersion, kind and metadata.name (merge patches named *.patch.yaml are exempt).
- No kuma.io/service tag or key, no legacy policy kind, no standalone zone proxy kind, no built-in gateway kind.
- No wording about the removed CLI tools or the next major version, no em or en dash, no placeholder token inside YAML.
- Every Kuma policy is namespaced and carries the kuma.io/mesh label. A policy applied on a zone also
  carries kuma.io/origin: zone (files under shown/ and optional/ belong to the global control plane).
- Every field of a GatewayConfiguration or KonnectAPIAuthConfiguration exists in the Operator v2.3.3
  schema snapshot (lib/crd-schemas.json). A misspelled or nonexistent field fails. Gateway, GatewayClass
  and HTTPRoute are not in the snapshot: only the server-side dry run in apply.sh checks their fields.
- Stage rules: MeshRetry values, MeshTrafficPermission shape (one exact spiffeID allow entry, Dataplane
  target), Gateway annotations and listeners (no allowedRoutes from All), HTTPRoute scope,
  GatewayConfiguration (no loadBalancerSourceRanges, externalTrafficPolicy Local), canary weights,
  NetworkPolicy (never admits the world, TCP ports only, no endPort), MeshIdentity (Bundled
  provider, one identity per ServiceAccount), Deployments (own ServiceAccount, mesh label, image from
  an environment placeholder or pinned by digest).
- Text scan over all of the code folder outside this checker and its schema file: banned wording, dashes and the removed service tag.
"""
import json
import pathlib
import re
import subprocess
import sys

# Words that must not appear in shipped files. Built from parts so this file does not contain them.
BANNED_WORDS = ["kuma" + "ctl", "kong" + "ctl", "mesh " + "3", "mesh" + "3"]
DASHES = [chr(0x2014), chr(0x2013)]
LEGACY_KINDS = {
    "TrafficPermission", "TrafficRoute", "TrafficTrace", "TrafficLog", "HealthCheck", "CircuitBreaker",
    "Retry", "Timeout", "FaultInjection", "RateLimit", "ProxyTemplate", "VirtualOutbound",
    "ExternalService", "Dataplane", "ZoneIngress", "ZoneEgress", "MeshGateway", "MeshGatewayRoute",
    "MeshGatewayInstance", "MeshGatewayConfig",
}
PLACEHOLDER = "__REPLACE" + "_ME__"
SCHEMA_FILE = pathlib.Path(__file__).resolve().parent / "crd-schemas.json"
SCHEMA_KINDS = ("GatewayConfiguration", "KonnectAPIAuthConfiguration")
SCHEMA_KEEP = ("type", "required", "enum", "x-kubernetes-preserve-unknown-fields", "x-kubernetes-int-or-string")
errors = []
DEPLOYMENT_SAS = []  # (stage, namespace, serviceAccountName, path)
DECLARED_SAS = set()  # (stage, namespace, name)
STAGES_ROOT = None


def stage_of(path):
    try:
        return pathlib.Path(path).relative_to(STAGES_ROOT).parts[0]
    except (ValueError, TypeError, IndexError):
        return ""


def err(path, msg):
    errors.append(f"{path}: {msg}")


def load_docs(path):
    out = subprocess.run(["yq", "-o=json", "-I=0", ".", str(path)], capture_output=True, text=True)
    if out.returncode != 0:
        err(path, "yq cannot parse: " + out.stderr.strip())
        return []
    docs = []
    for line in out.stdout.splitlines():
        if line.strip() and line.strip() != "null":
            docs.append(json.loads(line))
    return docs


def walk(node, fn, trail=""):
    if isinstance(node, dict):
        for k, v in node.items():
            fn(trail, k, v)
            walk(v, fn, f"{trail}/{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, fn, f"{trail}[{i}]")


def trim_schema(node):
    """Keep only what the field walker needs: structure, not prose."""
    out = {k: node[k] for k in SCHEMA_KEEP if k in node}
    if isinstance(node.get("properties"), dict):
        out["properties"] = {k: trim_schema(v) for k, v in node["properties"].items()}
    if isinstance(node.get("items"), dict):
        out["items"] = trim_schema(node["items"])
    if isinstance(node.get("additionalProperties"), dict):
        out["additionalProperties"] = trim_schema(node["additionalProperties"])
    elif node.get("additionalProperties") is True:
        out["additionalProperties"] = True
    return out


def build_schemas(root):
    """Build {"group/Kind": {version: trimmed openAPIV3Schema}} for the served versions of the kinds used."""
    result = {}
    for f in sorted(pathlib.Path(root, "config", "crd").rglob("*.yaml")):
        for d in load_docs(f):
            spec = d.get("spec") or {}
            if d.get("kind") != "CustomResourceDefinition" or "group" not in spec:
                continue
            if spec["names"]["kind"] not in SCHEMA_KINDS:
                continue
            result[f"{spec['group']}/{spec['names']['kind']}"] = {
                v["name"]: trim_schema(v["schema"]["openAPIV3Schema"]) for v in spec["versions"] if v.get("served")
            }
    return result


def walk_schema(path, value, schema, trail):
    """Report every field of value that the schema does not define."""
    if isinstance(value, dict):
        props = schema.get("properties")
        extra = schema.get("additionalProperties")
        if props is None and extra is None:
            if not schema.get("x-kubernetes-preserve-unknown-fields") and schema.get("type") == "object" and value:
                err(path, f"unknown field {trail or '/'}: the schema defines no fields here")
            return
        for k, v in value.items():
            if props is not None and k in props:
                walk_schema(path, v, props[k], f"{trail}/{k}")
            elif isinstance(extra, dict):
                walk_schema(path, v, extra, f"{trail}/{k}")
            elif extra is True or schema.get("x-kubernetes-preserve-unknown-fields"):
                continue
            else:
                err(path, f"unknown field {trail}/{k}: not in the Operator v2.3.3 schema")
    elif isinstance(value, list) and isinstance(schema.get("items"), dict):
        for i, v in enumerate(value):
            walk_schema(path, v, schema["items"], f"{trail}[{i}]")


def check_schema(path, doc, schema_db):
    api, kind = str(doc.get("apiVersion", "")), str(doc.get("kind", ""))
    group, _, version = api.rpartition("/")
    if kind not in SCHEMA_KINDS:
        return
    entry = (schema_db.get(f"{group}/{kind}") or {}).get(version)
    if entry is None:
        err(path, f"{kind} {api} is not in the Operator v2.3.3 schema snapshot")
        return
    top = entry.get("properties") or {}
    for k, v in doc.items():
        if k in ("apiVersion", "kind", "metadata"):
            continue
        if k not in top:
            err(path, f"unknown field /{k}: not in the Operator v2.3.3 schema")
        else:
            walk_schema(path, v, top[k], f"/{k}")


def check_doc(path, doc, global_owned=False, schema_db=None):
    for key in ("apiVersion", "kind"):
        if not isinstance(doc.get(key), str) or not doc[key]:
            err(path, f"missing {key}")
    name = (doc.get("metadata") or {}).get("name")
    if not isinstance(name, str) or not name:
        err(path, "missing metadata.name")
    api = str(doc.get("apiVersion", ""))
    kind = str(doc.get("kind", ""))
    meta = doc.get("metadata") or {}

    def no_service_tag(trail, key, value):
        if key == "kuma.io/service" or (isinstance(value, str) and value == "kuma.io/service"):
            err(path, f"kuma.io/service tag at {trail}/{key}")

    walk(doc, no_service_tag)

    if api.startswith("kuma.io/"):
        if kind in LEGACY_KINDS:
            err(path, f"legacy or removed kind {kind}")
        if not kind.startswith("Mesh") and kind != "HostnameGenerator":
            err(path, f"kuma.io kind {kind} is not a Mesh* policy")
        if kind not in ("Mesh",):
            if not meta.get("namespace"):
                err(path, f"{kind} has no metadata.namespace")
            if "kuma.io/mesh" not in (meta.get("labels") or {}):
                err(path, f"{kind} has no kuma.io/mesh label")
            if not global_owned and (meta.get("labels") or {}).get("kuma.io/origin") != "zone":
                err(path, f"{kind} has no kuma.io/origin: zone label")
    if kind in ("ZoneIngress", "ZoneEgress"):
        err(path, f"standalone {kind}")
    check_schema(path, doc, schema_db or {})

    rule = {
        "MeshRetry": check_meshretry,
        "MeshTrafficPermission": check_mtp,
        "Gateway": check_gateway,
        "HTTPRoute": check_httproute,
        "GatewayConfiguration": check_gatewayconfig,
        "MeshHTTPRoute": check_meshhttproute,
        "MeshTrust": check_meshtrust,
        "MeshIdentity": check_meshidentity,
        "NetworkPolicy": check_networkpolicy,
    }.get(kind)
    if kind == "Deployment" and api == "apps/v1":
        check_deployment(path, doc)
    if kind == "ServiceAccount" and api == "v1":
        DECLARED_SAS.add((stage_of(path), meta.get("namespace", ""), meta.get("name", "")))
    if rule and (api.startswith("kuma.io/") or "gateway" in api or "gateway-operator" in api or kind == "NetworkPolicy"):
        rule(path, doc)


def check_meshretry(path, doc):
    spec = doc.get("spec", {})
    if spec.get("targetRef", {}).get("kind") != "Mesh":
        err(path, "MeshRetry top targetRef must be kind Mesh")
    if "from" in spec:
        err(path, "MeshRetry uses `to`, not `from`")
    for to in spec.get("to", []):
        http = to.get("default", {}).get("http", {})
        if http.get("numRetries") != 3:
            err(path, "MeshRetry numRetries must be 3")
        if http.get("retryOn") != ["503"]:
            err(path, 'MeshRetry retryOn must be ["503"]')
        labels = to.get("targetRef", {}).get("labels", {})
        if "kuma.io/display-name" not in labels or "k8s.kuma.io/namespace" not in labels:
            err(path, "MeshRetry `to` must select by kuma.io/display-name and k8s.kuma.io/namespace labels")
    if not spec.get("to"):
        err(path, "MeshRetry has no `to`")


def check_mtp(path, doc):
    spec = doc.get("spec", {})
    if "from" in spec:
        err(path, "MeshTrafficPermission must use `rules`, not `from`")
    target = json.dumps(spec.get("targetRef", {})).lower()
    if "gateway" in target or "kong" in target:
        err(path, "MeshTrafficPermission must not target the gateway")
    rules = spec.get("rules", [])
    if not rules:
        err(path, "MeshTrafficPermission has no rules")
    tref = spec.get("targetRef", {})
    if tref.get("kind") == "Mesh":
        err(path, "an allow rule must not target kind Mesh: it would allow the caller to every workload")
    elif tref.get("kind") != "Dataplane" or not tref.get("labels"):
        err(path, "an allow rule must target kind Dataplane with labels")
    for r in rules:
        d = r.get("default", {})
        if d.get("deny") or d.get("allowWithShadowDeny"):
            err(path, "the gateway allow rule must only allow")
        allows = d.get("allow", [])
        if not allows:
            err(path, "no allow entry")
        elif len(allows) != 1:
            err(path, "an allow rule must hold exactly one allow entry")
        for a in allows:
            sid = a.get("spiffeID")
            if not sid:
                err(path, "allow entry without spiffeID (would match all callers)")
                continue
            if sid.get("type") != "Exact":
                err(path, "spiffeID type must be Exact")
            if "*" in str(sid.get("value", "")):
                err(path, "spiffeID value has a wildcard")


def check_gateway(path, doc):
    if "gateway.networking.k8s.io" not in doc.get("apiVersion", ""):
        return
    ann = doc.get("spec", {}).get("infrastructure", {}).get("annotations", {})
    ports = ann.get("traffic.kuma.io/exclude-inbound-ports", "")
    if not re.fullmatch(r"\d+(,\d+)*", ports):
        err(path, "traffic.kuma.io/exclude-inbound-ports must be a comma-separated port list")
    if ann.get("kuma.io/ignore") != "true":
        err(path, 'kuma.io/ignore must be "true"')
    if "kuma.io/gateway" in ann:
        err(path, "kuma.io/gateway annotation is removed")
    if not doc.get("spec", {}).get("gatewayClassName"):
        err(path, "no gatewayClassName")
    for listener in doc.get("spec", {}).get("listeners", []):
        if ((listener.get("allowedRoutes") or {}).get("namespaces") or {}).get("from") == "All":
            err(path, "listener allowedRoutes.namespaces.from All lets any namespace attach a route")
        if listener.get("protocol") == "HTTPS":
            tls = listener.get("tls") or {}
            if tls.get("mode") != "Terminate" or not tls.get("certificateRefs"):
                err(path, "an HTTPS listener must terminate TLS with certificateRefs")


def check_httproute(path, doc):
    for rule in doc.get("spec", {}).get("rules", []):
        for m in rule.get("matches", []):
            if m.get("path", {}).get("type") != "Exact" or m.get("path", {}).get("value") != "/" or m.get("method") != "GET":
                err(path, "the route must match GET with the exact path / only")
        if not rule.get("matches"):
            err(path, "a route rule without matches would pass every path")


def check_gatewayconfig(path, doc):
    ingress = (
        doc.get("spec", {}).get("dataPlaneOptions", {}).get("network", {}).get("services", {}).get("ingress") or {}
    )
    if "loadBalancerSourceRanges" in ingress:
        err(path, "loadBalancerSourceRanges does not exist in GatewayConfiguration v2beta1 ingress: the load balancer firewall limits the sources")
    if ingress.get("externalTrafficPolicy") != "Local":
        err(path, "ingress externalTrafficPolicy must be Local: it keeps the client address for the load balancer firewall (relax with GATEWAY_TRAFFIC_POLICY in lib/gateway.sh)")


def check_meshhttproute(path, doc):
    total = 0
    for to in doc.get("spec", {}).get("to", []):
        for rule in to.get("rules", []):
            for b in rule.get("default", {}).get("backendRefs", []):
                if b.get("kind") != "MeshService":
                    err(path, "backendRef kind must be MeshService")
                if "tags" in b:
                    err(path, "backendRef tags are not used")
                total += b.get("weight", 1)
    if total != 100:
        err(path, f"canary weights add up to {total}, expected 100")


def check_networkpolicy(path, doc):
    """A policy shipped in a stage must never admit the world. (Stage 03 ships none: the Operator makes its
    own policy for the gateway pods, policies add up, so a policy here could only widen access.)"""
    if (doc.get("metadata") or {}).get("namespace") != "kong":
        err(path, "the NetworkPolicy must be in namespace kong")
    for rule in (doc.get("spec") or {}).get("ingress", []):
        sources = rule.get("from") or []
        ports = rule.get("ports") or []
        if not sources:
            err(path, "a rule with no from list admits every source (the load balancer firewall is the edge control, not a policy here)")
        for f in sources:
            if f == {} or ("namespaceSelector" in f and f["namespaceSelector"] == {}):
                err(path, "an empty peer or an empty namespaceSelector admits every pod")
            if (f.get("ipBlock") or {}).get("cidr") in ("0.0.0.0/0", "::/0"):
                err(path, "an ipBlock of 0.0.0.0/0 admits the world")
        for p in ports:
            if "endPort" in p:
                err(path, "endPort is not allowed: name each port")
            if p.get("protocol") != "TCP":
                err(path, "only TCP ports are allowed: give protocol: TCP on every port")


def check_deployment(path, doc):
    tmpl = doc.get("spec", {}).get("template", {})
    sa = tmpl.get("spec", {}).get("serviceAccountName")
    if not sa or sa == "default":
        err(path, "a workload must run as its own ServiceAccount: the SPIFFE ID names it, and default would share one identity")
    else:
        DEPLOYMENT_SAS.append((stage_of(path), (doc.get("metadata") or {}).get("namespace", ""), sa, path))
    if "kuma.io/mesh" not in (tmpl.get("metadata", {}).get("labels") or {}):
        err(path, "the pod template needs the kuma.io/mesh label")
    for c in tmpl.get("spec", {}).get("containers", []):
        image = str(c.get("image", ""))
        if not (re.fullmatch(r"\$\{[A-Z_]+\}", image) or re.search(r"@sha256:[0-9a-f]{64}$", image)):
            err(path, f"image must be an environment placeholder or digest-pinned, got {image}")


def check_meshidentity(path, doc):
    spec = doc.get("spec", {})
    if not spec.get("selector"):
        err(path, "MeshIdentity needs a selector")
    if (spec.get("provider") or {}).get("type") != "Bundled":
        err(path, "MeshIdentity provider must be Bundled")
    spiffe = spec.get("spiffeID") or {}
    if spiffe.get("path") != "/ns/{{ .Namespace }}/sa/{{ .ServiceAccount }}":
        err(path, "MeshIdentity spiffeID path must be exactly /ns/{{ .Namespace }}/sa/{{ .ServiceAccount }} (one identity per ServiceAccount)")
    if "*" in json.dumps(spiffe):
        err(path, "MeshIdentity spiffeID has a wildcard")


def check_meshtrust(path, doc):
    spec = doc.get("spec", {})
    if not spec.get("trustDomain") or not spec.get("caBundles"):
        err(path, "MeshTrust needs trustDomain and caBundles")


def main():
    global STAGES_ROOT
    one_stage = None
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--stage":
        one_stage = pathlib.Path(args[1]).resolve()
        stages = one_stage.parent
    elif args:
        stages = pathlib.Path(args[0])
    else:
        stages = pathlib.Path(__file__).resolve().parent.parent / "stages"
    STAGES_ROOT = stages
    code_dir = stages.parent
    try:
        schema_db = json.loads(SCHEMA_FILE.read_text())
    except (OSError, ValueError):
        schema_db = {}
        err(SCHEMA_FILE, "schema snapshot missing or unreadable: rebuild it with --schemas")
    yaml_files = sorted(p for p in (one_stage or stages).rglob("*") if p.is_file() and (p.suffix in (".yaml", ".yml") or p.name.endswith(".yaml.tmpl")))
    if not yaml_files:
        err(stages, "no manifests found")
    for path in yaml_files:
        text = path.read_text()
        if PLACEHOLDER in text:
            err(path, "placeholder token inside a manifest (read plain env vars instead)")
        if path.name.endswith((".patch.yaml", ".patch.yml")):
            load_docs(path)  # must still parse
            continue
        docs = load_docs(path)
        if not docs:
            err(path, "no YAML document")
        rel = path.relative_to(stages).parts
        global_owned = any(part in ("shown", "optional") for part in rel[:-1])
        for doc in docs:
            if not isinstance(doc, dict):
                err(path, "document is not a mapping")
                continue
            check_doc(path, doc, global_owned, schema_db)

    if one_stage is None:
        scan_tree(code_dir)
    return finish(len(yaml_files))


def scan_tree(code_dir):
    # Text scan over every shipped file under the code folder.
    for path in sorted(code_dir.rglob("*")):
        if not path.is_file() or path.suffix in (".png", ".svg", ".woff2"):
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        low = text.lower()
        # Test scripts name the banned words on purpose, to assert that scripts reject them. Only
        # The code test folder is exempt, found by its position under the code directory.
        in_tests = path.name in ("manifests_check.py", "crd-schemas.json")
        for word in BANNED_WORDS:
            if word in low and not in_tests:
                err(path, f"banned wording '{word}'")
        for d in DASHES:
            if d in text:
                err(path, "em or en dash")
        if path.suffix in (".yaml", ".sh", ".tmpl", ".py") and "kuma.io/service" in text and not in_tests:
            err(path, "kuma.io/service")

    seen = {}
    for stage, ns, sa, path in DEPLOYMENT_SAS:
        if (stage, ns, sa) not in DECLARED_SAS:
            err(path, f"ServiceAccount {sa} is not declared in the same stage")
        if (ns, sa) in seen and seen[(ns, sa)] != path:
            err(path, f"two Deployments name the same ServiceAccount {sa}: they would share one SPIFFE ID")
        seen.setdefault((ns, sa), path)


def finish(count):
    if errors:
        for e in errors:
            print("FAIL " + e)
        print(f"{len(errors)} problem(s)")
        return 1
    print(f"ok: {count} manifest files checked")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--schemas":
        print(json.dumps(build_schemas(sys.argv[2]), sort_keys=True, separators=(",", ":")))
        sys.exit(0)
    sys.exit(main())
