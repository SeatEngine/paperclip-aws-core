# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'paperclip/aws/core/version'

Gem::Specification.new do |spec|
  spec.name          = "paperclip-aws-core"
  spec.version       = Paperclip::Aws::Core::VERSION
  spec.authors       = ["Bill Centinaro"]
  spec.email         = ["billc@seatengine.com"]
  spec.summary       = %q{A simple gem to add support for the AWS Core Gem for paperclip}
  spec.description   = %q{}
  spec.homepage      = "https://github.com/SeatEngine/paperclip-aws-core"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  
  spec.add_dependency "aws-sdk-core"

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
end
