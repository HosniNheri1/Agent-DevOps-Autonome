"""
Lambda Ingestion — Déclenchée par SNS
Analyse l'alerte, fait un diagnostic, puis appelle la Lambda Remediation
"""

import json
import boto3

def lambda_handler(event, context):
    """
    Lambda déclenchée par SNS quand une alarme CloudWatch se déclenche.
    MODE DEMO : Diagnostic simulé (Bedrock quota atteint)
    """
    
    print("=" * 50)
    print("AGENT DEVOPS — INGESTION")
    print("=" * 50)
    print("Event recu:")
    print(json.dumps(event, indent=2))
    
    # Parser le message SNS
    sns_message = event.get('Records', [{}])[0].get('Sns', {})
    message = sns_message.get('Message', '{}')
    
    try:
        alarm_data = json.loads(message)
    except:
        alarm_data = {"raw_message": message}
    
    # Extraire les informations
    alarm_name = alarm_data.get('AlarmName', 'Unknown')
    instance_id = alarm_data.get('Trigger', {}).get('Dimensions', [{}])[0].get('value', 'Unknown')
    
    print(f"\nAlarme: {alarm_name}")
    print(f"Instance: {instance_id}")
    
    # MODE DEMO : Diagnostic simulé basé sur le nom de l'alarme
    if 'cpu' in alarm_name.lower():
        diagnosis = {
            "category": "CPU_OVERLOAD",
            "confidence": "HIGH",
            "summary": f"Alerte CPU detectee sur {instance_id}. Charge processeur > 80% pendant 5 minutes.",
            "root_cause": "Processus consommateur de CPU detecte"
        }
    elif 'error' in alarm_name.lower() or '5xx' in alarm_name.lower():
        diagnosis = {
            "category": "DEPLOYMENT_ERROR",
            "confidence": "MEDIUM",
            "summary": f"Taux d'erreur 5xx eleve detecte sur {instance_id}.",
            "root_cause": "Deploiement defectueux probable"
        }
    else:
        diagnosis = {
            "category": "SERVICE_CRASH",
            "confidence": "MEDIUM",
            "summary": f"Probleme de service detecte sur {instance_id}.",
            "root_cause": "Service non repondant"
        }
    
    print(f"\nDiagnostic: {diagnosis['category']} - {diagnosis['confidence']}")
    
    # === APPELER LA LAMBDA REMEDIATION ===
    print("\nAppel de la Lambda Remediation...")
    
    remediation_payload = {
        "diagnosis": diagnosis,
        "instance_id": instance_id
    }
    
    # Invoquer la Lambda remediation
    lambda_client = boto3.client('lambda', region_name='us-east-1')
    
    try:
        response = lambda_client.invoke(
            FunctionName='agent-devops-remediation',
            InvocationType='RequestResponse',  # Attendre la réponse
            Payload=json.dumps(remediation_payload)
        )
        
        # Lire la réponse
        response_payload = json.loads(response['Payload'].read())
        print(f"Reponse Remediation: {json.dumps(response_payload, indent=2)}")
        
        remediation_status = response_payload.get('statusCode', 500)
        
    except Exception as e:
        print(f"Erreur appel Remediation: {e}")
        remediation_status = 500
        response_payload = {"error": str(e)}
    
    # Retourner le résultat complet
    return {
        'statusCode': 200,
        'body': json.dumps({
            'phase': 'ingestion_complete',
            'alarm_name': alarm_name,
            'instance_id': instance_id,
            'diagnosis': diagnosis,
            'remediation_status': remediation_status,
            'remediation_result': response_payload
        })
    }