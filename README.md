# Sentinel — Agent DevOps Autonome pour Infrastructure Auto-Réparatrice

> Autonomous DevOps agent that detects, diagnoses, and remediates AWS infrastructure incidents without human intervention — built during a summer internship at Smartovate LTD (ENET'COM Sfax).

[![AWS](https://img.shields.io/badge/AWS-Lambda%20%7C%20CloudWatch%20%7C%20SNS%20%7C%20DynamoDB%20%7C%20SSM-orange)](#)
[![IaC](https://img.shields.io/badge/IaC-Terraform-844FBA)](#)
[![Status](https://img.shields.io/badge/status-not%20deployed%20(AWS%20resources%20pending)-yellow)](#)

## Overview

Manual incident response on cloud infrastructure is slow and repetitive: every minute of CPU overload, a crashed service, or a bad deployment costs money and trust. This project automates the full loop — **detect → diagnose → remediate** — while guarding against runaway automation ("flapping") with a DynamoDB-based lock.

```
CloudWatch Alarm → SNS Topic → Lambda (Ingestion) → Lambda (Remediation + AI Diagnosis)
                                                              │
                                        ┌─────────────────────┼─────────────────────┐
                                        ▼                     ▼                     ▼
                                 SSM: restart-service   SSM: scale-up ASG   SSM: rollback-deployment
                                        │
                                        ▼
                          DynamoDB anti-flapping lock (TTL = 10 min)
```

## Key features

- **Detection** — CloudWatch alarms on critical metrics (CPU > 80% for 5 min, error rate)
- **Ingestion** — a Lambda function validates and enriches the SNS notification
- **AI-assisted diagnosis** — a second Lambda classifies the incident (`CPU_OVERLOAD`, `SERVICE_DOWN`, `DEPLOYMENT_ERROR`) via Amazon Bedrock, with an automatic local fallback ("demo mode") when the Bedrock quota isn't available
- **Automated remediation** — one of three SSM documents is executed: `restart-service`, `scale-up`, or `rollback-deployment`
- **Anti-flapping protection** — before acting, the agent checks a DynamoDB lock keyed by target; a locked target gets an HTTP 429 instead of a repeated action; a new lock (TTL 10 min) is created after each execution
- **Infrastructure as Code** — the entire stack (39 AWS resources) is provisioned and reproducible via Terraform
- **Traceability** — every step is logged to CloudWatch Logs and audited via CloudTrail

## Architecture

| Layer | Resources |
|---|---|
| Network | VPC `10.0.0.0/16`, 2 public subnets, Internet Gateway, route tables, security groups |
| Compute | Launch template, Auto Scaling Group, ALB + listener, EC2 web instances |
| Monitoring | 2 CloudWatch alarms, SNS topic, S3 bucket, CloudTrail, log groups |
| Serverless | Ingestion & Remediation Lambdas (Python 3.11), IAM roles/policies, SNS permission/subscription |
| Remediation | 3 SSM documents (`restart-service`, `scale-up`, `rollback-deployment`) |
| Protection | DynamoDB table `remediation-locks` (PK `instance_id`, TTL on `ttl_timestamp`) |

Full design details (UML use-case, sequence and class diagrams, network architecture, end-to-end data flow) are in the [internship report](docs/Rapport-de-stage.pdf).

## Repository structure

```
.
├── infra/              # Terraform (VPC, ASG/ALB, CloudWatch, SNS, Lambda, SSM, DynamoDB)
├── lambda/
│   ├── ingestion/       # SNS → validate & enrich alarm payload
│   └── remediation/     # Diagnose (Bedrock/demo), choose action, anti-flapping lock, execute
├── dashboard/           # Standalone HTML monitoring dashboard (Sentinel UI)
├── docs/                # Internship report (French) with full methodology, diagrams & tests
└── README.md
```

> **Note:** the AWS resources for this project are not currently provisioned (they were deployed under a Free Tier account during the internship and have since been torn down). The Terraform and Lambda source code will be added here as it's recovered/cleaned up for public release; `infra/` and `lambda/` are scaffolded but empty for now.

## Tech stack

AWS (CloudWatch, SNS, Lambda, DynamoDB, Systems Manager, EC2/ASG/ALB, IAM, CloudTrail, S3, Bedrock) · Terraform · Python 3.11 · AWS CLI

## Validation (from internship testing)

| Test | Result |
|---|---|
| Alarm received by ingestion Lambda | ✅ |
| Diagnosis classification (e.g. `CPU_OVERLOAD`, confidence `HIGH`) | ✅ |
| Scale-up remediation (Desired Capacity 1 → 3) | ✅ |
| SSM `restart-service` on target instances | ✅ |
| Anti-flapping lock (second call → HTTP 429) | ✅ |
| `terraform state list` — 39 managed resources | ✅ |

## Dashboard

`dashboard/index.html` is a self-contained monitoring UI ("Sentinel") for the agent — open it directly in a browser, no build step required.

## Author

**Hosni Nheri** — Génie des Télécommunications, ENET'COM Sfax
Summer internship at **Smartovate LTD**, supervised by M. Abdelkhalek Bakkari

## License

Add a license of your choice (e.g. MIT) if you want this to be reusable by others.
