"""
Prompt Engineering - Itération 1
Test du prompt pour le diagnostic DevOps avec Claude 3
"""

import json
import boto3

def test_prompt_v1():
    """
    Premier prompt - structure basique
    """
    
    # Simuler une alerte CPU
    alarm_name = "agent-devops-cpu-high"
    alarm_description = "CPU > 80% pendant 5 minutes"
    instance_id = "i-1234567890abcdef0"
    
    # Simuler des logs
    logs = """
    [2026-07-19 10:00:01] CPU usage: 45%
    [2026-07-19 10:01:15] CPU usage: 67%
    [2026-07-19 10:02:30] CPU usage: 89%
    [2026-07-19 10:03:45] CPU usage: 95%
    [2026-07-19 10:04:00] Process python_app consuming 85% CPU
    [2026-07-19 10:05:00] Memory usage: 72%
    """
    
    prompt = f"""Tu es un expert DevOps senior. Analyse cette alerte et ces logs système.

ALERTE: {alarm_name}
DESCRIPTION: {alarm_description}
INSTANCE: {instance_id}

LOGS RÉCENTS:
{logs}

INSTRUCTIONS:
1. Analyse la cause racine du problème
2. Classifie dans UNE SEULE catégorie parmi:
   - CPU_OVERLOAD
   - SERVICE_CRASH
   - DEPLOYMENT_ERROR
   - UNKNOWN

3. Donne un niveau de confiance: HIGH, MEDIUM, ou LOW

4. Résume le diagnostic en 2-3 phrases

Réponds UNIQUEMENT au format JSON suivant (pas de texte avant ou après):
{{
    "category": "NOM_DE_LA_CATEGORIE",
    "confidence": "NIVEAU_DE_CONFIANCE",
    "summary": "Résumé du diagnostic",
    "root_cause": "Cause racine identifiée"
}}
"""
    
    print("=== PROMPT V1 ===")
    print(prompt)
    print("\n" + "="*50 + "\n")
    
    # TODO: Appeler Bedrock quand le quota est rétabli
    print("Mode DEMO - Bedrock quota atteint")
    
    # Simulation de la réponse attendue
    expected_response = {
        "category": "CPU_OVERLOAD",
        "confidence": "HIGH",
        "summary": "Alerte CPU détectée sur l'instance. Le processus python_app consomme 85% du CPU.",
        "root_cause": "Processus python_app en boucle infinie ou pic de trafic"
    }
    
    print("Réponse attendue:")
    print(json.dumps(expected_response, indent=2))
    
    return prompt, expected_response

if __name__ == "__main__":
    test_prompt_v1()