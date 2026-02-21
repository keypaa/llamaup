# Documentation Index

Complete documentation for the **llamaup** project. Start here to find what you need.

---

## Quick Start

**New user?** Start with:
1. [README.md](README.md) — Project overview, installation, and usage
2. [Scripts Reference](#scripts-reference) (in README) — Guide to all available tools

**Want to contribute?** Read:
1. [CONTRIBUTING.md](CONTRIBUTING.md) — How to contribute GPU mappings, binaries, or code
2. [TESTING.md](TESTING.md) — Testing guide and validation workflows

---

## Documentation Files

### Core Documentation

| File | Purpose | Audience |
|------|---------|----------|
| [README.md](README.md) | Main project documentation, quick start, scripts reference | All users |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines for GPU mappings, binaries, and code | Contributors |
| [TESTING.md](TESTING.md) | Comprehensive testing guide, manual test workflows, troubleshooting | Developers & contributors |
| [LICENSE](LICENSE) | MIT license | Legal/compliance |

### Technical Documentation

| File | Purpose | Audience |
|------|---------|----------|
| [docs/GPU_MATCHING.md](docs/GPU_MATCHING.md) | How GPU substring matching works, pattern validation, best practices | Contributors adding GPUs |
| [docs/NOTES.md](docs/NOTES.md) | Project progress log, bash concepts, implementation notes | Developers |
| [CLAUDE.md](CLAUDE.md) | Project context for AI assistants, design decisions, conventions | Developers |
| [AGENTS.md](AGENTS.md) | Full implementation spec and task breakdown | Developers |
| [CONVENTION.md](CONVENTION.md) | Binary naming convention | Developers |

---

## Documentation by Topic

### For Users

**Installation & Setup:**
- [Quick Start](README.md#quick-start) — Install pre-built binaries
- [Requirements](README.md#requirements) — Dependencies for pulling and building
- [Setup: Forking the repo](README.md#setup-forking-this-repo) — How to set up your own binary store

**Using llama.cpp:**
- [llama.cpp Quick Reference](README.md#using-llamacpp-quick-reference) — How to use the installed binaries
- [Scripts Reference](README.md#scripts-reference) — Detailed guide to all utility scripts

**Troubleshooting:**
- [detect.sh](README.md#scriptsdetectsh--diagnostic-and-gpu-detection) — Diagnose GPU/CUDA environment
- [TESTING.md - Troubleshooting](TESTING.md#troubleshooting-failed-tests) — Common test failures

### For Contributors

**Adding GPU Mappings:**
- [CONTRIBUTING.md - GPU Mappings](CONTRIBUTING.md#1-how-to-add-or-fix-a-gpu-mapping) — Step-by-step guide
- [GPU_MATCHING.md](docs/GPU_MATCHING.md) — Technical details of matching logic
- [Testing GPU Changes](TESTING.md#testing-detectsh) — How to validate your changes

**Building Binaries:**
- [README.md - Building Binaries](README.md#building-binaries) — Local build guide
- [CONTRIBUTING.md - Binaries](CONTRIBUTING.md#2-how-to-contribute-a-binary-for-a-new-sm-version) — Upload to releases
- [Testing Builds](TESTING.md#testing-buildsh) — Validate builds before submitting

**Code Contributions:**
- [CONTRIBUTING.md - Code Guidelines](CONTRIBUTING.md#4-code-contribution-guidelines) — Style, linting, testing rules
- [TESTING.md](TESTING.md) — Complete testing reference
- [CLAUDE.md](CLAUDE.md) — Design decisions and conventions

### For Maintainers

**Project Architecture:**
- [CLAUDE.md](CLAUDE.md) — High-level project context, design decisions
- [AGENTS.md](AGENTS.md) — Complete implementation specification
- [docs/NOTES.md](docs/NOTES.md) — Progress log and bash implementation notes

**CI/CD:**
- [README.md - Automatic Builds](README.md#automatic-builds-via-ci) — CI pipeline overview
- [TESTING.md - CI Testing](TESTING.md#ci-testing) — How CI validates binaries

---

## Scripts Documentation

All scripts include built-in help (`--help` flag). For detailed usage examples:

| Script | Quick Description | Full Docs |
|--------|-------------------|-----------|
| `pull.sh` | Download and install pre-built binaries | [README](README.md#scriptspullsh--download-and-install-pre-built-binaries) |
| `build.sh` | Build and package binaries | [README](README.md#scriptsbuildsh--build-and-package-binaries) |
| `detect.sh` | Diagnostic and GPU detection | [README](README.md#scriptsdetectsh--diagnostic-and-gpu-detection) |
| `list.sh` | List available binaries | [README](README.md#scriptslistsh--list-available-binaries) |
| `verify.sh` | Verify file checksums | [README](README.md#scriptsverifysh--verify-file-checksums) |
| `cleanup.sh` | Manage installed versions | [README](README.md#scriptscleanupsh--manage-installed-versions) |
| `test_gpu_matching.sh` | Test GPU matching logic | [TESTING](TESTING.md#scriptstest_gpu_matchingsh) |
| `test_archive_integrity.sh` | Test archive verification | [TESTING](TESTING.md#scriptstest_archive_integritysh) |

---

## Configuration Files

| File | Purpose | Schema |
|------|---------|--------|
| [`configs/gpu_map.json`](configs/gpu_map.json) | GPU model → SM version mapping | See [GPU_MATCHING.md](docs/GPU_MATCHING.md) |
| [`.github/workflows/build.yml`](.github/workflows/build.yml) | CI build pipeline | GitHub Actions YAML |

---

## Issue Templates

| Template | When to Use |
|----------|-------------|
| [wrong_sm.md](.github/ISSUE_TEMPLATE/wrong_sm.md) | GPU detected with incorrect SM version |
| [bad_binary.md](.github/ISSUE_TEMPLATE/bad_binary.md) | Downloaded binary crashes or fails to run |

---

## FAQ

**Where do I start as a new user?**
→ [README.md](README.md) → [Quick Start](README.md#quick-start)

**I have a new GPU, how do I add it?**
→ [CONTRIBUTING.md](CONTRIBUTING.md#1-how-to-add-or-fix-a-gpu-mapping)

**How do I test my changes?**
→ [TESTING.md](TESTING.md)

**What's the architecture behind GPU matching?**
→ [docs/GPU_MATCHING.md](docs/GPU_MATCHING.md)

**How do I build binaries locally?**
→ [README.md - Building Binaries](README.md#building-binaries)

**The binary doesn't work, what info should I provide?**
→ Run `./scripts/detect.sh --json` and include output in your issue

---

## Contributing to Documentation

Found a typo? Documentation unclear? PRs welcome!

- Keep READMEfocused on user-facing features
- Put technical implementation details in `docs/` or `CLAUDE.md`
- Update this index when adding new documentation files
- Use markdown linting (e.g., `markdownlint`) before committing

---

**Last Updated:** 2026-02-21  
**Maintainer:** keypaa/llamaup
