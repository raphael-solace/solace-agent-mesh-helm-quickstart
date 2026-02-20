#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/configs"
mkdir -p "${OUT_DIR}"

write_agent_config() {
  local slug="$1"
  local app_name="$2"
  local display_name="$3"
  local vendor="$4"
  local skill_id="$5"
  local skill_name="$6"
  local card_description="$7"
  local t1="$8"
  local t2="$9"
  local t3="${10}"
  local t4="${11}"

  cat > "${OUT_DIR}/${slug}.yaml" <<YAML
log:
  stdout_log_level: INFO
  log_file_level: DEBUG
  log_file: "${app_name}.log"

apps:
  - name: "${app_name}"
    app_base_path: "."
    app_module: "solace_agent_mesh.agent.sac.app"
    broker:
      dev_mode: \${SOLACE_DEV_MODE, false}
      broker_url: \${SOLACE_BROKER_URL, ws://localhost:8080}
      broker_username: \${SOLACE_BROKER_USERNAME, default}
      broker_password: \${SOLACE_BROKER_PASSWORD, default}
      broker_vpn: \${SOLACE_BROKER_VPN, default}
      temporary_queue: \${USE_TEMPORARY_QUEUES, true}

    app_config:
      namespace: "\${NAMESPACE}"
      supports_streaming: true
      agent_name: "${display_name}"
      display_name: "${display_name}"
      instruction: |
        You are ${display_name}.
        Primary enterprise system: ${vendor}.

        Core responsibilities:
        - ${t1}
        - ${t2}
        - ${t3}
        - ${t4}

        Operating rules:
        - Use connected enterprise tools and uploaded artifacts first.
        - If the required ${vendor} connector is unavailable, explicitly state the missing integration and proceed with user-provided data only.
        - Do not fabricate records, KPIs, IDs, approvals, or outcomes.
        - Return actionable outputs with owners, due dates, assumptions, and risk level.

      model:
        model: "\${LLM_SERVICE_GENERAL_MODEL_NAME}"
        api_base: "\${LLM_SERVICE_ENDPOINT}"
        api_key: "\${LLM_SERVICE_API_KEY}"

      tools:
        - tool_type: builtin-group
          group_name: "data_analysis"
        - tool_type: builtin-group
          group_name: "web"

      session_service:
        type: \${PERSISTENCE_TYPE, sql}
        database_url: \${DATABASE_URL, sqlite:///${app_name}.db}
        default_behavior: PERSISTENT

      artifact_service:
        type: \${ARTIFACT_SERVICE_TYPE, s3}
        bucket_name: \${S3_BUCKET_NAME}
        endpoint_url: \${S3_ENDPOINT_URL}
        aws_region: \${AWS_REGION, us-east-1}
        artifact_scope: namespace

      artifact_handling_mode: reference
      enable_embed_resolution: true
      enable_artifact_content_instruction: true

      agent_card:
        description: "${card_description}"
        defaultInputModes: ["text", "file"]
        defaultOutputModes: ["text", "file"]
        skills:
          - id: "${skill_id}"
            name: "${skill_name}"
            description: "${card_description}"

      agent_card_publishing:
        interval_seconds: 15

      agent_discovery:
        enabled: false

      inter_agent_communication:
        allow_list: []
        request_timeout_seconds: 30
YAML
}

write_agent_config \
  "crm-revenue" \
  "crm_revenue_agent" \
  "CRM Revenue Agent" \
  "Salesforce" \
  "crm_revenue_ops" \
  "Revenue Operations" \
  "Manages lead-to-revenue execution with account and pipeline intelligence." \
  "Manage lead-to-opportunity progression and stage hygiene." \
  "Track account health signals and churn or expansion indicators." \
  "Produce pipeline forecasts with confidence ranges and key assumptions." \
  "Generate next-best-action prompts for sellers and revenue leaders."

write_agent_config \
  "hr-people" \
  "hr_people_agent" \
  "HR People Agent" \
  "Workday" \
  "hr_people_operations" \
  "People Operations" \
  "Supports hiring, onboarding, policy, and workforce change operations." \
  "Coordinate hiring and onboarding workflows across recruiters, managers, and HR." \
  "Answer policy questions with source-backed guidance and escalation paths." \
  "Route PTO and benefits requests to the correct process owner." \
  "Manage organization changes and approval checkpoints with clear audit notes."

write_agent_config \
  "eng-product" \
  "eng_product_agent" \
  "Engineering Product Agent" \
  "GitHub" \
  "engineering_delivery" \
  "Engineering Delivery" \
  "Supports software delivery workflows from PR review through incident triage." \
  "Provide PR review assistance with focused quality and risk comments." \
  "Triage issues by severity, ownership, and customer impact." \
  "Draft release notes from merged changes and linked tickets." \
  "Assist CI or CD failure triage with likely root causes and next checks."

write_agent_config \
  "legal-counsel" \
  "legal_counsel_agent" \
  "Legal Counsel Agent" \
  "Harvey" \
  "legal_operations" \
  "Legal Operations" \
  "Handles contract intake, clause analysis, and legal approval routing." \
  "Intake contracts and extract key obligations, terms, and dates." \
  "Score clause risk based on policy and precedent alignment." \
  "Route contracts to approvers with concise legal rationale." \
  "Maintain an auditable trail of recommendations and final decisions."

write_agent_config \
  "news-strategy" \
  "news_strategy_agent" \
  "News Strategy Agent" \
  "Perplexity" \
  "market_intelligence" \
  "Market Intelligence" \
  "Tracks competitor and supply chain intelligence for strategic planning." \
  "Monitor competitor moves and relevant strategic announcements." \
  "Track supply chain headlines with likely operational and margin impact." \
  "Summarize signals by region and business unit for leadership review." \
  "Flag high-priority shifts requiring immediate response or scenario planning."

write_agent_config \
  "fin-finance" \
  "fin_finance_agent" \
  "Finance Agent" \
  "SAP" \
  "finance_operations" \
  "Finance Operations" \
  "Supports close, spend governance, and forward-looking finance controls." \
  "Coordinate month-end close tasks with owners, dependencies, and deadlines." \
  "Categorize spend patterns and detect policy or budget anomalies." \
  "Compare budget versus actuals and isolate main variance drivers." \
  "Identify forecast deltas early and issue actionable alerts."

write_agent_config \
  "ops-operations" \
  "ops_operations_agent" \
  "Operations Agent" \
  "n8n" \
  "operations_playbooks" \
  "Operations Playbooks" \
  "Automates incident playbooks across inventory, logistics, and escalation flows." \
  "Run incident playbooks for inventory exceptions and stock imbalances." \
  "Handle shipment delay triage with escalation triggers and updates." \
  "Coordinate escalation paths across support, logistics, and account teams." \
  "Send operational notifications with clear status, impact, and next actions."

write_agent_config \
  "cx-customer" \
  "cx_customer_agent" \
  "Customer Experience Agent" \
  "Zendesk" \
  "customer_support_orchestration" \
  "Customer Support Orchestration" \
  "Improves support operations with SLA-aware routing and escalation control." \
  "Classify incoming tickets by intent, urgency, and customer tier." \
  "Route tickets using SLA, entitlement, and team ownership rules." \
  "Draft suggested responses using known issue context and tone guidance." \
  "Escalate high-risk cases to operations or legal with structured context."

write_agent_config \
  "esg-sustainability" \
  "esg_sustainability_agent" \
  "ESG Sustainability Agent" \
  "Microsoft Fabric" \
  "esg_reporting" \
  "ESG Reporting" \
  "Produces ESG analytics, disclosures, and stakeholder-ready reporting packs." \
  "Aggregate ESG datasets across energy, travel, procurement, and operations." \
  "Estimate carbon impacts with transparent assumptions and boundaries." \
  "Generate disclosure-ready reporting packs with traceable metrics." \
  "Prepare stakeholder summaries with risk flags and remediation priorities."

write_agent_config \
  "factory-manufacturing" \
  "factory_manufacturing_agent" \
  "Factory Manufacturing Agent" \
  "AWS IoT" \
  "manufacturing_intelligence" \
  "Manufacturing Intelligence" \
  "Monitors factory telemetry to reduce downtime and optimize maintenance." \
  "Detect sensor anomalies and rank events by probable production impact." \
  "Recommend preventive maintenance schedules from runtime and fault trends." \
  "Alert on spare parts risk using usage velocity and lead-time constraints." \
  "Estimate downtime risk and propose mitigation actions by line or plant."

echo "Generated agent configs in ${OUT_DIR}"
