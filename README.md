# DevOps Master Orchestration Image

This is an all-in-one "master" docker image for use in CI tools such as GitlabCI, Github Actions, Jenkins for performing docker-based CI/CD orchestration.  This image has a variety of tools pre-installed and is as minimalistic as possible whilst still being fully functional with all those tools.  It is build on `alpine:3.9` and contains the following.

 * AWS CLI / SDK
 * GCloud CLI / SDK
 * Kubectl
 * Helm
   * Helm Diff && Helm S3 Plugins
 * Krane
 * docker (used for dind)
 * terraform (w/ preinstalled 12.13 && 12.24)
 * tfenv (used for supporting multiple versions of terraform automatically)
 * git
 * Python
 * Ruby

This image in some form is and has been used by a few dozen of my clients.
