# Model clauses for an audit conducted in Spain

**English** · [Español](LEGAL_ES.md)

**Informational document, not legal advice.** Audit Workbench clauses are starting templates for technical report writing, not an audit agreement, penetration-testing authorization, NDA, data processing agreement, insurance policy, or generally valid waiver of liability. The auditor must review each clause with the client and, when appropriate, legal counsel.

## General regulatory references (checked October 2026)

- **Regulation (EU) 2016/679 (GDPR):** Article 5 (processing principles), Article 28 (processor, where applicable), Article 32 (security), Articles 33 and 34 (breaches, depending on the circumstances). https://eur-lex.europa.eu/legal-content/ES/ALL/?uri=celex%3A32016R0679
- **Organic Law 3/2018 (LOPDGDD):** Spain's adaptation/supplementation of the GDPR. https://www.boe.es/eli/es/lo/2018/12/05/3/con
- **Spanish Data Protection Agency (AEPD):** agreements between controllers and processors are formalized when their relationship and processing require them, subject to specific requirements; the report template alone is not a substitute. https://www.aepd.es/preguntas-frecuentes/2-tus-obligaciones-como-responsable-del-tratamiento/8-responsable-y-encargado-del-tratamiento/FAQ-0238-cual-seria-el-contenido-del-contrato-de-encargo-de-tratamiento
- **Law 34/2002 (LSSI-CE):** includes provisions on electronic commercial communications; professional delivery of reports by email is not inherently advertising. This does not imply that sending confidential information by email is secure or contractually authorized. https://www.boe.es/eli/es/l/2002/07/11/34/con

Additional sector-specific regulations depend on the organization being assessed (public sector, essential service providers, critical operators, financial institutions, healthcare organizations, etc.). The assistant does not claim ENS, NIS2, DORA, ISO 27001, or CIS compliance by default. Scope, evidence, requirements, applicable interpretation, and legal assessment are needed before making such claims.

## What the agreement and report should cover

1. **Who authorizes:** identification of the authorized person, exact scope by assets/networks/sites, start/end dates, time windows, contacts, rules of engagement, and who handles incidents during testing.
2. **What is not assessed:** exclusions and restrictions, prohibited methods, dependencies/third parties, inherent risks, and the time-bound nature of results.
3. **Data processing:** parties' roles, data categories, purpose, retention, access, technical and organizational measures, subprocessors, international transfers, and required contracts/documentation.
4. **Custody:** where originals and JSON are retained, encryption, restricted access, delivery channels, and agreed return/deletion.
5. **Findings and interpretation:** evidence supporting the risk, unverified controls, false positives/limitations, responsible parties, residual risk, editorial review before delivery, and sign-off.
6. **Incidents and communication:** agreed contacts and process for an incident detected during the audit, without confusing this with statutory notification duties that may apply to either party.

## Rules for using application templates

Under **Clauses and privacy**, seven separate paragraphs can be edited. The application includes them in the PDF report, but **does not indicate that the client has approved them**. Adapt them before each audit. Do not use generic clauses to attempt to exclude liability for intentional wrongdoing, negligence, or legal violations. In particular, confidentiality alone does not authorize personal data processing or exploitation of devices.

Default texts are attached to the audit record and preserved in the backup. If the client has approved an authorization document or agreement, record its reference within the scope and preserve the original separately; storing signatures, keys, or sensitive original documents inside unencrypted JSON is not recommended.
