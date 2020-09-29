require_relative 'lib/faster_s3_url/version'

Gem::Specification.new do |spec|
  spec.name          = "faster_s3_url"
  spec.version       = FasterS3Url::VERSION
  spec.authors       = ["Jonathan Rochkind"]
  spec.email         = ["jrochkind@sciencehistory.org"]

  spec.summary       = %q{Generate public and presigned S3 GET URLs faster}
  spec.homepage      = "https://github.com/jrochkind/faster_s3_url"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  #spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jrochkind/faster_s3_url"
  #spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "aws-sdk-s3", "~> 1.81"
  spec.add_development_dependency "timecop", "< 2"
end
