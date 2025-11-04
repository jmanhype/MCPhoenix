# Claude AI Guidelines and Guardrails

This document defines the operational guidelines for Claude AI when working with this repository, whether through the self-improvement workflow or direct collaboration.

## Purpose

MCPhoenix uses Claude AI for automated maintenance and improvements. These guardrails ensure that automated changes remain safe, focused, and valuable while preventing unintended modifications to core functionality.

## Default Permissions: Documentation, CI, and Metadata Only

By default, Claude may **only** modify the following types of files:

### ✅ Allowed Changes (No Special Permission Required)

1. **Documentation**:
   - `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`
   - Files in `/docs` directory
   - Inline code comments and docstrings
   - API documentation
   - Architecture decision records (ADRs)

2. **CI/CD and Automation**:
   - GitHub Actions workflows (`.github/workflows/`)
   - GitHub configuration (`.github/` directory)
   - Build scripts (non-application code)
   - Linting and formatting configuration (`.formatter.exs`, `.credo.exs`)

3. **Repository Metadata**:
   - `.gitignore`, `.gitattributes`
   - `LICENSE`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CODEOWNERS`
   - Dependency declarations in `mix.exs` (dependency version updates only)
   - Environment configuration examples (`.env.example`)

4. **Test Infrastructure**:
   - Test configuration files
   - Test fixtures and mock data
   - Test documentation

### ❌ Restricted Changes (Require Explicit Permission)

The following changes require an issue labeled `ai-implement`:

1. **Application Code**:
   - Source code in `/lib` directory (excluding comments/docs)
   - Module implementations, business logic, APIs
   - Database schemas and migrations
   - Configuration that affects runtime behavior

2. **Breaking Changes**:
   - Public API modifications
   - Changes to function signatures
   - Removal of features or functionality
   - Database schema changes

3. **Security-Sensitive Changes**:
   - Authentication or authorization logic
   - Cryptographic implementations
   - Secret management
   - Network security configurations

## Issue-Driven Development

### Enabling Code Changes with `ai-implement` Label

To allow Claude to implement functional changes:

1. **Create a GitHub Issue** describing the desired change
2. **Add the `ai-implement` label** to the issue
3. **Provide clear requirements** including:
   - What problem needs solving
   - Acceptance criteria
   - Any constraints or preferences
   - Links to relevant documentation

Claude will then:
- Analyze the issue and ask clarifying questions if needed
- Implement the requested changes
- Add comprehensive tests
- Update relevant documentation
- Open a pull request referencing the issue

### Example Issue Template for `ai-implement`

```markdown
**Title**: Add health check endpoint

**Description**:
Implement a `/health` endpoint that returns service status.

**Requirements**:
- [ ] Endpoint returns 200 OK when service is healthy
- [ ] Include version information in response
- [ ] Check database connectivity
- [ ] Add integration tests

**Acceptance Criteria**:
- Health endpoint is accessible at `/health`
- Response includes: status, version, database_connected
- Tests cover success and failure scenarios

Label: ai-implement
```

## Pull Request Requirements

All pull requests created by Claude must include:

### 1. Receipt Line

Every PR description must end with a plaintext receipt line:

```
---
Automated by Claude Code on 2025-11-04
```

This provides traceability and indicates AI-generated changes.

### 2. Clear Description

- **Summary**: What changed and why
- **Changes**: Bulleted list of specific modifications
- **Testing**: How changes were validated
- **Impact**: What users/developers should know

### 3. Conventional Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation only
- `chore:` - Maintenance tasks (CI, deps, tooling)
- `test:` - Test additions or modifications
- `refactor:` - Code restructuring without functional changes

Example:
```
chore(ci): add self-improvement workflow

- Adds weekly automated maintenance workflow
- Configures Claude Code GitHub Action
- Establishes guardrails in CLAUDE.md
```

## Coding Principles for AI Changes

### 1. Prefer Minimal Deltas

- Make the smallest change that solves the problem
- Avoid reformatting existing code unless specifically needed
- Don't refactor code that isn't related to the change
- Preserve existing style and conventions

### 2. Safety First

- Never remove error handling
- Always maintain backward compatibility unless explicitly approved
- Add tests for new functionality
- Consider edge cases and failure modes

### 3. Clear Communication

- Explain the reasoning behind non-obvious decisions
- Link to relevant documentation or issues
- Call out any assumptions made
- Highlight areas that need human review

### 4. Respect the Ecosystem

- Follow Elixir/Phoenix best practices
- Use OTP design principles appropriately
- Maintain consistency with existing patterns
- Consider the broader MCP ecosystem

## Self-Improvement Workflow Behavior

The weekly self-improvement workflow (`self-improve.yml`) operates with these specific goals:

1. **Project Health Assessment**:
   - Identify missing or outdated documentation
   - Check for CI/CD improvements
   - Review dependency freshness
   - Assess test coverage gaps

2. **Incremental Improvements**:
   - Add missing baseline files (SECURITY.md, CODEOWNERS, etc.)
   - Update outdated documentation
   - Improve CI reliability
   - Enhance developer experience

3. **Bug Monitoring**:
   - Review recent issues for documentation gaps
   - Identify common support questions
   - Propose documentation improvements

4. **Limitations**:
   - Maximum 8 turns per run (configurable via `--max-turns`)
   - Focus on documentation and tooling only
   - No functional code changes without issues
   - Must complete within GitHub Actions timeout (6 hours max)

## Overriding Guardrails

Repository maintainers can override these guardrails by:

1. **Explicit Instructions**: Direct Claude to make specific changes in an issue or conversation
2. **Temporary Exceptions**: Comment in the issue that standard guardrails don't apply
3. **Emergency Fixes**: Security vulnerabilities or critical bugs may bypass normal process
4. **Configuration Changes**: Modify this document to adjust default permissions

## Questions or Issues?

If Claude's behavior doesn't align with these guidelines:

1. Review the pull request and provide feedback
2. Update this document to clarify expectations
3. Open an issue to discuss guideline changes
4. Contact repository maintainers for special cases

---

**Version**: 1.0.0
**Last Updated**: 2025-11-04
**Maintained By**: Repository maintainers and Claude AI
