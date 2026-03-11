# Framework Skills for Bug Hunter D33

Pre-committed skills from skills.sh for zero-dependency CI runs.

## Available Skills

| Framework | File | Source |
|-----------|------|--------|
| React/Next.js | `react-vercel.md` | vercel-labs/agent-skills |
| Vue | `vue.md` | vuejs/agent-skills |
| Godot/GDScript | `godot-gdscript.md` | godot/agent-skills |

## Detection Mapping

Frameworks are auto-detected from the diff:

```bash
# React/Next.js
- import React / from 'react'
- .jsx / .tsx extensions
- from 'next/' imports

# Vue
- from 'vue'
- .vue extensions

# Godot
- .gd extensions
- @onready / extends Node
```

## Updating Skills

To refresh a skill from skills.sh:

```bash
npx skills fetch vercel-labs/agent-skills > framework-skills/react-vercel.md
```

Then commit and push.

## Why Local?

- Zero network dependency during CI
- Deterministic reviews (skill version pinned)
- Faster execution (no fetch latency)
- Works on any runner (GitHub-hosted or self-hosted)
