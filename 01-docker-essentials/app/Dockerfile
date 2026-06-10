# A Docker image = your app + everything it needs to run, frozen into layers.
# This one is just nginx with our own home page copied in.
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
