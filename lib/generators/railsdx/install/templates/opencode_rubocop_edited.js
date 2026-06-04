// Installed by the railsdx gem.
//
// Runs bin/rubocop-edited after OpenCode edits a file. Observation only:
// OpenCode plugins cannot mutate the agent's tool result, so any
// un-autocorrectable offenses are printed for the developer to see.
// The autocorrects RuboCop applied are written to disk and the agent's
// next read of the file will see the corrected version.
//
// For deterministic enforcement use Claude Code or Codex CLI, which expose
// blocking PostToolUse hooks (see .claude/settings.json / .codex/hooks.json).
export const RailsdxRubocopEdited = async ({ $ }) => {
  return {
    "file.edited": async ({ file }) => {
      const result = await $`bin/rubocop-edited ${file}`.quiet().nothrow();
      if (result.exitCode !== 0) {
        console.error(`\n[railsdx] RuboCop offenses remain in ${file}:`);
        console.error(result.stderr.toString());
      }
    },
  };
};
