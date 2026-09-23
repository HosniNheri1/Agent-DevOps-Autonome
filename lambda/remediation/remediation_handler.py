"""
Lambda Remediation - Anti-Flapping + Actions SSM/API ASG
Corrigee : rollback utilise appPath + serviceName
"""

import json
import boto3
import time

# ============================================
# WHITELIST DES ACTIONS AUTORISEES
# ============================================
whitelist_actions = {
    "CPU_OVERLOAD": {
        "action": "scale_up_asg",
        "description": "Augmenter la capacite de l'ASG"
    },
    "SERVICE_CRASH": {
        "action": "restart_service",
        "ssm_document": "agent-devops-restart-service",
        "parameters": {"serviceName": ["nginx"]}
    },
    "DEPLOYMENT_ERROR": {
        "action": "rollback_deployment",
        "ssm_document": "agent-devops-rollback",
        "parameters": {"appPath": ["/var/www/app"], "serviceName": ["nginx"]}
    }
}

# ============================================
# EXECUTION DES ACTIONS
# ============================================
def execute_action(instance_id, document_name, parameters, category):
    """
    Execute une action de remediation.
    - CPU_OVERLOAD : API ASG directe (pas besoin d'instance)
    - Autres : SSM Run Command
    """

    if category == "CPU_OVERLOAD":
        asg = boto3.client('autoscaling', region_name='us-east-1')
        try:
            asg.update_auto_scaling_group(
                AutoScalingGroupName='agent-devops-asg',
                DesiredCapacity=3
            )
            print("ASG scale_up effectue via API - DesiredCapacity=3")
            return "asg-scale-up-direct"
        except Exception as e:
            print("Erreur ASG scale_up: " + str(e))
            return None

    ssm = boto3.client('ssm', region_name='us-east-1')
    try:
        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName=document_name,
            Parameters=parameters,
            TimeoutSeconds=300
        )
        command_id = response['Command']['CommandId']
        print("Commande SSM envoyee: " + command_id)
        return command_id
    except Exception as e:
        print("Erreur SSM: " + str(e))
        return None


# ============================================
# ANTI-FLAPPING : LOCK DYNAMODB
# ============================================
def check_and_create_lock(instance_id, action):
    """
    Verifie si un lock existe. Si non, le cree avec TTL 600s.
    Retourne : (peut_executer: bool, message: str)
    """
    dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
    table = dynamodb.Table('agent-devops-remediation-locks')

    response = table.get_item(Key={'instance_id': instance_id})

    if 'Item' in response:
        lock = response['Item']
        ttl = int(lock.get('ttl_timestamp', 0))
        now = int(time.time())

        if ttl > now:
            remaining = ttl - now
            print("Lock actif pour " + instance_id + " - " + str(remaining) + "s restantes")
            return False, "Cooldown anti-flapping actif - " + str(remaining) + "s restantes"
        else:
            print("Lock expire pour " + instance_id)
    else:
        print("Pas de lock pour " + instance_id)

    ttl_timestamp = int(time.time()) + 600
    table.put_item(Item={
        'instance_id': instance_id,
        'action': action,
        'ttl_timestamp': ttl_timestamp,
        'created_at': time.strftime("%Y-%m-%dT%H:%M:%S")
    })
    print("Lock cree pour " + instance_id + " (expire dans 600s)")
    return True, "Lock cree"


# ============================================
# LAMBDA HANDLER
# ============================================
def lambda_handler(event, context):
    print("=" * 50)
    print("AGENT DE REMEDIATION - Anti-Flapping")
    print("=" * 50)
    print(json.dumps(event, indent=2))

    # --- Extraire le diagnostic (2 formats supportes) ---
    try:
        if 'diagnosis' in event:
            diagnosis = event.get('diagnosis', {})
            instance_id = event.get('instance_id', 'Unknown')
        else:
            body = json.loads(event.get('body', '{}'))
            diagnosis = body.get('diagnosis', {})
            instance_id = body.get('instance_id', 'Unknown')

        category = diagnosis.get('category', 'UNKNOWN')
        confidence = diagnosis.get('confidence', 'LOW')
        summary = diagnosis.get('summary', 'Non specifie')

    except Exception as e:
        print("Erreur extraction diagnostic: " + str(e))
        return {
            'statusCode': 400,
            'body': json.dumps({'status': 'error', 'message': 'Format invalide'})
        }

    print("Diagnostic: " + category)
    print("Instance: " + instance_id)
    print("Confiance: " + confidence)

    # --- Verifier whitelist ---
    if category not in whitelist_actions:
        print("Categorie non autorisee: " + category)
        return {
            'statusCode': 403,
            'body': json.dumps({
                'status': 'blocked',
                'reason': 'Action not in whitelist',
                'category': category
            })
        }

    action_config = whitelist_actions[category]
    print("Action autorisee: " + action_config['action'])

    # --- Anti-Flapping ---
    can_execute, lock_msg = check_and_create_lock(instance_id, action_config['action'])

    if not can_execute:
        return {
            'statusCode': 429,
            'body': json.dumps({
                'status': 'blocked',
                'reason': 'Cooldown anti-flapping actif',
                'message': 'Une remediation a deja ete effectuee recemment. Attendez 10 minutes.',
                'instance_id': instance_id
            })
        }

    # --- Executer l'action ---
    print("Execution de l'action...")

    if category == "CPU_OVERLOAD":
        command_id = execute_action(instance_id, None, None, category)
    else:
        command_id = execute_action(
            instance_id,
            action_config['ssm_document'],
            action_config['parameters'],
            category
        )

    if command_id:
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'remediation_executed',
                'category': category,
                'action': action_config['action'],
                'instance_id': instance_id,
                'ssm_command_id': command_id,
                'cooldown_seconds': 600
            })
        }
    else:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'error',
                'message': 'Echec execution',
                'category': category
            })
        }
