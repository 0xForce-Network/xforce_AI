# xforce_AI Project Memory

## Technical Decisions & Architecture Registry

---

### Decision 1: Hybrid Shell Architecture (Decoupled Runtime and Interface)

#### Description
The system's core orchestration (container entrypoint, host CUDA detection, package/dependency provisioning, and supervisor service bootstrapping) will be written in POSIX-compliant Bash and Python.
The interactive shell presented to the user (via SSH or the Web Terminal console) will be Nushell.

#### Rationale
* **Compatibility**: Standard AI installation scripts, Conda activations, and node installations depend heavily on sourcing POSIX/Bash scripts. Running the boot/init sequence in Bash ensures 100% compatibility.
* **Robustness**: Python provides robust, cross-platform library management for complex JSON/YAML provisioning logic.
* **User Experience**: Nushell provides a structured, modern CLI experience which is a unique selling point (特色) for data science and AI workflows (e.g. data filtering, model listings).

#### Date
2026-06-08

---

### Decision 2: UI/UX Redesign Style - Claude Cream Theme

#### Description
Completely abandon traditional dark/neon console themes. All graphical web interfaces (Instance Portal dashboard, metrics meters, terminal wrappers) must conform to the `Claude Cream` visual style.

#### Rationale
* **Brand Consistency**: Aligns with the core visual identity of xforce workspace style.
* **Visual Distinction**: The warm parchment, ivory panels, and refined serif typography (`Fraunces` / `IBM Plex Sans` / `JetBrains Mono`) offer a highly premium, document-like, academic interface that stands out in the AI hosting market.

#### Date
2026-06-08

---

### Decision 3: PTY-Wrap Native Re-implementation

#### Description
Replace the legacy Tcl/Expect-based `unbuffer` wrapper used in the log filtering pipeline with a native PTY process wrapper written in Python or Go.

#### Rationale
* **Signal Integrity**: Native PTY wrapping ensures system signals (such as `SIGTERM` on container stop) are correctly and immediately forwarded to child processes, preventing zombie processes and database corruption.
* **Performance**: Reduces process spawning overhead and memory usage inside the container.

#### Date
2026-06-08

---

### Decision 4: GitHub Container Registry (GHCR) Primary Strategy

#### Description
Establish GitHub Container Registry (ghcr.io) as the **Primary Registry** for hosting and pulling xforce_AI base images. Docker Hub (docker.io) will be utilized solely as a **Secondary Mirror / Discovery Channel** to maintain platform searchability.

#### Rationale
* **Direct Drop-in Replacement**: GHCR is fully OCI-compliant and integrates seamlessly with standard Docker and container runtimes without any compatibility issues.
* **No Pull Rate Throttling**: Docker Hub's strict IP-based anonymous pull limits (100 pulls / 6 hours) represent a critical bottleneck for decentralized GPU miner nodes pulling multi-gigabyte images. GHCR does not enforce rate limits on public image pulls, making it much more reliable as the primary pull target.
* **Native CI/CD Integration**: Integrates directly with our GitHub Actions build pipelines using native GITHUB_TOKEN authentication, simplifying permission mapping and reducing credentials maintenance.
* **Discovery Mirroring**: While GHCR is the primary registry for pulls, the build pipeline will push to Docker Hub as a mirror to ensure users can still find the image through standard Docker Hub queries.

#### Date
2026-06-08

---

### Decision 5: Automated GPU Hardware-in-the-Loop (HIL) & Miner-Activated Validation Pipeline

#### Description
Implement an automated, API-driven GPU leasing pipeline for hardware validation and specialized package pre-compilation. When new GPU models are launched or base-image components undergo major upgrades, the orchestration engine will programmatically lease target GPU instances. Crucially, this pipeline integrates with the platform's miner-onboarding loop: when a new GPU miner lists their node on the marketplace, the platform automatically triggers this validation container as their **very first paid verification task (activation task)**. The node runs compilation/benchmarking suites, reports compatibility data, caches optimized artifacts to GHCR/Static storage, and pays the miner a standard test fee (instant activation income).

#### Rationale
* **Zero Capital Expenditure for Rare Hardware**: Eliminates the financial burden of purchasing and maintaining specialized or high-end enterprise GPUs (such as H100s, H200s, or AMD CDNA MI300X) solely for testing and optimization.
* **Crowdsourced Hardware Adapters**: Every new GPU card variant, driver combination, or host system setting that joins the marketplace is immediately tested and optimized. The compiled binary wheels or container hashes are cached, preventing cold-start compile delays for future actual renters.
* **Miner Win-Win Incentives**: Onboarding miners receive immediate validation that their setup is functionally correct, alongside instant initial income (the test verification reward), encouraging stable hosting and reducing listing errors.

#### Date
2026-06-08

---

### Decision 6: HIL Orchestrator Control Loop Automation

#### Description
Implement the automated HIL loop as an active microservice (HIL Orchestrator) in the xforce backend. The service continuously listens to new node registrations, filters out unverified hardware configurations, coordinates the API-driven rental and execution, compiles target wheels/images, registers them to our OCI registry/artifact cache, and releases the lease while triggering the payment callback to the miner.

#### Rationale
* **Operational Autonomy**: Prevents manual intervention when new miners list their hardware, enabling continuous platform adaptation 24/7.
* **Immediate Miner Reward**: Hooking the teardown directly to billing ensures the miner gets paid instantly, building strong confidence in the marketplace.
* **Deterministic Caching**: Keeps the platform registry up-to-date with optimized mappings (`[Hardware Fingerprint] -> [Cached Image Hash]`), ensuring subsequent user leases launch instantly.

#### Date
2026-06-08

---

### Decision 7: Model-to-Hardware Resource Registry & Pre-flight Availability Check

#### Description
Maintain a structured "Model Requirements Registry" mapping each AI model template (e.g., Llama-3-70B, SDXL) to its minimal hardware requirements (VRAM, CUDA Compute level, RAM, Disk). Integrate this registry into the booking/rental gateway: when a tenant selects a model, the system executes a real-time pre-flight availability check against the active online GPU miner database (filtering by state, capacity, and current idle status) and enforces atomic node locking during checkout to prevent race conditions.

#### Rationale
* **User Friction Reduction**: Prevents tenants from ordering resource-heavy models on incompatible or under-specced GPUs (e.g., trying to run Llama-3-70B on a single 12GB RTX 3060), which would result in out-of-memory (OOM) failures.
* **Efficient Inventory Allocation**: Helps match user requirements to the most cost-effective and compatible idle GPU nodes currently online.
* **Race Condition Prevention**: Atomic pre-flight lock ensures that once a matching GPU is selected and ordered, it is securely bound to the tenant before other sessions can request it.

#### Date
2026-06-08



