#!/usr/bin/env bash
# Provision (or re-use) the Windows Server 2025 EC2 instance for spec 01.
# Idempotent: re-running re-uses the key pair, security group and instance if they exist,
# and re-points the SSH ingress rule at this Mac's current public IP.
set -euo pipefail
source "$(dirname "$0")/config.sh"
TAGS='{Key=Project,Value=nuget-harness}'

# 1. SSH key (ed25519, outside the project folder). The key pair is imported into EC2 for the
#    record, but it is not attached to the instance: EC2 rejects ED25519 on Windows AMIs.
if [[ ! -f "${KEY_PATH}" ]]; then
  ssh-keygen -t ed25519 -N "" -C nuget-harness -f "${KEY_PATH}" -q
  log "generated ${KEY_PATH}"
fi
if ! aws ec2 describe-key-pairs "${AWSP[@]}" --key-names "${KEY_NAME}" >/dev/null 2>&1; then
  aws ec2 import-key-pair "${AWSP[@]}" --key-name "${KEY_NAME}" \
    --public-key-material "fileb://${KEY_PATH}.pub" \
    --tag-specifications "ResourceType=key-pair,Tags=[${TAGS}]" --output text --query KeyPairId
  log "imported key pair ${KEY_NAME}"
fi

# 2. Security group: inbound TCP 22 from this Mac's IP only.
MYIP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
VPC_ID="$(aws ec2 describe-vpcs "${AWSP[@]}" --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)"
SG_ID="$(aws ec2 describe-security-groups "${AWSP[@]}" --filters Name=group-name,Values="${SG_NAME}" Name=vpc-id,Values="${VPC_ID}" --query 'SecurityGroups[0].GroupId' --output text)"
if [[ "${SG_ID}" == "None" ]]; then
  SG_ID="$(aws ec2 create-security-group "${AWSP[@]}" --group-name "${SG_NAME}" --vpc-id "${VPC_ID}" \
    --description "nuget-harness: SSH from operator IP only" \
    --tag-specifications "ResourceType=security-group,Tags=[${TAGS}]" --query GroupId --output text)"
  log "created security group ${SG_ID}"
fi
# Remove every existing inbound rule, then add exactly one: tcp/22 from MYIP/32.
EXISTING="$(aws ec2 describe-security-group-rules "${AWSP[@]}" --filters Name=group-id,Values="${SG_ID}" \
  --query 'SecurityGroupRules[?IsEgress==`false`].SecurityGroupRuleId' --output text)"
if [[ -n "${EXISTING}" && "${EXISTING}" != "None" ]]; then
  aws ec2 revoke-security-group-ingress "${AWSP[@]}" --group-id "${SG_ID}" --security-group-rule-ids ${EXISTING} >/dev/null
fi
aws ec2 authorize-security-group-ingress "${AWSP[@]}" --group-id "${SG_ID}" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${MYIP}/32,Description=operator-mac}]" \
  --tag-specifications "ResourceType=security-group-rule,Tags=[${TAGS}]" >/dev/null
log "security group ${SG_ID}: inbound tcp/22 from ${MYIP}/32 only"
echo "${SG_ID}" > "${STATE_DIR}/sg-id"

# 3. Instance (re-use a non-terminated one with our Name tag).
IID="$(aws ec2 describe-instances "${AWSP[@]}" \
  --filters Name=tag:Name,Values="${INSTANCE_NAME}" Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)"
if [[ "${IID}" == "None" ]]; then
  AMI_ID="$(aws ssm get-parameter "${AWSP[@]}" --name "${AMI_PARAM}" --query Parameter.Value --output text)"
  ROOT_DEV="$(aws ec2 describe-images "${AWSP[@]}" --image-ids "${AMI_ID}" --query 'Images[0].RootDeviceName' --output text)"
  # Render user-data with the public key (ED25519 key pairs can't be attached to Windows AMIs).
  PUBKEY="$(cat "${KEY_PATH}.pub")"
  sed "s|__SSH_PUBLIC_KEY__|${PUBKEY}|" "${HARNESS_ROOT}/scripts/userdata.ps1" > "${STATE_DIR}/userdata.rendered.ps1"
  log "launching ${INSTANCE_TYPE} from ${AMI_ID} (root ${ROOT_DEV}, ${ROOT_GB} GB gp3)"
  IID="$(aws ec2 run-instances "${AWSP[@]}" \
    --image-id "${AMI_ID}" --instance-type "${INSTANCE_TYPE}" --count 1 \
    --security-group-ids "${SG_ID}" \
    --instance-initiated-shutdown-behavior stop \
    --metadata-options HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=1 \
    --block-device-mappings "DeviceName=${ROOT_DEV},Ebs={VolumeSize=${ROOT_GB},VolumeType=gp3,DeleteOnTermination=true,Encrypted=true}" \
    --user-data "file://${STATE_DIR}/userdata.rendered.ps1" \
    --tag-specifications "ResourceType=instance,Tags=[${TAGS},{Key=Name,Value=${INSTANCE_NAME}}]" \
                         "ResourceType=volume,Tags=[${TAGS},{Key=Name,Value=${INSTANCE_NAME}-root}]" \
                         "ResourceType=network-interface,Tags=[${TAGS}]" \
    --query 'Instances[0].InstanceId' --output text)"
  echo "${AMI_ID}" > "${STATE_DIR}/ami-id"
  log "launched ${IID}"
else
  STATE="$(aws ec2 describe-instances "${AWSP[@]}" --instance-ids "${IID}" --query 'Reservations[0].Instances[0].State.Name' --output text)"
  if [[ "${STATE}" == "stopped" ]]; then
    aws ec2 start-instances "${AWSP[@]}" --instance-ids "${IID}" >/dev/null
    log "started existing ${IID}"
  fi
fi
echo "${IID}" > "${STATE_DIR}/instance-id"
aws ec2 wait instance-running "${AWSP[@]}" --instance-ids "${IID}"
log "running: ${IID} at $(instance_ip)"

# 4. Wait for SSH (user-data enables it on first boot; can take several minutes).
for i in $(seq 1 60); do
  if rsh 'Write-Output ssh-ok' 2>/dev/null | grep -q ssh-ok; then log "ssh ready"; exit 0; fi
  sleep 20
done
log "ssh did not come up; see: aws ec2 get-console-output --instance-id ${IID} --latest"
exit 1
