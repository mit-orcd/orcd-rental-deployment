# Container Deployments (Experimental)

This directory contains experimental work on deploying ColdFront and related services inside containers. The goal is to enable reproducible, isolated development and testing environments that closely mirror production deployments.

## Contents

| Directory | Description |
|-----------|-------------|
| [aws_ec2_experiments/](aws_ec2_experiments/) | Container networking experiments targeting AWS EC2 instances |

## Status

This material is **experimental**. It is provided for reference and further development but is not yet integrated into the main deployment workflow.

## Background

Running ColdFront behind nginx inside an Apptainer container requires careful networking configuration. When Apptainer boots a container with systemd (`--boot`), it creates an isolated network namespace. Two approaches are documented here:

1. **IP tables bridge approach** — Use a CNI bridge network with manual iptables rules for NAT and port forwarding.
2. **Systemd override approach** — Share the host network namespace and disable container-side network managers via systemd drop-in overrides.

See the subdirectories for detailed documentation on each approach.
