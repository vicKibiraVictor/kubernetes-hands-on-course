#!/usr/bin/env bash
#
# Chapter 1 — Docker essentials.
# Builds an image, runs it, then shows the everyday Docker CLI commands.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need docker
title "Chapter 1 — Docker essentials"

IMAGE="hello-docker:1.0"
NAME="hello-docker"

step "1) Build an image from ./app/Dockerfile"
docker build -t "$IMAGE" ./app
info "an 'image' is the frozen package; 'docker images' lists them:"
docker images "$IMAGE"

step "2) Run a container from the image (in the background)"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p 8080:80 "$IMAGE"
info "a 'container' is a running copy of an image. See it:"
docker ps --filter "name=$NAME"

step "3) Talk to it"
sleep 1
curl -s http://localhost:8080 | grep -o '<h1>.*</h1>' || warn "curl failed (is port 8080 free?)"

step "4) Read its logs"
docker logs "$NAME" | tail -n 3

step "5) Run a command *inside* the container"
docker exec "$NAME" sh -c 'echo "hostname inside container: $(hostname)"'

step "6) Data: volumes keep files even after a container is gone"
docker volume create demo-data >/dev/null
docker run --rm -v demo-data:/data alpine sh -c 'echo "saved at $(date)" > /data/note.txt'
docker run --rm -v demo-data:/data alpine cat /data/note.txt

title "Your container is live at  http://localhost:8080"
info "Clean up when done:  ./cleanup.sh"
