# typed: false
# frozen_string_literal: true

# Homebrew formula for the Hatchbox CLI.
#
# This lives in the main repo for reference. For distribution, copy it into a
# tap repo named `homebrew-tap` (so users run `brew install blairanderson/tap/hatchbox`)
# and fill in the release `url` + `sha256`.
class Hatchbox < Formula
  desc "Command-line interface for the Hatchbox.io API"
  homepage "https://github.com/blairanderson/hatchbox-cli"
  url "https://github.com/blairanderson/hatchbox-cli/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_TARBALL_SHA256"
  license "MIT"

  depends_on "ruby"

  def install
    libexec.install "lib", "bin"
    (bin/"hatchbox").write <<~SH
      #!/bin/bash
      exec "#{Formula["ruby"].opt_bin}/ruby" "#{libexec}/bin/hatchbox" "$@"
    SH
    chmod 0755, bin/"hatchbox"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/hatchbox --version")
  end
end
