// Installed by the railsdx gem.
//
// Runs bin/rubocop-changed when OpenCode finishes a turn. Observation only:
// session.idle cannot block the turn or feed offense text back to the model,
// so the offenses are printed for the developer rather than the agent.
// For deterministic enforcement use Claude Code or Codex CLI, which expose
// blocking Stop hooks (see .claude/settings.json and .codex/hooks.json).
export const RailsdxRubocopChanged = async ({ $ }) => {
  return {
    "session.idle": async () => {
      const result = await $`bin/rubocop-changed`.quiet().nothrow();
      if (result.exitCode !== 0) {
        console.error("\n[railsdx] RuboCop found offenses on changed Ruby files:");
        console.error(result.stderr.toString());
      }
    },
  };
};
