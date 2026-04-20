# Contributing to Agent Deck

<a href="CONTRIBUTING.zh-CN.md">中文</a> | <strong>English</strong>

Thank you for your interest in contributing to Agent Deck!

---

## Human Parts

*This section is written for humans.*

We welcome all good ideas. If you have the will, you can turn any idea into code for this project and have it used by others.

Check the [Roadmap](docs/roadmap.md) to see where the project is heading and pick an area that interests you.

All code in this project is produced by AI. You should not contribute human-written code either.

### Getting Started

We've put effort into making it easy for AI to iterate on this project. To start contributing, paste the following into your code agent:

```
Please read this project's CONTRIBUTING.md and explain how I should iterate on this project.
Then list what you already know, such as release/build process, repo architecture, code conventions, PR standards, etc.
```

### Report a Bug via Your Code Agent

If you run into a problem, copy the prompt below into your code agent (Claude Code, Codex, etc.) and it will automatically collect environment info and create a well-structured issue for you.

<details>
<summary>Click to expand the prompt</summary>

```
I'm having an issue with Agent Deck (https://github.com/Octane0411/agent-deck).

Please help me file a GitHub issue. Do the following:

1. Collect my environment info:
   - Run `sw_vers` to get macOS version
   - Run `swift --version` to get Swift version
   - Check if Agent Deck is running: `ps aux | grep -i "agentdeck\|AgentDeckApp" | grep -v grep`
   - Get the app version: `defaults read ~/Applications/Open\ Island\ Dev.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "unknown"`
   - Check which terminal I'm using

2. Ask me to describe:
   - What I expected to happen
   - What actually happened
   - Steps to reproduce

3. Create the issue on GitHub using `gh issue create` with this format:
   - Title: concise summary
   - Body with sections: **Environment**, **Description**, **Steps to Reproduce**, **Expected vs Actual Behavior**
   - Add label "bug" if applicable

Repository: Octane0411/agent-deck
```

</details>

### Request a Feature via Your Code Agent

Have an idea? Let your agent draft the proposal for you.

<details>
<summary>Click to expand the prompt</summary>

```
I'd like to request a feature for Agent Deck (https://github.com/Octane0411/agent-deck).

Please help me file a GitHub issue. Do the following:

1. Ask me to describe:
   - What feature I want
   - Why it would be useful (what problem it solves)
   - Any ideas on how it should work

2. Create the issue on GitHub using `gh issue create` with this format:
   - Title: concise summary prefixed with "feat: "
   - Body with sections: **Feature Description**, **Motivation**, **Proposed Behavior**
   - Add label "enhancement" if applicable

Repository: Octane0411/agent-deck
```

</details>

---

## Agent Parts

*This section is written for agents.*

### About the Project

Agent Deck is a native macOS companion app for AI coding agents. It sits in the notch/top-bar area and monitors local agent sessions, surfaces permission requests, answers questions, and provides "jump back" to the correct terminal context. Local-first, no server dependency.

**Supported agents**: Codex, Claude Code

**Supported terminals**: Terminal.app, Ghostty

### Prerequisites

- macOS 14+
- Swift 6.2+
- Xcode (for app target)

### Build & Test

```bash
# Build the project
swift build

# Run tests
swift test

# Run the app
swift run AgentDeckApp

# Build hook binary (release)
swift build -c release --product AgentDeckHooks
```

You can also open `Package.swift` in Xcode to build and run the app target directly.

### Where to Go Next

- [`CLAUDE.md`](CLAUDE.md) — Architecture, conventions, branching rules, commit policy, and release workflow.
- [`docs/architecture.md`](docs/architecture.md) — System design and engineering decisions.
- [`docs/product.md`](docs/product.md) — Product scope and MVP boundary.
- [`docs/hooks.md`](docs/hooks.md) — Supported hook events, payload fields, and directive protocol.
