# score-dapr-example

This repo holds an example of using Score to deploy a Dapr application (the [hello-kubernetes](https://github.com/dapr/quickstarts/blob/master/tutorials/hello-kubernetes/README.md) from the Dapr docs) to both Docker Compose and Kubernetes using the same Workload specification files and relying on the resource provisioning capabilities of Score to generate appropriate services and manifests for each platform.

This allows developers to focus on their applications in Score format, testing using Docker Compose and custom provisioner files provided by their Platform Engineering team. Deployment to Kubernetes can then be done by converting the same Score files into manifests.

For `score-compose`, Dapr sidecars and placement services don't fit the Score abstractions and so are generated in the [Makefile](Makefile) using `yq`. A [custom provisioners file](.score-compose/00-custom.provisioners.yaml) is used to generate the Redis service component.

For `score-k8s`, we can rely on the Dapr operator to inject sidecars and to already have the Dapr placement service running. We use a [custom provisioners file](.score-k8s/00-custom.provisioners.yaml) to provision a persistent Redis service and install a Dapr component for it. The start store name as the output can be passed to the Node app.

References:

- [score-compose](https://github.com/score-spec/score-compose)
- [score-k8s](https://github.com/score-spec/score-k8s)
- [dapr](https://github.com/dapr/dapr/tree/master)

## Running the example

You will need:

- `score-compose` and `score-k8s` installed
- `yq` (YAML cli toolkit available in most Linux distros and homebrew)
- a recent version of `docker` installed with Compose support
- (Optional) A Kubernetes cluster, we can set one up with [kind](https://kind.sigs.k8s.io/) to run in Docker.

### Step 1: local development in Docker Compose

**Generate the compose file and K8s manifests:**

```
make build
```

Browse through the input Score files and the `compose.yaml` file to see how the Score workloads have been converted. Notice how the `daprd` sidecar's and placement service have been setup along with a Redis state store. Also notice how we are setting the build context so that the Docker images are built from source as needed.

**Launch the app in Docker Compose:**

```
$ docker compose up -d
[+] Running 14/14
 ✔ Volume "redis-1St3wf-data"                                           Created
 ✔ Volume "redis-CmAR2d-data"                                           Created
 ✔ Container score-dapr-example-placement-1                             Started
 ✔ Container score-dapr-example-redis-1St3wf-1                          Started
 ✔ Container score-dapr-example-wait-for-resources-1                    Started
 ✔ Container score-dapr-example-nodeapp-nodeapp-1                       Started
 ✔ Container score-dapr-example-pythonapp-pythonapp-1                   Started
 ✔ Container score-dapr-example-nodeapp-nodeapp-sidecar-1               Started
 ✔ Container score-dapr-example-pythonapp-pythonapp-sidecar-1           Started
```

View the logs of the nodeapp to see the requests flowing!

```
$ docker logs score-dapr-example-nodeapp-nodeapp-1 
Got a new order! Order ID: 15
Successfully persisted state.
Got a new order! Order ID: 16
Successfully persisted state.
Got a new order! Order ID: 17
Successfully persisted state.
Got a new order! Order ID: 18
Successfully persisted state.
Got a new order! Order ID: 19
Successfully persisted state.
Got a new order! Order ID: 20
Successfully persisted state.
Got a new order! Order ID: 21
Successfully persisted state.
```

These are requests that have successfully gone from the Python app (running a loop) through the Dapr service mesh to the Node app and then across to Redis as the backing state store!

**Clean up:**

```
docker compose down --remove-orphans
```

### Step 2: deployment in Kubernetes

**Ensure you have a Kubernetes cluster with Dapr installed:**

Skip this step if you already have one, for the sake of the demo we'll create one with `kind`.

```
$ kind create cluster
$ kubectl config use-context kind-kind
$ dapr init --kubernetes
$ dapr status -k
```

Wait for the status checks to turn to Running.

**Install the generated manifests:**

```
$ kubectl apply -f manifests.yaml
component.dapr.io/redis-nodeapp-2bf9a2df created
secret/redis-nodeapp-2bf9a2df created
statefulset.apps/redis-nodeapp-2bf9a2df created
service/redis-nodeapp-2bf9a2df created
deployment.apps/nodeapp created
deployment.apps/pythonapp created
```

List the Dapr apps:

```
$ dapr list -k --namespace default
NAMESPACE  APP ID     APP PORT  AGE  CREATED
default    nodeapp    3000      33s  2024-05-15 11:12.43
default    pythonapp            33s  2024-05-15 11:12.43
```

List the Dapr components:

```
$ dapr components -k
NAMESPACE  NAME                    TYPE         VERSION  SCOPES  CREATED              AGE
default    redis-nodeapp-2bf9a2df  state.redis  v1               2024-05-15 11:12.43  1m
```

And view the logs of the nodeapp sidecar:

```
$ dapr logs -k -a nodeapp | tail -n 4
time="2024-05-15T10:15:30.274899093Z" level=info msg="HTTP API Called" app_id=nodeapp code=204 duration=0 instance=nodeapp-cbd784878-2hqx4 method="POST /v1.0/state/redis-nodeapp-2bf9a2df" scope=dapr.runtime.http-info size=0 type=log useragent="node-fetch/1.0 (+https://github.com/bitinn/node-fetch)" ver=1.13.2
time="2024-05-15T10:15:31.295385969Z" level=info msg="HTTP API Called" app_id=nodeapp code=204 duration=1 instance=nodeapp-cbd784878-2hqx4 method="POST /v1.0/state/redis-nodeapp-2bf9a2df" scope=dapr.runtime.http-info size=0 type=log useragent="node-fetch/1.0 (+https://github.com/bitinn/node-fetch)" ver=1.13.2
time="2024-05-15T10:15:32.313568719Z" level=info msg="HTTP API Called" app_id=nodeapp code=204 duration=1 instance=nodeapp-cbd784878-2hqx4 method="POST /v1.0/state/redis-nodeapp-2bf9a2df" scope=dapr.runtime.http-info size=0 type=log useragent="node-fetch/1.0 (+https://github.com/bitinn/node-fetch)" ver=1.13.2
```

And the logs of the nodeapp itself (grab the instance id from the log above):

```
$ kubectl logs nodeapp-cbd784878-2hqx
Got a new order! Order ID: 198
Successfully persisted state for Order ID: 198
Got a new order! Order ID: 199
Successfully persisted state for Order ID: 199
Got a new order! Order ID: 200
Successfully persisted state for Order ID: 200
Got a new order! Order ID: 201
Successfully persisted state for Order ID: 201
```

🎉

## FAQ

...
