# HOW TO USE YOUR SKILLS

## Quick start
- Tell your AI agent:  "Read skill-instructions.md and follow it for everything in this project."
- That file lists your skills and the exact workflow the agent must follow.

## 1. What is now in your project folder
- DESIGN.md          = the design system (colors, fonts, spacing) your UI must follow
- skill-instructions.md = the file you tell your agent to read: skills + mandatory workflow
- CLAUDE.md          = frontend rules your AI agent reads at the start of a session
- AGENTS.md          = the same rules, for agents that use AGENTS.md
- .claude/skills/    = the installed skills (Claude Code and compatible agents)
- .agents/skills/    = a copy of the same skills for other agents
- .mcp.json          = Playwright MCP: lets the agent open a real browser and take screenshots

## 2. Daily workflow (works with any AI coding agent)
1. Open a terminal in THIS project folder (the one that contains DESIGN.md).
2. Start your agent there: claude, freebuff, codex, gemini, cursor-agent, etc.
3. Check that it sees your setup. Ask:
   "What frontend rules, DESIGN.md and skills do you have in this project?"
4. Give it a UI task. Example:
   "Read DESIGN.md and CLAUDE.md. Build a pricing page following the rules."
5. Ask it to verify visually:
   "Open the localhost page with Playwright, take a screenshot and fix any visual bugs."
6. Run the audit skills, review the result, then commit.

## 3. Tips for each kind of agent
- Claude Code: reads CLAUDE.md and .claude/skills automatically. Skills start from your
  request, or call one by name, e.g.  /impeccable audit  (type / to see the list).
  The first time, approve the Playwright server from .mcp.json (check with /mcp).
- Freebuff / Codebuff and other agents: auto-loading of skills and MCP can differ.
  If the agent does not know your rules, start with this first prompt:
  "Read CLAUDE.md, DESIGN.md and the SKILL.md files inside .agents/skills before any UI work."
  Slash commands like /impeccable only work in agents that support skills; otherwise say:
  "Follow the Impeccable skill and audit this page."
- Cursor / Codex and others: most read AGENTS.md. Gemini CLI reads GEMINI.md by default,
  so run:  cp AGENTS.md GEMINI.md   (check your agent's docs for the exact file name).
- Agent without MCP support: take screenshots yourself and let the agent look at the file:
  npx playwright screenshot http://localhost:3000 shot.png

## 4. Example prompts
- Design system:  "Use DESIGN.md strictly: exact hex colors, type scale, spacing, radius, shadows."
- Impeccable:     "/impeccable audit"  then  "/impeccable polish"  on components, typography, background.
- Taste Skill:    "Use the Taste skill. Bold = high, Motion = medium, Density = low. Redesign the hero."
- Vercel rules:   "Review this page with the Web Design Guidelines skill: accessibility, hit targets, zoom, loading states."
- Playwright QA:  "Open http://localhost:3000, click every button, screenshot, fix overflow or overlap."
- Full pipeline:  "Build the dashboard from DESIGN.md, polish it, audit it, then QA it in the browser."

## 5. Change the design later
- Run  ./setup-design-skills.sh --list  to see all designs, then
  ./setup-design-skills.sh --brand stripe  to switch. Your old DESIGN.md is kept as DESIGN.md.bak.
- Preview designs first at https://getdesign.md/

## 6. If something does not work
- Agent ignores the rules: restart the agent session and say "Read CLAUDE.md and DESIGN.md first."
- Skill not found: run  ls .claude/skills  then say
  "Read .claude/skills/<skill-name>/SKILL.md and follow it for this task."
- Screenshot fails (no browser): run  npx playwright install chromium
- Something failed during setup: re-run the script (it is safe to repeat) or add --debug.

## 7. Superpowers skills (installed)
- They start from your request. Try: "Use brainstorming to plan this feature",
  "Write the plan first", "Use test-driven-development", "Use systematic-debugging on this bug".
- Best habit: ask for a plan before code, then ask it to verify before it says done.
