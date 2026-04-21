class WorkforceLocalMcp < Formula
  desc "Local MCP server giving Claude Code a code graph, memory, and adapter tools"
  homepage "https://github.com/driftwerk/homebrew-tap"
  version "0.1.2"
  license "MIT"

  # Apple Silicon only for now. The embedded ONNX runtime (via
  # fastembed/ort) doesn't ship prebuilt x86_64 macOS binaries, and
  # cross-compiling it from source wasn't worth the CI fragility for
  # the shrinking Intel-Mac audience. Intel users can still build
  # from source (see the project README in the original workforce
  # repo, access-gated).
  on_macos do
    on_arm do
      url "https://github.com/driftwerk/homebrew-tap/releases/download/local-mcp-v#{version}/workforce-local-mcp-#{version}-aarch64-apple-darwin.tar.gz"
      sha256 "REPLACE_WITH_ACTUAL_SHA256"
    end
  end

  def install
    bin.install "workforce-local-mcp"
    (pkgshare/"skills").install Dir["skills/*"]
  end

  def caveats
    <<~EOS
      Register the MCP server with Claude Code (user scope so every session
      sees it):

        claude mcp add workforce-local --scope user -- #{opt_bin}/workforce-local-mcp

      Symlink the bundled SKILL.md directories into Claude Code's skills dir
      so it knows when to reach for the tools:

        mkdir -p ~/.claude/skills
        ln -sfn #{opt_pkgshare}/skills/codebase-knowledge ~/.claude/skills/codebase-knowledge
        ln -sfn #{opt_pkgshare}/skills/project-memory     ~/.claude/skills/project-memory
        ln -sfn #{opt_pkgshare}/skills/adapter-integrations ~/.claude/skills/adapter-integrations

      Configure adapter credentials as needed (all optional — each
      adapter activates only when its creds are set):

        workforce-local-mcp config jira     --email you@example.com --site https://you.atlassian.net
        workforce-local-mcp config linear
        workforce-local-mcp config datadog  --site eu1
        workforce-local-mcp config metabase --site-url https://mb.yourcompany.com

      Then restart Claude Code; '/mcp' in a session will show the
      workforce-local server connected with up to 107 tools.
    EOS
  end

  test do
    assert_match "workforce-local-mcp",
                 shell_output("#{bin}/workforce-local-mcp --help")
  end
end
