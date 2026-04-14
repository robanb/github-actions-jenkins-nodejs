# Jenkins LTS image for github-actions-jenkins-nodejs.
# Adds curl + git on top of the base image and pre-installs the plugins
# listed in plugins.txt. See docs/JENKINS.md for how to build and run it.

FROM jenkins/jenkins:lts-jdk17

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
USER jenkins

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --latest true
