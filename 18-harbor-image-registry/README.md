# Chapter 18 — Your Own Registry with Harbor

## The idea (plain English)

Images have to live somewhere. Docker Hub is public; companies want a **private
registry** they control. **Harbor** is the popular open-source one. It gives you:

- **Projects** — folders for images, with their own access rules (public/private).
- **Vulnerability scanning** — flags images with known security holes.
- **Access control** — who can pull vs push, robot accounts for CI.
- **Signing & replication** — trust and copy images between registries.

## Run it

```bash
./run.sh
```

> ⚠️ Harbor runs several pods (core, registry, database, redis, portal). Give it a
> few minutes.

It installs Harbor and creates a project named **`course-demo`**.

## The simple project — push an image

Keep a port-forward running in one terminal:

```bash
kubectl -n harbor port-forward svc/harbor 8080:80
```

Then in another terminal:

```bash
docker pull nginx:alpine
docker tag  nginx:alpine localhost:8080/course-demo/nginx:1.0
docker login localhost:8080 -u admin -p Harbor12345
docker push localhost:8080/course-demo/nginx:1.0
```

Now open **http://localhost:8080** (admin / Harbor12345) → project **course-demo**
→ you'll see your image, its size, and tags.

> Docker treats `localhost` registries as insecure-OK over HTTP, so this works
> without editing the Docker daemon config. For a registry on a real hostname
> you'd enable TLS in Harbor instead.

## Clean up

```bash
./cleanup.sh
```

🎉 **That's the course.** You went from a single container to a secured,
observable, multi-tenant cluster with its own registry. Back to the
[course overview](../README.md).
