# Agent DevOps Autonome — Rapport de Stage

**Entreprise** : SMARTOVATE LTD  
**Période** : Juillet 2026  
**Technologies** : AWS, Terraform, Python, Lambda, DynamoDB, CloudWatch

---

## Table des matières

1. [Contexte et Objectifs](#1-contexte-et-objectifs)
2. [Architecture](#2-architecture)
3. [Infrastructure as Code](#3-infrastructure-as-code)
4. [Monitoring et Alertes](#4-monitoring-et-alertes)
5. [Agent de Diagnostic](#5-agent-de-diagnostic)
6. [Agent de Remédiation](#6-agent-de-remédiation)
7. [Anti-Flapping](#7-anti-flapping)
8. [Tests et Validation](#8-tests-et-validation)
9. [Résultats](#9-résultats)
10. [Améliorations Futures](#10-améliorations-futures)

---

## 1. Contexte et Objectifs

### Problématique
Les incidents d'infrastructure (CPU élevé, erreurs 5xx, crashes de service) nécessitent une intervention manuelle qui peut être longue et source d'erreurs humaines.

### Objectif
Créer un **agent DevOps autonome** capable de :
- Détecter automatiquement les problèmes via CloudWatch
- Diagnostiquer la cause racine
- Exécuter des actions de remédiation automatiques
- Éviter les boucles infinies (anti-flapping)

### Périmètre
- Infrastructure AWS (VPC, EC2, ALB, RDS)
- Monitoring CloudWatch
- Automatisation via Lambda et SSM
- Sécurité (IAM moindre privilège)

---


## 2. Architecture

### Diagramme global
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  CloudWatch     │────▶│  SNS Topic      │────▶│  Lambda         │
│  Alarms         │     │  agent-devops   │     │  Ingestion      │
│  (CPU, 5xx)     │     │  -alarms        │     │  (Diagnostic)   │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
│
┌──────────────────────┘
│ (invoke via boto3)
▼
┌─────────────────┐
│  Lambda         │
│  Remediation    │
│  (Anti-Flapping │
│   + SSM/API)    │
└────────┬────────┘
│
┌─────────────┼─────────────┐
▼             ▼             ▼
┌─────────┐   ┌─────────┐   ┌─────────┐
│  ASG    │   │  SSM    │   │DynamoDB │
│ Scale Up│   │ Restart │   │  Lock   │
│  API    │   │Rollback │   │  TTL    │
└─────────┘   └─────────┘   └─────────┘

### Composants

| Composant | Service AWS | Rôle |
|-----------|-------------|------|
| VPC | AWS VPC | Réseau isolé (10.0.0.0/16) |
| EC2 | Auto Scaling Group | Instances web (1-3, t3.micro) |
| ALB | Application Load Balancer | Distribution du trafic HTTP |
| RDS | MySQL db.t3.micro | Base de données |
| CloudWatch | Metric Alarms | Surveillance CPU et erreurs 5xx |
| SNS | Topic | Notification des alarmes |
| Lambda | Python 3.11 | Logique métier (diagnostic + remédiation) |
| DynamoDB | Table on-demand | Lock anti-flapping avec TTL |
| SSM | Documents | Commandes de remédiation |
| IAM | Roles + Policies | Sécurité moindre privilège |

---

## 3. Infrastructure as Code

### Terraform
Toute l'infrastructure est gérée via Terraform (`infra/main.tf`) :

- **39 ressources** déployées
- **0 duplication**
- **State local** (peut être migré vers S3 pour la collaboration)

### Ressources principales

| Ressource | Nom | Type |
|-----------|-----|------|
| VPC | agent-devops-vpc | aws_vpc |
| ALB | agent-devops-alb-v2 | aws_lb |
| ASG | agent-devops-asg | aws_autoscaling_group |
| RDS | agent-devops-db-2 | aws_db_instance |
| Lambda Ingestion | agent-devops-ingestion | aws_lambda_function |
| Lambda Remediation | agent-devops-remediation | aws_lambda_function |
| DynamoDB | agent-devops-remediation-locks | aws_dynamodb_table |
| SSM Documents | agent-devops-* | aws_ssm_document |

---

## 4. Monitoring et Alertes

### Alarmes CloudWatch

| Alarme | Métrique | Seuil | Période |
|--------|----------|-------|---------|
| agent-devops-cpu-high | CPUUtilization | > 80% | 5 minutes |
| agent-devops-error-rate | HTTPCode_Target_5XX_Count | > 5 | 2 minutes |

### Notifications
Les alarmes publient sur le topic SNS `agent-devops-alarms`, qui déclenche la Lambda Ingestion.

---

## 5. Agent de Diagnostic (Lambda Ingestion)

### Fonctionnement
1. Reçoit l'événement SNS (alarme CloudWatch)
2. Extrait le nom de l'alarme et l'instance/ASG
3. Simule un diagnostic basé sur le type d'alarme

### Catégories de diagnostic

| Type d'alarme | Catégorie | Confiance |
|---------------|-----------|-----------|
| CPU élevé | CPU_OVERLOAD | HIGH |
| Erreurs 5xx | DEPLOYMENT_ERROR | MEDIUM |
| Autre | SERVICE_CRASH | MEDIUM |

### Mode démo
En attendant l'activation de Bedrock (quota atteint), le diagnostic est simulé par règles.

---

## 6. Agent de Remédiation (Lambda Remediation)

### Whitelist d'actions

| Diagnostic | Action | Description | Implémentation |
|------------|--------|-------------|--------------|
| CPU_OVERLOAD | scale_up_asg | Augmenter ASG à 3 | API ASG directe |
| SERVICE_CRASH | restart_service | Redémarrer nginx | SSM Document |
| DEPLOYMENT_ERROR | rollback_deployment | Git rollback + restart | SSM Document |

### Sécurité
- **Whitelist stricte** : seules les actions définies sont autorisées
- **IAM moindre privilège** : chaque Lambda a uniquement les permissions nécessaires

---

## 7. Anti-Flapping

### Problème
Sans protection, une alarme persistante pourrait déclencher des actions en boucle infinie.

### Solution : Lock DynamoDB avec TTL

| Attribut | Type | Description |
|----------|------|-------------|
| instance_id | String (clé) | Identifiant de l'instance/ASG |
| ttl_timestamp | Number | Timestamp d'expiration (Unix) |
| created_at | String | Date de création ISO 8601 |
| action | String | Action effectuée |

### Fonctionnement
1. Avant chaque action, vérifier si un lock existe
2. Si lock actif (< 10 min) → **bloquer** (HTTP 429)
3. Si pas de lock → exécuter l'action + créer le lock (TTL 600s)

---

## 8. Tests et Validation

### Test 1 : Diagnostic simulé
- **Entrée** : Alarme CPU élevé
- **Sortie** : `CPU_OVERLOAD`, confiance `HIGH`
- **Résultat** : ✅

### Test 2 : Anti-flapping
- **1er appel** : Action exécutée, lock créé
- **2ème appel** (même instance) : Bloqué, cooldown actif
- **Résultat** : ✅

### Test 3 : Orchestration complète
- **Chaîne** : CloudWatch → SNS → Ingestion → Remediation → ASG API
- **Résultat** : `DesiredCapacity` passé de 2 à 3
- **Résultat** : ✅

---

## 9. Résultats

### Ce qui fonctionne

| Fonctionnalité | Statut | Preuve |
|----------------|--------|--------|
| Infrastructure Terraform | ✅ | 39 ressources déployées |
| Monitoring CloudWatch | ✅ | 2 alarmes actives |
| Lambda Ingestion | ✅ | Diagnostic simulé fonctionnel |
| Lambda Remediation | ✅ | Whitelist + anti-flapping |
| DynamoDB Lock | ✅ | TTL 10 minutes |
| ASG Scale Up | ✅ | DesiredCapacity=3 confirmé |
| IAM Sécurisé | ✅ | Moindre privilège |

### Architecture déployée
Région: us-east-1
Compte: 718897321963
VPC: agent-devops-vpc (10.0.0.0/16)
├── Subnet public-1 (10.0.1.0/24) - us-east-1a
├── Subnet public-2 (10.0.2.0/24) - us-east-1b
├── ALB: agent-devops-alb-v2
├── ASG: agent-devops-asg (min=1, max=3, desired=2→3)
├── RDS: agent-devops-db-2 (MySQL 8.0)
└── Security Group: ports 22, 80, 443
Serverless:
├── Lambda: agent-devops-ingestion
├── Lambda: agent-devops-remediation
├── DynamoDB: agent-devops-remediation-locks
└── SNS: agent-devops-alarms
SSM:
├── agent-devops-restart-service
├── agent-devops-scale-up
└── agent-devops-rollback

---

## 10. Améliorations Futures

### Court terme
| Amélioration | Description | Complexité |
|--------------|-------------|------------|
| Bedrock (Claude 3) | Diagnostic IA intelligent au lieu de règles | Moyenne |
| SSM Agent sur instances | Installer l'agent pour exécuter restart/rollback | Faible |
| Tests restart/rollback | Valider les documents SSM sur instances réelles | Moyenne |

### Moyen terme
| Amélioration | Description | Complexité |
|--------------|-------------|------------|
| API Gateway | Exposer l'agent via REST API | Moyenne |
| Dashboard web | Interface de monitoring | Élevée |
| Multi-région | Déploiement sur us-west-2 | Élevée |

### Budget estimé
| Service | Coût mensuel |
|---------|-------------|
| EC2 (t3.micro, Free Tier) | $0 |
| RDS (db.t3.micro, Free Tier) | $0 |
| ALB | ~$0-5 |
| Lambda (faible usage) | ~$0 |
| DynamoDB (on-demand) | ~$0 |
| Bedrock (quand activé) | ~$1-5 |
| **Total** | **~$0-10/mois** |

---

## Conclusion

Ce projet démontre la mise en place d'un **agent DevOps autonome** capable de détecter, diagnostiquer et remédier aux incidents d'infrastructure AWS. L'architecture serverless (Lambda) combinée à l'Infrastructure as Code (Terraform) offre une solution scalable, sécurisée et économique.

Les tests end-to-end confirment le bon fonctionnement de la chaîne complète, de la détection CloudWatch à l'action de remédiation via l'API ASG.

---

*Rapport généré le 19 juillet 2026*
