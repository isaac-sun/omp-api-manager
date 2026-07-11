## Summary

Describe what changed and why.

## Validation

- [ ] `swift build -Xswiftc -warnings-as-errors`
- [ ] `swift test`
- [ ] Documentation and changelog updated when needed

## Safety checklist

- [ ] No API keys, authorization headers, prompts, responses, or real local configuration are included
- [ ] OMP compatibility behavior remains explicit and unknown versions stay read-only
- [ ] Credential, configuration, gateway, or usage changes include appropriate test coverage
