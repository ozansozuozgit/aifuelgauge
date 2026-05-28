cask "ai-fuel-gauge" do
  version :latest
  sha256 :no_check

  url "https://github.com/ozansozuozgit/aifuelgauge/releases/latest/download/AI-Fuel-Gauge-latest.zip"
  name "AI Fuel Gauge"
  desc "Local-first menu bar app for tracking AI coding quota and API usage"
  homepage "https://github.com/ozansozuozgit/aifuelgauge"

  depends_on macos: ">= :sonoma"

  app "AI Fuel Gauge.app"

  zap trash: [
    "~/Library/Application Support/AI Fuel Gauge",
    "~/Library/Preferences/com.ozansozuoz.aifuelgauge.plist",
  ]

  caveats <<~EOS
    AI Fuel Gauge is a menu bar app. Open it from Applications after install.

    The source install path (`make install`) also creates a LaunchAgent for login startup.
  EOS
end
