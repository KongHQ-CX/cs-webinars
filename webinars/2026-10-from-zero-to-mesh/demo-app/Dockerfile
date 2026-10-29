# BASE has no default, so a build without it stops at "base name should not be blank". No digest can be verified offline, and a tag alone can move. Pass a python slim
# image pinned by digest, read from the registry when you build:
#   docker build --build-arg BASE=python:3.13.5-slim@sha256:<digest> ...
# Standard library only, no pip step.
ARG BASE
FROM ${BASE}
RUN useradd --system --uid 10001 app
WORKDIR /app
COPY src/server.py src/adminctl.py /app/
USER 10001
ENV PORT=8080 ADMIN_PORT=9911 PYTHONUNBUFFERED=1
EXPOSE 8080
# ZONE and ALLOWED_ORIGIN come from the Deployment. The admin port is 127.0.0.1 only and is not exposed.
ENTRYPOINT ["python3", "-I", "/app/server.py"]
