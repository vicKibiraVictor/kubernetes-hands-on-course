# Chapter 1 — Docker Essentials

## The idea (plain English)

Your app needs a specific OS, libraries, and settings to run. A **container**
packages all of that together so it runs the same on your laptop, a teammate's
machine, or a server. Kubernetes runs containers — so we start here.

Three words to keep straight:

- **Image** — the frozen package (app + its dependencies). Built from a `Dockerfile`.
- **Container** — a running copy of an image. You can have many from one image.
- **Volume** — storage that lives *outside* the container, so data survives when
  the container is deleted.

The **Docker daemon** is the background service that builds images and runs
containers; the **Docker CLI** (`docker ...`) is how you talk to it.

## The sample

[`app/`](app) holds a one-line website (`index.html`) and a [`Dockerfile`](app/Dockerfile)
that bakes it into an nginx image.

## Run it

```bash
./run.sh
```

This builds the image, runs it on **http://localhost:8080**, then shows the
commands you'll use daily: `build`, `images`, `run`, `ps`, `logs`, `exec`, and
volumes.

## Try it yourself

```bash
docker ps                      # what's running
docker logs hello-docker       # its output
docker exec -it hello-docker sh   # get a shell inside it (type 'exit' to leave)
docker images                  # images on your machine
```

## Clean up

```bash
./cleanup.sh
```

➡️ **Next:** [Chapter 2 — a real Kubernetes cluster with KinD](../02-kind-multinode-cluster).
