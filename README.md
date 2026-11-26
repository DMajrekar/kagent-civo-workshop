# Your cluster called — kagent on Civo

This is the code behind the workshop: a capture-the-flag in a week of
production logs, played first with **Grafana** and then with **kagent**
agents asking the same logs the same questions.

If you were in the room, everything you used is here: the three agents, the
questions that worked, and how the environment was put together. This page
gets you from nothing to an agent of your own answering questions on your own
cluster.

**Built with:** [kagent](https://kagent.dev) · [Civo Kubernetes](https://civo.com)
· [relax.ai](https://relax.ai) · Grafana and Loki over MCP

---

## What you saw

An agent in kagent is a Kubernetes resource with three parts: a **model** to
think with, a **prompt** saying what it is for, and the **tools** it may use.
Tools come from MCP servers. In the workshop the only tool was a read-only
view of Loki, and the three agents differed mostly in their prompts:

| Agent | What it was told | File |
|---|---|---|
| `log-reader` | Almost nothing. It answers direct questions and flounders on open ones. | [`agents/01-log-reader.yaml`](agents/01-log-reader.yaml) |
| `log-detective` | What the data looks like and how to look for a pattern. | [`agents/02-log-detective.yaml`](agents/02-log-detective.yaml) |
| `early-warning` | To ignore what is already failing and find what is about to. | [`agents/03-early-warning.yaml`](agents/03-early-warning.yaml) |

Compare the first two side by side. Same model, same logs, same tools: the
difference in what they find is the prompt.

## Get kagent running

You need a Kubernetes cluster, `kubectl`, `helm`, and an API key for a model
that supports tool calling. These steps use Civo and relax.ai, as the workshop
did. Any cluster and any OpenAI-compatible model will do.

### 1. A cluster

With the [Civo CLI](https://github.com/civo/cli#set-up):

```bash
civo kubernetes create my-kagent --size g4s.kube.medium --nodes 2 --wait
civo kubernetes config my-kagent > kubeconfig
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes
```

Or with Terraform: [`terraform/main.tf`](terraform/main.tf) is the cluster
from the slides. Set `CIVO_TOKEN`, then `terraform init && terraform apply`.

### 2. kagent

```bash
# The resource types: Agent, ModelConfig, RemoteMCPServer.
helm upgrade --install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --namespace kagent --create-namespace --version 0.10.1 --wait

# Your model key, as a Secret. Agents never see it; kagent does.
kubectl -n kagent create secret generic kagent-relax \
  --from-literal=RELAX_API_KEY='<your relax.ai key>'

# kagent itself: a controller, a dashboard, and a database for conversations.
helm upgrade --install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent --version 0.10.1 --wait --timeout 10m \
  --values examples/kagent-values.yaml

kubectl -n kagent get pods
```

[`examples/kagent-values.yaml`](examples/kagent-values.yaml) is short and
worth reading: the model, where its key is, and which ready-made agents to
install. To use a different provider, change the model name and address there.

### 3. Talk to it

```bash
kubectl -n kagent port-forward svc/kagent-ui 8082:8080
```

Open <http://localhost:8082>. The install includes `k8s-agent`, which can look
around the cluster it runs in. Ask it what is running, or what looks
unhealthy.

The dashboard has no login. Keep it behind the port-forward; do not put it on
the internet as it is. [`docs/HOSTING.md`](docs/HOSTING.md) describes what the
workshop put in front of it to share one kagent with a room.

### 4. Your own agent

[`examples/my-agent.yaml`](examples/my-agent.yaml) is a scaffold. Rename it,
write the prompt, pick the tools, and apply it:

```bash
kubectl -n kagent get remotemcpservers          # the tool servers you have
kubectl apply -f examples/my-agent.yaml
kubectl -n kagent get agents
```

The scaffold lists two tool servers. `kagent-tool-server` came with the
install. `workshop-logs` is the workshop's log endpoint, which you will not
have yet: delete that entry, or see the next section.

## Give an agent your logs

The workshop's agents reach Loki through
[mcp-grafana](https://github.com/grafana/mcp-grafana), an MCP server that
reads Grafana's API. In kagent that is one resource:

```yaml
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: workshop-logs
  namespace: kagent
spec:
  description: Logs, through Grafana and Loki.
  protocol: STREAMABLE_HTTP
  url: http://<your mcp-grafana>/mcp
  timeout: 60s
```

Point `url` at an mcp-grafana in front of your own Grafana and the three
agents in [`agents/`](agents/) work against your logs. Edit two things in each
first: the datasource UID in the prompt, and the description of your services
and labels. [`hub/step-06-mcp/`](hub/step-06-mcp/) is a working mcp-grafana
deployment, including a bearer-token check in front of it.

To rebuild the workshop's own dataset instead, with its week of seeded
incidents, see [`docs/HOSTING.md`](docs/HOSTING.md).

## Asking good questions

The most transferable thing from the session: what you get back depends mostly
on how you ask.

- Ask the open question first. *"Has anything got worse in the last week?"*
  finds more than *"show me the errors"*.
- Put the constraint in the question. *"Is there anything that will fail in
  the next two weeks but is not failing today?"* finds a certificate about to
  expire. Without the last five words, the agent reports whatever is loudest.
- Ask it to quote the log line. It keeps the answer honest and gives you
  something to check.

[`docs/DEMO-PROMPTS.md`](docs/DEMO-PROMPTS.md) has the questions that worked
and how the models compared. [`docs/INCIDENTS.md`](docs/INCIDENTS.md)
describes the dataset and what was hidden in it; it contains the answers to
the flags.

## Clean up

A cluster costs money for every hour it runs.

```bash
civo kubernetes remove my-kagent --yes
civo volume ls        # a cluster's volumes outlive it; remove any left over
```

## Running the workshop yourself

[`docs/HOSTING.md`](docs/HOSTING.md) covers building the whole environment:
the logs, Grafana, the CTF app, a kagent that a room can share, and the slide
deck. [`docs/RUNSHEET.md`](docs/RUNSHEET.md) is the plan for the session
itself.
