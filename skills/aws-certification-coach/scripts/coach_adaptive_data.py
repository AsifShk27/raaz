#!/usr/bin/env python3
"""Static datasets used by adaptive SAP-C02 coaching."""

LEVEL_LABELS = {
    1: "Basics",
    2: "Foundation+",
    3: "Applied Trade-offs",
    4: "Advanced Constraints",
    5: "Exam Pressure",
}

LEVEL_DESCRIPTION = {
    1: "Concept clarity and first-principles decisions.",
    2: "Service selection with explicit requirement mapping.",
    3: "Trade-off defense across reliability, security, performance, and cost.",
    4: "Multi-account, governance, migration, and failure-mode constraints.",
    5: "Exam-style ambiguity with strict prioritization under time pressure.",
}

KEYWORD_KITS = [
    {
        "keywords": ["network connectivity", "multi-account"],
        "learn": [
            "Start with connectivity intent: isolation boundaries first, routing second.",
            "Pick a hub model only when route ownership and blast radius are clear.",
            "Prove resilience with failover and failback tests, not assumptions.",
        ],
        "scenario": (
            "Design connectivity for 12 AWS accounts and one on-prem data center with strict segmentation."
        ),
        "principle": "Define account/network boundaries before finalizing interconnect services.",
        "first_step": "Map traffic classes and trust boundaries, then choose connectivity patterns.",
        "pitfall": "Adding peering links first and hoping governance can be fixed later.",
        "tradeoff_best": "Use centralized routing for scale, but enforce strict route ownership and inspection.",
        "advanced_best": "Design fault-isolated hubs with tested DX/VPN failover and clear route-domain controls.",
    },
    {
        "keywords": ["security controls", "security"],
        "learn": [
            "Security architecture must include preventive, detective, and response controls.",
            "Apply org-level guardrails first, then account-level least privilege.",
            "Automate evidence generation from day one to reduce audit friction.",
        ],
        "scenario": "Design security controls for a regulated workload spanning 30 AWS accounts.",
        "principle": "Apply preventive controls early and use detective controls for verification and response.",
        "first_step": "Translate compliance requirements into guardrails by identity, data, and network layers.",
        "pitfall": "Relying only on detective alerts without preventive policy boundaries.",
        "tradeoff_best": "Centralize governance while delegating controlled execution to workload accounts.",
        "advanced_best": "Use org-wide guardrails plus centralized telemetry and incident automation across accounts.",
    },
    {
        "keywords": ["business continuity", "reliability", "resilient"],
        "learn": [
            "RTO and RPO define architecture shape; do not reverse this.",
            "Design recovery mechanisms by workload tier, not generic templates.",
            "Operational readiness requires frequent game days and measured recovery.",
        ],
        "scenario": "Build continuity strategy for payments API with RTO 15m and RPO 5m.",
        "principle": "Align architecture choices directly with explicit RTO/RPO targets.",
        "first_step": "Map business impact by component and set recovery targets per tier.",
        "pitfall": "Choosing multi-region before validating operational failover capability.",
        "tradeoff_best": "Balance faster recovery against higher complexity with clear runbooks and ownership.",
        "advanced_best": "Combine automated failover signals with manual override and regular recovery drills.",
    },
    {
        "keywords": ["performance"],
        "learn": [
            "Measure bottlenecks first; optimization without evidence is waste.",
            "Fix data-path inefficiencies before adding raw compute.",
            "Performance changes must preserve reliability and security constraints.",
        ],
        "scenario": "Improve p95 latency for a global API with heavy traffic bursts.",
        "principle": "Base optimization decisions on user-impact metrics and bottleneck evidence.",
        "first_step": "Establish baseline latency/error metrics and isolate the bottleneck component.",
        "pitfall": "Scaling blindly without proving where latency is introduced.",
        "tradeoff_best": "Use targeted caching and data-path tuning before broad horizontal scaling.",
        "advanced_best": "Run canary performance changes with rollback criteria tied to SLO violations.",
    },
    {
        "keywords": ["cost optimization", "cost"],
        "learn": [
            "Treat cost as a design and operations loop, not a one-time cleanup.",
            "Right-size from observed load patterns; avoid static assumptions.",
            "Any savings plan must preserve SLO and security requirements.",
        ],
        "scenario": "Achieve 25% cloud cost reduction without reliability degradation.",
        "principle": "Optimize cost with workload-aware decisions that preserve service objectives.",
        "first_step": "Rank top cost drivers by verified usage and business criticality.",
        "pitfall": "Cutting capacity first without validating performance/reliability impact.",
        "tradeoff_best": "Prioritize waste removal and lifecycle controls before deep architecture rewrites.",
        "advanced_best": "Apply guardrails, anomaly alerts, and periodic optimization reviews for durable savings.",
    },
    {
        "keywords": ["migration", "modernization", "deployment strategy", "new architecture"],
        "learn": [
            "Choose migration approach per workload risk, coupling, and timeline.",
            "Modernize where ROI and risk profile justify change, not everywhere.",
            "Define cutover and rollback gates before production migration waves.",
        ],
        "scenario": "Migrate a legacy monolith within 6 months with strict change windows.",
        "principle": "Use phased, reversible migration waves tied to business risk.",
        "first_step": "Segment workloads by risk and dependency, then define migration waves.",
        "pitfall": "Running a big-bang migration without reversible checkpoints.",
        "tradeoff_best": "Balance migration speed with operational safety using progressive cutovers.",
        "advanced_best": "Use modernization per component with explicit cutover/rollback and post-migration SLO checks.",
    },
]

DEFAULT_KIT = {
    "learn": [
        "Anchor every design decision to explicit requirements.",
        "Create at least two options and compare trade-offs objectively.",
        "Validate outcomes through measurable service-level signals.",
    ],
    "scenario": (
        "Design two architecture options, pick one, and defend cost/reliability/security/performance trade-offs."
    ),
    "principle": "Requirements-first reasoning produces defensible architecture decisions.",
    "first_step": "Clarify business and technical constraints before selecting services.",
    "pitfall": "Service-first choices without explicit requirement mapping.",
    "tradeoff_best": "Choose the option that best satisfies weighted business priorities and failure tolerance.",
    "advanced_best": "Use multi-constraint decision tables with rollback and observability plans.",
}

GENERIC_DISTRACTORS = [
    "Choose services first and infer requirements later.",
    "Optimize only one dimension and defer other risks.",
    "Assume operational readiness if architecture diagram looks complete.",
]

STEP_DISTRACTORS = [
    "Select a favorite service stack and align requirements afterward.",
    "Start by maximizing scale before identifying failure modes.",
    "Copy a previous architecture pattern without workload analysis.",
]

PITFALL_DISTRACTORS = [
    "Documenting assumptions and testing them early.",
    "Mapping ownership before operational handoff.",
    "Using measurable success criteria before rollout.",
]

TRADEOFF_DISTRACTORS = [
    "Pick the cheapest path even if reliability targets are missed.",
    "Pick the highest-performance path even if operations become unmanageable.",
    "Delay trade-off analysis until post-launch incidents.",
]

ADVANCED_DISTRACTORS = [
    "Increase complexity without clarifying operational ownership.",
    "Skip rollback paths because confidence in the design is high.",
    "Treat control-plane and data-plane risks as equivalent.",
]
