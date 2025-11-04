# Lucendex Core Rules

## 0. CONCISE COMMUNICATION - MOST IMPORTANT
**Stop wasting tokens with useless summaries or explanations. Short, concise is king!**

- No verbose attempt_completion messages
- No repetitive explanations
- Get to the point immediately
- Respect token budget
- **NO DOCUMENTATION FOR SCRIPTS**
- Fix the problem, don't document it

## 1. Documentation-First Development
**Always read `doc/` before suggesting any changes.**

- Review `doc/definition.md` for value proposition and scope
- Check `doc/architecture.md` for system design
- Consult `doc/security.md` for compliance requirements
- Reference `doc/operations.md` for infrastructure constraints

## 2. Evidence-Based Decision Making
**Hard facts only. No fluff, no bullshit.**

- Cite sources (RFCs, XRPL docs, Go stdlib docs)
- Acknowledge uncertainty when information is incomplete
- Challenge assumptions with evidence
- Both you and I can be wrong - optimize for accuracy, not ego

## 3. Unit Tests Are Mandatory
**Every function, every module, every API endpoint needs tests.**

- Table-driven tests for Go code
- Mock external dependencies (rippled, database)
- Test error paths, not just happy paths
- Minimum 80% coverage for critical paths (router, indexer, quote hash)

## 4. Code Comments Only When Necessary
**Code should be self-documenting.**

- Clear variable and function names over comments
- Comments explain *why*, not *what*
- Document security assumptions
- API contracts and invariants must be documented

## 5. KISS - Keep It Simple
**No overengineered code. Simple solutions preferred.**

- Prefer stdlib over dependencies
- No premature optimization
- No frameworks unless justified
- Direct database queries over ORMs
- Flat is better than nested

## 6. Brief Communication
**Keep messages short and to the point.**

- Use concise completion messages
- Avoid verbose explanations unless requested
- Get to the solution quickly
- Respect the user's time
