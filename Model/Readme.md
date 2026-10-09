# KilnWatch

> **From satellite imagery to an inspection plan someone can use tomorrow.**

KilnWatch is an AWS-native monitoring and compliance-support platform for brick kilns around Delhi. It uses free Sentinel-2 satellite imagery to find likely kilns, measures their proximity to rules-relevant places, estimates nearby population exposure, and gives inspectors a clear, evidence-backed plan for what to verify on site.

It is being built for the **WeMakeDevs × AWS Bharat Builds Tour — Environmental Hacks**.

## Why KilnWatch?

Brick kilns are a significant but difficult-to-monitor source of air pollution across the Delhi airshed. They are seasonal, dispersed across rural land, and too numerous for inspection teams to find and visit efficiently.

The rules already exist. The operational gap is knowing:

- where every kiln is;
- which locations may breach siting or technology requirements;
- who may be exposed; and
- which sites deserve an inspector's attention first.

KilnWatch closes that gap without treating a model prediction as a legal decision.

| KilnWatch does | KilnWatch does not do |
| --- | --- |
| Detect likely kiln footprints from satellite imagery | Declare a kiln illegal |
| Measure distances against versioned rules | Replace a field inspection |
| Rank sites using exposure and evidence | Change a legal status automatically |
| Create a review and inspection workflow | Present model output as final fact |

## The idea in one line

**The model finds. Code checks. Agents plan. People decide.**

```text
Sentinel-2 imagery
        ↓
Vision model detects likely kilns
        ↓
Rules engine measures distances and records evidence
        ↓
Review queue and inspection planner prioritise action
        ↓
Inspector verifies on site
        ↓
Verdict becomes a training signal for the next model version
```

## What we are building

The first deployment focuses on the Uttar Pradesh side of the National Capital Region: **Hapur, Ghaziabad, Baghpat, and Meerut**.

### 1. Kiln detection

We train an oriented-object detector on **SentinelKilnDB** to identify kiln footprints and classify likely kiln type:

- Fixed Chimney Bull's Trench Kiln (FCBK)
- Circular FCBK (CFCBK)
- Zigzag kiln

The first model is **YOLO11-OBB**. Oriented boxes matter because kilns sit at every angle; a rotated footprint is more accurate for clusters, proximity checks, and maps than a conventional rectangular box.

### 2. Evidence-based rule checks

For each detection, deterministic geospatial code checks the relevant state and central siting rules. A record contains the measured distance, threshold, legal source, and supporting imagery—not a model-generated judgement.

Examples include proximity to:

- habitation;
- schools;
- other kilns;
- orchards;
- national highways and railway lines; and
- non-attainment cities, where kiln technology requirements may apply.

### 3. Human-centred workflows

KilnWatch serves three users from the same registry:

| Surface | User | Purpose |
| --- | --- | --- |
| Inspector app | Pollution-board and CAQM inspectors | View a ranked route, evidence, and field-verdict form |
| Resident portal | People living near a kiln | Check nearby satellite flags and understand the evidence in Hindi or English |
| Review console | Authorised reviewers | Approve or reject new detections and changes before they update the registry |

All public-facing results are described as **“flagged by satellite, pending inspection.”**

## Current priority

We are deliberately building two tracks in parallel.

### Track A — baseline model training

1. Prepare a selective SentinelKilnDB subset.
2. Run a fast `yolo11s-obb` baseline at 128 px for roughly 20 epochs.
3. Verify labels, preprocessing, paths, and output geometry.
4. Store weights, configuration, metrics, and dataset version in Amazon S3.
5. Move to the larger training run only after the baseline is trustworthy.

The baseline is a **pipeline check**, not our final accuracy claim.

### Track B — app development

Build the inspector experience against mock kiln records first:

1. Map and ranked daily inspection route
2. Kiln detail card with before/after evidence
3. Flagged-rule explanation with measured distances
4. Field verdict form with photos and notes
5. Reviewer workflow for approving or rejecting changes

This means UI work never waits for model training, and the model later has a clear output contract to satisfy.

## AWS architecture

```text
                         TRAIN ONCE
 SentinelKilnDB ──► SageMaker Training ──► S3 model artefacts

                    PROCESS EACH NEW SCENE
 Earth Search / Sentinel-2 ──► Lambda filter ──► Step Functions
                                                    │
                              ┌─────────────────────┼─────────────────────┐
                              ▼                     ▼                     ▼
                       Fargate inference      Rules engine          Bedrock triage
                       tile + detect + merge  PostGIS distances     review queue only
                              │                     │                     │
                              └─────────────────────┴──────────┬──────────┘
                                                                 ▼
                                    S3 evidence + RDS PostgreSQL / PostGIS
                                                                 │
                              ┌──────────────────────────────────┼──────────────────────────────────┐
                              ▼                                  ▼                                  ▼
                    Inspector app                        Resident portal                    Review console
                    SwiftUI + MapKit                     Amplify Hosting                    authorised users
```

| Layer | AWS services | Responsibility |
| --- | --- | --- |
| Training | SageMaker, S3 | Reproducible model training and versioned artefacts |
| Ingestion | SNS, Lambda | Identify new, low-cloud scenes covering the target area |
| Workflow | Step Functions | Retries, orchestration, and visible pipeline state |
| Compute | Fargate | Containerised tiling, inference, merging, and rules evaluation |
| Registry | RDS PostgreSQL + PostGIS | Kilns, spatial queries, violations, review queue, and audit data |
| Evidence | S3, CloudFront | Image patches and immutable evidence links |
| API and identity | API Gateway, Lambda, Cognito | App APIs and sign-in |
| Authorisation | Amazon Verified Permissions | District- and role-scoped access with Cedar policies |
| Planning and explanation | Amazon Bedrock, Strands Agents SDK | Read-only planning, triage, and plain-language explanations |
| Maps | Amazon Location Service | Road-distance estimates for inspection routes |
| Operations | CloudWatch | Logs, metrics, alarms, and demo health |

## A record that can be trusted

The kiln record is the contract between the model, rules engine, agents, and applications.

```json
{
  "kiln_id": "KW-0412",
  "footprint": "oriented GeoJSON polygon",
  "type": "FCBK",
  "detection_confidence": 0.82,
  "first_seen": "2026-10-01",
  "last_seen": "2026-10-06",
  "violations": [
    {
      "rule_id": "C-HAB-800",
      "measured_distance_m": 410,
      "threshold_m": 800,
      "legal_source": "versioned rule citation",
      "evidence_url": "evidence image link"
    }
  ],
  "exposure": {
    "people_within_800m": 6240
  },
  "status": "flagged"
}
```

Only an inspector verdict or an approved human review may change the status. Agents cannot do so.

## Agent guardrails

Language models are useful for planning, summarising, and explaining—not for measuring distances or deciding compliance. KilnWatch keeps ground truth in geospatial code and structured data.

Every agent:

- receives typed, narrowly scoped tools;
- has read-only access, except for adding an item to a review queue;
- must cite existing `kiln_id` and `rule_id` values in any claim;
- cannot record a field verdict or alter a kiln’s legal status; and
- is checked by deterministic validation before an answer is shown.

## Data sources

| Source | Use | Notes |
| --- | --- | --- |
| [SentinelKilnDB](https://github.com/rishabh-mondal/SENTINELKILNDB_NeurIPS_2025) | Model training and benchmark comparison | Sentinel-2 tiles and oriented-box labels |
| [Sentinel-2 L2A COGs](https://registry.opendata.aws/sentinel-2-l2a-cogs/) | Fresh imagery | Accessed through Earth Search / AWS Open Data |
| [Meta HRSL](https://registry.opendata.aws/dataforgood-fb-hrsl/) | Population exposure estimates | Used for aggregate proximity estimates |
| OpenStreetMap / Geofabrik | Schools, roads, railways, rivers, and related features | Used as a starting geospatial layer; important features are reviewed |
| Versioned rules JSON | Siting and technology checks | Each threshold carries its source and version |

## Responsible use

KilnWatch is a decision-support tool for a sensitive enforcement context.

- A detection is a satellite-derived signal, not a finding of illegality.
- A likely technology mismatch always requires a site check.
- Confidence, scene date, model version, and supporting evidence remain visible to authorised users.
- Residents see plain-language evidence and a clear “pending inspection” status, never an accusation.
- Field verdicts and review decisions create labels for improvement, including hard negatives.

## Project roadmap

- [ ] Establish S3 data, model, and evidence layout
- [ ] Train and evaluate the selective-data baseline in SageMaker
- [ ] Define PostGIS kiln registry and versioned rule schema
- [ ] Process one Sentinel-2 scene end-to-end through the AWS workflow
- [ ] Build inspector app against mock data
- [ ] Connect app to API Gateway and registry data
- [ ] Implement reviewer approval flow
- [ ] Add the inspection-planner agent with citation validation
- [ ] Add CloudWatch dashboard, alarms, and deployment documentation

## Licence and acknowledgements

KilnWatch credits the authors of SentinelKilnDB and the *Space to Policy* study from the IIT Gandhinagar Sustainability Lab. SentinelKilnDB is licensed **CC BY-NC 4.0**; this project is currently a non-commercial hackathon prototype and must remain within that licence’s terms unless the data strategy changes.

The project also draws on the Environment (Protection) Amendment Rules, 2022 and applicable state siting requirements. Rules are represented as versioned data and verified against their legal source before operational use.

---

Built with the principle that environmental AI should make public action more **visible, evidence-based, and accountable**.
