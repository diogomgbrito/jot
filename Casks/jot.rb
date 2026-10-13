cask "jot" do
  version "1.0.0"
  sha256 "c1682a7eda995a7c3a27a339a762d4e345ea6f5932ffdf193eea5f540aba344f"

  url "https://github.com/diogomgbrito/jot/releases/download/v#{version}/Jot-#{version}.dmg"
  name "Jot"
  desc "Menu bar Markdown scratchpad with unlimited notes stored as plain files"
  homepage "https://github.com/diogomgbrito/jot"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Jot.app"

  # App is ad-hoc signed (not notarized): clear quarantine so Gatekeeper doesn't block launch.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Jot.app"],
        writable_paths: ["{{appdir}}/Jot.app"]
  end

  uninstall quit: "com.brilean.jot"

  # Notes live in the folder chosen in Settings (default ~/Notes) and are never removed.
  zap trash: "~/Library/Preferences/com.brilean.jot.plist"
end
