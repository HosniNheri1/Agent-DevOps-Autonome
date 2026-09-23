"""
Prompt Engineering - Itération 2
Prompt amélioré avec exemples few-shot
"""

import json

def test_prompt_v2():
    """
    Deuxième prompt - avec exemples few-shot pour guider Claude
    """
    
    alarm_name = "agent-devops-cpu-high"
    alarm_description = "CPU > 80% pendant 5 minutes"
    instance_id = "i-1234567890abcdef0"
    
    logs = """
    [2026-07-19 10:00:01] CPU usage: 45%
    [2026-07-19 10:01:15] CPU usage: 67%
    [2026-07-19 10:02:30] CPU usage: 89%
    [2026-07-19 10:03:45] CPU usage: 95%
    [2026-07-19 10:04:00] Process python_app consuming 85% CPU
    [2026-07-19 10:05:00] Memory usage: 72%
    """
    
    prompt = f"""Tu es un expert DevOps senior spécialisé en diagnostic d'infrastructure cloud.

CONTEXTE:
- Tu analyses des alertes AWS CloudWatch
- Tu diagnostiques des problèmes sur des instances EC2
- Tu dois être précis et concis

ALERTE À ANALYSER:
Nom: {alarm_name}
Description: {alarm_description}
Instance: {instance_id}

LOGS SYSTÈME:
{logs}

EXEMPLES DE DIAGNOSTICS:

Exemple 1 - CPU_OVERLOAD:
Input: CPU 95%, process python_app 85%
Output: {{
    "category": "CPU_OVERLOAD",
    "confidence": "HIGH",
    "summary": "Processus python_app consommant 85% CPU détecté",
    "root_cause": "Boucle infinie ou charge de travail excessive"
}}

Exemple 2 - SERVICE_CRASH:
Input: Service nginx stopped, port 80 closed
Output: {{
    "category": "SERVICE_CRASH",
    "confidence": "HIGH",
    "summary": "Service nginx arrêté, port 80 inaccessible",
    "root_cause": "Crash du service suite à une erreur de configuration"
}}

Exemple 3 - DEPLOYMENT_ERROR:
Input: 500 errors after deployment v2.1
Output: {{
    "category": "DEPLOYMENT_ERROR",
    "confidence": "MEDIUM",
    "summary": "Erreurs 500 après déploiement v2.1",
    "root_cause": "Bug introduit dans la nouvelle version"
}}

INSTRUCTIONS:
1. Analyse les logs fournis
2. Choisis la catégorie la plus appropriée
3. Sois précis dans le root_cause
4. Réponds UNIQUEMENT en JSON valide

RÉPONSE:
"""
    
    print("=== PROMPT V2 (Few-Shot) ===")
    print(prompt)
    print("\n" + "="*50 + "\n")
    
    print("Avantages de V2:")
    print("- Exemples few-shot pour guider le modèle")
    print("- Contexte DevOps plus précis")
    print("- Format JSON strictement demandé")
    
    return prompt

if __name__ == "__main__":
    test_prompt_v2()